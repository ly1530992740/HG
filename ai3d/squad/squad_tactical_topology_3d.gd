extends RefCounted
class_name SquadTacticalTopology3D

enum CellKind { BLOCKED, OPEN, CHOKE, DEAD_END }

const CARDINALS: Array[Vector2i] = [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
]

var cell_size := 1.0
var origin := Vector3.ZERO
var bounds := Rect2i()
var walkable: Dictionary = {}
var clearance: Dictionary = {}
var cell_kinds: Dictionary = {}
var cell_regions: Dictionary = {}
var regions: Array[Dictionary] = []
var portals: Array[Dictionary] = []
var version := 0

var narrow_clearance_cells := 1
var maximum_clearance_scan := 5

func analyze_grid(
		walkable_cells: Dictionary,
		new_cell_size := 1.0,
		new_origin := Vector3.ZERO,
		explicit_bounds := Rect2i()
) -> void:
	cell_size = maxf(0.25, new_cell_size)
	origin = new_origin
	walkable = walkable_cells.duplicate()
	bounds = explicit_bounds if explicit_bounds.size != Vector2i.ZERO else _derive_bounds(walkable)
	clearance.clear()
	cell_kinds.clear()
	cell_regions.clear()
	regions.clear()
	portals.clear()
	_compute_clearance()
	_build_regions()
	_build_portals()
	_classify_dead_ends()
	version += 1

func bake_from_world(
		world: World3D,
		world_bounds: Rect2,
		ground_y: float,
		excluded_rids: Array[RID] = [],
		collision_mask := 1,
		agent_radius := 0.48,
		agent_height := 1.7
) -> void:
	if world == null or world.direct_space_state == null or world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return
	var grid_width := maxi(1, floori(world_bounds.size.x / cell_size) + 1)
	var grid_height := maxi(1, floori(world_bounds.size.y / cell_size) + 1)
	var grid_bounds := Rect2i(0, 0, grid_width, grid_height)
	var sampled: Dictionary = {}
	var shape := CylinderShape3D.new()
	shape.radius = maxf(0.1, agent_radius)
	shape.height = maxf(shape.radius * 2.0, agent_height)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.exclude = excluded_rids
	var sample_origin := Vector3(world_bounds.position.x, ground_y, world_bounds.position.y)
	for x in grid_width:
		for y in grid_height:
			var key := Vector2i(x, y)
			var floor_position := sample_origin + Vector3(float(x) * cell_size, 0.0, float(y) * cell_size)
			var ground_query := PhysicsRayQueryParameters3D.create(
				floor_position + Vector3.UP * 0.45,
				floor_position + Vector3.DOWN * 1.5,
				collision_mask,
				excluded_rids
			)
			ground_query.collide_with_areas = false
			var ground_hit := world.direct_space_state.intersect_ray(ground_query)
			var has_ground := ground_hit.get("collider") is StaticBody3D
			var position := floor_position + Vector3.UP * (agent_height * 0.5 + 0.08)
			query.transform = Transform3D(Basis.IDENTITY, position)
			var blocked := _has_static_blocker(world.direct_space_state.intersect_shape(query, 16))
			sampled[key] = has_ground and not blocked
	analyze_grid(sampled, cell_size, sample_origin, grid_bounds)

func get_route_waypoints(from_position: Vector3, to_position: Vector3) -> Array[Vector3]:
	var start_region := _nearest_region_id(from_position)
	var finish_region := _nearest_region_id(to_position)
	if start_region < 0 or finish_region < 0 or start_region == finish_region:
		return []
	var queue: Array[int] = [start_region]
	var came_from := {start_region: {"previous": -1, "portal": -1}}
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == finish_region:
			break
		for portal in portals:
			var connected: Array = portal.get("regions", [])
			if current not in connected:
				continue
			for next_value in connected:
				var next_region := int(next_value)
				if next_region == current or came_from.has(next_region):
					continue
				came_from[next_region] = {"previous": current, "portal": int(portal.get("id", -1))}
				queue.append(next_region)
	if not came_from.has(finish_region):
		return []
	var portal_ids: Array[int] = []
	var cursor := finish_region
	while cursor != start_region:
		var step: Dictionary = came_from[cursor]
		portal_ids.push_front(int(step.get("portal", -1)))
		cursor = int(step.get("previous", start_region))
	var result: Array[Vector3] = []
	for portal_id in portal_ids:
		if portal_id >= 0 and portal_id < portals.size():
			result.append(portals[portal_id].get("center", Vector3.ZERO) as Vector3)
	return result

func score_connection(from_position: Vector3, to_position: Vector3) -> Dictionary:
	var waypoints := get_route_waypoints(from_position, to_position)
	var destination_region := _nearest_region_id(to_position)
	var narrowest := INF
	for waypoint in waypoints:
		var portal := _nearest_portal(waypoint)
		if not portal.is_empty():
			narrowest = minf(narrowest, float(portal.get("width", INF)))
	return {
		"waypoints": waypoints,
		"choke_count": waypoints.size(),
		"narrowest_width": 0.0 if narrowest == INF else narrowest,
		"destination_dead_end": destination_region >= 0 and bool(regions[destination_region].get("dead_end", false)),
		"start_region": _nearest_region_id(from_position),
		"destination_region": destination_region,
		"topology_version": version,
	}

func get_debug_cells() -> Dictionary:
	return cell_kinds.duplicate()

func get_summary() -> Dictionary:
	return {
		"version": version,
		"cell_size": cell_size,
		"walkable_cells": walkable.values().count(true),
		"regions": regions.size(),
		"portals": portals.size(),
		"chokepoints": portals.filter(func(portal: Dictionary): return bool(portal.get("is_choke", false))).size(),
		"dead_ends": regions.filter(func(region: Dictionary): return bool(region.get("dead_end", false))).size(),
	}

func world_position_for(key: Vector2i) -> Vector3:
	return origin + Vector3(float(key.x) * cell_size, 0.0, float(key.y) * cell_size)

func _compute_clearance() -> void:
	for key_value in walkable.keys():
		var key := key_value as Vector2i
		if not bool(walkable.get(key, false)):
			cell_kinds[key] = CellKind.BLOCKED
			continue
		var distance := maximum_clearance_scan
		for radius in range(1, maximum_clearance_scan + 1):
			if _ring_hits_blocked(key, radius):
				distance = radius - 1
				break
		clearance[key] = distance
		cell_kinds[key] = CellKind.OPEN

func _ring_hits_blocked(center: Vector2i, radius: int) -> bool:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in [center.y - radius, center.y + radius]:
			var key := Vector2i(x, y)
			if not bounds.has_point(key) or not bool(walkable.get(key, false)):
				return true
	for y in range(center.y - radius + 1, center.y + radius):
		for x in [center.x - radius, center.x + radius]:
			var key := Vector2i(x, y)
			if not bounds.has_point(key) or not bool(walkable.get(key, false)):
				return true
	return false

func _build_regions() -> void:
	var visited: Dictionary = {}
	for key_value in walkable.keys():
		var key := key_value as Vector2i
		if visited.has(key) or not _is_region_interior(key):
			continue
		var cells := _flood(key, func(candidate: Vector2i): return _is_region_interior(candidate), visited)
		var region_id := regions.size()
		for cell in cells:
			cell_regions[cell] = region_id
		regions.append({
			"id": region_id,
			"cells": cells,
			"center": _center_of(cells),
			"area": float(cells.size()) * cell_size * cell_size,
			"neighbors": [],
			"dead_end": false,
		})

func _build_portals() -> void:
	var visited: Dictionary = {}
	for key_value in walkable.keys():
		var key := key_value as Vector2i
		if visited.has(key) or not _is_narrow_walkable(key):
			continue
		var cells := _flood(key, func(candidate: Vector2i): return _is_narrow_walkable(candidate), visited)
		var connected_lookup: Dictionary = {}
		var minimum_clearance := maximum_clearance_scan
		for cell in cells:
			minimum_clearance = mini(minimum_clearance, int(clearance.get(cell, 0)))
			for offset in CARDINALS:
				var neighbor := cell + offset
				if cell_regions.has(neighbor):
					connected_lookup[int(cell_regions[neighbor])] = true
		if connected_lookup.size() < 2:
			continue
		var connected: Array = connected_lookup.keys()
		connected.sort()
		var portal_id := portals.size()
		var width := float(minimum_clearance * 2 + 1) * cell_size
		portals.append({
			"id": portal_id,
			"cells": cells,
			"center": _center_of(cells),
			"regions": connected,
			"width": width,
			"is_choke": width <= cell_size * 3.1,
		})
		for cell in cells:
			cell_kinds[cell] = CellKind.CHOKE
		for region_id_value in connected:
			var region_id := int(region_id_value)
			var neighbors: Array = regions[region_id].get("neighbors", [])
			for other_value in connected:
				var other := int(other_value)
				if other != region_id and other not in neighbors:
					neighbors.append(other)
			regions[region_id]["neighbors"] = neighbors

func _classify_dead_ends() -> void:
	if regions.size() <= 1:
		return
	for region in regions:
		var is_dead_end := (region.get("neighbors", []) as Array).size() <= 1
		region["dead_end"] = is_dead_end
		if not is_dead_end:
			continue
		for cell in region.get("cells", []):
			cell_kinds[cell] = CellKind.DEAD_END

func _flood(start: Vector2i, predicate: Callable, visited: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		result.append(current)
		for offset in CARDINALS:
			var neighbor: Vector2i = current + offset
			if visited.has(neighbor) or not bool(predicate.call(neighbor)):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return result

func _is_region_interior(key: Vector2i) -> bool:
	return bool(walkable.get(key, false)) and int(clearance.get(key, 0)) > narrow_clearance_cells

func _is_narrow_walkable(key: Vector2i) -> bool:
	return bool(walkable.get(key, false)) and not _is_region_interior(key)

func _center_of(cells: Array) -> Vector3:
	if cells.is_empty():
		return origin
	var center := Vector3.ZERO
	for cell_value in cells:
		center += world_position_for(cell_value as Vector2i)
	return center / float(cells.size())

func _nearest_region_id(position: Vector3) -> int:
	var key := Vector2i(roundi((position.x - origin.x) / cell_size), roundi((position.z - origin.z) / cell_size))
	if cell_regions.has(key):
		return int(cell_regions[key])
	var best_id := -1
	var best_distance := INF
	for region in regions:
		var distance := _flat_distance(position, region.get("center", origin) as Vector3)
		if distance < best_distance:
			best_distance = distance
			best_id = int(region.get("id", -1))
	return best_id

func _nearest_portal(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for portal in portals:
		var distance := _flat_distance(position, portal.get("center", origin) as Vector3)
		if distance < best_distance:
			best_distance = distance
			best = portal
	return best

func _derive_bounds(cells: Dictionary) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var first := cells.keys()[0] as Vector2i
	var minimum := first
	var maximum := first
	for key_value in cells.keys():
		var key := key_value as Vector2i
		minimum.x = mini(minimum.x, key.x)
		minimum.y = mini(minimum.y, key.y)
		maximum.x = maxi(maximum.x, key.x)
		maximum.y = maxi(maximum.y, key.y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _has_static_blocker(hits: Array[Dictionary]) -> bool:
	for hit in hits:
		var collider := hit.get("collider") as Node
		if collider is StaticBody3D:
			return true
	return false
