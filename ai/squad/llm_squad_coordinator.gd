extends SquadCoordinator
class_name LlmSquadCoordinator

signal llm_request_started(state: Dictionary)
signal llm_decision_received(plan: StringName, reason: String, latency_ms: int, used_fallback: bool)

const ALLOWED_PLANS: Array[String] = [
	"TAKE_COVER",
	"SUPPRESS_AND_FLANK",
	"ASSAULT",
	"DEFEND",
	"RETREAT",
	"AMBUSH",
	"GUARD",
]

const PLAN_LABELS := {
	"TAKE_COVER": "寻找掩体",
	"SUPPRESS_AND_FLANK": "压制包抄",
	"ASSAULT": "强攻合围",
	"DEFEND": "防守反击",
	"RETREAT": "掩护撤退",
	"AMBUSH": "伏击包围",
	"GUARD": "分散警戒",
}

const LOCALIZED_PLAN_TO_INTERNAL := {
	"寻找掩体": "TAKE_COVER",
	"压制包抄": "SUPPRESS_AND_FLANK",
	"强攻合围": "ASSAULT",
	"防守反击": "DEFEND",
	"掩护撤退": "RETREAT",
	"伏击包围": "AMBUSH",
	"分散警戒": "GUARD",
}

const TASK_SYSTEM_PROMPT := """你是游戏中的小队长，只根据当前JSON里的已确认态势下达任务。程序会把你的总体意图、分组人数、合法路线和执行顺序编译成每名士兵的GOAP目标。不得虚构坐标、路线、掩体、士兵或敌人。

决策原则：
1. 没有发现敌人时，分散到周边建立多个观察扇区并持续警戒。
2. 敌人未发现我方、接近路线隐蔽且掩体容量足够时，可先全员就位，再全员瞄准，最后同步开火。
3. 双方接敌而正面火力受压时，如果候选路线中存在低暴露侧路，应留下正面组建立压制，至少派3名合适的机动士兵沿合法路线ID包抄；机动必须依赖压制已经建立。
4. 没有合法侧路时依托掩体防守；兵力和生命严重不利时撤退；优势明显且路线允许时才突击。

参考不是固定答案：
- 已知敌军0：总体意图=分散警戒，执行顺序=分散-警戒。
- 敌军未警觉、我方接近隐蔽、掩体容量覆盖全队：总体意图=伏击包围，执行顺序=就位-瞄准-开火。
- 敌方正面火力强且存在低暴露候选路线：总体意图=压制包抄，机动路线ID必须取自候选路线，机动组人数不少于3，执行顺序=压制-机动-侧击。

只输出符合Schema的简体中文JSON，不展示思维过程。"""

@export_group("本地 Qwen 决策")
@export var llm_endpoint := "http://127.0.0.1:8081/v1/chat/completions"
@export_range(0.25, 3.0, 0.25) var llm_timeout_seconds := 3.0
@export_range(1.0, 15.0, 0.5) var llm_min_decision_interval := 4.0
@export var llm_max_tokens := 180
@export var commander_display_name := "SQUAD"
@export var debug_show_full_prompt := false
@export var initial_guard_enabled := true

@export_group("决策调试界面")
@export var status_label_path: NodePath
@export var input_label_path: NodePath
@export var output_label_path: NodePath
@export var orders_label_path: NodePath

var llm_request_count := 0
var llm_success_count := 0
var llm_fallback_count := 0
var llm_request_status := "IDLE"
var last_llm_plan: StringName = &"WAITING"
var last_llm_reason := "等待确认敌情。"
var last_llm_latency_ms := 0
var last_order_summary := "命令：无"
var last_llm_input := "等待确认敌情。"
var last_llm_output := "尚无模型输出。"

var _http_request: HTTPRequest
var _request_pending := false
var _request_started_msec := 0
var _request_target: Node2D = null
var _request_input := ""
var _request_output := ""
var _request_context: StringName = &"combat"
var _last_state: Dictionary = {}
var _last_request_msec := -1000000
var _debug_refresh_timer := 0.0
var task_scheduler: SquadTaskScheduler
var situation_version := 0
var plan_version := 0
var _request_situation_version := 0
var _last_decision: Dictionary = {}
var _guard_requested_for_situation := -1
var _last_tactical_signature := ""
var _search_contact_version_bumped := false

func _ready() -> void:
	super()
	task_scheduler = SquadTaskScheduler.new()
	task_scheduler.name = "SquadTaskScheduler"
	add_child(task_scheduler)
	task_scheduler.task_state_changed.connect(_on_task_state_changed)
	member_unregistered.connect(_on_task_member_unregistered)
	_http_request = HTTPRequest.new()
	_http_request.name = "LlmHttpRequest"
	_http_request.timeout = llm_timeout_seconds
	add_child(_http_request)
	_http_request.request_completed.connect(_on_llm_request_completed)
	_update_decision_label()
	if initial_guard_enabled:
		call_deferred("_request_guard_plan")

func _process(delta: float) -> void:
	super(delta)
	_debug_refresh_timer -= delta
	if _debug_refresh_timer <= 0.0:
		_debug_refresh_timer = 0.25
		last_order_summary = _summarize_current_orders()
		_update_decision_label()

func _begin_ambush(target: Node2D) -> void:
	if _contact_phase == ContactPhase.AMBUSH:
		super._begin_ambush(target)
		return
	if _request_pending:
		return
	_request_llm_decision(target, &"ambush_opportunity")

func _begin_direct_contact(target: Node2D) -> void:
	super._begin_direct_contact(target)
	if not _request_pending:
		_request_llm_decision(target, &"combat")

func _accept_contact_report(observer: SquadMember, contact: CombatContact) -> void:
	if _contact_phase == ContactPhase.SEARCH and not _search_contact_version_bumped:
		_search_contact_version_bumped = true
		situation_version += 1
		_guard_requested_for_situation = -1
		if task_scheduler:
			task_scheduler.cancel_active_plan("发现新敌情")
	super._accept_contact_report(observer, contact)

func _reset_contact_state() -> void:
	super._reset_contact_state()
	_search_contact_version_bumped = false
	situation_version += 1
	if task_scheduler:
		task_scheduler.cancel_active_plan("敌情消失")
	_request_guard_plan()

func _request_guard_plan() -> void:
	if _request_pending or _guard_requested_for_situation == situation_version:
		return
	_guard_requested_for_situation = situation_version
	_request_llm_decision(null, &"no_contact")

func _issue_tactical_order() -> void:
	if _request_pending:
		return
	if Time.get_ticks_msec() - _last_request_msec < int(llm_min_decision_interval * 1000.0):
		return
	var target := _find_primary_target()
	if target == null:
		if _contact_phase == ContactPhase.SEARCH:
			_request_guard_plan()
		return
	refresh_group_analysis(target)
	if task_scheduler != null and task_scheduler.active_plan != null and task_scheduler.active_plan.intent == &"AMBUSH":
		if not _is_target_combat_aware(target) and not bool(blackboard.get_fact(&"estimated_enemy_awareness", false)):
			return
	var signature := _build_tactical_signature(target)
	if task_scheduler != null and task_scheduler.active_plan != null and signature == _last_tactical_signature:
		return
	if not _last_tactical_signature.is_empty() and signature != _last_tactical_signature:
		situation_version += 1
		task_scheduler.cancel_active_plan("关键态势变化")
	_request_llm_decision(target, &"combat")

func _request_llm_decision(target: Node2D, context: StringName) -> void:
	_last_request_msec = Time.get_ticks_msec()
	_request_context = context
	_request_situation_version = situation_version
	refresh_group_analysis(target)
	var candidate_plan_labels := _get_candidate_plan_labels(context)
	var route_ids := _get_available_route_ids()
	if route_ids.is_empty():
		route_ids.append("NONE")
	var state := _build_tactical_state(target, context, candidate_plan_labels)
	_last_tactical_signature = _build_tactical_signature(target) if is_instance_valid(target) else "no_contact"
	_last_state = state
	_request_input = JSON.stringify(state).replace(",", ", ")
	_request_output = ""
	last_llm_input = _format_debug_input(_request_input)
	last_llm_output = "等待本地Qwen返回决策。"
	var schema := {
		"type": "object",
		"properties": {
			"总体意图": {"type": "string", "enum": candidate_plan_labels},
			"正面组人数": {"type": "integer", "minimum": 0, "maximum": 12},
			"机动组人数": {"type": "integer", "minimum": 0, "maximum": 12},
			"机动路线ID": {"type": "string", "enum": route_ids},
			"执行顺序": {"type": "string", "enum": ["分散-警戒", "就位-瞄准-开火", "压制-机动-侧击", "掩体-还击", "推进-攻击", "撤离-警戒"]},
			"理由": {"type": "string", "maxLength": 120},
		},
		"required": ["总体意图", "正面组人数", "机动组人数", "机动路线ID", "执行顺序", "理由"],
		"additionalProperties": false,
	}
	var payload := {
		"model": "qwen3-0.6b",
		"messages": [
			{
				"role": "system",
				"content": TASK_SYSTEM_PROMPT
			},
			{
				"role": "user",
				"content": _request_input + " /no_think"
			},
		],
		"max_tokens": llm_max_tokens,
		"temperature": 0.1,
		"top_p": 0.8,
		"stream": false,
		"response_format": {
			"type": "json_schema",
			"json_schema": {
				"name": "squad_plan",
				"strict": true,
				"schema": schema,
			},
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json; charset=utf-8"])
	_http_request.timeout = llm_timeout_seconds
	var error := _http_request.request(llm_endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_apply_rule_fallback(target, "request_error_%d" % error)
		return
	_request_pending = true
	_request_target = target
	_request_started_msec = Time.get_ticks_msec()
	llm_request_count += 1
	llm_request_status = "PENDING"
	last_llm_reason = "本地Qwen正在分析当前态势。"
	llm_request_started.emit(state)
	_update_decision_label()

func _build_tactical_state(target: Node2D, context: StringName, candidate_plan_labels: Array[String]) -> Dictionary:
	var exposed_count := 0
	var health_total := 0.0
	var health_max_total := 0.0
	var ammo_total := 0
	var role_counts := {
		"步枪手": 0,
		"精确射手": 0,
		"机枪手": 0,
		"霰弹突击手": 0,
		"手枪侦察员": 0,
	}
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var actor := member.actor
		if actor.get_active_cover() == null:
			exposed_count += 1
		health_total += float(actor.get("health"))
		health_max_total += maxf(1.0, float(actor.get("max_health")))
		var firearm := actor.get("firearm_weapon") as FirearmWeapon
		if firearm != null:
			ammo_total += firearm.get_total_ammo()
		match actor.get_combat_role() as SquadCombatRole.Type:
			SquadCombatRole.Type.MARKSMAN:
				role_counts["精确射手"] += 1
			SquadCombatRole.Type.MACHINE_GUNNER:
				role_counts["机枪手"] += 1
			SquadCombatRole.Type.SHOTGUNNER:
				role_counts["霰弹突击手"] += 1
			SquadCombatRole.Type.PISTOL_SCOUT:
				role_counts["手枪侦察员"] += 1
			_:
				role_counts["步枪手"] += 1
	var center := _get_squad_center()
	if not is_instance_valid(target):
		return {
			"任务目标": "保持警戒并及时发现新敌情",
			"候选指令": candidate_plan_labels,
			"我方存活": members.size(),
			"已知敌军": 0,
			"平均生命比例": snappedf(health_total / maxf(1.0, health_max_total), 0.01),
			"总弹药": ammo_total,
			"兵种编成": role_counts,
			"当前状态": "未发现敌人",
			"可用警戒扇区": ["北", "东", "南", "西"],
			"要求": "队员分散站位并覆盖不同方向，不得原地聚集",
		}
	var enemy_aware := _is_target_combat_aware(target)
	var target_facing := Vector2.RIGHT
	if target.has_method("get_facing_direction"):
		target_facing = target.get_facing_direction()
	if target_facing == Vector2.ZERO:
		target_facing = Vector2.RIGHT
	var direction_to_us := (center - target.global_position).normalized()
	var enemy_facing_us := target_facing.normalized().dot(direction_to_us) > 0.25
	var ambush_cover_candidates := _find_ambush_cover_candidates(target)
	var ambush_cover_capacity := 0
	for candidate in ambush_cover_candidates:
		ambush_cover_capacity += int(candidate.get("capacity", 0))
	var ally_count := members.size()
	var known_hostile_count := _count_identified_hostiles(target, context)
	var force_ratio := float(ally_count) / float(maxi(1, known_hostile_count))
	var route_summaries := _format_route_candidates_for_qwen()
	return {
		"任务目标": "在保存兵力的前提下击败敌军",
		"候选指令": candidate_plan_labels,
		"我方存活": ally_count,
		"已知敌军": known_hostile_count,
		"初始兵力": int(blackboard.get_fact(&"initial_squad_strength", members.size())),
		"我方阵亡": int(blackboard.get_fact(&"squad_casualties", 0)),
		"我方人数除以已知敌军人数": snappedf(force_ratio, 0.01),
		"兵力人数差（我方减敌方）": ally_count - known_hostile_count,
		"平均生命比例": snappedf(health_total / maxf(1.0, health_max_total), 0.01),
		"暴露人数": exposed_count,
		"掩体内人数": maxi(0, members.size() - exposed_count),
		"总弹药": ammo_total,
		"兵种编成": role_counts,
		"目标距离": roundi(center.distance_to(target.global_position)),
		"交战时间秒": roundi(_engagement_time),
		"敌军是否警觉": enemy_aware,
		"敌军正面朝向我方": enemy_facing_us,
		"可用隐蔽掩体组": ambush_cover_candidates.size(),
		"隐蔽掩体总容量": ambush_cover_capacity,
		"抵达隐蔽掩体前会进入敌军正面视野": not (context == &"ambush_opportunity" and not enemy_aware),
		"左路可用": bool(blackboard.get_fact(&"left_flank_available", false)),
		"右路可用": bool(blackboard.get_fact(&"right_flank_available", false)),
		"候选包抄路线": route_summaries,
		"敌方正面火力": String(blackboard.get_fact(&"enemy_frontal_firepower", "普通")),
		"上次模型指令": _get_plan_label(String(last_llm_plan)),
	}

func _count_identified_hostiles(target: Node2D, context: StringName) -> int:
	if context != &"ambush_opportunity":
		return int(blackboard.get_fact(&"hostile_alive_count", 0))
	var identified: Dictionary = {}
	var seeds := _collect_known_hostile_targets()
	if is_instance_valid(target) and not seeds.has(target):
		seeds.append(target)
	for seed in seeds:
		if is_instance_valid(seed):
			identified[seed] = true
	for candidate_value in get_tree().get_nodes_in_group("combatant"):
		if not candidate_value is Node2D:
			continue
		var candidate := candidate_value as Node2D
		if identified.has(candidate) or not _is_hostile_target(candidate):
			continue
		if candidate.has_method("is_visually_concealed") and bool(candidate.is_visually_concealed()):
			continue
		for seed in seeds:
			if is_instance_valid(seed) and _same_combat_formation(seed, candidate) and seed.global_position.distance_to(candidate.global_position) <= ambush_formation_identification_radius:
				identified[candidate] = true
				break
	return identified.size()

func _get_candidate_plan_labels(context: StringName) -> Array[String]:
	if context == &"no_contact":
		return [String(PLAN_LABELS["GUARD"])]
	var labels: Array[String] = []
	var left_available := bool(blackboard.get_fact(&"left_flank_available", false))
	var right_available := bool(blackboard.get_fact(&"right_flank_available", false))
	var frontal_firepower := String(blackboard.get_fact(&"enemy_frontal_firepower", "普通"))
	var frontal_assault_viable := not frontal_firepower.begins_with("强")
	for plan in ALLOWED_PLANS:
		if plan == "GUARD":
			continue
		if plan == "AMBUSH" and context != &"ambush_opportunity":
			continue
		if plan == "SUPPRESS_AND_FLANK" and not left_available and not right_available:
			continue
		if plan == "ASSAULT" and not frontal_assault_viable:
			continue
		labels.append(String(PLAN_LABELS[plan]))
	return labels

func _on_llm_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _request_pending:
		return
	_request_pending = false
	last_llm_latency_ms = Time.get_ticks_msec() - _request_started_msec
	if _request_situation_version != situation_version:
		llm_request_status = "STALE"
		last_llm_reason = "态势版本已变化，丢弃旧决策。"
		_request_target = null
		var current_target := _find_primary_target()
		if is_instance_valid(current_target):
			if _is_target_combat_aware(current_target) or bool(blackboard.get_fact(&"estimated_enemy_awareness", false)):
				_begin_direct_contact(current_target)
			else:
				_begin_ambush(current_target)
		else:
			_request_guard_plan()
		return
	var target := _request_target
	_request_target = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_apply_rule_fallback(target, "http_%d_result_%d" % [response_code, result])
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if not response is Dictionary:
		_request_output = body.get_string_from_utf8()
		_apply_rule_fallback(target, "invalid_api_json")
		return
	var choices = response.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		_apply_rule_fallback(target, "missing_choices")
		return
	var message = choices[0].get("message", {})
	var content := String(message.get("content", "")) if message is Dictionary else ""
	_request_output = content
	last_llm_input = _format_debug_input(_request_input)
	last_llm_output = _request_output
	var decision = JSON.parse_string(content)
	if not decision is Dictionary:
		_apply_rule_fallback(target, "invalid_decision_json")
		return
	var localized_plan := String(decision.get("总体意图", ""))
	var plan := String(LOCALIZED_PLAN_TO_INTERNAL.get(localized_plan, ""))
	var reason := String(decision.get("理由", "")).strip_edges()
	_last_decision = decision.duplicate(true)
	var normalized_plan := _normalize_plan_from_reason(plan, reason)
	if normalized_plan != plan:
		_last_decision["模型原始意图"] = localized_plan
		_last_decision["语义校正"] = "%s -> %s" % [plan, normalized_plan]
		print("[LLM COMMANDER] semantic_normalization raw=%s normalized=%s reason=%s" % [plan, normalized_plan, reason])
		plan = normalized_plan
	reason = _validate_decision_reason(plan, reason)
	if plan not in ALLOWED_PLANS:
		_apply_rule_fallback(target, "illegal_plan_%s" % localized_plan)
		return
	if plan == "AMBUSH" and _request_context != &"ambush_opportunity":
		_apply_rule_fallback(target, "ambush_without_hidden_opportunity")
		return
	if plan == "SUPPRESS_AND_FLANK" and route_analyzer != null:
		var selected_route := get_route_candidate(StringName(_last_decision.get("机动路线ID", "")))
		if selected_route.is_empty() or not bool(selected_route.get("available", false)):
			selected_route = get_best_route_candidate()
		if selected_route.is_empty():
			_apply_rule_fallback(target, "no_available_flank_route")
			return
		_last_decision["机动路线ID"] = String(selected_route.get("id", ""))
		_last_decision["程序确认路线"] = String(selected_route.get("reason", ""))
	if plan != "GUARD" and not is_instance_valid(target):
		target = _find_primary_target()
	if plan != "GUARD" and target == null:
		_apply_rule_fallback(null, "target_lost")
		return
	_apply_llm_plan(plan, reason, target)

func _apply_llm_plan(plan: String, reason: String, target: Node2D) -> void:
	plan_version += 1
	var intent := StringName(plan)
	var command_plan := SquadPlanCompiler.compile(self, intent, _last_decision, target, situation_version, plan_version, "LOCAL_QWEN")
	var validation_errors := command_plan.validate()
	if not validation_errors.is_empty() or not task_scheduler.start_plan(command_plan, members):
		_apply_rule_fallback(target, "invalid_task_graph:%s" % ",".join(validation_errors))
		return
	if plan == "GUARD":
		_contact_phase = ContactPhase.SEARCH
		_engagement_active = false
		blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)
		blackboard.set_fact(&"tactical_plan", "PERIMETER_GUARD")
	else:
		_has_ever_engaged = true
		_contact_phase = ContactPhase.COMBAT
		_engagement_active = true
		_engagement_time = 0.0
		if is_instance_valid(target):
			_set_squad_alert_combat(target.global_position)
		blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD if plan == "AMBUSH" else RulesOfEngagement.Type.WEAPONS_FREE)
		blackboard.set_fact(&"tactical_plan", "TASK_%s" % plan)
	blackboard.set_fact(&"contact_phase", _contact_phase)
	llm_success_count += 1
	llm_request_status = "APPLIED"
	last_llm_plan = StringName(plan)
	last_llm_reason = reason if not reason.is_empty() else "模型未提供理由。"
	last_order_summary = _summarize_current_orders()
	blackboard.set_fact(&"commander_source", "LOCAL_QWEN")
	blackboard.set_fact(&"llm_plan", plan)
	blackboard.set_fact(&"llm_reason", last_llm_reason)
	blackboard.set_fact(&"llm_latency_ms", last_llm_latency_ms)
	print("[LLM COMMANDER] plan=%s latency=%dms %s state=%s reason=%s" % [plan, last_llm_latency_ms, last_order_summary, JSON.stringify(_last_state), last_llm_reason])
	llm_decision_received.emit(StringName(plan), last_llm_reason, last_llm_latency_ms, false)
	_update_decision_label()

func _summarize_current_orders() -> String:
	if task_scheduler != null and task_scheduler.active_plan != null:
		return "任务图：" + task_scheduler.get_summary()
	var counts: Dictionary = {}
	for member in members:
		if not is_instance_valid(member):
			continue
		var order := member.get_current_order()
		var order_name := _get_order_label(order.type) if order != null else "无"
		counts[order_name] = int(counts.get(order_name, 0)) + 1
	var parts := PackedStringArray()
	var names := counts.keys()
	names.sort()
	for order_name in names:
		parts.append("%s x%d" % [String(order_name), int(counts[order_name])])
	return "命令：" + "，".join(parts)

func _apply_rule_fallback(target: Node2D, reason: String) -> void:
	_request_pending = false
	_request_target = null
	llm_fallback_count += 1
	llm_request_status = "FALLBACK"
	last_llm_plan = &"RULE_FALLBACK"
	last_llm_reason = reason
	last_llm_input = _format_debug_input(_request_input) if not _request_input.is_empty() else last_llm_input
	last_llm_output = _request_output if not _request_output.is_empty() else "NO VALID MODEL OUTPUT (%s)" % reason
	blackboard.set_fact(&"commander_source", "RULE_FALLBACK")
	blackboard.set_fact(&"llm_reason", reason)
	blackboard.set_fact(&"llm_latency_ms", last_llm_latency_ms)
	var fallback_intent := &"GUARD" if not is_instance_valid(target) else (&"AMBUSH" if _request_context == &"ambush_opportunity" else &"DEFEND")
	_last_decision = {
		"理由": "本地模型不可用，程序按已确认态势生成安全任务图。",
		"机动组人数": 3,
		"机动路线ID": String(get_best_route_candidate().get("id", "NONE")),
	}
	plan_version += 1
	var fallback_plan := SquadPlanCompiler.compile(self, fallback_intent, _last_decision, target, situation_version, plan_version, "RULE_FALLBACK")
	if task_scheduler != null and fallback_plan.validate().is_empty():
		task_scheduler.start_plan(fallback_plan, members)
	if fallback_intent == &"GUARD":
		_contact_phase = ContactPhase.SEARCH
		_engagement_active = false
		blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)
		blackboard.set_fact(&"tactical_plan", "PERIMETER_GUARD")
	else:
		_contact_phase = ContactPhase.COMBAT
		_engagement_active = true
		blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD if fallback_intent == &"AMBUSH" else RulesOfEngagement.Type.WEAPONS_FREE)
		blackboard.set_fact(&"tactical_plan", "TASK_%s" % fallback_intent)
	last_order_summary = _summarize_current_orders()
	print("[LLM COMMANDER] fallback=%s latency=%dms" % [reason, last_llm_latency_ms])
	llm_decision_received.emit(&"RULE_FALLBACK", reason, last_llm_latency_ms, true)
	_update_decision_label()

func _update_decision_label() -> void:
	var tactical_stage := String(blackboard.get_fact(&"tactical_plan", "FORMING_UP"))
	var ready_ratio := float(blackboard.get_fact(&"ambush_ready_ratio", 0.0))
	var aim_ratio := float(blackboard.get_fact(&"ambush_aim_ready_ratio", 0.0))
	var pause_text := "｜演示已暂停，按P继续" if bool(blackboard.get_fact(&"demo_paused", false)) else ""
	_set_debug_text(status_label_path, "%s｜Qwen 0.6B｜%s｜%d ms｜成功%d / 回退%d%s" % [
		commander_display_name,
		_get_request_status_label(llm_request_status),
		last_llm_latency_ms,
		llm_success_count,
		llm_fallback_count,
		pause_text,
	])
	var input_text := last_llm_input if debug_show_full_prompt else _format_debug_state_summary(_last_state)
	var input_control := get_node_or_null(input_label_path)
	if input_control != null:
		input_control.set("scroll_active", debug_show_full_prompt)
	_set_debug_text(input_label_path, input_text)
	_set_debug_text(output_label_path, _format_debug_decision())
	_set_debug_text(orders_label_path, "GOAP：%s\n执行：%s｜就位%d%%｜瞄准%d%%" % [
		last_order_summary.trim_prefix("命令："),
		_get_plan_label(tactical_stage),
		int(round(ready_ratio * 100.0)),
		int(round(aim_ratio * 100.0)),
	])

func _set_debug_text(path: NodePath, value: String) -> void:
	if path.is_empty():
		return
	var control := get_node_or_null(path)
	if control != null:
		control.set("text", value)

func _format_debug_input(state_json: String) -> String:
	return "【系统角色与参考样本】\n%s\n\n【当前态势】\n%s\n/no_think" % [TASK_SYSTEM_PROMPT, state_json]

func _format_debug_state_summary(state: Dictionary) -> String:
	if state.is_empty():
		return "等待侦察数据。"
	if int(state.get("已知敌军", 0)) == 0:
		return "兵力：我方%d｜敌方未发现｜弹药%d\n态势：%s\n任务约束：%s" % [
			int(state.get("我方存活", 0)),
			int(state.get("总弹药", 0)),
			String(state.get("当前状态", "未发现敌人")),
			String(state.get("要求", "分散警戒")),
		]
	var role_parts := PackedStringArray()
	var role_counts: Dictionary = state.get("兵种编成", {})
	for role_name in role_counts:
		var count := int(role_counts[role_name])
		if count > 0:
			role_parts.append("%s%d" % [String(role_name), count])
	var enemy_awareness := "已警觉" if bool(state.get("敌军是否警觉", false)) else "未警觉"
	var enemy_facing := "正面朝向我方" if bool(state.get("敌军正面朝向我方", false)) else "未正面朝向我方"
	var route_exposure := "接近路线暴露" if bool(state.get("抵达隐蔽掩体前会进入敌军正面视野", true)) else "接近路线隐蔽"
	return "兵力：我方%d / 敌方%d｜阵亡%d｜生命%d%%｜弹药%d\n接敌：%s｜%s｜距离%d\n地形：隐蔽掩体%d组 / %d位｜%s｜暴露%d / 掩体内%d\n编成：%s" % [
		int(state.get("我方存活", 0)),
		int(state.get("已知敌军", 0)),
		int(state.get("我方阵亡", 0)),
		int(round(float(state.get("平均生命比例", 0.0)) * 100.0)),
		int(state.get("总弹药", 0)),
		enemy_awareness,
		enemy_facing,
		int(state.get("目标距离", 0)),
		int(state.get("可用隐蔽掩体组", 0)),
		int(state.get("隐蔽掩体总容量", 0)),
		route_exposure,
		int(state.get("暴露人数", 0)),
		int(state.get("掩体内人数", 0)),
		"、".join(role_parts),
	]

func _format_debug_decision() -> String:
	if llm_request_status == "PENDING":
		return "决策：分析中\n依据：正在等待本地模型返回。"
	if last_llm_plan == &"WAITING":
		return "决策：等待接敌\n依据：尚无模型决策。"
	if last_llm_plan == &"RULE_FALLBACK":
		return "决策：规则回退\n原因：%s" % last_llm_reason
	var route := String(_last_decision.get("机动路线", "无"))
	var sequence := String(_last_decision.get("执行顺序", ""))
	var groups := "正面%d / 机动%d" % [int(_last_decision.get("正面组人数", 0)), int(_last_decision.get("机动组人数", 0))]
	return "决策：%s｜%s｜%s\n顺序：%s\n依据：%s" % [_get_plan_label(String(last_llm_plan)), groups, route, sequence, last_llm_reason]

func _get_request_status_label(status: String) -> String:
	match status:
		"PENDING":
			return "正在请求"
		"APPLIED":
			return "已采纳"
		"FALLBACK":
			return "规则回退"
		"STALE":
			return "旧决策已丢弃"
	return "等待接敌"

func _get_plan_label(plan: String) -> String:
	if PLAN_LABELS.has(plan):
		return String(PLAN_LABELS[plan])
	match plan:
		"WAITING", "FORMING_UP":
			return "等待"
		"RULE_FALLBACK":
			return "规则回退"
		"SEARCH_HALT":
			return "原地警戒"
		"SEARCH_SWEEP":
			return "队形搜索"
		"CONTACT_TO_COVER", "LLM_TAKE_COVER":
			return "接敌找掩体"
		"CONTACT_BASE_OF_FIRE":
			return "建立火力线"
		"SUPPRESS_AND_FLANK":
			return "压制包抄"
		"AGGRESSIVE_ENVELOPMENT":
			return "强攻合围"
		"HOLD_DEFENSIVE_LINE":
			return "防守火力线"
		"COVERING_RETREAT":
			return "交替掩护撤退"
		"AMBUSH_SETUP":
			return "寻找掩体并包围"
		"AMBUSH_VOLLEY":
			return "同步齐射"
		"PERIMETER_GUARD":
			return "分散警戒"
	return plan

func _on_task_state_changed(task: SquadTask, _previous: SquadTask.State, current: SquadTask.State) -> void:
	print("[TASK GRAPH] team=%s situation=%d plan=%d task=%s type=%s state=%s recipients=%s" % [
		squad_id,
		situation_version,
		plan_version,
		task.task_id,
		task.get_type_name(),
		SquadTask.State.keys()[current],
		",".join(task.recipient_ids),
	])
	if task.task_id in [&"ambush_fire", &"flank_attack"] and current == SquadTask.State.ACTIVE:
		blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_FREE)
		if task.task_id == &"ambush_fire":
			blackboard.set_fact(&"tactical_plan", "AMBUSH_VOLLEY")
	if task.task_id == &"ambush_cover":
		blackboard.set_fact(&"ambush_ready_ratio", _get_task_progress(task, SquadTask.State.SUCCEEDED))
	elif task.task_id == &"ambush_aim":
		blackboard.set_fact(&"ambush_aim_ready_ratio", _get_task_progress(task, SquadTask.State.SUCCEEDED))
	last_order_summary = _summarize_current_orders()

func _on_task_member_unregistered(member: SquadMember) -> void:
	if task_scheduler != null:
		task_scheduler.remove_member(member)

func _get_task_progress(task: SquadTask, expected: SquadTask.State) -> float:
	if task.member_states.is_empty():
		return 0.0
	var count := 0
	for state in task.member_states.values():
		if state == expected or state == SquadTask.State.READY:
			count += 1
	return float(count) / float(task.member_states.size())

func _build_tactical_signature(target: Node2D) -> String:
	var alive := 0
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor) or not member.actor.is_combat_alive():
			continue
		alive += 1
	var strength_ratio := float(alive) / float(maxi(1, _initial_strength))
	var strength_band := "FULL" if strength_ratio > 0.75 else ("REDUCED" if strength_ratio > 0.5 else "CRITICAL")
	var enemy_firepower_band := String(last_analysis_snapshot.get("enemy_firepower_label", "普通"))
	var best_route := get_best_route_candidate()
	return "%s|%s|%s|%s|%s" % [
		strength_band,
		enemy_firepower_band,
		str(blackboard.get_fact(&"left_flank_available", false)),
		str(blackboard.get_fact(&"right_flank_available", false)),
		String(best_route.get("id", "NONE")),
	]

func _get_available_route_ids() -> Array[String]:
	var result: Array[String] = []
	for route in last_route_candidates:
		if bool(route.get("available", false)):
			result.append(String(route.get("id", "")))
	return result

func _format_route_candidates_for_qwen() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route in last_route_candidates:
		result.append({
			"路线ID": String(route.get("id", "")),
			"方向": String(route.get("side_label", "")),
			"可到达": bool(route.get("available", false)),
			"预计暴露比例": float(route.get("exposure", 1.0)),
			"移动距离": int(route.get("distance", 0)),
			"可掩护人数": int(route.get("capacity", 0)),
			"依据": String(route.get("reason", "")),
		})
	return result

func _normalize_plan_from_reason(plan: String, reason: String) -> String:
	var has_flank_route := bool(blackboard.get_fact(&"left_flank_available", false)) or bool(blackboard.get_fact(&"right_flank_available", false))
	if has_flank_route and (reason.contains("包抄") or reason.contains("侧击")) and (reason.contains("压制") or String(blackboard.get_fact(&"enemy_frontal_firepower", "普通")).begins_with("强")):
		return "SUPPRESS_AND_FLANK"
	if _request_context == &"ambush_opportunity" and reason.contains("瞄准") and (reason.contains("伏击") or reason.contains("同步开火")):
		return "AMBUSH"
	if _request_context == &"no_contact" and reason.contains("警戒"):
		return "GUARD"
	return plan

func _validate_decision_reason(plan: String, reason: String) -> String:
	if plan == "AMBUSH" and (reason.contains("正面火力强") or reason.contains("仅右翼")):
		return "敌军未警觉且未正面朝向我方，接近路线隐蔽，现有掩体容量足以让全队就位瞄准后同步开火。"
	if plan == "GUARD" and not reason.contains("警戒"):
		return "当前没有已确认敌军，分散到多个观察扇区持续警戒。"
	return reason if not reason.is_empty() else "模型已根据当前态势选择任务意图。"

func _get_posture_label(posture: String) -> String:
	match posture:
		"ASSAULT":
			return "进攻"
		"DEFENSIVE":
			return "防守"
		"ROUT":
			return "溃退"
	return "均衡"

func _get_order_label(order_type: SquadOrder.Type) -> String:
	match order_type:
		SquadOrder.Type.HOLD:
			return "警戒"
		SquadOrder.Type.TAKE_COVER:
			return "寻找掩体"
		SquadOrder.Type.SUPPRESS:
			return "压制射击"
		SquadOrder.Type.FOCUS_FIRE:
			return "集中射击"
		SquadOrder.Type.ADVANCE:
			return "推进"
		SquadOrder.Type.RETREAT:
			return "撤退"
		SquadOrder.Type.STAY_HIDDEN:
			return "保持隐蔽"
		SquadOrder.Type.OVERWATCH:
			return "监视射击"
		SquadOrder.Type.FLANK_LEFT:
			return "左翼包抄"
		SquadOrder.Type.FLANK_RIGHT:
			return "右翼包抄"
		SquadOrder.Type.AMBUSH_POSITION:
			return "伏击就位"
		SquadOrder.Type.SEARCH_AREA:
			return "搜索区域"
	return "未知"
