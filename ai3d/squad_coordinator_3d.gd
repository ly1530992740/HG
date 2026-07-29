extends Node3D
class_name SquadCoordinator3D

signal command_changed(plan: String, summary: String, source: String)
signal qwen_debug_updated(input: String, output: String, summary: String)
signal squad_eliminated(squad: SquadCoordinator3D)

@export_category("小队配置")
@export var squad_id: StringName = &"squad3d"
@export var squad_display_name := "红队"
@export var combat_team: Soldier3D.Team = Soldier3D.Team.RED
@export var can_target_players := true
@export var member_root_path := NodePath("Members")
@export var free_when_all_members_dead := false

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
@export_range(0.5, 10.0, 0.1) var qwen_timeout_seconds := 2.8

var members: Array[Soldier3D] = []
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
var _qwen_brain: QwenSquadBrain3D
var _evaluation_timer := 0.0
var _last_qwen_request_msec := -100000
var _directive_version := 0
var _stage_versions: Dictionary = {}
var _last_signature := ""
var _initial_member_count := 0

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
	if use_qwen:
		_qwen_brain = QwenSquadBrain3D.new()
		_qwen_brain.name = "QwenBrain3D"
		_qwen_brain.endpoint = qwen_endpoint
		_qwen_brain.timeout_seconds = qwen_timeout_seconds
		add_child(_qwen_brain)
		_qwen_brain.decision_ready.connect(_on_qwen_decision)
	_register_configured_members()
	_initial_member_count = members.size()
	if knows_primary_target_at_start:
		known_target = _find_primary_target()
	call_deferred("_evaluate_situation", true)

func _process(delta: float) -> void:
	_evaluation_timer -= delta
	if _evaluation_timer <= 0.0:
		_evaluation_timer = evaluation_interval
		_evaluate_situation(false)
	_process_plan_stage()

func get_configured_member_actors() -> Array[Soldier3D]:
	return members.duplicate()

func set_known_combat_objective(target: Node3D) -> void:
	if target == null:
		return
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
		if not soldier.contact_spotted.is_connected(_on_member_contact):
			soldier.contact_spotted.connect(_on_member_contact)
		if not soldier.died.is_connected(_on_member_died):
			soldier.died.connect(_on_member_died)
		members.append(soldier)

func _evaluate_situation(force: bool) -> void:
	var living := _living_members()
	if living.is_empty():
		return
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
	if not use_qwen or _qwen_brain == null or _qwen_brain.pending:
		return
	var now := Time.get_ticks_msec()
	if now - _last_qwen_request_msec < int(qwen_reconsider_interval * 1000.0):
		return
	_last_qwen_request_msec = now
	var state := _build_qwen_state(target, living)
	_qwen_brain.request_decision(state, fallback_plan)
	last_qwen_input = _qwen_brain.last_input
	last_qwen_output = _qwen_brain.last_output
	qwen_debug_updated.emit(last_qwen_input, last_qwen_output, last_command_summary)

func _build_qwen_state(target: Node3D, living: Array[Soldier3D]) -> Dictionary:
	var hostile_count := _enemy_formation_members(target).size() if is_instance_valid(target) else 0
	return {
		"小队": squad_display_name,
		"我方存活": living.size(),
		"我方初始人数": _initial_member_count,
		"平均生命比例": snappedf(_average_health_ratio(living), 0.01),
		"已确认敌军": hostile_count,
		"敌军是否警觉": _enemy_formation_is_aware(target) if is_instance_valid(target) else false,
		"目标距离": snappedf(_squad_center(living).distance_to(target.global_position), 0.1) if is_instance_valid(target) else -1.0,
		"我方火力": snappedf(_formation_power(living), 0.1),
		"敌方火力": snappedf(_enemy_formation_power(target), 0.1) if is_instance_valid(target) else 0.0,
		"掩体数量": _get_registered_covers().size(),
		"候选包抄路线": _route_analyzer.format_for_qwen(),
		"合法总体意图": QwenSquadBrain3D.ALLOWED_PLANS,
	}

func _on_qwen_decision(plan: String, reason: String, raw_output: String, fallback: bool, latency_ms: int) -> void:
	last_qwen_input = _qwen_brain.last_input
	last_qwen_output = raw_output
	last_qwen_reason = reason
	last_qwen_latency_ms = latency_ms
	var source := "RULE_FALLBACK" if fallback else "LOCAL_QWEN"
	var living := _living_members()
	var guarded_plan := _validate_qwen_plan(plan, known_target, living)
	if guarded_plan != plan:
		reason = "程序拒绝不符合当前态势的%s，改为%s" % [_plan_label(plan), _plan_label(guarded_plan)]
		plan = guarded_plan
		source = "QWEN_GUARDED"
	if plan == "AMBUSH" and is_instance_valid(known_target) and _enemy_formation_is_aware(known_target):
		plan = "COVER_ATTACK"
		reason = "敌军已经警觉，程序拒绝过期的伏击意图"
	if plan == "SUPPRESS_FLANK" and _route_analyzer.get_best_available().is_empty():
		plan = "COVER_ATTACK"
		reason = "没有程序验证的侧翼路线，改为掩体交火"
	if not fallback and plan == "SUPPRESS_FLANK":
		_apply_qwen_group_count(raw_output, living.size())
	_apply_plan(plan, known_target, reason, source)
	qwen_debug_updated.emit(last_qwen_input, last_qwen_output, last_command_summary)

func _validate_qwen_plan(plan: String, target: Node3D, living: Array[Soldier3D]) -> String:
	var rule_plan := _choose_rule_plan(target, living)
	if not is_instance_valid(target):
		return "GUARD"
	if plan == "GUARD":
		return rule_plan
	if plan == "AMBUSH" and _enemy_formation_is_aware(target):
		return rule_plan
	if plan == "ASSAULT" and _formation_power(living) <= _enemy_formation_power(target) * 1.35:
		return rule_plan
	if plan == "SUPPRESS_FLANK" and _route_analyzer.get_best_available().is_empty():
		return rule_plan
	return plan

func _apply_qwen_group_count(raw_output: String, living_count: int) -> void:
	var decision = JSON.parse_string(raw_output)
	if not decision is Dictionary or living_count < 2:
		return
	var requested := int(decision.get("机动组人数", flank_member_count))
	flank_member_count = clampi(requested, 1, living_count - 1)

func _apply_plan(plan: String, target: Node3D, reason: String, source: String) -> void:
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
		_issue_to_members(living, SquadDirective3D.Type.AIM, known_target, Vector3.ZERO, [], null, 0.0, "全员稳定瞄准")
		current_stage = 2
	elif current_stage == 2 and _all_current_directives_complete(living):
		_issue_to_members(living, SquadDirective3D.Type.ATTACK, known_target, Vector3.ZERO, [], null, 0.0, "同步开火" if ambush else "掩体还击")
		current_stage = 3

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

func _issue_to_member(member: Soldier3D, type: SquadDirective3D.Type, target: Node3D, position: Vector3, route: Array[Vector3], cover: TacticalCover3D, duration: float, reason: String) -> void:
	_directive_version += 1
	var directive := SquadDirective3D.new().configure(type, _directive_version, target, position, route, cover, duration, reason)
	member.receive_directive(directive)
	_stage_versions[member] = directive.version

func _all_current_directives_complete(list: Array[Soldier3D]) -> bool:
	if list.is_empty():
		return false
	for member in list:
		if not is_instance_valid(member):
			continue
		var expected := int(_stage_versions.get(member, 0))
		if expected <= 0 or member.last_completed_directive_version < expected:
			return false
	return true

func _on_member_contact(_member: Soldier3D, hostile: Node3D) -> void:
	if hostile == null:
		return
	# 保持当前有效目标，避免多个队员的扫描结果让整个小队反复重发指令。
	if is_instance_valid(known_target) and _is_alive(known_target):
		return
	for member in _living_members():
		member.apply_reaction_delay(formation_surprise_delay)
	known_target = hostile
	for member in _living_members():
		member.current_target = hostile
	_evaluate_situation(true)

func _on_member_died(actor: Soldier3D) -> void:
	members.erase(actor)
	_stage_versions.erase(actor)
	if members.is_empty():
		squad_eliminated.emit(self)
		if free_when_all_members_dead:
			queue_free()
	else:
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
	return "等待决策"

func _get_registered_covers() -> Array:
	var registry := BattlefieldRegistry3D.find(get_tree())
	return registry.get_covers() if registry != null else get_tree().get_nodes_in_group("cover3d")
