extends MeshInstance3D
class_name TacticalSandboxSightVisualizer3D

const RAY_COUNT := 48

var render_version := 0
var visible_ray_count := 0

func show_soldier(soldier: Soldier3D) -> void:
	if soldier == null or not soldier.is_inside_tree() or soldier.get_world_3d() == null:
		clear_view()
		return
	var forward := soldier.logical_forward
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var half_fov := deg_to_rad(clampf(soldier.field_of_view_degrees, 1.0, 360.0) * 0.5)
	var center := soldier.global_position
	center.y = 0.075
	var eye := soldier.global_position + Vector3.UP * 1.25
	var points: Array[Vector3] = []
	for index in range(RAY_COUNT + 1):
		var amount := float(index) / float(RAY_COUNT)
		var angle := lerpf(-half_fov, half_fov, amount)
		var direction := forward.rotated(Vector3.UP, angle)
		var endpoint := eye + direction * soldier.sight_range
		var query := PhysicsRayQueryParameters3D.create(eye, endpoint, 1, [soldier.get_rid()])
		query.collide_with_areas = false
		var hit := soldier.get_world_3d().direct_space_state.intersect_ray(query)
		var point := endpoint if hit.is_empty() else hit.get("position", endpoint) as Vector3
		point.y = center.y
		points.append(point)
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(0.18, 0.84, 1.0, 0.18) \
		if soldier.combat_team == Soldier3D.Team.BLUE else Color(1.0, 0.3, 0.2, 0.18)
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for index in RAY_COUNT:
		immediate.surface_add_vertex(center)
		immediate.surface_add_vertex(points[index])
		immediate.surface_add_vertex(points[index + 1])
	immediate.surface_end()
	mesh = immediate
	visible = true
	visible_ray_count = points.size()
	render_version += 1

func clear_view() -> void:
	mesh = null
	visible = false
	visible_ray_count = 0
	render_version += 1

func get_visible_ray_count() -> int:
	return visible_ray_count
