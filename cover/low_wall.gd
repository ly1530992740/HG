extends StaticBody2D
class_name LowWall

@export_range(0.0, 1.0) var blind_block_chance := 0.9
@export_range(0.0, 1.0) var precision_block_chance := 0.35
@export var cover_half_length := 88.0
@export var minimum_actor_spacing := 34.0

@onready var interaction_area: Area2D = $InteractionArea
@onready var slots: Array[Marker2D] = []

var assignments: Dictionary = {}
var reservations: Dictionary = {}
var lateral_offsets: Dictionary = {}

func _ready() -> void:
	for child in $CoverSlots.get_children():
		if child is Marker2D:
			slots.append(child)
	add_to_group("cover")
	add_to_group("projectile_blocker")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func request_cover(actor: Node2D) -> Marker2D:
	return _request_cover(actor, null)

func request_cover_against(actor: Node2D, threat_position: Vector2) -> Marker2D:
	return _request_cover(actor, threat_position)

func has_available_cover_against(threat_position: Vector2) -> bool:
	_cleanup_assignments()
	for slot in slots:
		if _is_slot_claimed(slot):
			continue
		if _slot_protects_against(slot, threat_position):
			return true
	return false

func get_available_slot_count_against(threat_position: Vector2) -> int:
	_cleanup_assignments()
	var count := 0
	for slot in slots:
		if not _is_slot_claimed(slot) and _slot_protects_against(slot, threat_position):
			count += 1
	return count

func get_cover_capacity_per_side() -> int:
	return slots.size() / 2

func reserve_cover_against(actor: Node2D, threat_position: Vector2) -> Marker2D:
	_cleanup_assignments()
	if assignments.has(actor):
		var occupied_slot := assignments[actor] as Marker2D
		return occupied_slot if _slot_protects_against(occupied_slot, threat_position) else null
	if reservations.has(actor):
		var reserved_slot := reservations[actor] as Marker2D
		if _slot_protects_against(reserved_slot, threat_position):
			return reserved_slot
		reservations.erase(actor)
	var nearest_slot: Marker2D = null
	var nearest_distance := INF
	for slot in slots:
		if _is_slot_claimed(slot) or not _slot_protects_against(slot, threat_position):
			continue
		var distance := actor.global_position.distance_to(slot.global_position)
		if distance < nearest_distance:
			nearest_slot = slot
			nearest_distance = distance
	if nearest_slot:
		reservations[actor] = nearest_slot
	return nearest_slot

func _request_cover(actor: Node2D, threat_position: Variant) -> Marker2D:
	_cleanup_assignments()
	if assignments.has(actor):
		var assigned_slot := assignments[actor] as Marker2D
		if threat_position == null or _slot_protects_against(assigned_slot, threat_position as Vector2):
			return assigned_slot
		return null
	if reservations.has(actor):
		var reserved_slot := reservations[actor] as Marker2D
		if threat_position == null or _slot_protects_against(reserved_slot, threat_position as Vector2):
			reservations.erase(actor)
			assignments[actor] = reserved_slot
			lateral_offsets[actor] = 0.0
			return reserved_slot
		reservations.erase(actor)

	var nearest_slot: Marker2D = null
	var nearest_distance := INF
	for slot in slots:
		if _is_slot_claimed(slot):
			continue
		if threat_position != null and not _slot_protects_against(slot, threat_position as Vector2):
			continue
		var distance := actor.global_position.distance_to(slot.global_position)
		if distance < nearest_distance:
			nearest_slot = slot
			nearest_distance = distance

	if nearest_slot:
		assignments[actor] = nearest_slot
		lateral_offsets[actor] = 0.0
	return nearest_slot

func release_cover(actor: Node) -> void:
	assignments.erase(actor)
	reservations.erase(actor)
	lateral_offsets.erase(actor)

func get_cover_axis() -> Vector2:
	return global_transform.x.normalized()

func get_navigation_detour_waypoint(from_position: Vector2, destination: Vector2, clearance := 120.0) -> Variant:
	var local_from := to_local(from_position)
	var local_destination := to_local(destination)
	if is_zero_approx(local_destination.y - local_from.y) or signf(local_from.y) == signf(local_destination.y):
		return null
	var crossing_ratio := -local_from.y / (local_destination.y - local_from.y)
	if crossing_ratio <= 0.0 or crossing_ratio >= 1.0:
		return null
	var crossing_x := lerpf(local_from.x, local_destination.x, crossing_ratio)
	var endpoint_clearance := cover_half_length + clearance
	# A path tangent to the clearance boundary has already rounded the wall end.
	if absf(crossing_x) >= endpoint_clearance - 1.0:
		return null
	var side_y := signf(local_from.y) * (12.0 + clearance)
	var left_waypoint := Vector2(-endpoint_clearance, side_y)
	var right_waypoint := Vector2(endpoint_clearance, side_y)
	var left_cost := local_from.distance_to(left_waypoint) + left_waypoint.distance_to(local_destination)
	var right_cost := local_from.distance_to(right_waypoint) + right_waypoint.distance_to(local_destination)
	return to_global(left_waypoint if left_cost <= right_cost else right_waypoint)

func get_cover_position(actor: Node2D, slot: Marker2D, lateral_offset: float) -> Vector2:
	if not slots.has(slot):
		return slot.global_position
	var clamped_offset := clamp_lateral_offset(actor, slot, lateral_offset)
	return slot.global_position + get_cover_axis() * clamped_offset

func clamp_lateral_offset(actor: Node2D, slot: Marker2D, value: float) -> float:
	var desired_x := clampf(slot.position.x + value, -cover_half_length, cover_half_length)
	for other_actor in assignments.keys():
		if other_actor == actor or not is_instance_valid(other_actor):
			continue
		var other_slot := assignments[other_actor] as Marker2D
		if other_slot == null or signf(other_slot.position.y) != signf(slot.position.y):
			continue
		var other_x := other_slot.position.x + float(lateral_offsets.get(other_actor, 0.0))
		if slot.position.x <= other_slot.position.x:
			desired_x = minf(desired_x, other_x - minimum_actor_spacing)
		else:
			desired_x = maxf(desired_x, other_x + minimum_actor_spacing)
	var result := desired_x - slot.position.x
	lateral_offsets[actor] = result
	return result

func should_block_projectile(projectile: Node) -> bool:
	var shooter := projectile.get("shooter") as Node2D
	if shooter == null:
		return true

	if assignments.has(shooter):
		return false

	var shooter_local := to_local(shooter.global_position)
	for actor in assignments.keys():
		if not is_instance_valid(actor):
			continue
		if shooter.has_method("can_damage_target") and not shooter.can_damage_target(actor):
			continue
		var actor_local := to_local(actor.global_position)
		if signf(actor_local.y) == signf(shooter_local.y):
			continue
		var precision: bool = actor.has_method("is_cover_precision") and bool(actor.is_cover_precision())
		var block_chance: float = precision_block_chance if precision else blind_block_chance
		var blocked := randf() <= block_chance
		if blocked and actor.has_method("on_cover_blocked_projectile"):
			actor.on_cover_blocked_projectile()
		return blocked

	return true

func _is_source_across_wall(actor: Node2D, source_position: Vector2) -> bool:
	var actor_local := to_local(actor.global_position)
	var source_local := to_local(source_position)
	return signf(actor_local.y) != signf(source_local.y)

func _slot_protects_against(slot: Marker2D, threat_position: Vector2) -> bool:
	var threat_local := to_local(threat_position)
	return not is_zero_approx(threat_local.y) and signf(slot.position.y) != signf(threat_local.y)

func _cleanup_assignments() -> void:
	for actor in assignments.keys():
		if not is_instance_valid(actor):
			assignments.erase(actor)
			lateral_offsets.erase(actor)
	for actor in reservations.keys():
		if not is_instance_valid(actor):
			reservations.erase(actor)

func _is_slot_claimed(slot: Marker2D) -> bool:
	return assignments.values().has(slot) or reservations.values().has(slot)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("register_cover_candidate"):
		body.register_cover_candidate(self)

func _on_body_exited(body: Node2D) -> void:
	if body.has_method("unregister_cover_candidate"):
		body.unregister_cover_candidate(self)
