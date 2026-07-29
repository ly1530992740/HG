extends Node
class_name PlayerBallisticsComponent3D

func ray_endpoint(actor: Node3D, origin: Vector3, direction: Vector3, distance: float, collision_mask: int, exclusions: Array[RID]) -> Vector3:
	if actor.get_world_3d() == null:
		return origin + direction * distance
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, collision_mask, exclusions)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", origin + direction * distance) as Vector3

func apply_spread(direction: Vector3, spread_radians: float) -> Vector3:
	if spread_radians <= 0.0:
		return direction
	var right := direction.cross(Vector3.UP).normalized()
	if right == Vector3.ZERO:
		right = Vector3.RIGHT
	var up := right.cross(direction).normalized()
	return (direction + right * randf_range(-spread_radians, spread_radians) + up * randf_range(-spread_radians, spread_radians)).normalized()

func perform_shot(actor: Node3D, origin: Vector3, direction: Vector3, distance: float, collision_mask: int, damage: int) -> Dictionary:
	if actor.get_world_3d() == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, collision_mask, [actor.get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.get("collider") as Node
	if collider != null and collider.has_method("receive_shot"):
		collider.receive_shot(damage, hit.get("position", Vector3.ZERO), actor)
	return hit

func spawn_tracer(actor: Node3D, origin: Vector3, destination: Vector3, tracer_speed: float, tracer_length: float) -> void:
	var length := origin.distance_to(destination)
	if length <= 0.01 or actor.get_tree().current_scene == null:
		return
	var direction := (destination - origin).normalized()
	var visible_length := minf(tracer_length, length)
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, visible_length)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.78, 0.22, 0.9)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.48, 0.08)
	mesh.material = material
	tracer.mesh = mesh
	actor.get_tree().current_scene.add_child(tracer)
	tracer.global_position = origin + direction * visible_length * 0.5
	tracer.look_at(destination, Vector3.UP)
	var tween := tracer.create_tween()
	var travel_distance := maxf(0.0, length - visible_length)
	var travel_duration := travel_distance / maxf(0.01, tracer_speed)
	if travel_duration > 0.0:
		tween.tween_property(tracer, "global_position", destination - direction * visible_length * 0.5, travel_duration)
	tween.tween_property(tracer, "transparency", 1.0, 0.05)
	tween.tween_callback(tracer.queue_free)
