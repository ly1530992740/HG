extends RefCounted
class_name SquadObjectiveClearance3D

const SAMPLE_OFFSETS := [
	Vector2.ZERO,
	Vector2(1.0, 0.0),
	Vector2(-1.0, 0.0),
	Vector2(0.0, 1.0),
	Vector2(0.0, -1.0),
]

static func is_area_observed(members: Array[Soldier3D], center: Vector3, radius: float) -> bool:
	var observation_distance := maxf(8.0, radius + 6.0)
	for member in members:
		if member == null or not member.is_combat_alive():
			continue
		if _flat_distance(member.global_position, center) > observation_distance:
			continue
		if visible_sample_count(member.get_world_3d(), member.global_position, member.get_rid(), center, radius) >= 3:
			return true
	return false

static func visible_sample_count(
		world: World3D,
		observer_position: Vector3,
		observer_rid: RID,
		center: Vector3,
		radius: float
) -> int:
	if world == null:
		return 0
	var visible := 0
	var sample_radius := maxf(1.5, radius * 0.55)
	var origin := observer_position + Vector3.UP * 1.25
	for offset in SAMPLE_OFFSETS:
		var destination := center + Vector3(offset.x, 0.0, offset.y) * sample_radius + Vector3.UP * 1.05
		var query := PhysicsRayQueryParameters3D.create(origin, destination, 1, [observer_rid])
		query.collide_with_areas = false
		if world.direct_space_state.intersect_ray(query).is_empty():
			visible += 1
	return visible

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
