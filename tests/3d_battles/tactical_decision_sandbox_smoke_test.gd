extends Node

const SANDBOX_SCENE := preload("res://tests/3d_battles/tactical_decision_sandbox_3d.tscn")

var _failures: Array[String] = []
var _cases := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sandbox := SANDBOX_SCENE.instantiate() as TacticalDecisionSandbox3D
	sandbox.start_paused = true
	add_child(sandbox)
	await get_tree().process_frame
	await get_tree().process_frame
	sandbox.set_simulation_paused(true)
	sandbox.force_debug_analysis()
	await get_tree().process_frame
	await get_tree().process_frame
	var initial := sandbox.get_sandbox_debug_snapshot()
	_check(int(initial.get("blue_members", 0)) == 4, "Default blue force should contain four soldiers")
	_check(int(initial.get("red_members", 0)) == 4, "Default red force should contain four soldiers")
	_check(int(initial.get("editable_covers", 0)) == 5, "Default terrain should contain five editable covers")
	_check(int(initial.get("editable_grass", 0)) == 2, "Default terrain should contain two editable grass zones")
	_check(int(initial.get("heat_cells", 0)) > 0, "Squad perception heatmap should render sampled cells")
	_check(bool(initial.get("ui_visible", false)), "Sandbox debug UI should be visible by default")
	sandbox.set_debug_ui_visible(false)
	_check(not bool(sandbox.get_sandbox_debug_snapshot().get("ui_visible", true)), "Debug UI should support temporary hiding")
	_check(sandbox.debug_move_soldier_initial("Blue_Rifle_01", Vector3(-8.0, 0.0, 11.0)),
		"Hiding the UI must not disable battlefield editing")
	sandbox.set_debug_ui_visible(true)
	var analysis := initial.get("analysis", {}) as Dictionary
	_check(not (analysis.get("candidates", []) as Array).is_empty(), "Utility preview should expose legal candidates")
	_check(not (analysis.get("preview_tasks", []) as Array).is_empty(), "HTN preview should expose decomposed tasks")
	await get_tree().process_frame
	var moved_soldier := sandbox.get_node("SandboxWorld/Actors/BlueSquad/Members/Blue_Rifle_01") as Soldier3D
	_check(moved_soldier.global_position.distance_to(Vector3(-8.0, 0.0, 11.0)) < 0.05,
		"Dragged soldier should keep the edited initial position")

	sandbox.debug_add_cover(Vector3(12.0, 0.0, 0.0))
	sandbox.debug_add_grass(Vector3(-14.0, 0.0, 2.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var edited := sandbox.get_sandbox_debug_snapshot()
	_check(int(edited.get("editable_covers", 0)) == 6, "Paused sandbox should accept new cover")
	_check(int(edited.get("editable_grass", 0)) == 3, "Paused sandbox should accept new grass")

	_check(sandbox.debug_select_source("Blue_Rifle_01"), "A specific soldier local threat source should be selectable")
	await get_tree().process_frame
	await get_tree().process_frame
	var local := sandbox.get_sandbox_debug_snapshot()
	_check(int(local.get("heat_cells", 0)) > 0, "SoldierLocalThreatField3D should render sampled local cells")

	sandbox.set_simulation_paused(false)
	await get_tree().create_timer(3.0, true, false, true).timeout
	var blue := sandbox.get_node("SandboxWorld/Actors/BlueSquad") as SquadCoordinator3D
	var red := sandbox.get_node("SandboxWorld/Actors/RedSquad") as SquadCoordinator3D
	_check(blue.get_advanced_tactics().belief.get_estimated_enemy_count() > 0, "Running sandbox should let blue acquire perception-scoped contacts")
	_check(red.get_advanced_tactics().belief.get_estimated_enemy_count() > 0, "Running sandbox should let red acquire perception-scoped contacts")
	_check(blue.current_plan != "WAITING", "Running sandbox should dispatch a blue tactical plan")
	_check(red.current_plan != "WAITING", "Running sandbox should dispatch a red tactical plan")
	var red_state_before_preview := red.get_advanced_tactics().mission.get_state_name()
	sandbox.set_simulation_paused(true)
	_check(sandbox.debug_select_source("red_squad"), "Red squad debug source should be selectable")
	sandbox.force_debug_analysis()
	await get_tree().process_frame
	await get_tree().process_frame
	var paused_analysis := (sandbox.get_sandbox_debug_snapshot().get("analysis", {}) as Dictionary)
	_check(String(paused_analysis.get("mission_state", "")) == red_state_before_preview,
		"Paused preview must not reset the live mission state")
	var paused_simulation_frame := int(paused_analysis.get("simulation_frame", -1))
	sandbox.force_debug_analysis()
	await get_tree().process_frame
	var repeated_pause_analysis := (sandbox.get_sandbox_debug_snapshot().get("analysis", {}) as Dictionary)
	_check(int(repeated_pause_analysis.get("simulation_frame", -2)) == paused_simulation_frame,
		"Repeated paused analysis should evaluate the same frozen physics frame")

	get_tree().paused = false
	if _failures.is_empty():
		print("TACTICAL_DECISION_SANDBOX_PASS cases=%d" % _cases)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("TACTICAL_DECISION_SANDBOX_FAIL cases=%d failures=%d" % [_cases, _failures.size()])
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	_cases += 1
	if not condition:
		_failures.append(message)
