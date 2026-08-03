extends StaticBody3D
class_name BarbedWire3D

@export_range(1.0, 12.0, 0.5) var wire_length := 5.0
@export var wire_color := Color(0.22, 0.24, 0.23)

func _ready() -> void:
	add_to_group("barbed_wire3d")
	_build_wire()

func _build_wire() -> void:
	var blocking_shape := BoxShape3D.new()
	blocking_shape.size = Vector3(wire_length, 1.25, 0.38)
	var collision := CollisionShape3D.new()
	collision.name = "PersonnelBlocker"
	collision.shape = blocking_shape
	collision.position.y = 0.63
	add_child(collision)
	for x in [-wire_length * 0.5, 0.0, wire_length * 0.5]:
		_add_box(Vector3(0.1, 1.45, 0.1), Vector3(x, 0.72, 0.0), Color(0.26, 0.22, 0.16))
	for y in [0.38, 0.76, 1.12]:
		_add_box(Vector3(wire_length, 0.035, 0.035), Vector3(0.0, y, 0.0), wire_color)
		for index in 12:
			var x := lerpf(-wire_length * 0.48, wire_length * 0.48, float(index) / 11.0)
			_add_box(Vector3(0.025, 0.16, 0.025), Vector3(x, y, 0.0), wire_color, Vector3(0.0, 0.0, deg_to_rad(45.0 if index % 2 == 0 else -45.0)))

func _add_box(size: Vector3, position_value: Vector3, color: Color, rotation_value := Vector3.ZERO) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.metallic = 0.5
	material.roughness = 0.75
	mesh.material = material
	visual.mesh = mesh
	visual.position = position_value
	visual.rotation = rotation_value
	add_child(visual)
