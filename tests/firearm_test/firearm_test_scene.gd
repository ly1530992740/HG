extends Node2D

@onready var player: Node2D = $Player
@onready var battle_camera: Camera2D = $BattleCamera
@onready var alpha_coordinator: SquadCoordinator = $EnemySquadCoordinator
@onready var bravo_coordinator: SquadCoordinator = $EnemySquadCoordinatorBravo
@onready var ammo_label: Label = $CanvasLayer/Hud/VBoxContainer/AmmoLabel
@onready var enemy_label: Label = $CanvasLayer/Hud/VBoxContainer/EnemyLabel
@onready var status_label: Label = $CanvasLayer/Hud/VBoxContainer/StatusLabel
@onready var ai_state_label: Label = $CanvasLayer/AiDebugPanel/MarginContainer/VBoxContainer/AiStateLabel

@export var verbose_battle_trace := false

var enemies: Array[Node] = []
var initial_team_counts: Dictionary = {}
var ai_hud_timer := 0.0
var battle_trace_timer := 0.0
var battle_started_msec := 0
var battle_trace_file: FileAccess = null
var trace_state_cache: Dictionary = {}
var ambush_member_state_cache: Dictionary = {}
var traced_actor_fire: Dictionary = {}
var prefire_guard_timer := 0.0
var trace_flush_timer := 0.0
var alpha_ambush_opened_all_in_cover := false
var alpha_ambush_opened_cover_count := 0
var alpha_first_fire_observed := false
var bravo_unaware_at_alpha_first_fire := false
var bravo_combat_order_before_alpha_fire := false
var bravo_responded_after_alpha_fire := false
var alpha_first_fire_msec := 0
var bravo_first_fire_msec := 0
var bravo_surprise_reaction_count := 0
var alpha_opening_volley_fire_msec: Dictionary = {}
var alpha_opening_volley_targets: Dictionary = {}
var alpha_opening_volley_aim_quality: Dictionary = {}
var alpha_opening_volley_shot_counts: Dictionary = {}
var alpha_ambush_open_reason: StringName = &""

func _ready() -> void:
	battle_started_msec = Time.get_ticks_msec()
	var trace_path := ProjectSettings.globalize_path("res://.godot/ambush_timeline.log")
	battle_trace_file = FileAccess.open(trace_path, FileAccess.WRITE)
	_trace_event("SCENARIO_START", {
		"alpha": "search east",
		"bravo": "hold facing east",
		"cover": "multi blind-side assignment",
		"required_ready": "100%",
	})
	GlobalPlayer.set_active_pawn(player)
	var player_camera := player.get_node_or_null("Camera2D") as Camera2D
	if player_camera:
		player_camera.enabled = false
	battle_camera.enabled = true
	battle_camera.global_position = player.global_position
	call_deferred("_bind_player_weapon")
	_bind_enemies()
	_bind_squad_trace(alpha_coordinator)
	_bind_squad_trace(bravo_coordinator)
	status_label.text = "WASD | C掩体 | Space精确 | F/Q射击 | R装弹"

func _process(delta: float) -> void:
	if is_instance_valid(player) and is_instance_valid(battle_camera):
		battle_camera.global_position = player.global_position
	battle_trace_timer -= delta
	if battle_trace_timer <= 0.0:
		battle_trace_timer = 0.5
		_trace_squad_state(alpha_coordinator)
		_trace_squad_state(bravo_coordinator)
		_trace_alpha_ambush_members()
	prefire_guard_timer -= delta
	if not alpha_first_fire_observed and prefire_guard_timer <= 0.0:
		prefire_guard_timer = 2.0
		_trace_prefire_guard()
	ai_hud_timer -= delta
	if ai_hud_timer <= 0.0:
		ai_hud_timer = 0.35
		_update_enemy_hud()
		_update_ai_state_hud()
	trace_flush_timer -= delta
	if battle_trace_file and trace_flush_timer <= 0.0:
		trace_flush_timer = 1.0
		battle_trace_file.flush()

func _bind_player_weapon() -> void:
	var weapon := player.get("firearm_weapon") as FirearmWeapon
	if weapon == null:
		ammo_label.text = "Weapon: not ready"
		return

	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.attack_failed.connect(_on_weapon_attack_failed)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.cycle_started.connect(_on_weapon_cycle_started)
	weapon.cycle_finished.connect(_on_weapon_cycle_finished)
	weapon.weapon_changed.connect(_on_weapon_changed)
	_on_ammo_changed(weapon.magazine_ammo, weapon.reserve_ammo)
	_on_weapon_changed(weapon.weapon_data)

func _bind_enemies() -> void:
	enemies.clear()
	for node in get_tree().get_nodes_in_group("goblin"):
		if node is Node and is_ancestor_of(node):
			enemies.append(node)
	initial_team_counts.clear()
	for enemy in enemies:
		var team: StringName = enemy.get_combat_team() if enemy.has_method("get_combat_team") else &"unknown"
		initial_team_counts[team] = int(initial_team_counts.get(team, 0)) + 1
		var perception := enemy.get("perception_component") as PerceptionComponent
		if perception and not perception.contact_confirmed.is_connected(_on_local_contact_confirmed):
			perception.contact_confirmed.connect(_on_local_contact_confirmed.bind(enemy))
		var alert := enemy.get("alert_component") as AlertComponent
		if alert and not alert.state_changed.is_connected(_on_actor_alert_changed):
			alert.state_changed.connect(_on_actor_alert_changed.bind(enemy))
		var weapon := enemy.get("firearm_weapon") as FirearmWeapon
		if weapon and not weapon.fired.is_connected(_on_ai_weapon_fired):
			weapon.fired.connect(_on_ai_weapon_fired.bind(enemy))
		if enemy.has_signal("died") and not enemy.died.is_connected(_on_traced_actor_died):
			enemy.died.connect(_on_traced_actor_died)
		if enemy.has_signal("surprise_reaction_started") and not enemy.surprise_reaction_started.is_connected(_on_surprise_reaction_started):
			enemy.surprise_reaction_started.connect(_on_surprise_reaction_started.bind(enemy))
	_update_enemy_hud()

	if player.has_signal("died"):
		player.connect("died", _on_player_died)

func _bind_squad_trace(coordinator: SquadCoordinator) -> void:
	if coordinator == null:
		return
	coordinator.contact_report_queued.connect(_on_contact_report_queued.bind(coordinator))
	coordinator.contact_report_accepted.connect(_on_contact_report_accepted.bind(coordinator))
	coordinator.order_issued.connect(_on_traced_order_issued.bind(coordinator))
	coordinator.ambush_opened.connect(_on_ambush_opened.bind(coordinator))

func _on_local_contact_confirmed(contact: CombatContact, observer: Node2D) -> void:
	if not verbose_battle_trace:
		return
	_trace_event("LOCAL_CONTACT", {
		"team": observer.get_combat_team() if observer.has_method("get_combat_team") else &"unknown",
		"observer": observer.name,
		"target": contact.target.name if contact.is_valid() else "INVALID",
		"stimulus": contact.stimulus_type,
		"target_aware": contact.estimated_enemy_awareness,
	})

func _on_contact_report_queued(observer: SquadMember, contact: CombatContact, coordinator: SquadCoordinator) -> void:
	if not verbose_battle_trace:
		return
	_trace_event("REPORT_QUEUED", {
		"team": coordinator.squad_id,
		"observer": observer.actor.name if is_instance_valid(observer.actor) else "INVALID",
		"target": contact.target.name if contact.is_valid() else "INVALID",
		"stimulus": contact.stimulus_type,
	})

func _on_contact_report_accepted(observer: SquadMember, contact: CombatContact, coordinator: SquadCoordinator) -> void:
	if not verbose_battle_trace and coordinator.get_contact_phase() != SquadCoordinator.ContactPhase.SEARCH:
		return
	_trace_event("REPORT_ACCEPTED", {
		"team": coordinator.squad_id,
		"observer": observer.actor.name if is_instance_valid(observer.actor) else "INVALID",
		"target": contact.target.name if contact.is_valid() else "INVALID",
		"target_aware": contact.estimated_enemy_awareness,
	})

func _on_traced_order_issued(order: SquadOrder, coordinator: SquadCoordinator) -> void:
	var recipients: PackedStringArray = []
	for recipient in order.recipients:
		if recipient is SquadMember and is_instance_valid(recipient.actor):
			recipients.append(recipient.actor.name)
	if verbose_battle_trace or order.type == SquadOrder.Type.AMBUSH_POSITION:
		_trace_event("ORDER", {
			"team": coordinator.squad_id,
			"type": order.get_type_name(),
			"recipients": ",".join(recipients) if not recipients.is_empty() else "ALL",
			"cover": order.assigned_cover.name if is_instance_valid(order.assigned_cover) else "NONE",
		})
	if coordinator.squad_id == &"bravo" and order.type != SquadOrder.Type.HOLD:
		if alpha_first_fire_observed:
			if not bravo_responded_after_alpha_fire:
				_trace_event("BRAVO_RESPONSE_CONFIRMED", {"order": order.get_type_name()})
			bravo_responded_after_alpha_fire = true
		else:
			bravo_combat_order_before_alpha_fire = true
			_trace_event("INVARIANT_VIOLATION", {"rule": "bravo ordered before alpha fire", "order": order.get_type_name()})

func _on_ambush_opened(_target: Node2D, reason: StringName, coordinator: SquadCoordinator) -> void:
	var all_in_cover := not coordinator.members.is_empty()
	for member in coordinator.members:
		var assigned_cover := coordinator.get_ambush_cover_for(member)
		if not is_instance_valid(member) or not is_instance_valid(member.actor) or not is_instance_valid(assigned_cover) or member.actor.get_active_cover() != assigned_cover:
			all_in_cover = false
			break
	if coordinator.squad_id == &"alpha":
		alpha_ambush_opened_all_in_cover = all_in_cover
		alpha_ambush_opened_cover_count = coordinator.get_active_ambush_covers().size()
		alpha_ambush_open_reason = reason
	_trace_event("AMBUSH_OPEN", {
		"team": coordinator.squad_id,
		"reason": reason,
		"ready": "%.0f%%" % (float(coordinator.get_blackboard().get_fact(&"ambush_ready_ratio", 0.0)) * 100.0),
		"cover": coordinator.get_blackboard().get_fact(&"ambush_cover", "NONE"),
		"all_in_cover": all_in_cover,
	})

func _on_actor_alert_changed(previous: AlertComponent.State, current: AlertComponent.State, actor: Node2D) -> void:
	if not verbose_battle_trace and current != AlertComponent.State.COMBAT:
		return
	_trace_event("ALERT", {
		"team": actor.get_combat_team() if actor.has_method("get_combat_team") else &"unknown",
		"actor": actor.name,
		"from": AlertComponent.State.keys()[previous],
		"to": AlertComponent.State.keys()[current],
	})

func _on_ai_weapon_fired(actor: Node2D) -> void:
	var firing_team: StringName = actor.get_combat_team() if actor.has_method("get_combat_team") else &"unknown"
	var actor_member := actor.get("squad_member") as SquadMember
	var actor_order := actor_member.get_current_order() if actor_member else null
	var fire_target := actor_order.target if actor_order != null and is_instance_valid(actor_order.target) else null
	var weapon := actor.get("firearm_weapon") as FirearmWeapon
	var final_spread := weapon.last_shot_spread_degrees if weapon != null else -1.0
	var aim_quality := float(actor.get_aim_quality()) if actor.has_method("get_aim_quality") else 0.0
	if firing_team == &"alpha" and String(alpha_coordinator.get_blackboard().get_fact(&"tactical_plan", "")) == "AMBUSH_VOLLEY" and not alpha_opening_volley_fire_msec.has(actor):
		alpha_opening_volley_fire_msec[actor] = Time.get_ticks_msec()
		alpha_opening_volley_targets[actor] = fire_target.name if is_instance_valid(fire_target) else "NONE"
		alpha_opening_volley_aim_quality[actor] = aim_quality
	if firing_team == &"alpha" and String(alpha_coordinator.get_blackboard().get_fact(&"tactical_plan", "")) == "AMBUSH_VOLLEY":
		alpha_opening_volley_shot_counts[actor.name] = int(alpha_opening_volley_shot_counts.get(actor.name, 0)) + 1
	if firing_team == &"alpha" and not alpha_first_fire_observed:
		alpha_first_fire_observed = true
		alpha_first_fire_msec = Time.get_ticks_msec()
		bravo_unaware_at_alpha_first_fire = bravo_coordinator.get_contact_phase() == SquadCoordinator.ContactPhase.SEARCH
		_trace_event("ALPHA_FIRST_FIRE_GATE", {
			"all_in_cover_at_open": alpha_ambush_opened_all_in_cover,
			"bravo_phase": SquadCoordinator.ContactPhase.keys()[bravo_coordinator.get_contact_phase()],
			"bravo_early_order": bravo_combat_order_before_alpha_fire,
		})
	elif firing_team == &"bravo" and bravo_first_fire_msec == 0:
		bravo_first_fire_msec = Time.get_ticks_msec()
	if traced_actor_fire.has(actor):
		return
	traced_actor_fire[actor] = true
	_trace_event("FIRST_FIRE", {
		"team": firing_team,
		"actor": actor.name,
		"roe": RulesOfEngagement.get_label(actor._get_rules_of_engagement()) if actor.has_method("_get_rules_of_engagement") else "UNKNOWN",
		"cover": actor.get_active_cover().name if actor.has_method("get_active_cover") and is_instance_valid(actor.get_active_cover()) else "NONE",
		"target": fire_target.name if is_instance_valid(fire_target) else "NONE",
		"aiming": actor.is_weapon_aiming() if actor.has_method("is_weapon_aiming") else false,
		"aim_quality": "%.2f" % aim_quality,
		"spread": "%.2fdeg" % final_spread,
	})

func _on_surprise_reaction_started(duration: float, actor: Node2D) -> void:
	if actor.has_method("get_combat_team") and actor.get_combat_team() == &"bravo":
		bravo_surprise_reaction_count += 1
	_trace_event("SURPRISE_REACTION", {
		"team": actor.get_combat_team() if actor.has_method("get_combat_team") else &"unknown",
		"actor": actor.name,
		"duration": "%.2f" % duration,
	})

func _on_traced_actor_died(actor: Node) -> void:
	_trace_event("DEATH", {
		"team": actor.get_combat_team() if is_instance_valid(actor) and actor.has_method("get_combat_team") else &"unknown",
		"actor": actor.name if is_instance_valid(actor) else "INVALID",
	})

func _trace_squad_state(coordinator: SquadCoordinator) -> void:
	if coordinator == null:
		return
	var board := coordinator.get_blackboard()
	var ready_ratio := float(board.get_fact(&"ambush_ready_ratio", 0.0))
	var aim_ready_ratio := float(board.get_fact(&"ambush_aim_ready_ratio", 0.0))
	var state_key := "%d|%s|%d|%.2f|%s" % [
		coordinator.get_contact_phase(),
		String(board.get_fact(&"tactical_plan", "NONE")),
		int(board.get_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)),
		ready_ratio,
		"%s|%.2f" % [String(board.get_fact(&"ambush_cover", "NONE")), aim_ready_ratio],
	]
	if trace_state_cache.get(coordinator.squad_id, "") == state_key:
		return
	trace_state_cache[coordinator.squad_id] = state_key
	_trace_event("SQUAD_STATE", {
		"team": coordinator.squad_id,
		"phase": SquadCoordinator.ContactPhase.keys()[coordinator.get_contact_phase()],
		"plan": board.get_fact(&"tactical_plan", "NONE"),
		"roe": RulesOfEngagement.get_label(int(board.get_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)) as RulesOfEngagement.Type),
		"known_hostiles": board.get_fact(&"hostile_alive_count", 0),
		"ready": "%.0f%%" % (ready_ratio * 100.0),
		"aim_ready": "%.0f%%" % (aim_ready_ratio * 100.0),
		"assigned_targets": board.get_fact(&"ambush_assigned_target_count", 0),
		"cover": board.get_fact(&"ambush_cover", "NONE"),
	})

func _trace_alpha_ambush_members() -> void:
	if alpha_coordinator == null or alpha_coordinator.get_contact_phase() != SquadCoordinator.ContactPhase.AMBUSH:
		return
	for member in alpha_coordinator.members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var order := member.get_current_order()
		if order == null or order.type != SquadOrder.Type.AMBUSH_POSITION:
			continue
		var assigned_cover := order.assigned_cover
		var active_cover: Node = member.actor.get_active_cover()
		var ready := is_instance_valid(assigned_cover) and active_cover == assigned_cover
		var distance := member.actor.global_position.distance_to((assigned_cover as Node2D).global_position) if is_instance_valid(assigned_cover) else member.actor.global_position.distance_to(order.target_position)
		var action_id := int(member.actor.get("_active_squad_action"))
		var detour := member.actor.get("_movement_detour_waypoint") as Vector2
		var state_key := "%s|%s|%s|%d|%d|%d" % [
			"READY" if ready else "MOVING",
			assigned_cover.name if is_instance_valid(assigned_cover) else "NONE",
			active_cover.name if is_instance_valid(active_cover) else "NONE",
			int(distance / 150.0),
			action_id,
			int(member.actor.global_position.distance_to(detour) / 150.0) if detour != Vector2.ZERO else -1,
		]
		if ambush_member_state_cache.get(member.actor, "") == state_key:
			continue
		ambush_member_state_cache[member.actor] = state_key
		_trace_event("AMBUSH_MEMBER", {
			"actor": member.actor.name,
			"state": "READY" if ready else "MOVING",
			"assigned": assigned_cover.name if is_instance_valid(assigned_cover) else "NONE",
			"active": active_cover.name if is_instance_valid(active_cover) else "NONE",
			"distance": "%.0f" % distance,
			"action": action_id,
			"speed": "%.0f" % member.actor.velocity.length(),
			"detour": detour,
			"target": alpha_coordinator.get_ambush_target_for(member).name if is_instance_valid(alpha_coordinator.get_ambush_target_for(member)) else "NONE",
			"aim_quality": "%.2f" % float(member.actor.get_aim_quality()),
		})

func _trace_prefire_guard() -> void:
	if bravo_coordinator == null:
		return
	var non_hold_orders: PackedStringArray = []
	for member in bravo_coordinator.members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var order := member.get_current_order()
		if order != null and order.type != SquadOrder.Type.HOLD:
			non_hold_orders.append("%s:%s" % [member.actor.name, order.get_type_name()])
	_trace_event("PREFIRE_GUARD", {
		"bravo_phase": SquadCoordinator.ContactPhase.keys()[bravo_coordinator.get_contact_phase()],
		"known_hostiles": bravo_coordinator.get_blackboard().get_fact(&"hostile_alive_count", 0),
		"non_hold_orders": ",".join(non_hold_orders) if not non_hold_orders.is_empty() else "NONE",
	})
	if bravo_coordinator.get_contact_phase() != SquadCoordinator.ContactPhase.SEARCH or not non_hold_orders.is_empty():
		_trace_event("INVARIANT_VIOLATION", {"rule": "bravo awareness or orders changed before alpha fire"})

func _trace_event(event_name: String, fields: Dictionary = {}) -> void:
	var elapsed := float(Time.get_ticks_msec() - battle_started_msec) / 1000.0 if battle_started_msec > 0 else 0.0
	var parts: PackedStringArray = []
	for key in fields:
		parts.append("%s=%s" % [key, fields[key]])
	var line := "[BATTLE_TRACE t=%.2f] %s %s" % [elapsed, event_name, " ".join(parts)]
	print(line)
	if battle_trace_file:
		battle_trace_file.store_line(line)

func _exit_tree() -> void:
	if battle_trace_file:
		battle_trace_file.close()
		battle_trace_file = null

func _on_ammo_changed(magazine_ammo: int, reserve_ammo: int) -> void:
	var weapon := player.get("firearm_weapon") as FirearmWeapon
	var weapon_name: String = weapon.weapon_data.weapon_name if weapon and weapon.weapon_data else "Weapon"
	ammo_label.text = "%s %d/%d" % [weapon_name, magazine_ammo, reserve_ammo]

func _on_weapon_changed(data: WeaponData) -> void:
	if data == null:
		status_label.text = "Weapon: none"
		return

	status_label.text = "%s | C掩体 Space精确" % data.weapon_name
	var weapon := player.get("firearm_weapon") as FirearmWeapon
	if weapon:
		_on_ammo_changed(weapon.magazine_ammo, weapon.reserve_ammo)

func _on_weapon_attack_failed(reason: String) -> void:
	status_label.text = "Weapon: %s" % reason

func _on_reload_started() -> void:
	status_label.text = "Reloading..."

func _on_reload_finished() -> void:
	status_label.text = "Ready"

func _on_weapon_cycle_started(_duration: float) -> void:
	status_label.text = "Cycling..."

func _on_weapon_cycle_finished() -> void:
	status_label.text = "Ready"

func _on_player_died(_pawn) -> void:
	status_label.text = "Player defeated!"
	enemy_label.text = "Player down"

func _update_enemy_hud() -> void:
	if not is_instance_valid(enemy_label):
		return
	var alpha_stats := _get_team_stats(&"alpha")
	var bravo_stats := _get_team_stats(&"bravo")
	if int(alpha_stats.alive) == 0 or int(bravo_stats.alive) == 0:
		enemy_label.text = "战斗结束 | 蓝%d 红%d" % [alpha_stats.alive, bravo_stats.alive]
		return
	enemy_label.text = "蓝 %d/%d HP%d | 红 %d/%d HP%d" % [
		alpha_stats.alive, int(initial_team_counts.get(&"alpha", 0)), alpha_stats.health,
		bravo_stats.alive, int(initial_team_counts.get(&"bravo", 0)), bravo_stats.health,
	]

func _get_team_stats(team: StringName) -> Dictionary:
	var alive := 0
	var health := 0
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("get_combat_team"):
			continue
		if enemy.get_combat_team() != team:
			continue
		alive += 1
		health += int(enemy.get("health"))
	return {"alive": alive, "health": health}

func _update_ai_state_hud() -> void:
	if ai_state_label == null or alpha_coordinator == null or bravo_coordinator == null:
		return
	var lines := _build_squad_debug(alpha_coordinator)
	lines.append("")
	lines.append_array(_build_squad_debug(bravo_coordinator))
	ai_state_label.text = "\n".join(lines)

func _build_squad_debug(coordinator: SquadCoordinator) -> PackedStringArray:
	var board := coordinator.get_blackboard()
	var leader_name := "选举中"
	var team_name := coordinator.squad_display_name if not coordinator.squad_display_name.is_empty() else String(coordinator.squad_id)
	if coordinator.leader and is_instance_valid(coordinator.leader.actor):
		leader_name = coordinator.leader.actor.name
		if coordinator.leader.actor.has_method("get_combat_team_label"):
			team_name = coordinator.leader.actor.get_combat_team_label()
		if coordinator.leader.actor.has_method("get_combat_role_label"):
			leader_name = coordinator.leader.actor.get_combat_role_label()
	var current_order := board.current_order
	var order_name := _get_order_label(current_order.type) if current_order else "无"
	var plan_name := _get_plan_label(String(board.get_fact(&"tactical_plan", "FORMING_UP")))
	var force_ratio := float(board.get_fact(&"force_ratio", 0.0))
	var ally_count := int(board.get_fact(&"ally_alive_count", 0))
	var hostile_count := int(board.get_fact(&"hostile_alive_count", 0))
	var casualties := int(board.get_fact(&"squad_casualties", 0))
	var roe := int(board.get_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)) as RulesOfEngagement.Type
	var ready_ratio := float(board.get_fact(&"ambush_ready_ratio", 0.0))
	var contact_phase := coordinator.get_contact_phase()
	var engagement_text := "未接敌"
	if coordinator.is_engagement_active():
		engagement_text = "%.1fs" % coordinator.get_engagement_time()
	var suppression_total := 0.0
	var pinned_count := 0
	var valid_member_count := 0
	for member in coordinator.members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var suppression := member.actor.get("suppression_component") as SuppressionComponent
		if suppression:
			suppression_total += suppression.suppression
			valid_member_count += 1
			if suppression.should_hunker_down():
				pinned_count += 1
	var suppressor_name := "无"
	var active_suppressor := coordinator.get_active_suppressor()
	if active_suppressor and is_instance_valid(active_suppressor.actor):
		suppressor_name = active_suppressor.actor.name
		if active_suppressor.actor.has_method("get_combat_role_label"):
			suppressor_name = active_suppressor.actor.get_combat_role_label()
	var average_suppression := suppression_total / float(maxi(1, valid_member_count))
	return PackedStringArray([
		"[%s] %d | 队长:%s | %s" % [team_name, ally_count, leader_name, _get_posture_label(coordinator.get_posture_name())],
		"计划:%s | 命令:%s | 敌我%d:%d" % [plan_name, order_name, hostile_count, ally_count],
		"认知:%s 敌:%d | %s | 伏击:%d%%" % [_get_contact_phase_label(contact_phase), hostile_count, RulesOfEngagement.get_label(roe), int(round(ready_ratio * 100.0))],
		"编成:%s | 压:%s %.0f/%d | 亡%d" % [_get_role_summary(coordinator), suppressor_name, average_suppression, pinned_count, casualties],
	])

func _get_role_summary(coordinator: SquadCoordinator) -> String:
	var counts: Dictionary = {}
	for role in SquadCombatRole.Type.values():
		counts[role] = 0
	for member in coordinator.members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		if member.actor.has_method("get_combat_role"):
			var role: SquadCombatRole.Type = member.actor.get_combat_role()
			counts[role] = int(counts.get(role, 0)) + 1
	var parts: PackedStringArray = []
	for role in SquadCombatRole.Type.values():
		var count := int(counts.get(role, 0))
		if count > 0:
			parts.append("%s%d" % [SquadCombatRole.get_short_label(role), count])
	return " ".join(parts)

func _get_plan_label(plan_name: String) -> String:
	match plan_name:
		"SEARCH_HALT":
			return "原地警戒"
		"SEARCH_SWEEP":
			return "队形搜索"
		"CONTACT_TO_COVER":
			return "接敌找掩体"
		"CONTACT_BASE_OF_FIRE":
			return "建立火力线"
		"SUPPRESS_AND_FLANK":
			return "压制包抄"
		"AGGRESSIVE_ENVELOPMENT":
			return "强攻合围"
		"HOLD_DEFENSIVE_LINE":
			return "防线固守"
		"COVERING_RETREAT":
			return "掩护撤退"
		"AMBUSH_SETUP":
			return "静默伏击"
		"AMBUSH_OPEN_FIRE":
			return "伏击开火"
		"AMBUSH_VOLLEY":
			return "掩体齐射"
		"NO_TARGET":
			return "搜索目标"
	return "集结"

func _get_posture_label(posture_name: String) -> String:
	match posture_name:
		"ASSAULT":
			return "进攻"
		"DEFENSIVE":
			return "防守"
		"ROUT":
			return "撤退"
	return "均衡"

func _get_contact_phase_label(phase: SquadCoordinator.ContactPhase) -> String:
	match phase:
		SquadCoordinator.ContactPhase.AMBUSH:
			return "伏击"
		SquadCoordinator.ContactPhase.COMBAT:
			return "交战"
	return "未发现"

func _get_order_label(order_type: SquadOrder.Type) -> String:
	match order_type:
		SquadOrder.Type.SEARCH_AREA:
			return "区域搜索"
		SquadOrder.Type.AMBUSH_POSITION:
			return "伏击就位"
		SquadOrder.Type.TAKE_COVER:
			return "找掩体"
		SquadOrder.Type.SUPPRESS:
			return "压制"
		SquadOrder.Type.FOCUS_FIRE:
			return "集火"
		SquadOrder.Type.OVERWATCH:
			return "警戒"
		SquadOrder.Type.FLANK_LEFT:
			return "左包抄"
		SquadOrder.Type.FLANK_RIGHT:
			return "右包抄"
		SquadOrder.Type.RETREAT:
			return "撤退"
		SquadOrder.Type.STAY_HIDDEN:
			return "隐蔽"
		SquadOrder.Type.ADVANCE:
			return "推进"
	return "待命"
