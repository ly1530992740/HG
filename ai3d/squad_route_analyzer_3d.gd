extends Node
class_name SquadRouteAnalyzer3D

@export_category("3D路线分析")
@export_range(2.0, 30.0, 0.5) var minimum_cover_length := 4.0
@export_range(1, 12, 1) var minimum_capacity := 2
@export_range(0.2, 5.0, 0.1) var route_clearance := 1.4
@export_range(0.5, 50.0, 0.5) var side_offset_required := 2.0

var last_candidates: Array[Dictionary] = []

func analyze(squad_center: Vector3, target_position: Vector3) -> Array[Dictionary]:
	last_candidates.clear()
	var forward := target_position - squad_center
	forward.y = 0.0
	if forward == Vector3.ZERO:
		return last_candidates
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var registry := BattlefieldRegistry3D.find(get_tree())
	var cover_nodes: Array = registry.get_covers() if registry != null else get_tree().get_nodes_in_group("cover3d")
	for node in cover_nodes:
		if not node is TacticalCover3D:
			continue
		var cover := node as TacticalCover3D
		if cover.cover_length < minimum_cover_length:
			continue
		var offset := cover.global_position - squad_center
		offset.y = 0.0
		var side_distance := offset.dot(right)
		if absf(side_distance) < side_offset_required:
			continue
		var forward_distance := offset.dot(forward)
		var target_distance := squad_center.distance_to(target_position)
		if forward_distance < -1.0 or forward_distance > target_distance + 3.0:
			continue
		var route := cover.get_flank_route(squad_center, target_position, route_clearance)
		var reachable := _route_is_reachable(squad_center, route, cover)
		var exposure := _estimate_exposure(route, target_position, cover)
		var capacity := cover.get_cover_capacity_per_side()
		var distance := _route_distance(squad_center, route)
		var side := "LEFT" if side_distance < 0.0 else "RIGHT"
		last_candidates.append({
			"id": "%s_%s" % [side, String(cover.name).to_upper()],
			"side": side,
			"direction": "北侧" if side == "LEFT" else "南侧",
			"available": reachable and capacity >= minimum_capacity and exposure <= 0.75,
			"reachable": reachable,
			"exposure": snappedf(exposure, 0.01),
			"distance": snappedf(distance, 0.1),
			"capacity": capacity,
			"cover": cover,
			"points": route,
			# 长掩体能在更长路段遮断火线，容量在路线评分中代表连续隐蔽价值。
			"score": distance + exposure * 35.0 - float(capacity) * 4.5,
		})
	last_candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) < float(b.score))
	return last_candidates

func get_best_available() -> Dictionary:
	for candidate in last_candidates:
		if bool(candidate.get("available", false)):
			return candidate
	return {}

func format_for_qwen() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate in last_candidates:
		result.append({
			"路线ID": String(candidate.get("id", "")),
			"方向": String(candidate.get("direction", "")),
			"可到达": bool(candidate.get("available", false)),
			"预计暴露比例": float(candidate.get("exposure", 1.0)),
			"移动距离": float(candidate.get("distance", 0.0)),
			"可掩护人数": int(candidate.get("capacity", 0)),
		})
	return result

func _estimate_exposure(route: Array[Vector3], target_position: Vector3, route_cover: TacticalCover3D) -> float:
	var world := get_viewport().world_3d
	if route.is_empty():
		return 1.0
	var exposed := 0
	for point in route:
		var origin := point + Vector3.UP * 1.1
		var endpoint := target_position + Vector3.UP * 1.1
		var blocked := _cover_blocks_segment(route_cover, origin, endpoint)
		if not blocked and world != null:
			var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1)
			blocked = not world.direct_space_state.intersect_ray(query).is_empty()
		if not blocked:
			exposed += 1
	return float(exposed) / float(route.size())

func _cover_blocks_segment(cover: TacticalCover3D, origin: Vector3, endpoint: Vector3) -> bool:
	var local_origin := cover.to_local(origin)
	var local_endpoint := cover.to_local(endpoint)
	if minf(local_origin.y, local_endpoint.y) > cover.cover_height or maxf(local_origin.y, local_endpoint.y) < 0.0:
		return false
	var half := Vector2(cover.cover_length * 0.5, cover.cover_width * 0.5)
	var start := Vector2(local_origin.x, local_origin.z)
	var finish := Vector2(local_endpoint.x, local_endpoint.z)
	var direction := finish - start
	var t_min := 0.0
	var t_max := 1.0
	for axis in 2:
		var start_value := start[axis]
		var direction_value := direction[axis]
		var half_size := half[axis]
		if absf(direction_value) < 0.0001:
			if start_value < -half_size or start_value > half_size:
				return false
			continue
		var first := (-half_size - start_value) / direction_value
		var second := (half_size - start_value) / direction_value
		if first > second:
			var swap := first
			first = second
			second = swap
		t_min = maxf(t_min, first)
		t_max = minf(t_max, second)
		if t_min > t_max:
			return false
	return t_max >= 0.0 and t_min <= 1.0

func _route_distance(origin: Vector3, route: Array[Vector3]) -> float:
	var result := 0.0
	var previous := origin
	for point in route:
		result += previous.distance_to(point)
		previous = point
	return result

func _route_is_reachable(origin: Vector3, route: Array[Vector3], route_cover: TacticalCover3D) -> bool:
	if route.is_empty() or get_viewport().world_3d == null:
		return false
	var points: Array[Vector3] = [origin]
	points.append_array(route)
	var space := get_viewport().world_3d.direct_space_state
	for index in range(points.size() - 1):
		var start := points[index] + Vector3.UP * 0.55
		var finish := points[index + 1] + Vector3.UP * 0.55
		var query := PhysicsRayQueryParameters3D.create(start, finish, 1, [route_cover.get_rid()])
		query.collide_with_areas = false
		if not space.intersect_ray(query).is_empty():
			return false
	return true
