extends Node
const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")
var _failed := false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var influence := SquadInfluenceMap3D.new()
	influence.configure(2.0, 20.0)
	influence.origin = Vector3.ZERO
	for x in range(-6, 7):
		for z in range(-6, 7):
			influence.cells[Vector2i(x, z)] = _cell(0.0)
	for x in range(-3, 4):
		for z in range(-1, 2):
			influence.cells[Vector2i(x, z)] = _cell(100.0)
	influence.version = 7

	var planner := SquadHeatmapRoutePlanner3D.new()
	var origin := Vector3(-10.0, 0.0, 0.0)
	var destination := Vector3(10.0, 0.0, 0.0)
	var direct: Array[Vector3] = [destination]
	var direct_metrics := planner.evaluate_route(origin, direct, influence)
	var plan := planner.build_route(origin, destination, influence)
	var route: Array[Vector3] = []
	route.assign(plan.get("route", []))
	_assert(route.size() > 1, "minimum-cost routing must add a detour around the lethal corridor")
	_assert(float(plan.get("peak_threat", 100.0)) < float(direct_metrics.get("peak_threat", 0.0)), "selected route must reduce peak threat")
	_assert(float(plan.get("exposure_seconds", INF)) < float(direct_metrics.get("exposure_seconds", 0.0)), "selected route must reduce exposure time")
	var left_corridor := false
	for point in route:
		if absf(point.z) >= 3.5:
			left_corridor = true
			break
	_assert(left_corridor, "route must visibly leave the direct-fire corridor")
	_assert(float(plan.get("route_length", 0.0)) <= float(plan.get("baseline_length", 0.0)) * 1.65 + 0.05,
		"safe detour must stay inside the configured length ratio")
	_assert(float(plan.get("route_length", 0.0)) <= float(plan.get("baseline_length", 0.0)) + 10.05,
		"safe detour must stay inside the configured extra-distance budget")
	_assert(String(plan.get("selection_reason", "")) == "risk_route_within_budget",
		"affordable safe detour must be selected explicitly")

	_test_route_budget_limit(planner)
	_test_only_dangerous_route(planner)
	_test_directional_cover_shadow()

	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	soldier.name = "StateChart_Route_Test_Soldier"
	add_child(soldier)
	await get_tree().physics_frame
	soldier.relocate_for_scenario_setup(origin)
	soldier.set_squad_influence_map(influence)
	var directive := SquadDirective3D.new().configure(
		SquadDirective3D.Type.MOVE,
		91,
		null,
		destination,
		[],
		null,
		0.0,
		"route invariant smoke test"
	)
	soldier.receive_directive(directive)
	_assert(directive.route.size() > 1, "Soldier3D must plan a minimum-cost route even when the caller supplies no route")
	_assert(directive.route_peak_threat < float(direct_metrics.get("peak_threat", 0.0)), "soldier-issued route must avoid peak threat")
	print("[TACTICAL_ROUTE_SMOKE_PASS] points=%d direct_peak=%.1f safe_peak=%.1f" % [
		route.size(), float(direct_metrics.get("peak_threat", 0.0)), float(plan.get("peak_threat", 0.0)),
	])
	get_tree().quit(1 if _failed else 0)

func _test_route_budget_limit(planner: SquadHeatmapRoutePlanner3D) -> void:
	var influence := SquadInfluenceMap3D.new()
	influence.configure(2.0, 32.0)
	influence.origin = Vector3.ZERO
	for x in range(-8, 9):
		for z in range(-8, 9):
			var threat := 100.0 if x in range(-3, 4) and z in range(-1, 2) else 0.0
			influence.cells[Vector2i(x, z)] = _cell(threat)
	influence.version = 8
	var origin := Vector3(-10.0, 0.0, 0.0)
	var destination := Vector3(10.0, 0.0, 0.0)
	var plan := planner.build_route(origin, destination, influence, [], Callable(), 1.65, 1.0)
	_assert(String(plan.get("selection_reason", "")) == "shortest_route_budget_limit",
		"a risk detour beyond the configured extra-distance budget must fall back to the shortest route")
	_assert(float(plan.get("route_length", INF)) <= float(plan.get("baseline_length", 0.0)) + 0.1,
		"budget fallback must use the geometric shortest route")
	_assert(float(plan.get("peak_threat", 0.0)) >= 90.0,
		"a mandatory short route may remain dangerous instead of abandoning the order")

func _test_only_dangerous_route(planner: SquadHeatmapRoutePlanner3D) -> void:
	var influence := SquadInfluenceMap3D.new()
	influence.configure(2.0, 20.0)
	influence.origin = Vector3.ZERO
	for x in range(-5, 6):
		influence.cells[Vector2i(x, 0)] = _cell(100.0)
	influence.version = 9
	var destination := Vector3(10.0, 0.0, 0.0)
	var plan := planner.build_route(Vector3(-10.0, 0.0, 0.0), destination, influence)
	var route: Array[Vector3] = []
	route.assign(plan.get("route", []))
	_assert(not route.is_empty() and route[-1].distance_to(destination) <= 0.1,
		"the only dangerous route must still reach the ordered destination")
	_assert(float(plan.get("peak_threat", 0.0)) >= 90.0,
		"the only-route case must preserve its real threat diagnostics")

func _test_directional_cover_shadow() -> void:
	var cover := TacticalCover3D.new()
	cover.cover_length = 5.0
	cover.cover_width = 0.5
	cover.cover_height = 1.25
	add_child(cover)
	var influence := SquadInfluenceMap3D.new()
	var frontal := CombatContact3D.new()
	frontal.last_known_position = Vector3(0.0, 0.0, 10.0)
	frontal.last_report_msec = Time.get_ticks_msec()
	frontal.confidence = 1.0
	frontal.estimated_firepower = 1.0
	var behind := Vector3(0.0, 0.0, -2.0)
	var front := Vector3(0.0, 0.0, 2.0)
	var behind_raw := influence._contact_threat_at_position(frontal, behind, [])
	var behind_blocked := influence._contact_threat_at_position(frontal, behind, [cover])
	var front_raw := influence._contact_threat_at_position(frontal, front, [])
	var front_with_cover := influence._contact_threat_at_position(frontal, front, [cover])
	_assert(behind_blocked < behind_raw * 0.45,
		"cover must create a strong fire shadow only behind it")
	_assert(absf(front_with_cover - front_raw) <= 0.05,
		"the threat-facing side of cover must not receive shadow protection")
	var flank := CombatContact3D.new()
	flank.last_known_position = Vector3(10.0, 0.0, -2.0)
	flank.last_report_msec = Time.get_ticks_msec()
	flank.confidence = 1.0
	flank.estimated_firepower = 1.0
	var flank_threat := influence._contact_threat_at_position(flank, behind, [cover])
	_assert(flank_threat > 0.0 and behind_blocked + flank_threat > behind_blocked,
		"side fire must remain dangerous and stack with the blocked frontal fire")

func _cell(enemy_threat: float) -> Dictionary:
	return {
		SquadInfluenceMap3D.LAYER_ENEMY_THREAT: enemy_threat,
		SquadInfluenceMap3D.LAYER_FRIENDLY_SUPPORT: 0.0,
		SquadInfluenceMap3D.LAYER_SUPPRESSION: 0.0,
		SquadInfluenceMap3D.LAYER_COVER: 0.0,
		SquadInfluenceMap3D.LAYER_CONCEALMENT: 0.0,
		SquadInfluenceMap3D.LAYER_ROUTE_EXPOSURE: 0.0,
		SquadInfluenceMap3D.LAYER_OBJECTIVE: 0.0,
		SquadInfluenceMap3D.LAYER_INFORMATION: 0.0,
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[TACTICAL_ROUTE_SMOKE_FAIL] %s" % message)
