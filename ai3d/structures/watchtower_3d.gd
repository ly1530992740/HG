extends TacticalStructure3D
class_name Watchtower3D

@export var wood_color := Color(0.31, 0.22, 0.13)

func _ready() -> void:
	structure_kind = Kind.WATCHTOWER
	defense_priority = 68.0
	firing_arc_degrees = 360.0
	vision_multiplier = 1.45
	super._ready()
	_build_visuals()

func _build_visuals() -> void:
	for x in [-1.05, 1.05]:
		for z in [-1.05, 1.05]:
			_add_box("Post", Vector3(0.18, 5.8, 0.18), Vector3(x, 2.9, z), true)
	_add_box("Platform", Vector3(2.55, 0.22, 2.55), Vector3(0.0, 3.55, 0.0), true)
	_add_box("Roof", Vector3(3.0, 0.16, 3.0), Vector3(0.0, 5.85, 0.0), true)
	for x in [-1.18, 1.18]:
		_add_box("Rail", Vector3(0.12, 0.95, 2.42), Vector3(x, 4.05, 0.0), true)
	for z in [-1.18, 1.18]:
		_add_box("Rail", Vector3(2.42, 0.95, 0.12), Vector3(0.0, 4.05, z), true)
	for rung in 8:
		_add_box("LadderRung", Vector3(0.9, 0.08, 0.08), Vector3(0.0, 0.45 + float(rung) * 0.42, 1.28), false)
	_add_box("LadderLeft", Vector3(0.08, 3.35, 0.08), Vector3(-0.48, 1.85, 1.28), false)
	_add_box("LadderRight", Vector3(0.08, 3.35, 0.08), Vector3(0.48, 1.85, 1.28), false)

func _add_box(name_value: String, size: Vector3, position_value: Vector3, collision_enabled: bool) -> void:
	var visual := MeshInstance3D.new()
	visual.name = name_value
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = wood_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.roughness = 1.0
	mesh.material = material
	visual.mesh = mesh
	visual.position = position_value
	add_child(visual)
	if collision_enabled:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = position_value
		add_child(collision)
