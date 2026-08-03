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

func show_structure(structure: TacticalStructure3D) -> void:
	if structure == null or not structure.is_inside_tree() or structure.get_world_3d() == null:
		clear_view()
		return
	var fire_range := structure.get_effective_fire_range()
	if fire_range <= 0.0:
		clear_view()
		return
	var forward := structure.global_transform.basis * Vector3.FORWARD
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var half_arc := deg_to_rad(clampf(structure.firing_arc_degrees, 1.0, 360.0) * 0.5)
	var center := structure.global_position
	center.y = 0.085
	var muzzle := structure.get_muzzle_position()
	var excluded: Array[RID] = [structure.get_rid()]
	var user := structure.get_user() as Soldier3D
	if user != null:
		excluded.append(user.get_rid())
	var points: Array[Vector3] = []
	for index in range(RAY_COUNT + 1):
		var amount := float(index) / float(RAY_COUNT)
		var angle := lerpf(-half_arc, half_arc, amount)
		var direction := forward.rotated(Vector3.UP, angle)
		var endpoint := muzzle + direction * fire_range
		var query := PhysicsRayQueryParameters3D.create(muzzle, endpoint, 1, excluded)
		query.collide_with_areas = false
		var hit := structure.get_world_3d().direct_space_state.intersect_ray(query)
		var point := endpoint if hit.is_empty() else hit.get("position", endpoint) as Vector3
		point.y = center.y
		points.append(point)
	var immediate := ImmediateMesh.new()
	var fill_material := StandardMaterial3D.new()
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.no_depth_test = false
	fill_material.albedo_color = Color(1.0, 0.36, 0.08, 0.18)
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill_material)
	for index in RAY_COUNT:
		immediate.surface_add_vertex(center)
		immediate.surface_add_vertex(points[index])
		immediate.surface_add_vertex(points[index + 1])
	immediate.surface_end()
	var line_material := StandardMaterial3D.new()
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.no_depth_test = false
	line_material.albedo_color = Color(1.0, 0.72, 0.12, 0.9)
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, line_material)
	for point in points:
		immediate.surface_add_vertex(point)
	immediate.surface_end()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	immediate.surface_add_vertex(center)
	immediate.surface_add_vertex(points.front())
	immediate.surface_add_vertex(center)
	immediate.surface_add_vertex(points.back())
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
