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
]

const PLAN_LABELS := {
	"TAKE_COVER": "寻找掩体",
	"SUPPRESS_AND_FLANK": "压制包抄",
	"ASSAULT": "强攻合围",
	"DEFEND": "防守反击",
	"RETREAT": "掩护撤退",
	"AMBUSH": "伏击包围",
}

const LOCALIZED_PLAN_TO_INTERNAL := {
	"寻找掩体": "TAKE_COVER",
	"压制包抄": "SUPPRESS_AND_FLANK",
	"强攻合围": "ASSAULT",
	"防守反击": "DEFEND",
	"掩护撤退": "RETREAT",
	"伏击包围": "AMBUSH",
}

const SYSTEM_PROMPT := """你是游戏中的小队长。你的任务是在保存兵力的前提下，根据侦察事实选择最合适的战术。只能从当前JSON的候选指令中选择一项，不得虚构士兵、武器、敌人或掩体。

下面是用于理解战术取舍的参考样本。样本中的人数和距离不是规则，请比较当前态势的关键条件后独立判断：
样本一：我方5人、敌军8人；已有3人阵亡，剩余人员平均生命不足一半。输出：{\"指令\":\"掩护撤退\",\"理由\":\"兵力和状态均处劣势，应保存剩余兵力。\"}
样本二：敌军已经警觉；我方7人中5人暴露，附近存在可用掩体。输出：{\"指令\":\"寻找掩体\",\"理由\":\"先降低暴露并建立稳定火力线。\"}
样本三：双方已经交火；我方有机枪手和机动突击手、兵力占优且多人已在掩体。输出：{\"指令\":\"压制包抄\",\"理由\":\"用持续火力限制敌军，再由机动兵种从侧翼接近。\"}
样本四：双方兵力接近且已经互相警觉；我方均在掩体内，但没有适合包抄的机动兵种。输出：{\"指令\":\"防守反击\",\"理由\":\"保持现有火力线，等待敌军暴露后集中反击。\"}
样本五：我方6人、敌军5人；敌军暂未警觉，但双方之间是开阔地，没有可用隐蔽掩体。输出：{\"指令\":\"寻找掩体\",\"理由\":\"直接接近会提前暴露，应先取得能保护队伍的射击位置。\"}
样本六：我方4人、敌军7人；敌军未警觉并背向我方；侧后方有两处互相分开的隐蔽射击位置，容量足够；抵达路径不会进入敌军正面视野。输出：{\"指令\":\"伏击包围\",\"理由\":\"敌军尚未发现我方，可从分散的隐蔽位置形成交叉火力，待全员就位瞄准后同步开火。\"}

只返回符合Schema的JSON。理由必须引用当前态势中的事实，使用简体中文，不要展示思维过程。"""

@export var llm_endpoint := "http://127.0.0.1:8081/v1/chat/completions"
@export_range(0.25, 3.0, 0.25) var llm_timeout_seconds := 3.0
@export_range(1.0, 15.0, 0.5) var llm_min_decision_interval := 4.0
@export var llm_max_tokens := 96
@export var commander_display_name := "SQUAD"
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

func _ready() -> void:
	super()
	_http_request = HTTPRequest.new()
	_http_request.name = "LlmHttpRequest"
	_http_request.timeout = llm_timeout_seconds
	add_child(_http_request)
	_http_request.request_completed.connect(_on_llm_request_completed)
	_update_decision_label()

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

func _issue_tactical_order() -> void:
	if _request_pending:
		return
	if Time.get_ticks_msec() - _last_request_msec < int(llm_min_decision_interval * 1000.0):
		return
	var target := _find_primary_target()
	if target == null:
		super._issue_tactical_order()
		return
	_request_llm_decision(target, &"combat")

func _request_llm_decision(target: Node2D, context: StringName) -> void:
	_last_request_msec = Time.get_ticks_msec()
	_request_context = context
	var candidate_plan_labels := _get_candidate_plan_labels(context)
	var state := _build_tactical_state(target, context, candidate_plan_labels)
	_last_state = state
	_request_input = JSON.stringify(state).replace(",", ", ")
	_request_output = ""
	last_llm_input = _format_debug_input(_request_input)
	last_llm_output = "等待本地Qwen返回决策。"
	var schema := {
		"type": "object",
		"properties": {
			"指令": {"type": "string", "enum": candidate_plan_labels},
			"理由": {"type": "string", "maxLength": 120},
		},
		"required": ["指令", "理由"],
		"additionalProperties": false,
	}
	var payload := {
		"model": "qwen3-0.6b",
		"messages": [
			{
				"role": "system",
				"content": SYSTEM_PROMPT
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
	var labels: Array[String] = []
	for plan in ALLOWED_PLANS:
		if plan == "AMBUSH" and context != &"ambush_opportunity":
			continue
		labels.append(String(PLAN_LABELS[plan]))
	return labels

func _on_llm_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _request_pending:
		return
	_request_pending = false
	last_llm_latency_ms = Time.get_ticks_msec() - _request_started_msec
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
	var localized_plan := String(decision.get("指令", ""))
	var plan := String(LOCALIZED_PLAN_TO_INTERNAL.get(localized_plan, ""))
	var reason := String(decision.get("理由", "")).strip_edges()
	if plan not in ALLOWED_PLANS:
		_apply_rule_fallback(target, "illegal_plan_%s" % localized_plan)
		return
	if plan == "AMBUSH" and _request_context != &"ambush_opportunity":
		_apply_rule_fallback(target, "ambush_without_hidden_opportunity")
		return
	if not is_instance_valid(target):
		target = _find_primary_target()
	if target == null:
		_apply_rule_fallback(null, "target_lost")
		return
	_apply_llm_plan(plan, reason, target)

func _apply_llm_plan(plan: String, reason: String, target: Node2D) -> void:
	if _request_context == &"ambush_opportunity" and plan != "AMBUSH" and _contact_phase == ContactPhase.SEARCH:
		super._begin_direct_contact(target)
	match plan:
		"TAKE_COVER":
			var exposed := _get_members_out_of_cover()
			if exposed.is_empty():
				_issue_defensive_plan(target)
			else:
				blackboard.set_fact(&"tactical_plan", "LLM_TAKE_COVER")
				_coordinate_cover_move(target, exposed, 110)
		"SUPPRESS_AND_FLANK":
			_issue_combined_arms_plan(target, false)
		"ASSAULT":
			_issue_combined_arms_plan(target, true)
		"DEFEND":
			_issue_defensive_plan(target)
		"RETREAT":
			_issue_covering_retreat(target)
		"AMBUSH":
			super._begin_ambush(target)
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
	if is_instance_valid(target):
		if _request_context == &"ambush_opportunity" and _contact_phase == ContactPhase.SEARCH:
			super._begin_ambush(target)
		else:
			super._issue_tactical_order()
	print("[LLM COMMANDER] fallback=%s latency=%dms" % [reason, last_llm_latency_ms])
	llm_decision_received.emit(&"RULE_FALLBACK", reason, last_llm_latency_ms, true)
	_update_decision_label()

func _update_decision_label() -> void:
	var tactical_stage := String(blackboard.get_fact(&"tactical_plan", "FORMING_UP"))
	var ready_ratio := float(blackboard.get_fact(&"ambush_ready_ratio", 0.0))
	var aim_ratio := float(blackboard.get_fact(&"ambush_aim_ready_ratio", 0.0))
	var pause_text := "｜演示已暂停，按P继续" if bool(blackboard.get_fact(&"demo_paused", false)) else ""
	_set_debug_text(status_label_path, "%s｜本地Qwen 0.6B｜%s｜上次：%s｜%d毫秒｜成功%d/回退%d\n当前阶段：%s｜就位%d%%｜瞄准%d%%%s" % [
		commander_display_name,
		_get_request_status_label(llm_request_status),
		_get_plan_label(String(last_llm_plan)),
		last_llm_latency_ms,
		llm_success_count,
		llm_fallback_count,
		_get_plan_label(tactical_stage),
		int(round(ready_ratio * 100.0)),
		int(round(aim_ratio * 100.0)),
		pause_text,
	])
	_set_debug_text(input_label_path, last_llm_input)
	_set_debug_text(output_label_path, last_llm_output)
	_set_debug_text(orders_label_path, "实际交给GOAP：%s" % last_order_summary)

func _set_debug_text(path: NodePath, value: String) -> void:
	if path.is_empty():
		return
	var control := get_node_or_null(path)
	if control != null:
		control.set("text", value)

func _format_debug_input(state_json: String) -> String:
	return "【系统角色与参考样本】\n%s\n\n【当前态势】\n%s\n/no_think" % [SYSTEM_PROMPT, state_json]

func _get_request_status_label(status: String) -> String:
	match status:
		"PENDING":
			return "正在请求"
		"APPLIED":
			return "已采纳"
		"FALLBACK":
			return "规则回退"
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
	return plan

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
