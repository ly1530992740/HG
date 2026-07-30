extends Node3D
class_name SquadCoordinator3D

signal command_changed(plan: String, summary: String, source: String)
signal qwen_debug_updated(input: String, output: String, summary: String)
signal squad_eliminated(squad: SquadCoordinator3D)
signal leader_changed(previous: Soldier3D, current: Soldier3D)

@export_category("小队配置")
@export var squad_id: StringName = &"squad3d"
@export var squad_display_name := "红队"
@export var combat_team: Soldier3D.Team = Soldier3D.Team.RED
@export var can_target_players := true
@export var member_root_path := NodePath("Members")
@export var free_when_all_members_dead := false

@export_category("Mission Configuration")
@export var use_advanced_tactics := false
@export_enum("Capture and hold", "Eliminate and return") var mission_type: int = int(SquadMissionController3D.MissionType.CAPTURE_AND_HOLD)
@export_node_path("Node3D") var mission_target_path: NodePath
@export_range(1.0, 80.0, 0.5) var mission_radius := 10.0
@export_range(0.0, 10.0, 0.1) var mission_clear_confirmation_seconds := 1.0
@export_range(0.5, 10.0, 0.5) var mission_return_radius := 2.0
@export_range(0.0, 3.0, 0.05) var contact_report_delay_min := 0.25
@export_range(0.0, 5.0, 0.05) var contact_report_delay_max := 0.75

@export_category("小队长决策")
@export var use_qwen := false
@export var autonomous_goap := false
@export var knows_primary_target_at_start := false
@export var primary_target_path: NodePath
@export_range(0.2, 5.0, 0.1) var evaluation_interval := 0.5
@export_range(1.0, 30.0, 0.5) var qwen_reconsider_interval := 5.0
@export_range(0.1, 1.0, 0.05) var low_health_cover_ratio := 0.3
@export_range(1, 8, 1) var flank_member_count := 3
@export_range(0.0, 2.0, 0.05) var formation_surprise_delay := 0.65

@export_category("本地模型")
@export var qwen_endpoint := "http://127.0.0.1:8081/v1/chat/completions"
@export_range(0.5, 10.0, 0.1) var qwen_timeout_seconds := 4.0

var members: Array[Soldier3D] = []
var leader: Soldier3D
var known_target: Node3D
var current_plan := "WAITING"
var current_stage := 0
var last_command_summary := ""
var last_command_source := ""
var last_qwen_input := ""
var last_qwen_output := ""
var last_qwen_reason := ""
var last_qwen_latency_ms := 0
var last_route_candidates: Array[Dictionary] = []

var _route_analyzer: SquadRouteAnalyzer3D
var _situation_analyzer: SquadSituationAnalyzer3D
var _rule_decision: SquadRuleDecision3D
var _battlefield_snapshot: SquadBattlefieldSnapshot3D
var _qwen_brain: QwenSquadBrain3D
var _evaluation_timer := 0.0
var _last_qwen_request_msec := -100000
var _directive_version := 0
var _stage_versions: Dictionary = {}
var _last_signature := ""
var _initial_member_count := 0
var _situation_version := 1
var _qwen_phases: Array[Array] = []
var _qwen_phase_index := -1
var _advanced_tactics: SquadAdvancedTactics3D

func _ready() -> void:
	add_to_group("squad3d")
	var registry := BattlefieldRegistry3D.find(get_tree())
	if registry != null:
		registry.register_node(self)
	_route_analyzer = SquadRouteAnalyzer3D.new()
	_route_analyzer.name = "RouteAnalyzer3D"
	add_child(_route_analyzer)
	_situation_analyzer = SquadSituationAnalyzer3D.new()
	_situation_analyzer.name = "SituationAnalyzer3D"
	add_child(_situation_analyzer)
	_rule_decision = SquadRuleDecision3D.new()
	_rule_decision.name = "RuleDecision3D"
	add_child(_rule_decision)
	_battlefield_snapshot = SquadBattlefieldSnapshot3D.new()
	_battlefield_snapshot.name = "BattlefieldSnapshot3D"
	add_child(_battlefield_snapshot)
	if use_qwen:
		_ensure_qwen_brain()
	_register_configured_members()
	_elect_leader()
	_initial_member_count = members.size()
	if use_advanced_tactics:
		_advanced_tactics = SquadAdvancedTactics3D.new()
		_advanced_tactics.name = "AdvancedTactics3D"
		add_child(_advanced_tactics)
		_advanced_tactics.configure(self)
		refresh_member_mission_constraints()
		return
	if knows_primary_target_at_start:
		known_target = _find_primary_target()
	call_deferred("_evaluate_situation", true)

func _process(delta: float) -> void:
	if use_advanced_tactics and _advanced_tactics != null:
		_advanced_tactics.process(delta)
		return
	_evaluation_timer -= delta
	if _evaluation_timer <= 0.0:
		_evaluation_timer = evaluation_interval
		_evaluate_situation(false)
	_process_plan_stage()

func get_configured_member_actors() -> Array[Soldier3D]:
	return members.duplicate()

func get_squad_center() -> Vector3:
	return _squad_center(_living_members())

func get_registered_covers() -> Array:
	return _get_registered_covers()

func get_situation_version() -> int:
	return _situation_version

func get_living_members() -> Array[Soldier3D]:
	return _living_members()

func get_member_by_id(member_id: String) -> Soldier3D:
	return _member_by_id(member_id)

func is_member(actor: Soldier3D) -> bool:
	return actor in members

func get_advanced_tactics() -> SquadAdvancedTactics3D:
	return _advanced_tactics

func request_advanced_candidate(state: Dictionary, candidates: Array[Dictionary], fallback_id: String, context_version: int) -> void:
	if not use_qwen or candidates.size() <= 1:
		return
	_ensure_qwen_brain()
	_elect_leader()
	if not is_instance_valid(leader) or _qwen_brain == null or _qwen_brain.pending:
		return
	var now := Time.get_ticks_msec()
	if now - _last_qwen_request_msec < int(qwen_reconsider_interval * 1000.0):
		return
	_last_qwen_request_msec = now
	_qwen_brain.request_candidate_selection(state, candidates, fallback_id, context_version)
	last_qwen_input = _qwen_brain.last_input
	last_qwen_output = _qwen_brain.last_output
	qwen_debug_updated.emit(last_qwen_input, last_qwen_output, last_command_summary)

func get_mission_target_position() -> Vector3:
	var target_node := get_node_or_null(mission_target_path) as Node3D
	return target_node.global_position if target_node != null else global_position

func is_position_allowed_by_mission(position: Vector3) -> bool:
	if not use_advanced_tactics or _advanced_tactics == null or not _advanced_tactics.mission.is_defense_locked():
		return true
	var delta := position - get_mission_target_position()
	delta.y = 0.0
	return delta.length() <= mission_radius

func refresh_member_mission_constraints() -> void:
	var enabled := use_advanced_tactics and _advanced_tactics != null and _advanced_tactics.mission.is_defense_locked()
	for member in _living_members():
		member.set_movement_constraint(enabled, get_mission_target_position(), mission_radius)

func issue_tactical_directive(
		member: Soldier3D,
		type: SquadDirective3D.Type,
		target: Node3D,
		position: Vector3,
		route: Array[Vector3],
		cover: TacticalCover3D,
		duration: float,
		reason: String,
		zone_id: StringName = &"",
		rules_of_engagement: int = SquadDirective3D.RulesOfEngagement.WEAPONS_FREE
) -> SquadDirective3D:
	return _issue_to_member(member, type, target, position, route, cover, duration, reason, zone_id, rules_of_engagement)

func set_known_combat_objective(target: Node3D) -> void:
	if target == null:
		return
	if known_target != target:
		_situation_version += 1
		_last_qwen_request_msec = -100000
	known_target = target
	for member in members:
		if is_instance_valid(member):
			member.current_target = target
			member.aware_of_enemy = true
	_evaluate_situation(true)

func issue_defense_order(position: Vector3, radius: float = 8.0) -> void:
	use_qwen = false
	autonomous_goap = false
	known_target = null
	current_plan = "PLAYER_DEFEND"
	current_stage = 1
	_stage_versions.clear()
	var living := _living_members()
	for index in living.size():
		var angle := TAU * float(index) / float(maxi(1, living.size()))
		var ring := 0.0 if living.size() == 1 else minf(radius * 0.35, 2.5)
		var destination := position + Vector3(cos(angle), 0.0, sin(angle)) * ring
		_issue_to_member(living[index], SquadDirective3D.Type.GUARD, null, destination, [], null, 0.0, "玩家命令：集结后坚守")
	last_command_source = "PLAYER"
	last_command_summary = "集结到指定位置并坚守 %.1f 米范围" % radius
	command_changed.emit(current_plan, last_command_summary, last_command_source)

func issue_hold_position_guard(reason := "保持朝向原地警戒") -> void:
	known_target = null
	current_plan = "GUARD"
	current_stage = 2
	_stage_versions.clear()
	for member in _living_members():
		_issue_to_member(member, SquadDirective3D.Type.GUARD, null, member.global_position, [], null, 0.0, reason)
	last_command_source = "RULES"
	last_command_summary = "原地保持朝向警戒｜%s" % reason
	command_changed.emit(current_plan, last_command_summary, last_command_source)

func is_squad_alive() -> bool:
	return not _living_members().is_empty()

func _register_configured_members() -> void:
	members.clear()
	var root := get_node_or_null(member_root_path)
	if root == null:
		root = self
	for child in root.get_children():
		if not child is Soldier3D:
			continue
		var soldier := child as Soldier3D
		soldier.squad_id = squad_id
		soldier.combat_team = combat_team
		soldier.can_target_players = can_target_players
		soldier.team_display_name = squad_display_name
		if use_advanced_tactics:
			if not soldier.perception_report_ready.is_connected(_on_member_perception_report):
				soldier.perception_report_ready.connect(_on_member_perception_report)
			if not soldier.directive_completed.is_connected(_on_member_directive_completed):
				soldier.directive_completed.connect(_on_member_directive_completed)
		elif not soldier.contact_spotted.is_connected(_on_member_contact):
			soldier.contact_spotted.connect(_on_member_contact)
		if not soldier.died.is_connected(_on_member_died):
			soldier.died.connect(_on_member_died)
		members.append(soldier)

func _ensure_qwen_brain() -> void:
	if _qwen_brain != null:
		return
	_qwen_brain = QwenSquadBrain3D.new()
	_qwen_brain.name = "QwenBrain3D"
	_qwen_brain.endpoint = qwen_endpoint
	_qwen_brain.timeout_seconds = qwen_timeout_seconds
	add_child(_qwen_brain)
	_qwen_brain.decision_ready.connect(_on_qwen_decision)
	_qwen_brain.candidate_ready.connect(_on_qwen_candidate)

func _on_qwen_candidate(candidate_id: String, reason: String, raw_output: String, fallback: bool, latency_ms: int, context_version: int) -> void:
	last_qwen_input = _qwen_brain.last_input
	last_qwen_output = raw_output
	last_qwen_reason = reason
	last_qwen_latency_ms = latency_ms
	if _advanced_tactics == null:
		return
	if context_version != _advanced_tactics.get_qwen_context_version():
		last_command_source = "QWEN_STALE"
		last_command_summary = "Discarded stale Qwen candidate context %d, current %d" % [context_version, _advanced_tactics.get_qwen_context_version()]
		_last_qwen_request_msec = -100000
		qwen_debug_updated.emit(last_qwen_input, last_qwen_output, last_command_summary)
		return
	if not fallback and not _advanced_tactics.apply_qwen_candidate(candidate_id, reason):
		last_command_source = "QWEN_REJECTED"
		last_command_summary = "Rejected Qwen candidate outside current legal set: %s" % candidate_id
	qwen_debug_updated.emit(last_qwen_input, last_qwen_output, last_command_summary)

func _elect_leader() -> void:
	var living := _living_members()
	var previous := leader
	if is_instance_valid(leader) and leader in living and leader.can_be_squad_leader:
		return
	leader = null
	if use_qwen:
		for candidate in living:
			if not candidate.can_be_squad_leader:
				continue
			if leader == null or candidate.leader_priority > leader.leader_priority:
				leader = candidate
	for member in living:
		member.set_squad_leader(member == leader)
	if previous != leader:
		_situation_version += 1
		_last_qwen_request_msec = -100000
		leader_changed.emit(previous, leader)
		print("[SQUAD3D] team=%s leader=%s living=%d" % [squad_display_name, String(leader.name) if is_instance_valid(leader) else "NONE", living.size()])

func _evaluate_situation(force: bool) -> void:
	var living := _living_members()
	if living.is_empty():
		return
	if use_qwen:
		_ensure_qwen_brain()
		_elect_leader()
	if not is_instance_valid(known_target) or not _is_alive(known_target):
		known_target = _best_member_contact()
	if not is_instance_valid(known_target) and knows_primary_target_at_start:
		known_target = _find_primary_target()
	var target := known_target
	if autonomous_goap:
		if is_instance_valid(target) and (force or current_plan != "AUTONOMOUS_ATTACK"):
			current_plan = "AUTONOMOUS_ATTACK"
			current_stage = 1
			last_command_source = "AUTONOMOUS_GOAP"
			last_command_summary = "单兵GOAP：自行规划并消灭已知敌人"
			_issue_to_members(living, SquadDirective3D.Type.ATTACK, target, Vector3.ZERO, [], null, 0.0, "单兵自主消灭目标")
			command_changed.emit(current_plan, last_command_summary, last_command_source)
		return
	var center := _squad_center(living)
	if is_instance_valid(target):
		last_route_candidates = _route_analyzer.analyze(center, target.global_position)
	else:
		last_route_candidates.clear()
	var rule_plan := _choose_rule_plan(target, living)
	var signature := _build_signature(target, living, rule_plan)
	if force or current_plan == "WAITING" or signature != _last_signature:
		if signature != _last_signature:
			_situation_version += 1
		_last_signature = signature
		_apply_plan(rule_plan, target, "程序根据3D态势选择", "RULES")
		_request_qwen_if_due(target, living, rule_plan)

func _choose_rule_plan(target: Node3D, living: Array[Soldier3D]) -> String:
	return _rule_decision.choose_plan(
		is_instance_valid(target),
		_average_health_ratio(living),
		low_health_cover_ratio,
		_enemy_formation_is_aware(target),
		_formation_power(living),
		_enemy_formation_power(target),
		not _route_analyzer.get_best_available().is_empty()
	)

func _request_qwen_if_due(target: Node3D, living: Array[Soldier3D], fallback_plan: String) -> void:
	if not use_qwen or not is_instance_valid(leader) or _qwen_brain == null or _qwen_brain.pending:
		return
	var now := Time.get_ticks_msec()
	if now - _last_qwen_request_msec < int(qwen_reconsider_interval * 1000.0):
		return
	_last_qwen_request_msec = now
	var state := _build_qwen_state(target, living)
	_qwen_brain.request_decision(state, fallback_plan, _situation_version)
	last_qwen_input = _qwen_brain.last_input
	last_qwen_output = _qwen_brain.last_output
	qwen_debug_updated.emit(last_qwen_input, last_qwen_output, last_command_summary)

func _build_qwen_state(target: Node3D, living: Array[Soldier3D]) -> Dictionary:
	return _battlefield_snapshot.build(self, living, leader, target, last_route_candidates, _situation_version)

func _on_qwen_decision(decision: Dictionary, reason: String, raw_output: String, fallback: bool, latency_ms: int, situation_version: int) -> void:
	last_qwen_input = _qwen_brain.last_input
	last_qwen_output = raw_output
	last_qwen_reason = reason
	last_qwen_latency_ms = latency_ms
	if situation_version != _situation_version:
		push_warning("[QWEN3D_STALE] team=%s response=%d current=%d" % [squad_display_name, situation_version, _situation_version])
		last_command_source = "QWEN_STALE"
		last_command_summary = "丢弃过期Qwen命令：态势%d已更新为%d" % [situation_version, _situation_version]
		_last_qwen_request_msec = -100000
		call_deferred("_evaluate_situation", true)
		return
	if fallback:
		_apply_plan(_choose_rule_plan(known_target, _living_members()), known_target, reason, "RULE_FALLBACK")
	else:
		var validation := _validate_qwen_orders(decision)
		if not bool(validation.get("valid", false)):
			push_warning("[QWEN3D_GUARD] team=%s reason=%s" % [squad_display_name, String(validation.get("reason", "Qwen命令非法"))])
			_apply_plan(_choose_rule_plan(known_target, _living_members()), known_target, String(validation.get("reason", "Qwen命令非法")), "QWEN_REJECTED")
		else:
			_apply_qwen_orders(decision, validation.get("orders", []), bool(validation.get("guarded", false)))
	qwen_debug_updated.emit(last_qwen_input, last_qwen_output, last_command_summary)

func _validate_qwen_orders(decision: Dictionary) -> Dictionary:
	var living := _living_members()
	if living.is_empty() or not is_instance_valid(known_target):
		return {"valid": false, "reason": "没有可执行命令的存活成员或目标"}
	var members_by_id: Dictionary = {}
	for member in living:
		members_by_id[String(member.name)] = member
	var routes_by_id := _routes_by_id()
	var covers_by_id := _covers_by_id()
	var normalized: Array[Dictionary] = []
	var used_by_phase: Dictionary = {}
	var offensive_members: Dictionary = {}
	var guarded := false
	var max_phase := 1
	var orders: Array = decision.get("orders", [])
	if orders.is_empty():
		return {"valid": false, "reason": "Qwen没有返回成员命令"}
	for raw_order in orders:
		if not raw_order is Dictionary:
			return {"valid": false, "reason": "命令不是JSON对象"}
		var goal := String(raw_order.get("goal", ""))
		var phase := clampi(int(raw_order.get("phase", 1)), 1, 3)
		var member_ids: Array = raw_order.get("members", [])
		var route_id := String(raw_order.get("route", "NONE"))
		var cover_id := String(raw_order.get("cover", "NONE"))
		if goal not in QwenSquadBrain3D.get_legal_goals(living.size(), true):
			return {"valid": false, "reason": "非法Goal：%s" % goal}
		if member_ids.is_empty():
			return {"valid": false, "reason": "命令没有接收成员"}
		var phase_conflict := true
		while phase_conflict:
			phase_conflict = false
			var existing_phase_members: Dictionary = used_by_phase.get(phase, {})
			for member_id_value in member_ids:
				if existing_phase_members.has(String(member_id_value)):
					phase_conflict = true
					phase += 1
					guarded = true
					break
		var phase_members: Dictionary = used_by_phase.get(phase, {})
		for member_id_value in member_ids:
			var member_id := String(member_id_value)
			if not members_by_id.has(member_id):
				return {"valid": false, "reason": "不存在或已死亡的成员：%s" % member_id}
			phase_members[member_id] = true
			if goal in ["SUPPRESS_TARGET", "FLANK_TARGET", "ATTACK_TARGET"]:
				offensive_members[member_id] = true
		used_by_phase[phase] = phase_members
		if goal in ["FLANK_TARGET", "MOVE_TO_ROUTE"]:
			var route: Dictionary = routes_by_id.get(route_id, {})
			if route.is_empty() or not bool(route.get("available", false)):
				return {"valid": false, "reason": "路线不可达：%s" % route_id}
			if member_ids.size() > int(route.get("capacity", 0)):
				return {"valid": false, "reason": "路线%s容量不足" % route_id}
		if goal == "TAKE_COVER":
			var cover := covers_by_id.get(cover_id) as TacticalCover3D
			var usable_slots := 0
			if cover != null:
				usable_slots = cover.get_available_slot_count_against(known_target.global_position)
				for member_id_value in member_ids:
					var assigned_member := members_by_id.get(String(member_id_value)) as Soldier3D
					if assigned_member != null and cover.get_reserved_slot(assigned_member) != null:
						usable_slots += 1
			if cover == null or usable_slots < member_ids.size():
				return {"valid": false, "reason": "掩体%s不存在或空位不足" % cover_id}
		max_phase = maxi(max_phase, phase)
		var normalized_order: Dictionary = raw_order.duplicate(true)
		normalized_order["phase"] = phase
		normalized.append(normalized_order)

	var supplemental_phase := max_phase + 1
	for member in living:
		var member_id := String(member.name)
		if offensive_members.has(member_id):
			continue
		guarded = true
		normalized.append({
			"phase": supplemental_phase,
			"members": [member_id],
			"goal": "ATTACK_TARGET",
			"route": "NONE",
			"cover": "NONE",
		})
	return {"valid": true, "orders": normalized, "guarded": guarded, "reason": ""}

func _apply_qwen_orders(decision: Dictionary, orders: Array, guarded: bool) -> void:
	var phases_by_number: Dictionary = {}
	for order in orders:
		var phase := int(order.get("phase", 1))
		var phase_orders: Array = phases_by_number.get(phase, [])
		phase_orders.append(order)
		phases_by_number[phase] = phase_orders
	var phase_numbers: Array = phases_by_number.keys()
	phase_numbers.sort()
	_qwen_phases.clear()
	for phase_number in phase_numbers:
		_qwen_phases.append(phases_by_number[phase_number])
	_qwen_phase_index = -1
	current_plan = String(decision.get("intent", "COVER_ATTACK"))
	current_stage = 0
	_stage_versions.clear()
	last_command_source = "QWEN_GUARDED" if guarded else "LOCAL_QWEN"
	last_command_summary = "%s｜队长%s｜%s｜%d阶段%d条命令" % [
		_plan_label(current_plan),
		String(leader.name) if is_instance_valid(leader) else "NONE",
		String(decision.get("reason", "Qwen未说明理由")),
		_qwen_phases.size(),
		orders.size(),
	]
	command_changed.emit(current_plan, last_command_summary, last_command_source)
	print("[QWEN3D] team=%s leader=%s plan=%s phases=%d orders=%d" % [squad_display_name, String(leader.name), current_plan, _qwen_phases.size(), orders.size()])
	_dispatch_next_qwen_phase()

func _dispatch_next_qwen_phase() -> void:
	_qwen_phase_index += 1
	if _qwen_phase_index >= _qwen_phases.size():
		return
	_stage_versions.clear()
	current_stage = _qwen_phase_index + 1
	for order in _qwen_phases[_qwen_phase_index]:
		_dispatch_qwen_order(order)

func _dispatch_qwen_order(order: Dictionary) -> void:
	var directive_type := _goal_to_directive(String(order.get("goal", "")))
	var route: Dictionary = _routes_by_id().get(String(order.get("route", "NONE")), {})
	var route_points: Array[Vector3] = []
	if not route.is_empty():
		route_points.assign(route.get("points", []))
	var cover := _covers_by_id().get(String(order.get("cover", "NONE"))) as TacticalCover3D
	for member_id_value in order.get("members", []):
		var member := _member_by_id(String(member_id_value))
		if member == null:
			continue
		var member_directive_type := directive_type
		var position := route_points[-1] if not route_points.is_empty() else member.global_position
		var assigned_cover: TacticalCover3D = null
		if member_directive_type == SquadDirective3D.Type.TAKE_COVER and cover != null:
			_release_other_cover_reservations(member, cover)
			var slot := cover.reserve_reachable_slot(member, known_target.global_position)
			if slot != null:
				position = slot.global_position
				assigned_cover = cover
			else:
				member_directive_type = SquadDirective3D.Type.ATTACK
		_issue_to_member(member, member_directive_type, known_target, position, route_points, assigned_cover, 5.0 if member_directive_type == SquadDirective3D.Type.SUPPRESS else 0.0, "Qwen队长命令")

func _goal_to_directive(goal: String) -> SquadDirective3D.Type:
	match goal:
		"TAKE_COVER": return SquadDirective3D.Type.TAKE_COVER
		"AIM_TARGET": return SquadDirective3D.Type.AIM
		"SUPPRESS_TARGET": return SquadDirective3D.Type.SUPPRESS
		"FLANK_TARGET": return SquadDirective3D.Type.FLANK
		"MOVE_TO_ROUTE": return SquadDirective3D.Type.MOVE
	return SquadDirective3D.Type.ATTACK

func _apply_plan(plan: String, target: Node3D, reason: String, source: String) -> void:
	if not _qwen_phases.is_empty():
		_qwen_phases.clear()
		_qwen_phase_index = -1
		current_stage = 0
	if plan == current_plan and current_stage > 0 and target == known_target:
		if source in ["LOCAL_QWEN", "QWEN_GUARDED", "RULE_FALLBACK"]:
			last_command_source = source
			last_command_summary = "%s｜%s" % [_plan_label(plan), reason]
			command_changed.emit(plan, last_command_summary, source)
		return
	current_plan = plan
	current_stage = 0
	known_target = target
	_stage_versions.clear()
	last_command_source = source
	last_command_summary = "%s｜%s" % [_plan_label(plan), reason]
	command_changed.emit(plan, last_command_summary, source)
	print("[SQUAD3D] team=%s plan=%s source=%s reason=%s" % [squad_display_name, plan, source, reason])

func _process_plan_stage() -> void:
	var living := _living_members()
	if living.is_empty():
		return
	if not _qwen_phases.is_empty():
		if _qwen_phase_index >= 0 and _all_current_directives_complete(living):
			_dispatch_next_qwen_phase()
		return
	match current_plan:
		"AUTONOMOUS_ATTACK", "PLAYER_DEFEND":
			return
		"GUARD":
			_process_guard(living)
		"AMBUSH":
			_process_cover_then_fire(living, true)
		"COVER_ATTACK":
			_process_cover_then_fire(living, false)
		"SUPPRESS_FLANK":
			_process_suppress_flank(living)
		"ASSAULT":
			if current_stage == 0 and is_instance_valid(known_target):
				_issue_to_members(living, SquadDirective3D.Type.ATTACK, known_target, Vector3.ZERO, [], null, 0.0, "全军突击")
				current_stage = 1

func _process_guard(living: Array[Soldier3D]) -> void:
	if current_stage == 0:
		var center := global_position
		for index in living.size():
			var angle := TAU * float(index) / float(maxi(1, living.size()))
			var position := center + Vector3(cos(angle), 0.0, sin(angle)) * 2.2
			_issue_to_member(living[index], SquadDirective3D.Type.MOVE, null, position, [], null, 0.0, "分散到警戒扇区")
		current_stage = 1
	elif current_stage == 1 and _all_current_directives_complete(living):
		for member in living:
			_issue_to_member(member, SquadDirective3D.Type.GUARD, null, member.global_position, [], null, 0.0, "四向警戒")
		current_stage = 2

func _process_cover_then_fire(living: Array[Soldier3D], ambush: bool) -> void:
	if not is_instance_valid(known_target):
		return
	if current_stage == 0:
		var assigned_any := _issue_cover_assignments(living, known_target, "隐蔽伏击就位" if ambush else "接敌寻找掩体")
		if not assigned_any:
			_issue_to_members(living, SquadDirective3D.Type.MOVE, known_target, _squad_center(living), [], null, 0.0, "没有掩体，保持疏散")
		current_stage = 1
	elif current_stage == 1 and _all_current_directives_complete(living):
		_issue_aim_or_hold(living)
		current_stage = 2
	elif current_stage == 2 and _all_current_directives_complete(living):
		_issue_attack_or_suppress(living, ambush)
		current_stage = 3

func _issue_aim_or_hold(living: Array[Soldier3D]) -> void:
	for member in living:
		var visible_target := member.perception_component.find_best_hostile(true)
		if visible_target != null:
			_issue_to_member(member, SquadDirective3D.Type.AIM, visible_target, Vector3.ZERO, [], null, 0.0, "Aim at individually visible contact")
		else:
			_issue_to_member(member, SquadDirective3D.Type.HOLD_SECTOR, null, member.global_position, [], null, 0.0, "No visible contact; observe assigned sector")

func _issue_attack_or_suppress(living: Array[Soldier3D], ambush: bool) -> void:
	for member in living:
		var visible_target := member.perception_component.find_best_hostile(true)
		if visible_target != null:
			var reason := "Synchronized fire" if ambush else "Return fire from cover"
			_issue_to_member(member, SquadDirective3D.Type.ATTACK, visible_target, Vector3.ZERO, [], null, 0.0, reason)
		else:
			_issue_to_member(member, SquadDirective3D.Type.SUPPRESS, known_target, Vector3.ZERO, [], null, 3.0, "Suppress last known enemy position")

func _process_suppress_flank(living: Array[Soldier3D]) -> void:
	if current_stage != 0 or not is_instance_valid(known_target):
		return
	var candidate := _route_analyzer.get_best_available()
	if candidate.is_empty():
		_apply_plan("COVER_ATTACK", known_target, "侧翼路线失效", "RULES")
		return
	var sorted := living.duplicate()
	sorted.sort_custom(func(a: Soldier3D, b: Soldier3D): return a.get_combat_power() < b.get_combat_power())
	var mobile_count := mini(flank_member_count, maxi(1, living.size() - 1))
	var flankers: Array[Soldier3D] = []
	var suppressors: Array[Soldier3D] = []
	for index in sorted.size():
		if index < mobile_count:
			flankers.append(sorted[index])
		else:
			suppressors.append(sorted[index])
	var points: Array[Vector3] = []
	points.assign(candidate.get("points", []))
	for flanker in flankers:
		_issue_to_member(flanker, SquadDirective3D.Type.FLANK, known_target, points[-1], points, candidate.get("cover") as TacticalCover3D, 0.0, "沿%s包抄" % candidate.get("direction", "侧翼"))
	for suppressor in suppressors:
		_issue_to_member(suppressor, SquadDirective3D.Type.SUPPRESS, known_target, Vector3.ZERO, [], null, 4.0, "正面火力掩护")
	current_stage = 1

func _issue_cover_assignments(living: Array[Soldier3D], target: Node3D, reason: String) -> bool:
	var covers: Array[TacticalCover3D] = []
	for node in _get_registered_covers():
		if node is TacticalCover3D and node.get_available_slot_count_against(target.global_position) > 0:
			covers.append(node)
	covers.sort_custom(func(a: TacticalCover3D, b: TacticalCover3D): return _squad_center(living).distance_to(a.global_position) < _squad_center(living).distance_to(b.global_position))
	var assigned := false
	for member in living:
		var chosen: TacticalCover3D
		var slot: Marker3D
		for cover in covers:
			slot = cover.reserve_reachable_slot(member, target.global_position)
			if slot != null:
				chosen = cover
				break
		if chosen != null and slot != null:
			_issue_to_member(member, SquadDirective3D.Type.TAKE_COVER, target, slot.global_position, [], chosen, 0.0, reason)
			assigned = true
		else:
			_issue_to_member(member, SquadDirective3D.Type.MOVE, target, member.global_position, [], null, 0.0, "无空余掩体，保持位置")
	return assigned

func _issue_to_members(list: Array[Soldier3D], type: SquadDirective3D.Type, target: Node3D, position: Vector3, route: Array[Vector3], cover: TacticalCover3D, duration: float, reason: String) -> void:
	for member in list:
		_issue_to_member(member, type, target, position, route, cover, duration, reason)

func _issue_to_member(
		member: Soldier3D,
		type: SquadDirective3D.Type,
		target: Node3D,
		position: Vector3,
		route: Array[Vector3],
		cover: TacticalCover3D,
		duration: float,
		reason: String,
		zone_id: StringName = &"",
		rules_of_engagement: int = SquadDirective3D.RulesOfEngagement.WEAPONS_FREE
) -> SquadDirective3D:
	_directive_version += 1
	var directive := SquadDirective3D.new().configure(type, _directive_version, target, position, route, cover, duration, reason, zone_id, rules_of_engagement)
	member.receive_directive(directive)
	_stage_versions[member] = directive.version
	return directive

func _all_current_directives_complete(list: Array[Soldier3D]) -> bool:
	if list.is_empty():
		return false
	var tracked := 0
	for member in list:
		if not is_instance_valid(member):
			continue
		var expected := int(_stage_versions.get(member, 0))
		if expected <= 0:
			continue
		tracked += 1
		if member.last_completed_directive_version < expected:
			return false
	return tracked > 0

func _on_member_contact(_member: Soldier3D, hostile: Node3D) -> void:
	if hostile == null:
		return
	# 保持当前有效目标，避免多个队员的扫描结果让整个小队反复重发指令。
	if is_instance_valid(known_target) and _is_alive(known_target):
		return
	for member in _living_members():
		member.apply_reaction_delay(formation_surprise_delay)
	known_target = hostile
	_situation_version += 1
	_last_qwen_request_msec = -100000
	for member in _living_members():
		member.current_target = hostile
	_evaluate_situation(true)

func _on_member_perception_report(member: Soldier3D, hostile: Node3D, position: Vector3, confidence: float, stimulus: StringName) -> void:
	if _advanced_tactics != null:
		_advanced_tactics.queue_perception_report(member, hostile, position, confidence, stimulus)

func _on_member_directive_completed(member: Soldier3D, directive: SquadDirective3D) -> void:
	if _advanced_tactics != null:
		_advanced_tactics.on_member_directive_completed(member, directive)

func _on_member_died(actor: Soldier3D) -> void:
	if _advanced_tactics != null:
		_advanced_tactics.on_member_died(actor)
	actor.set_squad_leader(false)
	members.erase(actor)
	_stage_versions.erase(actor)
	if members.is_empty():
		leader = null
		squad_eliminated.emit(self)
		if free_when_all_members_dead:
			queue_free()
	else:
		if actor == leader:
			leader = null
		_situation_version += 1
		_last_qwen_request_msec = -100000
		_elect_leader()
		if not use_advanced_tactics:
			_evaluate_situation(true)

func _living_members() -> Array[Soldier3D]:
	return _situation_analyzer.living_members(members)

func _best_member_contact() -> Node3D:
	for member in _living_members():
		if is_instance_valid(member.current_target) and _is_alive(member.current_target):
			return member.current_target
	return null

func _find_primary_target() -> Node3D:
	if not primary_target_path.is_empty():
		var configured := get_node_or_null(primary_target_path) as Node3D
		if configured != null:
			return configured
	if combat_team != Soldier3D.Team.PLAYER:
		var player := get_tree().get_first_node_in_group("player3d") as Node3D
		if player != null:
			return player
	var registry := BattlefieldRegistry3D.find(get_tree())
	var candidates: Array = registry.get_combatants() if registry != null else get_tree().get_nodes_in_group("combatant3d")
	for candidate in candidates:
		if candidate is Node3D and candidate.has_method("get_combat_team") and int(candidate.get_combat_team()) != int(combat_team):
			return candidate
	return null

func _squad_center(list: Array[Soldier3D]) -> Vector3:
	return _situation_analyzer.squad_center(list, global_position)

func _average_health_ratio(list: Array[Soldier3D]) -> float:
	return _situation_analyzer.average_health_ratio(list)

func _formation_power(list: Array[Soldier3D]) -> float:
	return _situation_analyzer.formation_power(list)

func _enemy_formation_members(target: Node3D) -> Array[Soldier3D]:
	return _situation_analyzer.enemy_members(get_tree(), target)

func _enemy_formation_power(target: Node3D) -> float:
	return _situation_analyzer.enemy_power(get_tree(), target)

func _enemy_formation_is_aware(target: Node3D) -> bool:
	return _situation_analyzer.enemy_is_aware(get_tree(), target)

func _build_signature(target: Node3D, living: Array[Soldier3D], rule_plan: String) -> String:
	return "%s|%d|%d|%s|%s" % [
		str(target.get_instance_id()) if is_instance_valid(target) else "none",
		living.size(),
		_enemy_formation_members(target).size(),
		str(_enemy_formation_is_aware(target)),
		rule_plan,
	]

func _is_alive(actor: Node) -> bool:
	return _situation_analyzer.is_alive(actor)

func _plan_label(plan: String) -> String:
	match plan:
		"GUARD": return "分散警戒"
		"AMBUSH": return "隐蔽就位、瞄准、齐射"
		"COVER_ATTACK": return "占领掩体后交火"
		"SUPPRESS_FLANK": return "正面压制、侧翼包抄"
		"ASSAULT": return "全军突击"
		"SEARCH_ATTACK": return "搜索并消灭目标"
	return "等待决策"

func _get_registered_covers() -> Array:
	var registry := BattlefieldRegistry3D.find(get_tree())
	return registry.get_covers() if registry != null else get_tree().get_nodes_in_group("cover3d")

func _member_by_id(member_id: String) -> Soldier3D:
	for member in _living_members():
		if String(member.name) == member_id:
			return member
	return null

func _routes_by_id() -> Dictionary:
	var result := {}
	for route in last_route_candidates:
		result[String(route.get("id", ""))] = route
	return result

func _covers_by_id() -> Dictionary:
	var result := {}
	for node in _get_registered_covers():
		if node is TacticalCover3D:
			result[String(node.name)] = node
	return result

func _release_other_cover_reservations(member: Soldier3D, selected: TacticalCover3D) -> void:
	for node in _get_registered_covers():
		if node is TacticalCover3D and node != selected:
			(node as TacticalCover3D).release_slot(member)
