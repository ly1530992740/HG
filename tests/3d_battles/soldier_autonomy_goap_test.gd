extends Node

const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")

var _case_count := 0
var _failure_count := 0

func _ready() -> void:
	await get_tree().process_frame
	await _test_idle_security()
	await _test_friendly_sound_is_ignored()
	await _test_nearby_hostile_sound_is_immediate()
	await _test_nearby_cover_is_preferred()
	await _test_no_cover_falls_prone()
	await _test_survival_interrupts_directive()
	await _test_directive_resumes_after_protection()
	await _test_visible_contact_return_fire_plan()
	await _test_empty_magazine_adds_reload()
	await _test_unseen_contact_scans_without_fire()
	await _test_same_visible_contact_does_not_reset_response()
	await _test_autonomy_never_approaches_target()
	if _failure_count > 0 or _case_count != 12:
		push_error("SOLDIER_AUTONOMY_GOAP_FAIL cases=%d failures=%d" % [_case_count, _failure_count])
		get_tree().quit(1)
		return
	print("SOLDIER_AUTONOMY_GOAP_PASS cases=%d" % _case_count)
	await get_tree().process_frame
	get_tree().quit()

func _test_idle_security() -> void:
	var soldier := await _spawn_soldier("Idle", Soldier3D.Team.BLUE, Vector3.ZERO)
	_plan(soldier)
	var goal := _current_autonomy_goal(soldier)
	_expect(goal != null and goal.kind == SoldierAutonomyGoal3D.Kind.MAINTAIN_SECURITY,
		"No threat and no directive must select MAINTAIN_SECURITY")
	_expect(_autonomy_operations(soldier) == [SoldierAutonomyAction3D.Operation.GUARD_SECTOR],
		"Idle security must only observe its sector")
	_pass_case()
	await _remove_nodes([soldier])

func _test_friendly_sound_is_ignored() -> void:
	var soldier := await _spawn_soldier("Listener", Soldier3D.Team.BLUE, Vector3.ZERO)
	var friendly := await _spawn_soldier("Friendly", Soldier3D.Team.BLUE, Vector3(0, 0, -8))
	soldier.hear_combat_sound(friendly.global_position, friendly)
	_expect(float(soldier.get("_threat_memory_timer")) <= 0.0,
		"Friendly gunfire must not create a hostile threat memory")
	_pass_case()
	await _remove_nodes([soldier, friendly])

func _test_nearby_hostile_sound_is_immediate() -> void:
	var soldier := await _spawn_soldier("Listener", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0, 0, -8))
	soldier.hear_combat_sound(hostile.global_position, hostile)
	_expect(float(soldier.get("_immediate_threat_timer")) > 0.0,
		"Nearby hostile gunfire must create an immediate threat")
	_expect(not bool(soldier.get("_contact_response_complete")),
		"A new hostile sound must open one contact-response cycle")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_nearby_cover_is_preferred() -> void:
	var soldier := await _spawn_soldier("CoverUser", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0, 0, -10))
	var blocked_cover := TacticalCover3D.new()
	blocked_cover.name = "WrongSideCover"
	blocked_cover.position = Vector3(0, 0, 1)
	add_child(blocked_cover)
	var cover := TacticalCover3D.new()
	cover.name = "EmergencyCover"
	cover.position = Vector3(0, 0, -3)
	add_child(cover)
	await get_tree().process_frame
	soldier.notify_near_miss(hostile.global_position, hostile)
	_plan(soldier)
	var operations := _autonomy_operations(soldier)
	_expect(operations.has(SoldierAutonomyAction3D.Operation.SEEK_COVER),
		"Reachable nearby cover must be preferred over dropping in the open")
	_expect(not operations.has(SoldierAutonomyAction3D.Operation.DROP_PRONE),
		"The cheapest survival plan must not drop prone when nearby cover is usable")
	_expect(soldier.get("_autonomy_cover_candidate") == cover,
		"Cover selection must skip a nearer slot that requires crossing the wall")
	_pass_case()
	await _remove_nodes([soldier, hostile, blocked_cover, cover])

func _test_no_cover_falls_prone() -> void:
	var soldier := await _spawn_soldier("Exposed", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0, 0, -10))
	soldier.notify_near_miss(hostile.global_position, hostile)
	_plan(soldier)
	_expect(_autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.DROP_PRONE),
		"An exposed soldier with no usable cover must drop prone")
	_agent(soldier).process(0.1)
	_expect(soldier.stance == Soldier3D.Stance.PRONE,
		"DROP_PRONE must change the runtime stance, not only the GOAP world state")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_survival_interrupts_directive() -> void:
	var soldier := await _spawn_soldier("Ordered", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0, 0, -10))
	soldier.receive_directive(SquadDirective3D.new().configure(
		SquadDirective3D.Type.GUARD, 1, null, Vector3.ZERO))
	soldier.receive_hit(1, "body", soldier.global_position, hostile)
	_plan(soldier)
	var goal := _current_autonomy_goal(soldier)
	_expect(goal != null and goal.kind == SoldierAutonomyGoal3D.Kind.SURVIVE_THREAT,
		"A hit must select SURVIVE_THREAT above the active squad directive")
	_expect(goal != null and goal.get_priority() > 100, "Survival must outrank the directive goal")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_directive_resumes_after_protection() -> void:
	var soldier := await _spawn_soldier("Ordered", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0, 0, -10))
	soldier.receive_directive(SquadDirective3D.new().configure(
		SquadDirective3D.Type.GUARD, 1, null, Vector3.ZERO))
	soldier.notify_near_miss(hostile.global_position, hostile)
	_plan(soldier)
	_agent(soldier).process(0.1)
	soldier._sync_dynamic_goap_state()
	_agent(soldier).process(0.0)
	_expect(_agent(soldier).get_current_goal() is SoldierDirectiveGoal3D,
		"Once protected, the soldier must return control to the existing directive")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_visible_contact_return_fire_plan() -> void:
	var pair := await _spawn_visible_pair("ReturnFire")
	var soldier := pair[0] as Soldier3D
	var hostile := pair[1] as Soldier3D
	_prepare_protected_visible_contact(soldier, hostile)
	var operations := _autonomy_operations(soldier)
	_expect(operations.has(SoldierAutonomyAction3D.Operation.ACQUIRE_VISIBLE_TARGET),
		"Visible contact response must explicitly confirm its target")
	_expect(operations.has(SoldierAutonomyAction3D.Operation.AIM),
		"Visible contact response must aim before firing")
	_expect(operations.has(SoldierAutonomyAction3D.Operation.RETURN_FIRE),
		"Visible in-range contact must produce a short return-fire action")
	var fired := [0]
	soldier.weapon_fired.connect(func(_actor, _target): fired[0] += 1)
	soldier.set("_reaction_timer", 0.0)
	for _step in 16:
		_agent(soldier).process(0.25)
		if bool(soldier.get("_contact_response_complete")):
			break
	_expect(int(fired[0]) >= 1, "The planned return-fire chain must execute at least one shot")
	_expect(bool(soldier.get("_contact_response_complete")),
		"Short return fire must close its response cycle instead of firing forever")
	_pass_case()
	await _remove_nodes(pair)

func _test_empty_magazine_adds_reload() -> void:
	var pair := await _spawn_visible_pair("Reload")
	var soldier := pair[0] as Soldier3D
	var hostile := pair[1] as Soldier3D
	soldier.magazine_ammo = 0
	soldier.reserve_ammo = 20
	_prepare_protected_visible_contact(soldier, hostile)
	_expect(_autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.RELOAD_COVERED),
		"An empty magazine must insert covered reload before return fire")
	_pass_case()
	await _remove_nodes(pair)

func _test_unseen_contact_scans_without_fire() -> void:
	var soldier := await _spawn_soldier("Scanner", Soldier3D.Team.BLUE, Vector3.ZERO)
	soldier.call("_register_autonomy_threat", Vector3(8, 0, 0), null, 0.45, false)
	_plan(soldier)
	var operations := _autonomy_operations(soldier)
	_expect(operations.has(SoldierAutonomyAction3D.Operation.ORIENT_TO_THREAT),
		"An unseen sound must orient the soldier toward the threat sector")
	_expect(operations.has(SoldierAutonomyAction3D.Operation.SCAN_THREAT_SECTOR),
		"An unseen sound must produce a sector scan")
	_expect(not operations.has(SoldierAutonomyAction3D.Operation.RETURN_FIRE),
		"An unseen shooter must never produce blind targeted fire")
	_pass_case()
	await _remove_nodes([soldier])

func _test_same_visible_contact_does_not_reset_response() -> void:
	var pair := await _spawn_visible_pair("NoLoop")
	var soldier := pair[0] as Soldier3D
	var hostile := pair[1] as Soldier3D
	soldier.call("_register_autonomy_threat", hostile.global_position, hostile, 1.0, true)
	soldier.set("_contact_response_complete", true)
	soldier.set("_reaction_timer", 0.1)
	_agent(soldier).get_world_state().set_state(&"contact_response_complete", true)
	soldier.call("_register_autonomy_threat", hostile.global_position, hostile, 1.0, true)
	_expect(bool(soldier.get("_contact_response_complete")),
		"Repeated scans of the same active contact must not restart autonomous fire")
	_expect(not soldier.is_autonomy_goal_valid(SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT),
		"The same remembered target must remain a completed response")
	_expect(is_equal_approx(float(soldier.get("_reaction_timer")), 0.1),
		"Repeated scans of the same contact must not restart reaction delay")
	_pass_case()
	await _remove_nodes(pair)

func _test_autonomy_never_approaches_target() -> void:
	var pair := await _spawn_visible_pair("NoChase")
	var soldier := pair[0] as Soldier3D
	var hostile := pair[1] as Soldier3D
	soldier.combat_role = Soldier3D.CombatRole.SHOTGUNNER
	soldier.weapon_component.configure(Soldier3D.CombatRole.SHOTGUNNER, int(soldier.combat_team))
	hostile.global_position = Vector3(0, 0, -25)
	await get_tree().physics_frame
	soldier.set_stance(Soldier3D.Stance.PRONE)
	soldier.call("_register_autonomy_threat", hostile.global_position, hostile, 1.0, true)
	soldier._sync_dynamic_goap_state()
	_plan(soldier)
	for item in _agent(soldier).get("_current_plan") as Array:
		_expect(not item is SoldierDirectiveAction3D,
			"Autonomous plans must not borrow directive movement or APPROACH_TARGET actions")
	_expect(not _autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.RETURN_FIRE),
		"An out-of-range autonomous contact must scan and wait instead of chasing")
	_pass_case()
	await _remove_nodes(pair)

func _spawn_visible_pair(prefix: String) -> Array:
	var soldier := await _spawn_soldier(prefix + "Soldier", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier(prefix + "Hostile", Soldier3D.Team.RED, Vector3(0, 0, -8))
	await get_tree().physics_frame
	_expect(soldier.perception_component.can_see(hostile), "Test setup must provide a visible hostile")
	return [soldier, hostile]

func _prepare_protected_visible_contact(soldier: Soldier3D, hostile: Soldier3D) -> void:
	soldier.set_stance(Soldier3D.Stance.PRONE)
	soldier.call("_register_autonomy_threat", hostile.global_position, hostile, 1.0, true)
	soldier._sync_dynamic_goap_state()
	_plan(soldier)

func _spawn_soldier(node_name: String, team: Soldier3D.Team, position_value: Vector3) -> Soldier3D:
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	soldier.name = node_name
	soldier.combat_team = team
	soldier.awards_player_score = false
	soldier.drops_ammo_on_death = false
	soldier.position = position_value
	soldier.set_physics_process(false)
	add_child(soldier)
	await get_tree().process_frame
	return soldier

func _plan(soldier: Soldier3D) -> void:
	_agent(soldier).process(0.0)

func _agent(soldier: Soldier3D) -> GoapAgent:
	return soldier.get("_goap_agent") as GoapAgent

func _current_autonomy_goal(soldier: Soldier3D) -> SoldierAutonomyGoal3D:
	return _agent(soldier).get_current_goal() as SoldierAutonomyGoal3D

func _autonomy_operations(soldier: Soldier3D) -> Array[int]:
	var result: Array[int] = []
	for item in _agent(soldier).get("_current_plan") as Array:
		if item is SoldierAutonomyAction3D:
			result.append((item as SoldierAutonomyAction3D).operation)
	return result

func _pass_case() -> void:
	_case_count += 1

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error("CASE FAILURE: %s" % message)

func _remove_nodes(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			(node as Node).queue_free()
	await get_tree().process_frame
