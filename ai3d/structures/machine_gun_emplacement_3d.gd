extends TacticalStructure3D
class_name MachineGunEmplacement3D

@export var metal_color := Color(0.19, 0.21, 0.17)
@export var earth_color := Color(0.31, 0.25, 0.16)

var _gun_pivot: Node3D
var _fixed_weapon: FixedWeapon3D
var _weapon_feedback: WeaponFeedback3D
var shot_animation_count := 0

func _ready() -> void:
	structure_kind = Kind.MACHINE_GUN
	defense_priority = 92.0
	firing_arc_degrees = 105.0
	vision_multiplier = 1.05
	super._ready()
	_build_visuals()
	_fixed_weapon = get_node_or_null("FixedWeapon3D") as FixedWeapon3D
	_setup_weapon_feedback()

func has_fixed_weapon() -> bool:
	return is_instance_valid(_fixed_weapon)

func get_effective_fire_range() -> float:
	return _fixed_weapon.effective_range if is_instance_valid(_fixed_weapon) else 46.0

func get_firepower_score() -> float:
	return 3.8 if get_user() != null else 0.0

func try_fixed_weapon_fire(actor: Soldier3D, target: Node3D) -> bool:
	if not has_fixed_weapon() or not can_engage_target(target):
		return false
	aim_at(target.global_position)
	var fired := _fixed_weapon.try_fire(actor, target, get_muzzle_position())
	if fired:
		_play_fire_animation(target)
	return fired

func aim_at(target_position: Vector3) -> void:
	if _gun_pivot == null:
		return
	var local_target := to_local(target_position)
	var yaw := atan2(-local_target.x, -local_target.z)
	_gun_pivot.rotation.y = clampf(yaw, -deg_to_rad(firing_arc_degrees * 0.5), deg_to_rad(firing_arc_degrees * 0.5))

func get_recoil_amount() -> float:
	return _weapon_feedback.get_recoil_amount() if is_instance_valid(_weapon_feedback) else 0.0

func is_muzzle_flash_visible() -> bool:
	return _weapon_feedback != null and _weapon_feedback.is_muzzle_flash_visible()

func _build_visuals() -> void:
	_add_box("EarthPad", Vector3(3.4, 0.16, 2.4), Vector3(0.0, 0.08, 0.1), earth_color, false)
	_gun_pivot = Node3D.new()
	_gun_pivot.name = "GunPivot"
	_gun_pivot.position = Vector3(0.0, 1.0, -0.15)
	add_child(_gun_pivot)
	var muzzle_marker := get_node_or_null("Muzzle") as Marker3D
	if muzzle_marker != null:
		muzzle_marker.reparent(_gun_pivot)
		muzzle_marker.position = Vector3(0.0, 0.09, -1.57)
		muzzle_path = ^"GunPivot/Muzzle"
	_add_box_to(_gun_pivot, "Receiver", Vector3(0.24, 0.22, 0.72), Vector3(0.0, 0.08, -0.18), metal_color)
	_add_box_to(_gun_pivot, "Barrel", Vector3(0.09, 0.09, 1.25), Vector3(0.0, 0.09, -1.05), metal_color)
	_add_box_to(_gun_pivot, "Shield", Vector3(0.9, 0.56, 0.08), Vector3(0.0, 0.08, -0.5), Color(0.23, 0.25, 0.19))
	for x in [-0.38, 0.38]:
		_add_box_to(self, "Tripod", Vector3(0.08, 0.75, 0.08), Vector3(x, 0.48, 0.25), metal_color, Vector3(deg_to_rad(22.0), 0.0, deg_to_rad(-18.0 if x < 0.0 else 18.0)))
	var collision := CollisionShape3D.new()
	collision.name = "GunCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.15, 1.25)
	collision.shape = shape
	collision.position = Vector3(0.0, 0.62, -0.42)
	add_child(collision)

func _setup_weapon_feedback() -> void:
	var muzzle_marker := get_node_or_null(muzzle_path) as Marker3D
	if muzzle_marker == null or _gun_pivot == null:
		return
	_weapon_feedback = WeaponFeedback3D.new()
	_weapon_feedback.name = "FixedWeaponFeedback"
	add_child(_weapon_feedback)
	_weapon_feedback.setup(self, _gun_pivot, muzzle_marker, true, true)
	_weapon_feedback.configure({
		"id": "type_92_hmg",
		"family": "lmg",
		"report": "lmg",
		"maximum_range": _fixed_weapon.effective_range if _fixed_weapon != null else 46.0,
		"camera_kick": 1.15,
		"recoil_distance": 0.15,
	}, false)
	var muzzle_flash := muzzle_marker.get_node_or_null("MuzzleFlash") as MeshInstance3D
	if muzzle_flash != null:
		muzzle_flash.scale = Vector3.ONE * 1.45

func _play_fire_animation(target: Node3D) -> void:
	shot_animation_count += 1
	if _weapon_feedback == null:
		return
	var origin := get_muzzle_position()
	var target_point: Vector3 = target.get_aim_point() as Vector3 if target.has_method("get_aim_point") else target.global_position + Vector3.UP
	var direction := (target_point - origin).normalized()
	_weapon_feedback.play_fire(direction, _fixed_weapon.last_hit_result)

func _add_box(name_value: String, size: Vector3, position_value: Vector3, color: Color, collision_enabled := false) -> void:
	_add_box_to(self, name_value, size, position_value, color)
	if collision_enabled:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = position_value
		add_child(collision)

func _add_box_to(parent: Node3D, name_value: String, size: Vector3, position_value: Vector3, color: Color, rotation_value := Vector3.ZERO) -> void:
	var visual := MeshInstance3D.new()
	visual.name = name_value
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.roughness = 0.9
	mesh.material = material
	visual.mesh = mesh
	visual.position = position_value
	visual.rotation = rotation_value
	parent.add_child(visual)
