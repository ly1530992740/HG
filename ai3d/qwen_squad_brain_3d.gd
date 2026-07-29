extends Node
class_name QwenSquadBrain3D

signal request_started(state: Dictionary)
signal decision_ready(plan: String, reason: String, raw_output: String, fallback: bool, latency_ms: int)

const ALLOWED_PLANS := ["GUARD", "AMBUSH", "COVER_ATTACK", "SUPPRESS_FLANK", "ASSAULT"]
const SYSTEM_PROMPT := """你是游戏中的小队长。程序会提供当前已确认兵力、敌我警觉状态、掩体和经过程序验证的侧翼路线。
你的职责是选择总体战术和分组人数，不得虚构坐标、路线、士兵或敌人。
无敌情时选择GUARD；敌人未发现我方且存在隐蔽接近条件时可选AMBUSH；双方接敌时优先COVER_ATTACK；正面火力劣势且存在低暴露侧路时选SUPPRESS_FLANK；优势明显时可选ASSAULT。所有小队必须坚持战斗，伤亡严重时选择COVER_ATTACK固守掩体，不得撤退或逃跑。
只输出JSON，不展示思维过程。"""

@export_category("本地Qwen")
@export var endpoint := "http://127.0.0.1:8081/v1/chat/completions"
@export var model := "qwen3-0.6b"
@export_range(0.5, 10.0, 0.1) var timeout_seconds := 2.8
@export_range(32, 512, 8) var max_tokens := 180

var pending := false
var last_input := ""
var last_output := ""
var last_plan := "WAITING"
var last_reason := "等待态势"
var last_latency_ms := 0
var _fallback_plan := "GUARD"
var _started_msec := 0
var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "QwenHttpRequest"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func request_decision(state: Dictionary, fallback_plan: String) -> bool:
	if pending:
		return false
	_fallback_plan = fallback_plan if fallback_plan in ALLOWED_PLANS else "GUARD"
	last_input = JSON.stringify(state, "  ")
	last_output = "等待本地Qwen返回"
	var route_ids: Array[String] = ["NONE"]
	for route in state.get("候选包抄路线", []):
		var route_id := String(route.get("路线ID", ""))
		if not route_id.is_empty():
			route_ids.append(route_id)
	var schema := {
		"type": "object",
		"properties": {
			"总体意图": {"type": "string", "enum": ALLOWED_PLANS},
			"正面组人数": {"type": "integer", "minimum": 0, "maximum": 12},
			"机动组人数": {"type": "integer", "minimum": 0, "maximum": 12},
			"机动路线ID": {"type": "string", "enum": route_ids},
			"理由": {"type": "string", "maxLength": 120},
		},
		"required": ["总体意图", "正面组人数", "机动组人数", "机动路线ID", "理由"],
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
		"response_format": {"type": "json_schema", "json_schema": {"name": "squad_plan_3d", "strict": true, "schema": schema}},
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
	var decision = JSON.parse_string(content)
	if not decision is Dictionary:
		_emit_fallback("决策JSON无效")
		return
	var plan := String(decision.get("总体意图", ""))
	if plan not in ALLOWED_PLANS:
		_emit_fallback("非法总体意图：%s" % plan)
		return
	last_plan = plan
	last_reason = String(decision.get("理由", "模型未说明理由"))
	decision_ready.emit(last_plan, last_reason, last_output, false, last_latency_ms)

func _emit_fallback(reason: String) -> void:
	pending = false
	last_plan = _fallback_plan
	last_reason = reason
	if last_output.is_empty() or last_output == "等待本地Qwen返回":
		last_output = "规则回退：%s" % reason
	decision_ready.emit(last_plan, last_reason, last_output, true, last_latency_ms)
