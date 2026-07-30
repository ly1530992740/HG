extends RefCounted
class_name WeaponModelFactory3D

static func rebuild(root: Node3D, definition: Dictionary, display_scale := 1.0) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()
	var wood := _material(_color(definition.get("wood_color", "70452b")), 0.02, 0.72)
	var metal := _material(_color(definition.get("metal_color", "24282b")), 0.72, 0.3)
	var dark := _material(Color(0.055, 0.06, 0.065), 0.55, 0.3)
	var model := String(definition.get("model", "long_rifle"))
	match model:
		"c96":
			_part(root, "Receiver", Vector3(0.12, 0.14, 0.38), Vector3(0.0, 0.02, -0.1), metal)
			_part(root, "Barrel", Vector3(0.055, 0.055, 0.42), Vector3(0.0, 0.05, -0.48), dark)
			_part(root, "Magazine", Vector3(0.11, 0.22, 0.14), Vector3(0.0, -0.13, -0.13), metal, Vector3(0.08, 0.0, 0.0))
			_part(root, "Grip", Vector3(0.13, 0.32, 0.12), Vector3(0.0, -0.22, 0.09), wood, Vector3(-0.25, 0.0, 0.0))
		"pocket_pistol":
			_part(root, "Slide", Vector3(0.11, 0.105, 0.36), Vector3(0.0, 0.04, -0.18), metal)
			_part(root, "Barrel", Vector3(0.045, 0.045, 0.25), Vector3(0.0, 0.055, -0.43), dark)
			_part(root, "Grip", Vector3(0.12, 0.26, 0.1), Vector3(0.0, -0.16, 0.02), wood, Vector3(-0.16, 0.0, 0.0))
		"m1911":
			_part(root, "Slide", Vector3(0.12, 0.115, 0.42), Vector3(0.0, 0.045, -0.18), metal)
			_part(root, "Barrel", Vector3(0.045, 0.045, 0.28), Vector3(0.0, 0.05, -0.46), dark)
			_part(root, "Grip", Vector3(0.13, 0.29, 0.11), Vector3(0.0, -0.18, 0.0), wood, Vector3(-0.2, 0.0, 0.0))
			_part(root, "TriggerGuard", Vector3(0.11, 0.09, 0.05), Vector3(0.0, -0.07, -0.1), dark)
		"drum_smg":
			_long_gun(root, wood, metal, 0.9, 0.42)
			_cylinder(root, "DrumMagazine", 0.18, 0.11, Vector3(0.0, -0.14, -0.1), metal, Vector3(PI * 0.5, 0.0, 0.0))
			_cylinder(root, "BarrelJacket", 0.075, 0.52, Vector3(0.0, 0.04, -0.65), metal, Vector3(PI * 0.5, 0.0, 0.0))
		"side_mag_smg":
			_long_gun(root, wood, metal, 0.82, 0.36)
			_part(root, "SideMagazine", Vector3(0.38, 0.08, 0.13), Vector3(0.18, -0.02, -0.25), metal, Vector3(0.0, 0.0, -0.08))
		"box_mag_smg":
			_long_gun(root, wood, metal, 0.86, 0.42)
			_part(root, "BoxMagazine", Vector3(0.1, 0.34, 0.15), Vector3(0.0, -0.2, -0.18), metal, Vector3(0.12, 0.0, 0.0))
			_cylinder(root, "PerforatedJacket", 0.06, 0.45, Vector3(0.0, 0.045, -0.61), metal, Vector3(PI * 0.5, 0.0, 0.0))
		"pan_lmg":
			_long_gun(root, wood, metal, 1.0, 0.54)
			_cylinder(root, "PanMagazine", 0.24, 0.07, Vector3(0.0, 0.16, -0.22), dark)
			_part(root, "BipodLeft", Vector3(0.025, 0.38, 0.025), Vector3(-0.15, -0.2, -0.66), metal, Vector3(0.2, 0.0, -0.3))
			_part(root, "BipodRight", Vector3(0.025, 0.38, 0.025), Vector3(0.15, -0.2, -0.66), metal, Vector3(0.2, 0.0, 0.3))
		"top_mag_lmg":
			_long_gun(root, wood, metal, 0.98, 0.52)
			_part(root, "TopMagazine", Vector3(0.12, 0.35, 0.18), Vector3(0.0, 0.22, -0.22), metal, Vector3(0.0, 0.0, 0.08))
		"zb26_lmg":
			_long_gun(root, wood, metal, 1.0, 0.56)
			_part(root, "TopMagazine", Vector3(0.11, 0.38, 0.17), Vector3(0.0, 0.24, -0.2), metal, Vector3(0.0, 0.0, 0.1))
			_part(root, "CarryHandle", Vector3(0.22, 0.025, 0.025), Vector3(0.0, 0.18, -0.5), dark, Vector3(0.0, 0.0, 0.25))
			_add_bipod(root, metal)
		"shotgun":
			_long_gun(root, wood, metal, 1.0, 0.6)
			_cylinder(root, "TubeMagazine", 0.035, 0.64, Vector3(0.0, -0.055, -0.64), metal, Vector3(PI * 0.5, 0.0, 0.0))
		"auto5":
			_long_gun(root, wood, metal, 0.95, 0.55)
			_part(root, "TallReceiver", Vector3(0.14, 0.18, 0.3), Vector3(0.0, 0.055, -0.08), metal)
			_cylinder(root, "TubeMagazine", 0.034, 0.58, Vector3(0.0, -0.055, -0.6), metal, Vector3(PI * 0.5, 0.0, 0.0))
		"knife":
			_part(root, "Blade", Vector3(0.055, 0.025, 0.55), Vector3(0.0, 0.02, -0.34), metal)
			_part(root, "Guard", Vector3(0.24, 0.04, 0.055), Vector3(0.0, 0.0, -0.02), dark)
			_part(root, "Handle", Vector3(0.09, 0.09, 0.28), Vector3(0.0, -0.01, 0.15), wood)
		"infantry_knife":
			_part(root, "Blade", Vector3(0.075, 0.025, 0.38), Vector3(0.0, 0.02, -0.24), metal)
			_part(root, "Guard", Vector3(0.18, 0.04, 0.055), Vector3(0.0, 0.0, -0.02), dark)
			_part(root, "Handle", Vector3(0.11, 0.09, 0.24), Vector3(0.0, -0.01, 0.14), wood)
		"dadao":
			_part(root, "Blade", Vector3(0.18, 0.035, 0.78), Vector3(0.0, 0.03, -0.48), metal, Vector3(0.0, 0.0, -0.08))
			_part(root, "BladeTip", Vector3(0.25, 0.035, 0.22), Vector3(0.035, 0.03, -0.93), metal, Vector3(0.0, 0.0, -0.28))
			_part(root, "Guard", Vector3(0.28, 0.05, 0.07), Vector3(0.0, 0.0, -0.02), dark)
			_part(root, "WrappedHandle", Vector3(0.11, 0.1, 0.38), Vector3(0.0, -0.01, 0.2), wood)
		"scoped_arisaka", "scoped_rifle":
			_long_gun(root, wood, metal, 1.05 if model == "scoped_arisaka" else 0.98, 0.67)
			_cylinder(root, "Scope", 0.045, 0.42, Vector3(0.0, 0.18, -0.16), dark, Vector3(PI * 0.5, 0.0, 0.0))
			_part(root, "ScopeMount", Vector3(0.09, 0.09, 0.04), Vector3(0.0, 0.12, -0.14), metal)
		"hanyang_rifle":
			_long_gun(root, wood, metal, 0.94, 0.58)
			_part(root, "BarrelBand", Vector3(0.13, 0.13, 0.06), Vector3(0.0, 0.02, -0.52), metal)
		_:
			_long_gun(root, wood, metal, 1.05 if model == "arisaka" else 0.98, 0.67)
			if model == "arisaka":
				_part(root, "FrontSight", Vector3(0.035, 0.09, 0.04), Vector3(0.0, 0.09, -0.92), metal)
	root.scale = Vector3.ONE * display_scale

static func get_muzzle_local_z(definition: Dictionary, model_root_z: float) -> float:
	var model := String(definition.get("model", "long_rifle"))
	var tip_from_root: float = float({
		"c96": -0.69,
		"pocket_pistol": -0.58,
		"m1911": -0.62,
		"drum_smg": -0.91,
		"side_mag_smg": -0.8,
		"box_mag_smg": -0.86,
		"pan_lmg": -0.89,
		"top_mag_lmg": -0.88,
		"zb26_lmg": -0.94,
		"shotgun": -0.92,
		"auto5": -0.88,
		"knife": -0.62,
		"infantry_knife": -0.5,
		"dadao": -1.08,
		"arisaka": -0.96,
		"hanyang_rifle": -0.88,
		"scoped_arisaka": -0.96,
		"scoped_rifle": -0.94,
		"long_rifle": -0.94,
	}.get(model, -0.94))
	return model_root_z + tip_from_root

static func _long_gun(root: Node3D, wood: Material, metal: Material, stock_length: float, barrel_length: float) -> void:
	_part(root, "Buttstock", Vector3(0.18, 0.15, stock_length * 0.34), Vector3(0.0, -0.035, 0.38), wood)
	_part(root, "StockWrist", Vector3(0.105, 0.115, stock_length * 0.25), Vector3(0.0, -0.02, 0.16), wood, Vector3(-0.06, 0.0, 0.0))
	_part(root, "Handguard", Vector3(0.105, 0.105, stock_length * 0.42), Vector3(0.0, 0.015, -0.3), wood)
	_part(root, "Receiver", Vector3(0.12, 0.12, 0.28), Vector3(0.0, 0.04, -0.065), metal)
	_part(root, "RearSight", Vector3(0.035, 0.075, 0.045), Vector3(0.0, 0.11, -0.16), metal)
	_cylinder(root, "Barrel", 0.022, barrel_length, Vector3(0.0, 0.045, -0.62), metal, Vector3(PI * 0.5, 0.0, 0.0))

static func _add_bipod(root: Node3D, metal: Material) -> void:
	_part(root, "BipodLeft", Vector3(0.025, 0.38, 0.025), Vector3(-0.14, -0.2, -0.68), metal, Vector3(0.2, 0.0, -0.3))
	_part(root, "BipodRight", Vector3(0.025, 0.38, 0.025), Vector3(0.14, -0.2, -0.68), metal, Vector3(0.2, 0.0, 0.3))

static func _part(root: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	root.add_child(part)
	return part

static func _cylinder(root: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	root.add_child(part)
	return part

static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

static func _color(hex: Variant) -> Color:
	return Color.from_string("#%s" % String(hex), Color.WHITE)
