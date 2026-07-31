extends Node

var failures: Array[String] = []
var cases := 0

func _ready() -> void:
	_test_empty_intelligence_keeps_direct_route()
	_test_shared_heat_avoids_exposed_lane()
	_test_personal_memory_avoids_recent_threat()
	_test_detour_stays_inside_command_corridor()
	_test_expired_memory_stops_affecting_route()
	if failures.is_empty():
		print("SOLDIER_LOCAL_THREAT_FIELD_PASS cases=%d" % cases)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SOLDIER_LOCAL_THREAT_FIELD_FAIL cases=%d failures=%d" % [cases, failures.size()])
		get_tree().quit(1)

func _test_empty_intelligence_keeps_direct_route() -> void:
	var field := SoldierLocalThreatField3D.new()
	field.configure(null, null)
	var choice := field.choose_local_detour(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 3.0, 4.0)
	_check(absf((choice.get("point", Vector3.ZERO) as Vector3).x) < 0.05,
		"No known danger should keep the shortest direct local route")

func _test_shared_heat_avoids_exposed_lane() -> void:
	var influence := SquadInfluenceMap3D.new()
	influence.configure(1.0, 20.0)
	influence.origin = Vector3.ZERO
	for z in range(-5, 0):
		influence.cells[Vector2i(0, z)] = _cell(100.0, 80.0, 90.0)
		influence.cells[Vector2i(1, z)] = _cell(65.0, 45.0, 55.0)
		influence.cells[Vector2i(2, z)] = _cell(0.0, 0.0, 5.0)
		influence.cells[Vector2i(-1, z)] = _cell(70.0, 50.0, 60.0)
		influence.cells[Vector2i(-2, z)] = _cell(15.0, 10.0, 20.0)
	var field := SoldierLocalThreatField3D.new()
	field.configure(null, null)
	field.set_shared_influence(influence)
	var choice := field.choose_local_detour(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 3.0, 4.0)
	var point := choice.get("point", Vector3.ZERO) as Vector3
	_check(absf(point.x) > 0.6, "A dangerous shared heat lane should produce a safer lateral waypoint")
	_check(float(choice.get("selected_risk", INF)) < float(choice.get("direct_risk", -INF)),
		"Selected local route must have lower sampled risk than the direct route")

func _test_personal_memory_avoids_recent_threat() -> void:
	var memory := SoldierWorkingMemory3D.new()
	memory.configure(null)
	memory.remember_threat(null, Vector3(0.0, 0.0, -6.0), 1.0, 5.0, true, true, &"near_miss")
	var field := SoldierLocalThreatField3D.new()
	field.configure(null, memory)
	var choice := field.choose_local_detour(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 3.0, 4.0)
	_check(float(choice.get("direct_risk", 0.0)) > 1.0,
		"A soldier's own recent threat memory should raise the local route risk")
	memory.free()

func _test_detour_stays_inside_command_corridor() -> void:
	var influence := SquadInfluenceMap3D.new()
	influence.configure(1.0, 20.0)
	influence.origin = Vector3.ZERO
	for z in range(-6, 0):
		influence.cells[Vector2i(0, z)] = _cell(100.0, 100.0, 100.0)
	var field := SoldierLocalThreatField3D.new()
	field.configure(null, null)
	field.set_shared_influence(influence)
	var choice := field.choose_local_detour(Vector3.ZERO, Vector3(0.0, 0.0, -12.0), 1.5, 4.0)
	var point := choice.get("point", Vector3.ZERO) as Vector3
	_check(absf(point.x) <= 1.55, "Local judgment must not leave the commander-provided movement corridor")
	_check(point.z < -0.25, "Local judgment must continue making progress toward the assigned goal")

func _test_expired_memory_stops_affecting_route() -> void:
	var memory := SoldierWorkingMemory3D.new()
	memory.configure(null)
	memory.remember_threat(null, Vector3(0.0, 0.0, -6.0), 1.0, 0.1, true, true, &"near_miss")
	memory.tick(0.2)
	var field := SoldierLocalThreatField3D.new()
	field.configure(null, memory)
	var choice := field.choose_local_detour(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 3.0, 4.0)
	_check(absf((choice.get("point", Vector3.ZERO) as Vector3).x) < 0.05,
		"Expired danger must not cause permanent detours")
	memory.free()

func _cell(enemy: float, suppression: float, exposure: float) -> Dictionary:
	return {
		SquadInfluenceMap3D.LAYER_ENEMY_THREAT: enemy,
		SquadInfluenceMap3D.LAYER_FRIENDLY_FIRE: 0.0,
		SquadInfluenceMap3D.LAYER_SUPPRESSION: suppression,
		SquadInfluenceMap3D.LAYER_COVER: 0.0,
		SquadInfluenceMap3D.LAYER_CONCEALMENT: 0.0,
		SquadInfluenceMap3D.LAYER_ROUTE_EXPOSURE: exposure,
		SquadInfluenceMap3D.LAYER_OBJECTIVE: 0.0,
		SquadInfluenceMap3D.LAYER_INFORMATION: 0.0,
	}

func _check(condition: bool, message: String) -> void:
	cases += 1
	if not condition:
		failures.append(message)
