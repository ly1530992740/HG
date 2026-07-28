extends Node

class PerceptionProbe:
	extends Node2D
	var hostile: Node2D = null

	func can_damage_target(candidate: Node) -> bool:
		return candidate == hostile

	func get_facing_direction() -> Vector2:
		return Vector2.RIGHT

class ConcealedProbe:
	extends Node2D
	var concealed := true

	func is_visually_concealed() -> bool:
		return concealed

const EXPECTED_ROLE_COUNTS := {
	SquadCombatRole.Type.RIFLEMAN: 3,
	SquadCombatRole.Type.MARKSMAN: 1,
	SquadCombatRole.Type.MACHINE_GUNNER: 1,
	SquadCombatRole.Type.SHOTGUNNER: 2,
	SquadCombatRole.Type.PISTOL_SCOUT: 1,
}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := $Scenario
	_assert_mutual_encounter_config(scene)
	_configure_ambush_test_scenario(scene)
	await get_tree().process_frame
	_configure_ambush_test_scenario(scene)
	await get_tree().process_frame

	var alpha := scene.get_node("EnemySquadCoordinator") as SquadCoordinator
	var bravo := scene.get_node("EnemySquadCoordinatorBravo") as SquadCoordinator
	assert(alpha.members.size() == 8, "Expected eight Alpha squad members.")
	assert(bravo.members.size() == 8, "Expected eight Bravo squad members.")
	assert(alpha.leader != null and bravo.leader != null, "Both squads must elect a leader.")
	_assert_role_composition(alpha)
	_assert_role_composition(bravo)

	var battle_camera := scene.get_node("BattleCamera") as Camera2D
	var player := scene.get_node("Player")
	var blindside_cover := scene.get_node("BravoBlindsideSquadCover") as LowWall
	var blindside_cover_2 := scene.get_node("BravoBlindsideSquadCover2") as LowWall
	assert(battle_camera.enabled and battle_camera.zoom.is_equal_approx(Vector2(0.32, 0.32)), "The overview camera is not configured.")
	assert(not (player.get_node("Camera2D") as Camera2D).enabled, "The player-follow camera must be disabled in the battle test.")
	assert(battle_camera.global_position.is_equal_approx(player.global_position), "The overview camera does not follow the player.")
	assert(blindside_cover.get_cover_capacity_per_side() >= 8 and blindside_cover_2.get_cover_capacity_per_side() >= 8, "The blind-side ambush walls have insufficient capacity.")
	assert(not scene.has_node("BravoWallNorth") and not scene.has_node("BravoForwardCenter"), "Old cover still remains near Bravo.")
	assert(alpha.ambush_ready_ratio_required == 1.0, "The scenario does not require the whole squad to be in cover before firing.")
	_assert_injury_damage_model()
	_assert_aim_model()
	_assert_bush_concealment(scene, player)

	for coordinator in [alpha, bravo]:
		for member in coordinator.members:
			_assert_member_loadout(member)
	_assert_sight_profiles(alpha)
	_assert_sight_profiles(bravo)
	_assert_concealment_perception()
	for member in alpha.members:
		assert((member.actor.get("initial_facing_direction") as Vector2).x > 0.0, "Alpha must initially observe the eastern approach.")
	for member in bravo.members:
		assert((member.actor.get("initial_facing_direction") as Vector2).x > 0.0, "Bravo must begin with its back toward Alpha.")
	assert(alpha.search_direction_override.is_equal_approx(Vector2.RIGHT), "Alpha search direction is not fixed toward the ambush target.")
	assert(bravo.search_movement_enabled and bravo.hold_search_until_first_contact, "Bravo should hold only until its first combat contact.")
	for member in alpha.members:
		assert(member.current_order != null and member.current_order.type == SquadOrder.Type.SEARCH_AREA, "An Alpha search member remained on HOLD.")
		assert(member.current_order.target_position.x > member.actor.global_position.x, "Alpha received a search destination that is not eastward.")
	for member in bravo.members:
		assert(member.current_order != null and member.current_order.type == SquadOrder.Type.HOLD, "Bravo should hold while facing away from Alpha.")
	var alpha_pre_ambush_ammo: Dictionary = {}
	var bravo_pre_ambush_health: Dictionary = {}
	for member in alpha.members:
		alpha_pre_ambush_ammo[member] = (member.actor.get("firearm_weapon") as FirearmWeapon).magazine_ammo
	for member in bravo.members:
		bravo_pre_ambush_health[member] = int(member.actor.get("health"))

	assert(not alpha.is_engagement_active() and not bravo.is_engagement_active(), "Squads gained omniscient contact before perception completed.")
	assert(alpha.get_blackboard().shared_target == null and bravo.get_blackboard().shared_target == null, "A target bypassed delayed squad reporting.")
	var perception_observer := _find_role_member(alpha, SquadCombatRole.Type.MARKSMAN)
	var observer_actor := perception_observer.actor
	var observer_perception := observer_actor.get("perception_component") as PerceptionComponent
	var perception_target := bravo.members[0].actor
	var target_original_position: Vector2 = perception_target.global_position
	var observer_facing: Vector2 = observer_actor.get_facing_direction()
	perception_target.global_position = observer_actor.global_position - observer_facing * 220.0
	observer_perception.forget_contact(perception_target)
	assert(not observer_perception.evaluate_candidate(perception_target, 1.0), "A target behind the observer was detected immediately.")
	perception_target.global_position = observer_actor.global_position + observer_facing * 220.0
	assert(observer_perception.evaluate_candidate(perception_target, 1.0), "A clear target in front did not accumulate detection.")
	observer_actor.set("target", perception_target)
	var held_ammo := (observer_actor.get("firearm_weapon") as FirearmWeapon).magazine_ammo
	observer_actor._try_fire_at(perception_target.global_position)
	assert((observer_actor.get("firearm_weapon") as FirearmWeapon).magazine_ammo == held_ammo, "WEAPONS_HOLD allowed a shot before the squad command.")
	assert(alpha.get_pending_contact_report_count() > 0 and alpha.get_blackboard().shared_target == null, "Contact reporting was not delayed.")
	perception_target.global_position = target_original_position

	var hearing_actor := alpha.members[1].actor
	var hearing_alert := hearing_actor.get("alert_component") as AlertComponent
	(hearing_actor.get("perception_component") as PerceptionComponent).hear_stimulus(hearing_actor.global_position + Vector2(80.0, 0.0))
	assert(hearing_alert.state >= AlertComponent.State.SUSPICIOUS, "A nearby gunshot stimulus did not raise suspicion.")
	await _assert_dead_observer_report_is_discarded()

	for frame_index in 240:
		await get_tree().physics_frame
		await get_tree().process_frame
		if alpha.is_engagement_active():
			break
	assert(alpha.is_engagement_active() and alpha.get_contact_phase() == SquadCoordinator.ContactPhase.AMBUSH, "Alpha did not establish a silent ambush contact.")
	assert(not bravo.is_engagement_active(), "Bravo detected Alpha before the ambush opened.")
	var known_hostiles := int(alpha.get_blackboard().get_fact(&"hostile_alive_count", 0))
	assert(known_hostiles > 0 and known_hostiles <= 8, "Finite squad intelligence published an impossible hostile count.")
	for member in alpha.members:
		assert(member.current_order != null and member.current_order.type == SquadOrder.Type.AMBUSH_POSITION, "An Alpha search order remained active after silent contact.")
		assert((member.actor.get("firearm_weapon") as FirearmWeapon).magazine_ammo == int(alpha_pre_ambush_ammo[member]), "Alpha fired before the ambush ROE opened.")
	for member in bravo.members:
		assert(int(member.actor.get("health")) == int(bravo_pre_ambush_health[member]), "Bravo took damage before Alpha entered firearm range and opened the ambush.")
	assert(int(alpha.get_blackboard().get_fact(&"roe")) == RulesOfEngagement.Type.WEAPONS_HOLD, "The ambushing squad did not hold fire.")

	var alpha_actor := alpha.members[0].actor
	var alpha_friend := alpha.members[1].actor
	var bravo_actor := bravo.members[0].actor
	assert(bravo_actor.get_facing_direction().x > 0.8, "Bravo HOLD drifted away from its initial east-facing direction.")
	assert(alpha_actor.can_damage_target(bravo_actor), "Opposing factions must be damageable.")
	assert(not alpha_actor.can_damage_target(alpha_friend), "Friendly damage filtering failed.")
	assert(not alpha_actor.can_damage_target(player), "The observer player must not be targeted.")

	alpha._begin_ambush(bravo_actor)
	assert(int(alpha.get_blackboard().get_fact(&"roe")) == RulesOfEngagement.Type.WEAPONS_HOLD, "Ambush setup did not enforce WEAPONS_HOLD.")
	var assigned_cover_counts: Dictionary = {}
	for member in alpha.members:
		assert(member.current_order != null and member.current_order.type == SquadOrder.Type.AMBUSH_POSITION, "A role received no ambush position.")
		assert(member.current_order.target_position != Vector2.ZERO, "An ambush role received no destination.")
		var assigned_cover := member.current_order.assigned_cover as LowWall
		assert(assigned_cover in [blindside_cover, blindside_cover_2], "Alpha received a cover outside the intended blind-side positions.")
		assigned_cover_counts[assigned_cover] = int(assigned_cover_counts.get(assigned_cover, 0)) + 1
		assert(int(assigned_cover_counts[assigned_cover]) <= assigned_cover.get_cover_capacity_per_side(), "An ambush cover was assigned beyond capacity.")
		assert(member.actor.enter_cover_against(assigned_cover, bravo_actor.global_position), "An Alpha member could not reserve its assigned ambush wall.")
	assert(assigned_cover_counts.size() == 2, "Alpha did not distribute across both viable blind-side covers.")
	assert(blindside_cover.assignments.size() + blindside_cover_2.assignments.size() == 8, "Not every Alpha member entered an assigned ambush wall.")
	var setup_targets: Dictionary = {}
	for member in alpha.members:
		setup_targets[alpha.get_ambush_target_for(member)] = true
	assert(setup_targets.size() == 8, "Alpha did not identify and assign the full nearby hostile formation.")
	alpha._open_ambush(&"test_ready")
	assert(int(alpha.get_blackboard().get_fact(&"roe")) == RulesOfEngagement.Type.WEAPONS_FREE, "Opening the ambush did not release weapon hold.")
	assert(String(alpha.get_blackboard().get_fact(&"tactical_plan")) == "AMBUSH_VOLLEY", "Ambush did not begin with a shared-cover opening volley.")
	assert(scene.alpha_ambush_opened_all_in_cover, "The ambush opened before every Alpha member occupied the shared cover.")
	var projectile_probe := Projectile.new()
	projectile_probe.shooter = alpha_actor
	projectile_probe.hit_groups = ["combatant", "player"]
	assert(projectile_probe._can_hit(bravo_actor), "Projectile faction filtering rejected an enemy.")
	assert(not projectile_probe._can_hit(alpha_friend), "Projectile faction filtering allowed a friendly hit.")
	assert(not projectile_probe._can_hit(player), "Projectile faction filtering allowed an observer hit.")

	var locked_will := alpha_actor.get("will_component") as WillComponent
	var suppression := alpha_actor.get("suppression_component") as SuppressionComponent
	var suppression_before := suppression.suppression
	alpha_actor.report_near_miss()
	locked_will.report_damage(100)
	locked_will.report_ally_death()
	for simulation_step in 20:
		locked_will._process(0.5)
	assert(suppression.suppression > suppression_before, "Suppression must remain active while morale is locked.")
	assert(locked_will.mental_state == WillComponent.MentalState.STEADY, "The test-scene morale lock allowed emotional collapse.")
	assert(not locked_will.should_seek_safety(), "Locked morale must not create a personal panic goal.")

	alpha._issue_combined_arms_plan(bravo_actor, false)
	assert(String(alpha.get_blackboard().get_fact(&"tactical_plan")) == "SUPPRESS_AND_FLANK", "Combined-arms plan was not published.")
	var left_flank_count := 0
	var right_flank_count := 0
	for member in alpha.members:
		var role: SquadCombatRole.Type = member.actor.get_combat_role()
		var order := member.current_order
		assert(order != null, "A role received no combined-arms order.")
		match role:
			SquadCombatRole.Type.MACHINE_GUNNER:
				assert(order.type == SquadOrder.Type.SUPPRESS, "Machine gunner was not assigned suppression.")
			SquadCombatRole.Type.MARKSMAN:
				assert(order.type == SquadOrder.Type.OVERWATCH, "Marksman was not assigned overwatch.")
			SquadCombatRole.Type.SHOTGUNNER, SquadCombatRole.Type.PISTOL_SCOUT:
				if alpha._member_can_fire_from_cover(member, bravo_actor):
					assert(order.type == SquadOrder.Type.FOCUS_FIRE, "A mobile specialist abandoned effective cover to flank.")
				else:
					assert(order.type in [SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT], "An out-of-range mobile specialist was not assigned a flank.")
					assert(order.target_position != Vector2.ZERO, "Flank order has no tactical destination.")
					if order.type == SquadOrder.Type.FLANK_LEFT:
						left_flank_count += 1
					else:
						right_flank_count += 1
			_:
				assert(order.type == SquadOrder.Type.FOCUS_FIRE, "Rifleman was not assigned to fix the enemy.")
	if left_flank_count + right_flank_count > 0:
		assert(left_flank_count > 0 and right_flank_count > 0, "The plan did not use both flanks when maneuver was required.")
	var original_bravo_position := bravo_actor.global_position
	bravo_actor.global_position = Vector2(3200.0, original_bravo_position.y)
	alpha._issue_combined_arms_plan(bravo_actor, false)
	left_flank_count = 0
	right_flank_count = 0
	for member in alpha.members:
		if member.actor.get_combat_role() not in [SquadCombatRole.Type.SHOTGUNNER, SquadCombatRole.Type.PISTOL_SCOUT]:
			continue
		assert(member.current_order.type in [SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT], "An out-of-range mobile specialist remained in static fire mode.")
		if member.current_order.type == SquadOrder.Type.FLANK_LEFT:
			left_flank_count += 1
		else:
			right_flank_count += 1
	assert(left_flank_count > 0 and right_flank_count > 0, "Out-of-range specialists were not assigned to both flanks.")
	bravo_actor.global_position = original_bravo_position

	var shotgun_member := _find_role_member(alpha, SquadCombatRole.Type.SHOTGUNNER)
	var shotgun_actor := shotgun_member.actor
	bravo_actor.global_position = shotgun_actor.global_position + Vector2(40.0, 0.0)
	shotgun_actor.set("target", bravo_actor)
	assert(shotgun_actor.is_melee_engagement_needed(), "Close hostile contact did not activate melee GOAP.")
	shotgun_actor.begin_melee_engagement()
	assert(shotgun_actor.get("current_combat_weapon") is MeleeWeapon, "AI did not switch to its melee weapon.")
	bravo_actor.global_position = shotgun_actor.global_position + Vector2(180.0, 0.0)
	shotgun_actor.end_melee_engagement()
	assert(shotgun_actor.get("current_combat_weapon") is FirearmWeapon, "AI did not return to its firearm after melee range opened.")

	alpha._issue_covering_retreat(bravo_actor)
	assert(String(alpha.get_blackboard().get_fact(&"tactical_plan")) == "COVERING_RETREAT", "Retreat plan was not published.")
	var retreat_count := 0
	var rear_guard_count := 0
	for member in alpha.members:
		if member.current_order.type == SquadOrder.Type.RETREAT:
			retreat_count += 1
			assert(member.current_order.target_position != Vector2.ZERO, "Retreat order has no destination.")
		elif member.current_order.type == SquadOrder.Type.SUPPRESS:
			rear_guard_count += 1
	assert(retreat_count == 7 and rear_guard_count == 1, "Covering retreat did not leave exactly one rear guard.")

	assert(player.get("firearm_crosshair") is WeaponCrosshair, "Player firearm crosshair was not created.")
	var wall := scene.get_node("PlayerWall")
	assert(player.enter_cover(wall), "Player could not enter the overview test cover.")
	var cover_user := player.get("cover_user") as CoverUser
	var cover_position_before: Vector2 = player.global_position
	cover_user.move_along_cover(1.0, 1.0)
	assert(player.global_position.distance_to(cover_position_before) > 40.0, "Player cover movement range regressed.")
	player.exit_cover()

	var ai_panel := scene.get_node("CanvasLayer/AiDebugPanel") as Control
	var ai_label := scene.get_node("CanvasLayer/AiDebugPanel/MarginContainer/VBoxContainer/AiStateLabel") as Label
	assert(ai_panel.size.x <= 280.0, "AI debug panel is still too wide.")
	assert(ai_label.get_theme_font_size("font_size") <= 9, "AI debug text was not reduced.")
	assert(ai_label.text.contains("编成") and ai_label.text.contains("计划"), "Role-aware tactical HUD was not updated.")

	alpha._reset_contact_state()
	assert(int(alpha.get_blackboard().get_fact(&"hostile_alive_count", -1)) == 0, "Contact reset kept a stale hostile count.")
	assert(int(alpha.get_blackboard().get_fact(&"ambush_assigned_target_count", -1)) == 0, "Contact reset kept stale ambush targets.")
	assert(String(alpha.get_blackboard().get_fact(&"ambush_cover", "")) == "NONE", "Contact reset kept a stale ambush cover summary.")

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var battle_scene: Node = (load("res://tests/firearm_test/firearm_test_scene.tscn") as PackedScene).instantiate()
	battle_scene.name = "AutonomousRoleBattle"
	add_child(battle_scene)
	_configure_ambush_test_scenario(battle_scene)
	await get_tree().process_frame
	_configure_ambush_test_scenario(battle_scene)
	await get_tree().process_frame
	var battle_alpha := battle_scene.get_node("EnemySquadCoordinator") as SquadCoordinator
	var battle_bravo := battle_scene.get_node("EnemySquadCoordinatorBravo") as SquadCoordinator
	for second in 35:
		await get_tree().create_timer(1.0).timeout
	assert(_squad_fired_or_lost_member(battle_alpha), "Alpha never fired during the role battle soak.")
	assert(_squad_fired_or_lost_member(battle_bravo), "Bravo never fired during the role battle soak.")
	assert(bool(battle_scene.get("alpha_first_fire_observed")), "The autonomous ambush never produced an Alpha opening shot.")
	assert(bool(battle_scene.get("alpha_ambush_opened_all_in_cover")), "Alpha opened fire before the whole squad entered the blind-side cover.")
	assert(int(battle_scene.get("alpha_ambush_opened_cover_count")) >= 2, "The autonomous ambush did not use both viable blind-side covers.")
	assert(StringName(battle_scene.get("alpha_ambush_open_reason")) == &"aimed_ready", "Alpha opened the planned ambush before every shooter finished aiming.")
	var volley_fire_times := battle_scene.get("alpha_opening_volley_fire_msec") as Dictionary
	var volley_targets := battle_scene.get("alpha_opening_volley_targets") as Dictionary
	var volley_aim_quality := battle_scene.get("alpha_opening_volley_aim_quality") as Dictionary
	assert(volley_fire_times.size() == 8, "The synchronized opening volley did not include all eight Alpha shooters.")
	var earliest_volley_shot := 9223372036854775807
	var latest_volley_shot := 0
	for fire_msec in volley_fire_times.values():
		earliest_volley_shot = mini(earliest_volley_shot, int(fire_msec))
		latest_volley_shot = maxi(latest_volley_shot, int(fire_msec))
	assert(latest_volley_shot - earliest_volley_shot <= 50, "Alpha opening shots were not released as one coordinated volley.")
	var unique_volley_targets: Dictionary = {}
	for target_name in volley_targets.values():
		unique_volley_targets[target_name] = true
	assert(unique_volley_targets.size() == 8, "Alpha did not assign one opening-volley target per shooter.")
	for quality in volley_aim_quality.values():
		assert(float(quality) >= battle_alpha.ambush_aim_quality_required, "An Alpha shooter fired before reaching the required aim quality.")
	var volley_shot_counts := battle_scene.get("alpha_opening_volley_shot_counts") as Dictionary
	for actor_name in ["AlphaA", "AlphaB", "AlphaC", "AlphaMarksman", "AlphaMachineGunner", "AlphaShotgunNorth", "AlphaShotgunSouth", "AlphaScout"]:
		assert(int(volley_shot_counts.get(actor_name, 0)) >= 3, "%s did not execute the SMG opening burst." % actor_name)
	assert(bool(battle_scene.get("bravo_unaware_at_alpha_first_fire")), "Bravo detected Alpha before the opening shot.")
	assert(not bool(battle_scene.get("bravo_combat_order_before_alpha_fire")), "Bravo issued a combat order before Alpha attacked.")
	var bravo_eliminated_during_reaction := not _has_living_member(battle_bravo)
	assert(bool(battle_scene.get("bravo_responded_after_alpha_fire")) or bravo_eliminated_during_reaction, "Bravo neither responded after the ambush nor was eliminated during its reaction delay.")
	assert(int(battle_scene.get("bravo_surprise_reaction_count")) > 0, "No Bravo soldier entered the surprise reaction after the ambush shot.")
	var alpha_fire_msec := int(battle_scene.get("alpha_first_fire_msec"))
	var bravo_fire_msec := int(battle_scene.get("bravo_first_fire_msec"))
	assert(bravo_fire_msec == 0 or bravo_fire_msec - alpha_fire_msec >= 500, "Bravo returned fire before the minimum human reaction delay elapsed.")
	assert(_all_survivors_steady(battle_alpha) and _all_survivors_steady(battle_bravo), "A test soldier left STEADY during autonomous combat.")

	print("Role battle smoke test passed: 8v8 loadouts, melee, morale lock, role orders, flanks, retreat, camera, HUD, and autonomous fire verified.")
	get_tree().quit(0)

func _configure_ambush_test_scenario(scene: Node) -> void:
	var alpha := scene.get_node("EnemySquadCoordinator") as SquadCoordinator
	var bravo := scene.get_node("EnemySquadCoordinatorBravo") as SquadCoordinator
	alpha.allow_silent_ambush = true
	alpha.ambush_ready_ratio_required = 1.0
	alpha.search_direction_override = Vector2.RIGHT
	bravo.allow_silent_ambush = true
	bravo.hold_search_until_first_contact = true
	bravo.search_direction_override = Vector2.ZERO
	for actor in alpha.get_configured_member_actors() + bravo.get_configured_member_actors():
		var soldier := actor as GoblinBase
		soldier.initial_facing_direction = Vector2.RIGHT
		soldier.last_move_dir = Vector2.RIGHT
	if not alpha.members.is_empty():
		alpha._issue_search_sweep()
	if not bravo.members.is_empty():
		bravo._issue_search_sweep()

func _assert_mutual_encounter_config(scene: Node) -> void:
	var alpha := scene.get_node("EnemySquadCoordinator") as SquadCoordinator
	var bravo := scene.get_node("EnemySquadCoordinatorBravo") as SquadCoordinator
	assert(not alpha.allow_silent_ambush and not bravo.allow_silent_ambush, "The playable scene still permits a silent ambush.")
	assert(not bravo.hold_search_until_first_contact, "Bravo still waits motionless for an ambush.")
	assert(alpha.search_direction_override.is_equal_approx(Vector2.RIGHT), "Alpha does not search toward Bravo.")
	assert(bravo.search_direction_override.is_equal_approx(Vector2.LEFT), "Bravo does not search toward Alpha.")
	assert(alpha.get_member_count() == 8 and bravo.get_member_count() == 8, "The playable battle is not authored as two eight-member Group rosters.")
	for child in scene.get_children():
		assert(not child is GoblinBase, "The playable battle still contains a hand-placed root soldier: %s" % child.name)
	for actor in alpha.get_configured_member_actors() + bravo.get_configured_member_actors():
		var soldier := actor as GoblinBase
		if soldier.combat_team == &"alpha":
			assert(soldier.initial_facing_direction.x > 0.0, "An Alpha soldier does not face the encounter.")
		elif soldier.combat_team == &"bravo":
			assert(soldier.initial_facing_direction.x < 0.0, "A Bravo soldier does not face the encounter.")

func _assert_role_composition(coordinator: SquadCoordinator) -> void:
	var actual: Dictionary = {}
	for member in coordinator.members:
		var role: SquadCombatRole.Type = member.actor.get_combat_role()
		actual[role] = int(actual.get(role, 0)) + 1
	for role in EXPECTED_ROLE_COUNTS:
		assert(int(actual.get(role, 0)) == int(EXPECTED_ROLE_COUNTS[role]), "Unexpected role composition for %s." % SquadCombatRole.get_label(role))

func _assert_member_loadout(member: SquadMember) -> void:
	var actor := member.actor
	var role: SquadCombatRole.Type = actor.get_combat_role()
	var firearm := actor.get("firearm_weapon") as FirearmWeapon
	assert(firearm != null, "A combat role has no firearm.")
	assert(is_equal_approx(float(actor.get("attack_range")), firearm.weapon_data.effective_range), "AI fire authorization is not synchronized with WeaponData effective range.")
	assert(firearm.weapon_data.projectile_speed * firearm.weapon_data.projectile_lifetime >= firearm.weapon_data.effective_range, "A projectile expires before reaching its weapon's effective range.")
	if actor.get_combat_team() == &"alpha":
		assert(firearm is SmgWeapon and firearm.weapon_data.weapon_name == "Tactical SMG", "An Alpha soldier does not use the scenario SMG loadout.")
	else:
		match role:
			SquadCombatRole.Type.MARKSMAN:
				assert(firearm is BoltActionRifleWeapon, "Marksman does not use BoltActionRifleWeapon.")
			SquadCombatRole.Type.MACHINE_GUNNER:
				assert(firearm is LmgWeapon, "Machine gunner does not use LmgWeapon.")
			SquadCombatRole.Type.SHOTGUNNER:
				assert(firearm is ShotgunWeapon and firearm.weapon_data.projectile_count > 1, "Shotgunner does not use a pellet shotgun.")
			SquadCombatRole.Type.PISTOL_SCOUT:
				assert(firearm is PistolWeapon, "Pistol scout does not use PistolWeapon.")
			_:
				assert(firearm is RifleWeapon, "Rifleman does not use RifleWeapon.")
	assert(actor.get("melee_weapon") is MeleeWeapon, "Every AI role must carry a melee weapon.")
	assert(actor.find_child("MeleeEngageAction", true, false) is MeleeEngageAction, "Every AI role must have melee GOAP.")
	assert(actor.get("goap_agent") is GoapAgent, "A combat role has no GOAP agent.")
	assert(actor.get("perception_component") is PerceptionComponent, "A combat role has no finite perception component.")
	assert(actor.get("alert_component") is AlertComponent, "A combat role has no cognitive alert component.")
	var will := actor.get("will_component") as WillComponent
	assert(will != null and will.lock_to_steady and will.mental_state == WillComponent.MentalState.STEADY, "Test morale is not locked to STEADY.")
	var role_label := actor.get_node("SquadRoleLabel") as Label
	assert(role_label.get_theme_font_size("font_size") >= 17, "Overview overhead role text is too small.")

func _assert_injury_damage_model() -> void:
	var injury := InjuryComponent.new()
	for fatal_location in [InjuryComponent.HitLocation.HEAD, InjuryComponent.HitLocation.HEART]:
		var fatal_hit := injury.resolve_hit(1, fatal_location, 10)
		assert(bool(fatal_hit.get("fatal", false)), "A head or heart hit was not fatal.")
	var torso_hit := injury.resolve_hit(1, InjuryComponent.HitLocation.TORSO, 10)
	assert(not bool(torso_hit.get("fatal", false)), "A torso hit was incorrectly treated as instantly fatal.")
	assert(ceili(10.0 / float(torso_hit.get("damage", 1))) in [2, 3], "Torso damage does not kill in two to three hits.")
	for max_hp in [7, 8, 10]:
		var arm_hit := injury.resolve_hit(1, InjuryComponent.HitLocation.ARM, max_hp)
		var leg_hit := injury.resolve_hit(1, InjuryComponent.HitLocation.LEG, max_hp)
		var arm_shots := ceili(float(max_hp) / float(arm_hit.get("damage", 1)))
		var leg_shots := ceili(float(max_hp) / float(leg_hit.get("damage", 1)))
		assert(arm_shots >= 2 and arm_shots <= 3, "Arm damage does not kill in two to three hits.")
		assert(leg_shots >= 2 and leg_shots <= 3, "Leg damage does not kill in two to three hits.")

func _assert_aim_model() -> void:
	var aim := AimComponent.new()
	assert(is_equal_approx(aim.get_spread_multiplier(false), 3.0), "Stationary hip-fire spread is incorrect.")
	assert(is_equal_approx(aim.get_spread_multiplier(true), 5.25), "Moving hip-fire spread is incorrect.")
	aim.set_aiming(true)
	assert(is_equal_approx(aim.get_spread_multiplier(false), 3.0), "Aiming became perfectly accurate without settling time.")
	aim.process(aim.aim_settle_time, false)
	assert(aim.is_settled() and is_equal_approx(aim.get_spread_multiplier(false), 1.0), "Stationary aim did not converge.")
	aim.report_shot()
	assert(aim.get_spread_multiplier(false) > 1.0, "Weapon recoil did not increase follow-up spread.")
	aim.process(2.0, false)
	assert(is_equal_approx(aim.get_spread_multiplier(false), 1.0), "Weapon recoil did not recover.")
	aim.reset_aim()
	aim.process(1.5, true)
	assert(is_equal_approx(aim.get_spread_multiplier(true), 1.5), "Moving aimed spread did not converge to its penalty.")
	assert(is_equal_approx(aim.get_movement_speed_multiplier(), 0.55), "Aiming does not reduce movement speed.")
	aim.free()

func _assert_sight_profiles(coordinator: SquadCoordinator) -> void:
	for member in coordinator.members:
		var actor = member.actor
		var perception := actor.get("perception_component") as PerceptionComponent
		actor.set_weapon_aiming(false)
		assert(is_equal_approx(perception.sight_range, 1800.0), "An AI role has a non-standard base sight range.")
		assert(is_equal_approx(perception.field_of_view_degrees, 110.0), "An AI role has a non-standard base field of view.")
		actor.set_weapon_aiming(true)
		if actor.get_combat_role() == SquadCombatRole.Type.MARKSMAN:
			assert(is_equal_approx(perception.sight_range, 3000.0), "Aiming marksman sight range was not extended.")
			assert(is_equal_approx(perception.field_of_view_degrees, 35.0), "Aiming marksman field of view was not narrowed.")
		else:
			assert(is_equal_approx(perception.sight_range, 1800.0), "Aiming changed a non-marksman sight range.")
			assert(is_equal_approx(perception.field_of_view_degrees, 110.0), "Aiming changed a non-marksman field of view.")
		actor.set_weapon_aiming(false)

func _assert_bush_concealment(scene: Node, player: Node) -> void:
	var bush := scene.get_node("PlayerBush") as Bush
	assert(bush != null, "The firearm test scene has no player bush.")
	assert(not bush.is_in_group("projectile_blocker"), "Bushes must not block projectiles.")
	assert(player.is_visually_concealed(), "The player did not register the overlapping bush concealment.")
	player.reveal_from_concealment()
	assert(not player.is_visually_concealed(), "Firing reveal did not disable bush concealment.")
	(player.get("concealment_component") as ConcealmentComponent).reveal_timer = 0.0
	assert(player.is_visually_concealed(), "Bush concealment did not resume after the reveal timer.")

func _assert_concealment_perception() -> void:
	var observer := PerceptionProbe.new()
	var target := ConcealedProbe.new()
	var alert := AlertComponent.new()
	var perception := PerceptionComponent.new()
	observer.hostile = target
	observer.global_position = Vector2.ZERO
	target.global_position = Vector2(220.0, 0.0)
	add_child(observer)
	add_child(target)
	observer.add_child(alert)
	observer.add_child(perception)
	perception.setup(observer, alert)
	assert(not perception.evaluate_candidate(target, 1.0), "A concealed hostile was visually confirmed.")
	assert(perception.get_contact(target) == null, "Visual concealment incorrectly created a combat contact.")
	perception.hear_stimulus(target.global_position, target, 1.0)
	assert(perception.get_contact(target) != null, "A concealed hostile gunshot did not create an auditory contact.")
	observer.queue_free()
	target.queue_free()

func _find_role_member(coordinator: SquadCoordinator, role: SquadCombatRole.Type) -> SquadMember:
	for member in coordinator.members:
		if member.actor.get_combat_role() == role:
			return member
	return null

func _squad_fired_or_lost_member(coordinator: SquadCoordinator) -> bool:
	if coordinator.members.size() < 8:
		return true
	for member in coordinator.members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			return true
		var weapon := member.actor.get("firearm_weapon") as FirearmWeapon
		if weapon and weapon.get_total_ammo() < weapon.weapon_data.magazine_size + weapon.weapon_data.reserve_ammo:
			return true
	return false

func _all_survivors_steady(coordinator: SquadCoordinator) -> bool:
	for member in coordinator.members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var will := member.actor.get("will_component") as WillComponent
		if will == null or will.mental_state != WillComponent.MentalState.STEADY:
			return false
	return true

func _has_living_member(coordinator: SquadCoordinator) -> bool:
	for member in coordinator.members:
		if is_instance_valid(member) and is_instance_valid(member.actor) and int(member.actor.get("health")) > 0:
			return true
	return false

func _assert_dead_observer_report_is_discarded() -> void:
	var coordinator := SquadCoordinator.new()
	coordinator.name = "DeadObserverReportCoordinator"
	coordinator.auto_discover_members = false
	coordinator.squad_id = &"dead_report_test"
	add_child(coordinator)
	var actor := Node2D.new()
	actor.name = "TemporaryObserverActor"
	add_child(actor)
	var member := SquadMember.new()
	member.name = "TemporaryObserverMember"
	add_child(member)
	member.setup(actor, &"dead_report_test")
	coordinator.register_member(member)
	var target := Node2D.new()
	target.name = "TemporaryContactTarget"
	add_child(target)
	var contact := CombatContact.new()
	contact.target = target
	contact.observer = actor
	contact.update_visual(Vector2(100.0, 0.0), 1.0, false)
	coordinator.report_contact(member, contact, 0.0)
	actor.queue_free()
	await get_tree().process_frame
	coordinator._process_contact_reports()
	assert(coordinator.get_blackboard().shared_target == null, "A dead observer transmitted its queued contact report.")
	member.queue_free()
	target.queue_free()
	coordinator.queue_free()
