extends Node

const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")
var _failed := false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	soldier.name = "StateChart_Test_Soldier"
	soldier.immediate_threat_seconds = 0.08
	soldier.threat_memory_seconds = 0.12
	soldier.autonomy_scan_seconds = 0.05
	add_child(soldier)
	await _wait_physics_frames(2)
	var controller := soldier._state_chart_controller as SoldierStateChart3D
	_assert(controller != null, "soldier must create its State Chart controller")
	var chart := controller.get_state_chart() if controller != null else null
	_assert(chart is StateChart, "controller must use the Godot State Charts StateChart node")
	_assert(chart != null and chart.get_node_or_null("SoldierExecution/IdleSecurity/DirectiveReceived") is Transition,
		"directive changes must be represented by a State Charts transition")

	var directive := SquadDirective3D.new().configure(
		SquadDirective3D.Type.HOLD_SECTOR,
		41,
		null,
		soldier.global_position,
		[],
		null,
		5.0,
		"State Chart interruption-resume smoke test"
	)
	soldier.receive_directive(directive)
	await _wait_physics_frames(4)
	var before := soldier.get_autonomy_debug_snapshot()
	_assert(before.get("root_state", "") == "EXECUTE_ORDER", "soldier must execute the assigned order")
	_assert((chart.get_node("SoldierExecution/ExecuteOrder") as AtomicState).active,
		"the plugin ExecuteOrder state must be active")

	soldier.notify_near_miss(soldier.global_position + Vector3(8.0, 0.0, 0.0), null, 1.0)
	await _wait_physics_frames(2)
	var interrupted := soldier.get_autonomy_debug_snapshot()
	_assert(interrupted.get("root_state", "") == "SURVIVAL_OVERRIDE", "danger must interrupt order execution")
	_assert(interrupted.get("resume_order_state", "") == "HOLD_SECTOR", "interruption must preserve the order state")
	_assert((chart.get_node("SoldierExecution/SurvivalOverride") as AtomicState).active,
		"the plugin SurvivalOverride state must be active")

	soldier._immediate_threat_timer = 0.0
	soldier._threat_memory_timer = 0.0
	soldier._environmental_danger = false
	soldier._contact_response_complete = true
	soldier._autonomy_escape_position = soldier.global_position
	await _wait_physics_frames(40)
	var resumed := soldier.get_autonomy_debug_snapshot()
	_assert(resumed.get("root_state", "") == "EXECUTE_ORDER", "soldier must resume the interrupted order")
	_assert(soldier.get_directive_version() == 41, "resume must retain the same directive")
	_assert(soldier.last_completed_directive_version < 41, "survival interruption must not complete a long hold order")
	soldier._die()
	var dead_snapshot := soldier.get_autonomy_debug_snapshot()
	_assert(dead_snapshot.get("root_state", "") == "DEAD", "death must enter the State Chart dead state before physics stops")
	_assert((chart.get_node("SoldierExecution/Dead") as AtomicState).active,
		"the plugin Dead state must be active")
	print("[STATE_CHART_SMOKE_PASS] interruption_resume action=%s" % resumed.get("action", ""))
	get_tree().quit(1 if _failed else 0)

func _wait_physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[STATE_CHART_SMOKE_FAIL] %s" % message)
