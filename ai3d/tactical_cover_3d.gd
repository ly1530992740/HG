@tool
extends StaticBody3D
class_name TacticalCover3D

@export_category("掩体尺寸")
@export_range(0.5, 30.0, 0.1) var cover_length := 5.0:
	set(value):
		cover_length = maxf(0.5, value)
		_schedule_rebuild()
@export_range(0.15, 4.0, 0.05) var cover_width := 0.5:
	set(value):
		cover_width = maxf(0.15, value)
		_schedule_rebuild()
@export_range(0.4, 5.0, 0.05) var cover_height := 1.25:
	set(value):
		cover_height = maxf(0.4, value)
		_schedule_rebuild()

@export_category("自动掩体点位")
@export_range(0.45, 3.0, 0.05) var slot_spacing := 1.05:
	set(value):
		slot_spacing = maxf(0.45, value)
		_schedule_rebuild()
@export_range(0.1, 1.5, 0.05) var slot_clearance := 0.45:
	set(value):
		slot_clearance = maxf(0.1, value)
		_schedule_rebuild()
@export var material_color := Color(0.38, 0.4, 0.38, 1.0):
	set(value):
		material_color = value
		_schedule_rebuild()

var _reservations: Dictionary = {}
var _rebuild_queued := false

func _ready() -> void:
	add_to_group("cover3d")
	if not Engine.is_editor_hint():
		var registry := BattlefieldRegistry3D.find(get_tree())
		if registry != null:
			registry.register_node(self)
	_rebuild()

func _schedule_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")

func _rebuild() -> void:
	_rebuild_queued = false
	var mesh_instance := get_node_or_null("GeneratedMesh") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "GeneratedMesh"
		add_child(mesh_instance)
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(cover_length, cover_height, cover_width)
	var material := StandardMaterial3D.new()
	material.albedo_color = material_color
	material.roughness = 0.9
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = cover_height * 0.5

	var collision := get_node_or_null("GeneratedCollision") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "GeneratedCollision"
		add_child(collision)
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(cover_length, cover_height, cover_width)
	collision.shape = box_shape
	collision.position.y = cover_height * 0.5
	_rebuild_slots()

func _rebuild_slots() -> void:
	var slots := get_node_or_null("Slots") as Node3D
	if slots == null:
		slots = Node3D.new()
		slots.name = "Slots"
		add_child(slots)
	for child in slots.get_children():
		child.free()
	_reservations.clear()
	var count := get_cover_capacity_per_side()
	var occupied_length := float(count - 1) * slot_spacing
	for side in [-1, 1]:
		for index in count:
			var marker := Marker3D.new()
			marker.name = "%s_%02d" % ["North" if side < 0 else "South", index + 1]
			marker.position = Vector3(-occupied_length * 0.5 + float(index) * slot_spacing, 0.0, float(side) * (cover_width * 0.5 + slot_clearance))
			marker.set_meta("side", side)
			slots.add_child(marker)

func get_cover_capacity_per_side() -> int:
	return maxi(1, floori(maxf(0.0, cover_length - 0.6) / slot_spacing) + 1)

func get_cover_axis() -> Vector3:
	return global_transform.basis.x.normalized()

func get_slots_against(threat_position: Vector3) -> Array[Marker3D]:
	var result: Array[Marker3D] = []
	var local_threat := to_local(threat_position)
	var safe_side := -1 if local_threat.z >= 0.0 else 1
	var slots := get_node_or_null("Slots")
	if slots == null:
		return result
	for child in slots.get_children():
		if child is Marker3D and int(child.get_meta("side", 0)) == safe_side:
			result.append(child)
	return result

func reserve_slot(actor: Node3D, threat_position: Vector3) -> Marker3D:
	if actor == null:
		return null
	for slot in get_slots_against(threat_position):
		var reserved := _get_reserved_actor(slot)
		if reserved == null or reserved == actor:
			_set_reservation(slot, actor)
			return slot
	return null

func reserve_reachable_slot(actor: Node3D, threat_position: Vector3) -> Marker3D:
	if actor == null:
		return null
	var existing := get_reserved_slot(actor)
	if existing != null:
		return existing
	var local_actor := to_local(actor.global_position)
	for slot in get_slots_against(threat_position):
		var local_slot := slot.position
		# Soldiers currently use direct GOAP movement, so do not assign a slot
		# that requires crossing the cover body itself.
		if absf(local_actor.z) > cover_width * 0.5 and signf(local_actor.z) != signf(local_slot.z):
			continue
		if _get_reserved_actor(slot) == null:
			_set_reservation(slot, actor)
			return slot
	return null

func get_nearest_available_slot(actor: Node3D) -> Marker3D:
	if actor == null:
		return null
	var existing := get_reserved_slot(actor)
	if existing != null:
		return existing
	var slots := get_node_or_null("Slots")
	if slots == null:
		return null
	var nearest: Marker3D
	var nearest_distance := INF
	for child in slots.get_children():
		if not child is Marker3D or _get_reserved_actor(child as Marker3D) != null:
			continue
		var slot := child as Marker3D
		var distance := actor.global_position.distance_to(slot.global_position)
		if distance < nearest_distance:
			nearest = slot
			nearest_distance = distance
	return nearest

func reserve_specific_slot(actor: Node3D, slot: Marker3D) -> bool:
	if actor == null or slot == null or slot.get_parent() != get_node_or_null("Slots"):
		return false
	var reserved := _get_reserved_actor(slot)
	if reserved != null and reserved != actor:
		return false
	_set_reservation(slot, actor)
	return true

func get_reserved_slot(actor: Node3D) -> Marker3D:
	for slot_value in _reservations.keys():
		if not is_instance_valid(slot_value) or not slot_value is Marker3D:
			_reservations.erase(slot_value)
			continue
		var slot := slot_value as Marker3D
		if _get_reserved_actor(slot) == actor:
			return slot
	return null

func release_slot(actor: Node3D) -> void:
	for slot_value in _reservations.keys():
		if not is_instance_valid(slot_value) or not slot_value is Marker3D:
			_reservations.erase(slot_value)
			continue
		var slot := slot_value as Marker3D
		if _get_reserved_actor(slot) == actor:
			_reservations.erase(slot)

func report_projectile_impact(threat_position: Vector3, intensity := 1.0) -> void:
	for slot in get_slots_against(threat_position):
		var occupant := _get_reserved_actor(slot)
		if occupant != null and occupant.has_method("notify_cover_impact"):
			occupant.notify_cover_impact(threat_position, intensity)

func get_available_slot_count_against(threat_position: Vector3) -> int:
	var count := 0
	for slot in get_slots_against(threat_position):
		if _get_reserved_actor(slot) == null:
			count += 1
	return count

func score_for_actor(actor: Node3D, threat_position: Vector3, preferred_range := 18.0) -> float:
	if actor == null:
		return -INF
	var slots := get_slots_against(threat_position)
	var best := -INF
	for slot in slots:
		var occupant := _get_reserved_actor(slot)
		if occupant != null and occupant != actor:
			continue
		var travel := actor.global_position.distance_to(slot.global_position)
		var threat_distance := slot.global_position.distance_to(threat_position)
		var range_error := absf(threat_distance - maxf(2.0, preferred_range))
		var score := 80.0 - travel * 4.0 - range_error * 0.65
		score += cover_height * 5.0
		score += float(get_available_slot_count_against(threat_position)) * 1.5
		if occupant == actor:
			score += 12.0
		best = maxf(best, score)
	return best

func _set_reservation(slot: Marker3D, actor: Node3D) -> void:
	_reservations[slot] = weakref(actor)

func _get_reserved_actor(slot: Marker3D) -> Node:
	if slot == null or not _reservations.has(slot):
		return null
	var stored = _reservations.get(slot)
	var occupant: Object
	if stored is WeakRef:
		occupant = (stored as WeakRef).get_ref()
	elif is_instance_valid(stored):
		occupant = stored as Object
	if not is_instance_valid(occupant) or not occupant is Node:
		_reservations.erase(slot)
		return null
	return occupant as Node

func get_flank_route(squad_position: Vector3, target_position: Vector3, clearance := 1.4) -> Array[Vector3]:
	var axis := get_cover_axis()
	if axis.dot(target_position - squad_position) < 0.0:
		axis = -axis
	var local_target := to_local(target_position)
	var safe_side := -1.0 if local_target.z >= 0.0 else 1.0
	var normal := global_transform.basis.z.normalized() * safe_side
	var half_length := cover_length * 0.5
	return [
		global_position - axis * (half_length + clearance) + normal * clearance,
		global_position + normal * clearance,
		global_position + axis * (half_length + clearance) + normal * clearance,
		global_position + axis * (half_length + clearance) - normal * clearance,
	]

func get_departure_route(slot: Marker3D, destination: Vector3, clearance := 0.8) -> Array[Vector3]:
	if slot == null:
		return []
	var axis := get_cover_axis()
	var exit_sign := signf(axis.dot(destination - global_position))
	if is_zero_approx(exit_sign):
		exit_sign = signf(axis.dot(slot.global_position - global_position))
	if is_zero_approx(exit_sign):
		exit_sign = 1.0
	var local_slot := to_local(slot.global_position)
	var side_sign := signf(local_slot.z)
	if is_zero_approx(side_sign):
		side_sign = 1.0
	var safe_normal := global_transform.basis.z.normalized() * side_sign
	var exit_position := global_position \
		+ axis * exit_sign * (cover_length * 0.5 + clearance) \
		+ safe_normal * (cover_width * 0.5 + slot_clearance)
	return [exit_position]

func get_bypass_point(from_position: Vector3, destination: Vector3, clearance := 0.9) -> Vector3:
	var points := get_bypass_points(from_position, destination, clearance)
	var first := points[0]
	var second := points[1]
	var first_score := from_position.distance_to(first) + first.distance_to(destination)
	var second_score := from_position.distance_to(second) + second.distance_to(destination)
	return first if first_score <= second_score else second

func get_bypass_points(from_position: Vector3, destination: Vector3, clearance := 0.9) -> Array[Vector3]:
	var local_from := to_local(from_position)
	var side_sign := signf(local_from.z)
	if is_zero_approx(side_sign):
		side_sign = signf(to_local(destination).z)
	if is_zero_approx(side_sign):
		side_sign = 1.0
	var side_offset := side_sign * (cover_width * 0.5 + slot_clearance + clearance * 0.35)
	var end_offset := cover_length * 0.5 + clearance
	var first := to_global(Vector3(-end_offset, 0.0, side_offset))
	var second := to_global(Vector3(end_offset, 0.0, side_offset))
	return [first, second]
