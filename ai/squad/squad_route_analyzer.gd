extends Node
class_name SquadRouteAnalyzer

@export_group("候选路线生成")
@export_range(120.0, 600.0, 10.0) var route_clearance := 150.0
@export_range(80.0, 400.0, 10.0) var endpoint_clearance := 170.0
@export_range(200.0, 2000.0, 20.0) var minimum_route_wall_length := 480.0
@export_range(0.1, 1.0, 0.05) var minimum_forward_alignment := 0.55
@export_range(1, 12, 1) var minimum_route_capacity := 3
@export_range(1, 8, 1) var max_candidates_per_side := 2

@export_group("路线评分")
@export var distance_weight := 0.01
@export var exposure_weight := 650.0
@export var capacity_bonus := 18.0
@export var side_distance_bonus := 0.08

var squad_group: SquadGroup = null
var last_candidates: Array[Dictionary] = []
var revision := 0

func bind_group(value: SquadGroup) -> void:
	squad_group = value

func analyze_routes(primary_target: Node2D) -> Array[Dictionary]:
	last_candidates.clear()
	if squad_group == null:
		squad_group = get_parent() as SquadGroup
	var coordinator := squad_group as SquadCoordinator
	if coordinator == null or not is_instance_valid(primary_target):
		_publish([])
		return last_candidates
	var squad_center := coordinator._get_squad_center()
	var target_position := _hostile_center(coordinator, primary_target)
	var forward := (target_position - squad_center).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	var right := Vector2(-forward.y, forward.x)
	var side_buckets := {-1: [], 1: []}
	for node in get_tree().get_nodes_in_group("cover"):
		if not node is LowWall:
			continue
		var wall := node as LowWall
		if wall.wall_length < minimum_route_wall_length:
			continue
		var offset := wall.global_position - squad_center
		var side_distance := offset.dot(right)
		var side_sign := signi(roundi(signf(side_distance)))
		if side_sign == 0:
			continue
		var axis_alignment := absf(wall.get_cover_axis().dot(forward))
		if axis_alignment < minimum_forward_alignment:
			continue
		var along := offset.dot(forward)
		var target_distance := squad_center.distance_to(target_position)
		if along < -250.0 or along > target_distance + 450.0:
			continue
		var candidate := _build_wall_route(wall, side_sign, squad_center, target_position, forward, right)
		(side_buckets[side_sign] as Array).append(candidate)
	for side_sign in [-1, 1]:
		var bucket := side_buckets[side_sign] as Array
		bucket.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("score", INF)) < float(b.get("score", INF)))
		for index in mini(max_candidates_per_side, bucket.size()):
			last_candidates.append(bucket[index])
	last_candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("score", INF)) < float(b.get("score", INF)))
	revision += 1
	_publish(last_candidates)
	return last_candidates

func _build_wall_route(
		wall: LowWall,
		side_sign: int,
		squad_center: Vector2,
		target_position: Vector2,
		forward: Vector2,
		right: Vector2
) -> Dictionary:
	var axis := wall.get_cover_axis()
	if axis.dot(forward) < 0.0:
		axis = -axis
	var normal := Vector2(-axis.y, axis.x)
	var target_local := wall.to_local(target_position)
	var safe_normal_sign := -signf(target_local.y)
	if is_zero_approx(safe_normal_sign):
		safe_normal_sign = signf((wall.global_position - squad_center).dot(right))
	var safe_normal := normal * safe_normal_sign
	var half_length := wall.wall_length * 0.5
	var protected_offset := wall.wall_width * 0.5 + route_clearance
	var protected_half_length := maxf(0.0, half_length - endpoint_clearance)
	var near_end := wall.global_position - axis * protected_half_length
	var far_end := wall.global_position + axis * protected_half_length
	if squad_center.distance_to(far_end) < squad_center.distance_to(near_end):
		axis = -axis
		near_end = wall.global_position - axis * protected_half_length
		far_end = wall.global_position + axis * protected_half_length
	var ingress := wall.global_position - axis * (half_length + endpoint_clearance) + safe_normal * protected_offset
	var protected_near := near_end + safe_normal * protected_offset
	var protected_mid := wall.global_position + safe_normal * protected_offset
	var protected_far := far_end + safe_normal * protected_offset
	var attack_side := wall.global_position + axis * (half_length + endpoint_clearance) - safe_normal * maxf(route_clearance, protected_offset * 0.75)
	var points: Array[Vector2] = [ingress, protected_near, protected_mid, protected_far, attack_side]
	var route_distance := squad_center.distance_to(points[0])
	for index in range(1, points.size()):
		route_distance += points[index - 1].distance_to(points[index])
	var exposure := _estimate_exposure(points, squad_center, target_position)
	var capacity := wall.get_cover_capacity_per_side()
	var available := capacity >= minimum_route_capacity
	var score := route_distance * distance_weight + exposure * exposure_weight - float(capacity) * capacity_bonus - absf((wall.global_position - squad_center).dot(right)) * side_distance_bonus
	var side_label := "北侧" if side_sign < 0 else "南侧"
	var route_id := StringName("%s_%s" % ["NORTH" if side_sign < 0 else "SOUTH", String(wall.name).to_upper()])
	return {
		"id": route_id,
		"side": &"LEFT" if side_sign < 0 else &"RIGHT",
		"side_label": side_label,
		"available": available,
		"exposure": snappedf(exposure, 0.01),
		"distance": roundi(route_distance),
		"capacity": capacity,
		"score": snappedf(score, 0.1),
		"cover": wall,
		"cover_name": String(wall.name),
		"points": points,
		"reason": "沿%s背敌侧移动，容量%d，预计暴露%d%%" % [String(wall.name), capacity, roundi(exposure * 100.0)],
	}

func _estimate_exposure(points: Array[Vector2], start_position: Vector2, target_position: Vector2) -> float:
	if points.is_empty():
		return 1.0
	var exposed := 0
	var samples := 0
	var segment_start := start_position
	for point_index in points.size():
		var point := points[point_index]
		var segment_length := segment_start.distance_to(point)
		var segment_samples := maxi(1, ceili(segment_length / 120.0))
		for sample_index in range(1, segment_samples + 1):
			# The final waypoint intentionally leaves cover to attack; route safety
			# describes the approach and protected movement that precede it.
			if point_index == points.size() - 1:
				break
			var sample := segment_start.lerp(point, float(sample_index) / float(segment_samples))
			samples += 1
			if not _line_blocked_by_cover(sample, target_position):
				exposed += 1
		segment_start = point
	return float(exposed) / float(maxi(1, samples))

func _line_blocked_by_cover(from_position: Vector2, to_position: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("cover"):
		if node is LowWall and _segment_crosses_wall(from_position, to_position, node):
			return true
	return false

func _segment_crosses_wall(from_position: Vector2, to_position: Vector2, wall: LowWall) -> bool:
	var local_from := wall.to_local(from_position)
	var local_to := wall.to_local(to_position)
	var half_width := wall.wall_width * 0.5
	if (local_from.y < -half_width and local_to.y < -half_width) or (local_from.y > half_width and local_to.y > half_width):
		return false
	var delta_y := local_to.y - local_from.y
	if is_zero_approx(delta_y):
		return absf(local_from.y) <= half_width \
			and minf(local_from.x, local_to.x) <= wall.wall_length * 0.5 \
			and maxf(local_from.x, local_to.x) >= -wall.wall_length * 0.5
	for edge_y in [-half_width, half_width]:
		var ratio: float = (float(edge_y) - local_from.y) / delta_y
		if ratio >= 0.0 and ratio <= 1.0:
			var crossing_x := lerpf(local_from.x, local_to.x, ratio)
			if absf(crossing_x) <= wall.wall_length * 0.5:
				return true
	return false

func _hostile_center(coordinator: SquadCoordinator, primary_target: Node2D) -> Vector2:
	var targets := coordinator._collect_known_hostile_targets()
	if targets.is_empty():
		return primary_target.global_position
	var center := Vector2.ZERO
	var count := 0
	for target in targets:
		if is_instance_valid(target):
			center += target.global_position
			count += 1
	return center / float(maxi(1, count))

func _publish(candidates: Array) -> void:
	var coordinator := squad_group as SquadCoordinator
	if coordinator == null:
		return
	var left_available := false
	var right_available := false
	for route in candidates:
		if not bool(route.get("available", false)):
			continue
		if StringName(route.get("side", &"")) == &"LEFT":
			left_available = true
		elif StringName(route.get("side", &"")) == &"RIGHT":
			right_available = true
	coordinator.get_blackboard().set_fact(&"flank_route_candidates", candidates)
	coordinator.get_blackboard().set_fact(&"flank_route_revision", revision)
	coordinator.get_blackboard().set_fact(&"left_flank_available", left_available)
	coordinator.get_blackboard().set_fact(&"right_flank_available", right_available)
