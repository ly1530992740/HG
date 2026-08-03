extends RefCounted
class_name SquadHeatmapRoutePlanner3D

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

const THREAT_WEIGHT := 1.0
const SUPPRESSION_WEIGHT := 0.9
const EXPOSURE_WEIGHT := 0.55
const COVER_REDUCTION := 0.45
const CONCEALMENT_REDUCTION := 0.25
const FRIENDLY_SUPPORT_REDUCTION := 0.08
const RISK_DISTANCE_SCALE := 28.0
const PEAK_THREAT_SCALE := 0.10
const NOMINAL_MOVEMENT_SPEED := 3.4

func build_route(
		origin: Vector3,
		destination: Vector3,
		influence: SquadInfluenceMap3D,
		preferred_waypoints: Array[Vector3] = [],
		segment_clear: Callable = Callable(),
		max_length_ratio := 1.65,
		max_extra_distance := 10.0
) -> Dictionary:
	var controls := preferred_waypoints.duplicate()
	if controls.is_empty() or _flat_distance(controls[-1], destination) > 0.35:
		controls.append(destination)
	if _flat_distance(origin, destination) <= 0.45 and controls.size() <= 1:
		return _result([], 0.0, _threat_at(destination, influence), influence, 0.0, 0.0, 0.0, "already_at_destination")

	var route: Array[Vector3] = []
	var baseline_route: Array[Vector3] = []
	var cursor := origin
	var baseline_length := 0.0
	var selection_reasons: Array[String] = []
	for control in controls:
		if _flat_distance(cursor, control) <= 0.35:
			continue
		var segment := _build_segment(
			cursor, control, influence, segment_clear,
			maxf(1.0, max_length_ratio), maxf(0.0, max_extra_distance)
		)
		var points: Array[Vector3] = []
		points.assign(segment.get("route", []))
		var baseline_points: Array[Vector3] = []
		baseline_points.assign(segment.get("baseline_route", points))
		baseline_length += float(segment.get("baseline_length", _flat_distance(cursor, control)))
		selection_reasons.append(String(segment.get("selection_reason", "unknown")))
		for point in points:
			if route.is_empty() or _flat_distance(route[-1], point) > 0.2:
				route.append(point)
		for point in baseline_points:
			if baseline_route.is_empty() or _flat_distance(baseline_route[-1], point) > 0.2:
				baseline_route.append(point)
		cursor = control

	var route_length := _route_length(origin, route)
	var global_allowed_length := minf(
		baseline_length * maxf(1.0, max_length_ratio),
		baseline_length + maxf(0.0, max_extra_distance)
	)
	if route_length > global_allowed_length + 0.05:
		route = baseline_route
		route_length = _route_length(origin, route)
		selection_reasons.clear()
		selection_reasons.append("shortest_route_global_budget_limit")
	var metrics := evaluate_route(origin, route, influence)
	return _result(
		route,
		float(metrics.get("total_cost", 0.0)),
		float(metrics.get("peak_threat", 0.0)),
		influence,
		float(metrics.get("exposure_seconds", 0.0)),
		route_length,
		baseline_length,
		",".join(selection_reasons)
	)

func evaluate_route(origin: Vector3, route: Array[Vector3], influence: SquadInfluenceMap3D) -> Dictionary:
	var total_cost := 0.0
	var peak_threat := _threat_at(origin, influence)
	var exposure_seconds := 0.0
	var cursor := origin
	for destination in route:
		var distance := _flat_distance(cursor, destination)
		var steps := maxi(1, ceili(distance / _cell_size(influence)))
		var previous := cursor
		for step in range(1, steps + 1):
			var point := cursor.lerp(destination, float(step) / float(steps))
			total_cost += _edge_cost(previous, point, influence)
			peak_threat = maxf(peak_threat, _threat_at(point, influence))
			var exposure_ratio := clampf(_movement_risk(point, influence) / 100.0, 0.0, 1.5)
			exposure_seconds += _flat_distance(previous, point) / NOMINAL_MOVEMENT_SPEED * exposure_ratio
			previous = point
		cursor = destination
	return {"total_cost": total_cost, "peak_threat": peak_threat, "exposure_seconds": exposure_seconds}

func _build_segment(
		origin: Vector3,
		destination: Vector3,
		influence: SquadInfluenceMap3D,
		segment_clear: Callable,
		max_length_ratio: float,
		max_extra_distance: float
) -> Dictionary:
	if influence == null or influence.cells.is_empty():
		return {
			"route": [destination],
			"baseline_route": [destination],
			"baseline_length": _flat_distance(origin, destination),
			"selection_reason": "no_influence_data",
		}
	var start := _key_for(origin, influence)
	var finish := _key_for(destination, influence)
	if start == finish:
		return {
			"route": [destination],
			"baseline_route": [destination],
			"baseline_length": _flat_distance(origin, destination),
			"selection_reason": "same_cell",
		}

	var direct_cells := maxi(abs(finish.x - start.x), abs(finish.y - start.y))
	var margin := clampi(ceili(float(direct_cells) * 0.45), 4, 14)
	var min_x := mini(start.x, finish.x) - margin
	var max_x := maxi(start.x, finish.x) + margin
	var min_y := mini(start.y, finish.y) - margin
	var max_y := maxi(start.y, finish.y) + margin
	var bounds := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	var baseline := _search_segment(origin, destination, influence, segment_clear, bounds, false)
	var safest := _search_segment(origin, destination, influence, segment_clear, bounds, true)
	var baseline_route: Array[Vector3] = []
	baseline_route.assign(baseline.get("route", [destination]))
	var safest_route: Array[Vector3] = []
	safest_route.assign(safest.get("route", baseline_route))
	var baseline_length := _route_length(origin, baseline_route)
	var safest_length := _route_length(origin, safest_route)
	var allowed_length := minf(
		baseline_length * max_length_ratio,
		baseline_length + max_extra_distance
	)
	if bool(safest.get("found", false)) and safest_length <= allowed_length + 0.05:
		return {
			"route": safest_route,
			"baseline_route": baseline_route,
			"baseline_length": baseline_length,
			"selection_reason": "risk_route_within_budget",
		}
	return {
		"route": baseline_route,
		"baseline_route": baseline_route,
		"baseline_length": baseline_length,
		"selection_reason": "shortest_route_budget_limit" if bool(baseline.get("found", false)) else "only_executable_route",
	}

func _search_segment(
		origin: Vector3,
		destination: Vector3,
		influence: SquadInfluenceMap3D,
		segment_clear: Callable,
		bounds: Rect2i,
		use_risk_cost: bool
) -> Dictionary:
	var start := _key_for(origin, influence)
	var finish := _key_for(destination, influence)
	var open_set: Array[Vector2i] = [start]
	var open_lookup := {start: true}
	var came_from: Dictionary = {}
	var g_score := {start: 0.0}
	var f_score := {start: _heuristic(start, finish, influence)}
	var iteration_limit := maxi(128, bounds.size.x * bounds.size.y * 2)
	var restrict_to_known_cells := influence.cells.has(start) and influence.cells.has(finish)

	for _iteration in iteration_limit:
		if open_set.is_empty():
			break
		var current := _pop_lowest(open_set, open_lookup, f_score)
		if current == finish:
			return {
				"found": true,
				"route": _reconstruct(came_from, current, origin, destination, influence),
			}
		for offset in NEIGHBOR_OFFSETS:
			var neighbor := current + offset
			if not bounds.has_point(neighbor):
				continue
			if restrict_to_known_cells and neighbor != finish and not influence.cells.has(neighbor):
				continue
			var current_position := _position_for(current, origin.y, influence)
			var neighbor_position := _position_for(neighbor, origin.y, influence)
			if segment_clear.is_valid() and not bool(segment_clear.call(current_position, neighbor_position)):
				continue
			var edge_cost := _edge_cost(current_position, neighbor_position, influence) \
				if use_risk_cost else _flat_distance(current_position, neighbor_position)
			var tentative := float(g_score.get(current, INF)) + edge_cost
			if tentative >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _heuristic(neighbor, finish, influence)
			if not open_lookup.has(neighbor):
				open_set.append(neighbor)
				open_lookup[neighbor] = true

	return {"found": false, "route": [destination]}

func _pop_lowest(open_set: Array[Vector2i], open_lookup: Dictionary, f_score: Dictionary) -> Vector2i:
	var best_index := 0
	var best_score := float(f_score.get(open_set[0], INF))
	for index in range(1, open_set.size()):
		var candidate_score := float(f_score.get(open_set[index], INF))
		if candidate_score < best_score:
			best_score = candidate_score
			best_index = index
	var result := open_set[best_index]
	open_set.remove_at(best_index)
	open_lookup.erase(result)
	return result

func _reconstruct(
		came_from: Dictionary,
		finish: Vector2i,
		origin: Vector3,
		destination: Vector3,
		influence: SquadInfluenceMap3D
) -> Array[Vector3]:
	var keys: Array[Vector2i] = [finish]
	var current := finish
	while came_from.has(current):
		current = came_from[current] as Vector2i
		keys.push_front(current)
	var route: Array[Vector3] = []
	var previous_direction := Vector2i.ZERO
	for index in range(1, keys.size()):
		var direction := keys[index] - keys[index - 1]
		if index > 1 and direction != previous_direction:
			route.append(_position_for(keys[index - 1], origin.y, influence))
		previous_direction = direction
	if route.is_empty() or _flat_distance(route[-1], destination) > 0.2:
		route.append(destination)
	else:
		route[-1] = destination
	return route

func _edge_cost(origin: Vector3, destination: Vector3, influence: SquadInfluenceMap3D) -> float:
	var distance := _flat_distance(origin, destination)
	var origin_risk := _movement_risk(origin, influence)
	var destination_risk := _movement_risk(destination, influence)
	var average_risk := (origin_risk + destination_risk) * 0.5
	var peak_threat := maxf(_threat_at(origin, influence), _threat_at(destination, influence))
	return distance * (1.0 + average_risk / RISK_DISTANCE_SCALE) + peak_threat * PEAK_THREAT_SCALE

func _movement_risk(position: Vector3, influence: SquadInfluenceMap3D) -> float:
	if influence == null:
		return 0.0
	var cell := influence.sample(position)
	var risk := float(cell.get(SquadInfluenceMap3D.LAYER_ENEMY_THREAT, 0.0)) * THREAT_WEIGHT
	risk += float(cell.get(SquadInfluenceMap3D.LAYER_SUPPRESSION, 0.0)) * SUPPRESSION_WEIGHT
	risk += float(cell.get(SquadInfluenceMap3D.LAYER_ROUTE_EXPOSURE, 0.0)) * EXPOSURE_WEIGHT
	risk -= float(cell.get(SquadInfluenceMap3D.LAYER_COVER, 0.0)) * COVER_REDUCTION
	risk -= float(cell.get(SquadInfluenceMap3D.LAYER_CONCEALMENT, 0.0)) * CONCEALMENT_REDUCTION
	risk -= float(cell.get(SquadInfluenceMap3D.LAYER_FRIENDLY_SUPPORT, 0.0)) * FRIENDLY_SUPPORT_REDUCTION
	return maxf(0.0, risk)

func _threat_at(position: Vector3, influence: SquadInfluenceMap3D) -> float:
	if influence == null:
		return 0.0
	return float(influence.sample(position).get(SquadInfluenceMap3D.LAYER_ENEMY_THREAT, 0.0))

func _heuristic(origin: Vector2i, destination: Vector2i, influence: SquadInfluenceMap3D) -> float:
	return Vector2(origin).distance_to(Vector2(destination)) * _cell_size(influence)

func _key_for(position: Vector3, influence: SquadInfluenceMap3D) -> Vector2i:
	var local := position - influence.origin
	return Vector2i(roundi(local.x / influence.cell_size), roundi(local.z / influence.cell_size))

func _position_for(key: Vector2i, y: float, influence: SquadInfluenceMap3D) -> Vector3:
	return influence.origin + Vector3(float(key.x) * influence.cell_size, y, float(key.y) * influence.cell_size)

func _cell_size(influence: SquadInfluenceMap3D) -> float:
	return maxf(1.0, influence.cell_size) if influence != null else 2.5

func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()

func _route_length(origin: Vector3, route: Array[Vector3]) -> float:
	var result := 0.0
	var cursor := origin
	for point in route:
		result += _flat_distance(cursor, point)
		cursor = point
	return result

func _result(
		route: Array[Vector3],
		total_cost: float,
		peak_threat: float,
		influence: SquadInfluenceMap3D,
		exposure_seconds := 0.0,
		route_length := 0.0,
		baseline_length := 0.0,
		selection_reason := ""
) -> Dictionary:
	var length_ratio := route_length / baseline_length if baseline_length > 0.01 else 1.0
	return {
		"route": route,
		"total_cost": total_cost,
		"peak_threat": peak_threat,
		"exposure_seconds": exposure_seconds,
		"route_length": route_length,
		"baseline_length": baseline_length,
		"length_ratio": length_ratio,
		"selection_reason": selection_reason,
		"influence_version": influence.version if influence != null else 0,
	}
