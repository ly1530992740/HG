extends Node3D
class_name BattlefieldDressing3D

@export var seed := 1945
@export_range(0, 80, 1) var ground_patch_count := 34
@export_range(0, 40, 1) var vegetation_cluster_count := 18
@export_range(0, 24, 1) var debris_count := 12

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = seed
	_build_dirt_tracks()
	_build_ground_patches()
	_build_craters()
	_build_vegetation()
	_build_defense_sandbags()
	_build_debris()

func _build_dirt_tracks() -> void:
	var dirt := _material(Color(0.155, 0.145, 0.115), 0.98)
	_box("NorthSouthTrack", Vector3(5.4, 0.012, 52.0), Vector3(7.5, 0.012, 0.0), dirt)
	_box("SupplyTrack", Vector3(33.0, 0.014, 3.2), Vector3(-10.0, 0.014, -10.0), dirt, Vector3(0.0, -0.12, 0.0))
	var wheel := _material(Color(0.065, 0.075, 0.065), 1.0)
	_box("WheelRutLeft", Vector3(0.2, 0.017, 50.0), Vector3(6.25, 0.017, 0.0), wheel)
	_box("WheelRutRight", Vector3(0.2, 0.017, 50.0), Vector3(8.75, 0.017, 0.0), wheel)

func _build_ground_patches() -> void:
	var colors := [Color(0.055, 0.09, 0.07), Color(0.085, 0.115, 0.08), Color(0.11, 0.115, 0.075), Color(0.06, 0.1, 0.085)]
	for index in ground_patch_count:
		var position := Vector3(_rng.randf_range(-29.0, 29.0), 0.008, _rng.randf_range(-24.0, 24.0))
		_ground_patch(
			"GroundPatch%02d" % index,
			Vector2(_rng.randf_range(1.4, 3.8), _rng.randf_range(1.1, 3.2)),
			position,
			_material(colors[index % colors.size()], 1.0)
		)

func _build_craters() -> void:
	var rim_material := _material(Color(0.105, 0.095, 0.075), 1.0)
	var center_material := _material(Color(0.025, 0.03, 0.028), 1.0)
	for index in 7:
		var crater := Node3D.new()
		crater.name = "ShellCrater%02d" % index
		crater.position = Vector3(_rng.randf_range(-25.0, 25.0), 0.02, _rng.randf_range(-21.0, 21.0))
		add_child(crater)
		var center := MeshInstance3D.new()
		var center_mesh := CylinderMesh.new()
		center_mesh.top_radius = _rng.randf_range(0.55, 1.0)
		center_mesh.bottom_radius = center_mesh.top_radius
		center_mesh.height = 0.025
		center_mesh.radial_segments = 10
		center_mesh.material = center_material
		center.mesh = center_mesh
		crater.add_child(center)
		for segment in 10:
			var angle := TAU * float(segment) / 10.0
			var radius := center_mesh.top_radius + 0.18
			var clod := _box_part(Vector3(0.24, _rng.randf_range(0.08, 0.16), 0.3), Vector3(cos(angle) * radius, 0.06, sin(angle) * radius), rim_material)
			clod.rotation.y = -angle
			crater.add_child(clod)

func _build_vegetation() -> void:
	var stem := _material(Color(0.075, 0.095, 0.06), 1.0)
	var leaf_colors := [Color(0.065, 0.11, 0.075), Color(0.09, 0.125, 0.07), Color(0.05, 0.085, 0.07)]
	for index in vegetation_cluster_count:
		var root := Node3D.new()
		root.name = "GrassCluster%02d" % index
		var edge_bias := _rng.randf() < 0.72
		root.position = Vector3(
			_rng.randf_range(-30.0, 30.0),
			0.0,
			_rng.randf_range(-25.0, 25.0)
		)
		if edge_bias and absf(root.position.x) < 12.0 and absf(root.position.z) < 12.0:
			root.position *= 1.8
		add_child(root)
		var leaf := _material(leaf_colors[index % leaf_colors.size()], 1.0)
		for blade_index in _rng.randi_range(4, 7):
			var blade := _box_part(Vector3(0.06, _rng.randf_range(0.28, 0.65), 0.06), Vector3(_rng.randf_range(-0.24, 0.24), 0.22, _rng.randf_range(-0.24, 0.24)), leaf if blade_index % 2 == 0 else stem)
			blade.rotation.z = _rng.randf_range(-0.3, 0.3)
			root.add_child(blade)

func _build_defense_sandbags() -> void:
	var sand := _material(Color(0.26, 0.25, 0.2), 1.0)
	for side in [-1, 1]:
		for index in 6:
			var bag := _box_part(Vector3(0.72, 0.22, 0.34), Vector3(side * (2.8 + index * 0.7), 0.12, 13.0 + absf(float(index) - 2.5) * 0.12), sand)
			bag.name = "DefenseSandbag"
			bag.rotation.y = 0.06 * side * (float(index) - 2.5)
			add_child(bag)

func _build_debris() -> void:
	var timber := _material(Color(0.11, 0.08, 0.06), 1.0)
	var steel := _material(Color(0.075, 0.085, 0.085), 0.74)
	for index in debris_count:
		var piece := _box_part(
			Vector3(_rng.randf_range(0.08, 0.18), _rng.randf_range(0.08, 0.16), _rng.randf_range(0.8, 2.2)),
			Vector3(_rng.randf_range(-28.0, 28.0), 0.12, _rng.randf_range(-23.0, 23.0)),
			timber if index % 3 else steel
		)
		piece.name = "BattleDebris%02d" % index
		piece.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-PI, PI), _rng.randf_range(-0.45, 0.45))
		add_child(piece)

func _box(node_name: String, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var instance := _box_part(size, position, material)
	instance.name = node_name
	instance.rotation = rotation
	add_child(instance)
	return instance

func _box_part(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	return instance

func _ground_patch(node_name: String, radii: Vector2, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var segment_count := _rng.randi_range(7, 10)
	var rotation_offset := _rng.randf_range(-PI, PI)
	var ring: Array[Vector3] = []
	for segment in segment_count:
		var angle := rotation_offset + TAU * float(segment) / float(segment_count)
		var irregularity := _rng.randf_range(0.72, 1.18)
		ring.append(Vector3(cos(angle) * radii.x * irregularity, 0.0, sin(angle) * radii.y * irregularity))
	for segment in segment_count:
		var next_segment := (segment + 1) % segment_count
		surface.set_uv(Vector2(0.5, 0.5))
		surface.add_vertex(Vector3.ZERO)
		surface.set_uv(Vector2(0.5 + ring[segment].x / radii.x * 0.5, 0.5 + ring[segment].z / radii.y * 0.5))
		surface.add_vertex(ring[segment])
		surface.set_uv(Vector2(0.5 + ring[next_segment].x / radii.x * 0.5, 0.5 + ring[next_segment].z / radii.y * 0.5))
		surface.add_vertex(ring[next_segment])
	instance.mesh = surface.commit()
	instance.position = position
	add_child(instance)
	return instance

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material
