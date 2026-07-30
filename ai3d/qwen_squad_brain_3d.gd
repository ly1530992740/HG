extends Node
class_name QwenSquadBrain3D

signal request_started(state: Dictionary)
signal decision_ready(decision: Dictionary, reason: String, raw_output: String, fallback: bool, latency_ms: int, situation_version: int)
signal candidate_ready(candidate_id: String, reason: String, raw_output: String, fallback: bool, latency_ms: int, context_version: int)

const ALLOWED_PLANS := ["AMBUSH", "COVER_ATTACK", "SUPPRESS_FLANK", "ASSAULT", "SEARCH_ATTACK"]
const ALLOWED_GOALS := ["TAKE_COVER", "AIM_TARGET", "SUPPRESS_TARGET", "FLANK_TARGET", "ATTACK_TARGET", "MOVE_TO_ROUTE"]
const SINGLE_MEMBER_GOALS := ["TAKE_COVER", "AIM_TARGET", "ATTACK_TARGET", "MOVE_TO_ROUTE"]
const SYSTEM_PROMPT := """你是游戏中的实体小队长，你自己也是成员之一。唯一任务是持续规划进攻并消灭指定目标，不得撤退、逃跑、投降或攻击其他目标。
程序提供的JSON只包含已确认的成员、敌情、掩体和合法路线。你只能引用JSON中存在的成员ID、目标ID、路线ID和掩体ID，不得虚构坐标或对象。
每个阶段内，每名存活成员最多接受一条命令；同一成员可以在后续阶段继续接受瞄准或攻击命令。相同命令可在members中合并。phase为执行阶段，阶段1完成后才执行阶段2。最多3个阶段，所有成员最终都必须承担攻击、压制或包抄任务。
敌人未警觉时可先占掩体、瞄准再攻击；正面受阻且有侧路时可分配压制与包抄；只有一名成员时不得压制分组或包抄。
只输出符合JSON Schema的JSON，不输出思维过程。"""

@export_category("本地Qwen")
@export var endpoint := "http://127.0.0.1:8081/v1/chat/completions"
@export var model := "qwen3-0.6b"
@export_range(0.5, 10.0, 0.1) var timeout_seconds := 4.0
@export_range(64, 768, 8) var max_tokens := 480

var pending := false
var last_input := ""
var last_output := ""
var last_plan := "WAITING"
var last_reason := "等待态势"
var last_latency_ms := 0
var _fallback_plan := "COVER_ATTACK"
var _started_msec := 0
var _request_situation_version := 0
var _request_kind := &"orders"
var _candidate_fallback_id := ""
var _http: HTTPRequest

static func get_legal_goals(member_count: int, has_target: bool) -> Array[String]:
	if not has_target:
		return ["MOVE_TO_ROUTE"]
	return SINGLE_MEMBER_GOALS.duplicate() if member_count <= 1 else ALLOWED_GOALS.duplicate()

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "QwenHttpRequest"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed_router)

func request_decision(state: Dictionary, fallback_plan: String, situation_version := 0) -> bool:
	if pending:
		return false
	_fallback_plan = fallback_plan if fallback_plan in ALLOWED_PLANS else "COVER_ATTACK"
	_request_situation_version = situation_version
	_request_kind = &"orders"
	last_input = JSON.stringify(state, "  ")
	last_output = "等待本地Qwen返回"

	var member_ids: Array[String] = []
	for member in state.get("squad", {}).get("members", []):
		member_ids.append(String(member.get("id", "")))
	var route_ids: Array[String] = ["NONE"]
	for route in state.get("routes", []):
		if bool(route.get("reachable", false)):
			route_ids.append(String(route.get("id", "")))
	var cover_ids: Array[String] = ["NONE"]
	for cover in state.get("covers", []):
		if int(cover.get("free_slots", 0)) > 0:
			cover_ids.append(String(cover.get("id", "")))
	var target_id := String(state.get("mission", {}).get("target_id", "UNKNOWN"))
	var legal_goals: Array = state.get("legal_goals", get_legal_goals(member_ids.size(), target_id != "UNKNOWN"))

	var order_schema := {
		"type": "object",
		"properties": {
			"phase": {"type": "integer", "minimum": 1, "maximum": 3},
			"members": {"type": "array", "items": {"type": "string", "enum": member_ids}, "minItems": 1, "uniqueItems": true},
			"goal": {"type": "string", "enum": legal_goals},
			"route": {"type": "string", "enum": route_ids},
			"cover": {"type": "string", "enum": cover_ids},
		},
		"required": ["phase", "members", "goal", "route", "cover"],
		"additionalProperties": false,
	}
	var schema := {
		"type": "object",
		"properties": {
			"intent": {"type": "string", "enum": ALLOWED_PLANS},
			"reason": {"type": "string", "maxLength": 120},
			"orders": {"type": "array", "items": order_schema, "minItems": 1, "maxItems": 12},
		},
		"required": ["intent", "reason", "orders"],
		"additionalProperties": false,
	}
	var payload := {
		"model": model,
		"messages": [
			{"role": "system", "content": SYSTEM_PROMPT},
			{"role": "user", "content": last_input + "\n/no_think"},
		],
		"temperature": 0.1,
		"top_p": 0.8,
		"max_tokens": max_tokens,
		"stream": false,
		"response_format": {"type": "json_schema", "json_schema": {"name": "squad_orders_3d", "strict": true, "schema": schema}},
	}
	_http.timeout = timeout_seconds
	var error := _http.request(endpoint, PackedStringArray(["Content-Type: application/json; charset=utf-8"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_emit_fallback("请求无法启动：%d" % error)
		return false
	pending = true
	_started_msec = Time.get_ticks_msec()
	request_started.emit(state)
	return true

func request_candidate_selection(state: Dictionary, candidates: Array[Dictionary], fallback_id: String, context_version: int) -> bool:
	if pending or candidates.is_empty():
		return false
	var candidate_ids: Array[String] = []
	var candidate_facts: Array[Dictionary] = []
	for candidate in candidates:
		var candidate_id := String(candidate.get("id", ""))
		if candidate_id.is_empty() or candidate_id in candidate_ids:
			continue
		candidate_ids.append(candidate_id)
		candidate_facts.append({
			"id": candidate_id,
			"kind": String(candidate.get("kind", "")),
			"utility": snappedf(float(candidate.get("utility", 0.0)), 0.1),
		})
	if candidate_ids.is_empty():
		return false
	_request_kind = &"candidate"
	_request_situation_version = context_version
	_candidate_fallback_id = fallback_id if fallback_id in candidate_ids else candidate_ids[0]
	last_input = JSON.stringify({"battlefield": state, "legal_candidates": candidate_facts}, "  ")
	last_output = "Waiting for local Qwen candidate selection"
	var schema := {
		"type": "object",
		"properties": {
			"candidate_id": {"type": "string", "enum": candidate_ids},
			"reason": {"type": "string", "maxLength": 120},
		},
		"required": ["candidate_id", "reason"],
		"additionalProperties": false,
	}
	var payload := {
		"model": model,
		"messages": [
			{"role": "system", "content": "You select squad tactical intent from limited reported intelligence. Choose exactly one legal candidate ID. Never invent coordinates, contacts, routes, or commands. Output only schema-valid JSON."},
			{"role": "user", "content": last_input + "\n/no_think"},
		],
		"temperature": 0.1,
		"top_p": 0.8,
		"max_tokens": 160,
		"stream": false,
		"response_format": {"type": "json_schema", "json_schema": {"name": "squad_candidate_3d", "strict": true, "schema": schema}},
	}
	_http.timeout = timeout_seconds
	var error := _http.request(endpoint, PackedStringArray(["Content-Type: application/json; charset=utf-8"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_emit_candidate_fallback("candidate request could not start: %d" % error)
		return false
	pending = true
	_started_msec = Time.get_ticks_msec()
	request_started.emit(state)
	return true

func _on_request_completed_router(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _request_kind != &"candidate":
		_on_request_completed(result, response_code, headers, body)
		return
	pending = false
	last_latency_ms = Time.get_ticks_msec() - _started_msec
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_emit_candidate_fallback("model unavailable: result=%d code=%d" % [result, response_code])
		return
	var envelope = JSON.parse_string(body.get_string_from_utf8())
	if not envelope is Dictionary:
		_emit_candidate_fallback("response envelope is not JSON")
		return
	var choices: Array = envelope.get("choices", [])
	if choices.is_empty():
		_emit_candidate_fallback("response has no choices")
		return
	var content := String((choices[0] as Dictionary).get("message", {}).get("content", "")).strip_edges()
	last_output = content
	print("[QWEN3D_CANDIDATE_RAW] %s" % content.replace("\n", " "))
	var decision = JSON.parse_string(content)
	if not decision is Dictionary:
		_emit_candidate_fallback("candidate response is not valid JSON")
		return
	var candidate_id := String(decision.get("candidate_id", ""))
	if candidate_id.is_empty():
		_emit_candidate_fallback("candidate response omitted candidate_id")
		return
	last_plan = candidate_id
	last_reason = String(decision.get("reason", "model did not provide a reason"))
	candidate_ready.emit(candidate_id, last_reason, last_output, false, last_latency_ms, _request_situation_version)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	pending = false
	last_latency_ms = Time.get_ticks_msec() - _started_msec
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_emit_fallback("模型不可用 result=%d code=%d" % [result, response_code])
		return
	var envelope = JSON.parse_string(body.get_string_from_utf8())
	if not envelope is Dictionary:
		_emit_fallback("响应不是JSON")
		return
	var choices: Array = envelope.get("choices", [])
	if choices.is_empty():
		_emit_fallback("响应没有choices")
		return
	var content := String((choices[0] as Dictionary).get("message", {}).get("content", "")).strip_edges()
	last_output = content
	print("[QWEN3D_RAW] %s" % content.replace("\n", " "))
	var decision = JSON.parse_string(content)
	if not decision is Dictionary:
		_emit_fallback("决策JSON无效")
		return
	var intent := String(decision.get("intent", ""))
	if intent not in ALLOWED_PLANS:
		_emit_fallback("非法总体意图：%s" % intent)
		return
	last_plan = intent
	last_reason = String(decision.get("reason", "模型未说明理由"))
	decision_ready.emit(decision, last_reason, last_output, false, last_latency_ms, _request_situation_version)

func _emit_fallback(reason: String) -> void:
	pending = false
	last_plan = _fallback_plan
	last_reason = reason
	if last_output.is_empty() or last_output == "等待本地Qwen返回":
		last_output = "规则回退：%s" % reason
	push_warning("[QWEN3D_FALLBACK] %s" % reason)
	var decision := {"intent": _fallback_plan, "reason": reason, "orders": []}
	decision_ready.emit(decision, last_reason, last_output, true, last_latency_ms, _request_situation_version)

func _emit_candidate_fallback(reason: String) -> void:
	pending = false
	last_plan = _candidate_fallback_id
	last_reason = reason
	if last_output.is_empty() or last_output == "Waiting for local Qwen candidate selection":
		last_output = "Rule fallback: %s" % reason
	push_warning("[QWEN3D_CANDIDATE_FALLBACK] %s" % reason)
	candidate_ready.emit(_candidate_fallback_id, reason, last_output, true, last_latency_ms, _request_situation_version)
