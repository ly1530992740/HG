extends Node3D
class_name VoxelSoldierVisual3D

enum Faction { JAPANESE, RED_ARMY, BLUE_ALLY }

@export var faction: Faction = Faction.JAPANESE
@export_range(0.5, 1.5, 0.05) var model_scale := 1.0
@export_range(1, 24, 1) var maximum_bullet_wounds := 14

var _rig: Node3D
var _torso: Node3D
var _head: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_forearm: Node3D
var _right_forearm: Node3D
var _left_lower_leg: Node3D
var _right_lower_leg: Node3D
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Dictionary = {}
var _time := 0.0
var _hit_time := 0.0
var _death_blend := 0.0
var _detached: Dictionary = {}
var _bullet_wounds: Array[Node3D] = []
var current_pose_name := "idle"
static var _surface_texture_cache: Dictionary = {}
static var _shoulder_texture_cache: Dictionary = {}
static var _shoulder_animation_cache: Dictionary = {}

const SHOULDER_FRAME_SIZE := Vector2i(240, 336)
const SHOULDER_ANIMATION_FRAMES := {
	"ready": 4,
	"aim": 4,
	"fire": 4,
	"reload": 8,
}

func _ready() -> void:
	rebuild()

func configure(new_faction: Faction) -> void:
	if faction == new_faction and _rig != null:
		return
	faction = new_faction
	rebuild()

func rebuild() -> void:
	if _rig != null:
		_rig.queue_free()
	_materials.clear()
	_base_colors.clear()
	_detached.clear()
	_bullet_wounds.clear()
	_rig = Node3D.new()
	_rig.name = "PixelRig"
	add_child(_rig)
	var palette := _get_palette()
	var uniform := _material(palette.uniform, 0.0, "fabric")
	var uniform_dark := _material(palette.uniform_dark, 0.0, "fabric")
	var skin := _material(palette.skin, 0.0, "skin")
	var leather := _material(Color(0.12, 0.085, 0.055), 0.0, "leather")
	var boot := _material(Color(0.055, 0.058, 0.052), 0.0, "leather")
	var metal := _material(Color(0.11, 0.12, 0.12), 0.48, "metal")

	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0.0, 1.19, 0.0)
	_rig.add_child(_torso)
	_shaped_torso(_torso, "Tunic", uniform)
	_tapered(_torso, "Neck", 0.14, 0.075, 0.085, Vector3(0.0, 0.405, 0.0), skin, 10)
	_box(_torso, "Belt", Vector3(0.41, 0.052, 0.31), Vector3(0.0, -0.205, 0.0), leather)
	_box(_torso, "BeltBuckle", Vector3(0.065, 0.058, 0.025), Vector3(0.0, -0.205, -0.17), metal)
	_box(_torso, "LeftPouch", Vector3(0.105, 0.125, 0.072), Vector3(-0.145, -0.245, -0.17), leather)
	_box(_torso, "RightPouch", Vector3(0.105, 0.125, 0.072), Vector3(0.145, -0.245, -0.17), leather)
	_box(_torso, "LeftPocket", Vector3(0.13, 0.13, 0.024), Vector3(-0.13, 0.01, -0.21), uniform_dark)
	_box(_torso, "RightPocket", Vector3(0.13, 0.13, 0.024), Vector3(0.13, 0.01, -0.21), uniform_dark)
	_box(_torso, "LeftEpaulette", Vector3(0.18, 0.026, 0.11), Vector3(-0.19, 0.31, -0.015), uniform_dark, Vector3(0.0, 0.0, -0.08))
	_box(_torso, "RightEpaulette", Vector3(0.18, 0.026, 0.11), Vector3(0.19, 0.31, -0.015), uniform_dark, Vector3(0.0, 0.0, 0.08))
	_box(_torso, "CollarLeft", Vector3(0.12, 0.075, 0.028), Vector3(-0.075, 0.285, -0.19), uniform_dark, Vector3(0.0, 0.0, -0.28))
	_box(_torso, "CollarRight", Vector3(0.12, 0.075, 0.028), Vector3(0.075, 0.285, -0.19), uniform_dark, Vector3(0.0, 0.0, 0.28))
	_box(_torso, "ShoulderStrap", Vector3(0.038, 0.62, 0.022), Vector3(-0.105, 0.0, 0.19), leather, Vector3(0.0, 0.0, -0.14))
	_box(_torso, "Backpack", Vector3(0.3, 0.39, 0.12), Vector3(0.0, -0.015, 0.195), uniform_dark)
	_box(_torso, "EntrenchingTool", Vector3(0.045, 0.36, 0.04), Vector3(0.2, -0.075, 0.23), metal, Vector3(0.15, 0.0, 0.25))
	for button_y in [-0.1, 0.01, 0.12, 0.23]:
		_ellipsoid(_torso, "Button", Vector3(0.026, 0.026, 0.018), Vector3(0.0, button_y, -0.225), metal, 8)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 1.735, 0.0)
	_rig.add_child(_head)
	_ellipsoid(_head, "Face", Vector3(0.18, 0.235, 0.17), Vector3(0.0, -0.005, -0.015), skin, 12)
	_box(_head, "FaceShadow", Vector3(0.045, 0.12, 0.01), Vector3(0.073, -0.03, -0.112), _material(palette.skin_shadow))
	_ellipsoid(_head, "Hair", Vector3(0.19, 0.07, 0.17), Vector3(0.0, 0.1, 0.005), _material(Color(0.035, 0.031, 0.028), 0.0, "hair"), 12)
	_ellipsoid(_head, "LeftEar", Vector3(0.035, 0.07, 0.035), Vector3(-0.105, -0.005, -0.01), skin, 9)
	_ellipsoid(_head, "RightEar", Vector3(0.035, 0.07, 0.035), Vector3(0.105, -0.005, -0.01), skin, 9)
	var face_detail := _material(Color(0.055, 0.048, 0.042))
	_box(_head, "LeftEye", Vector3(0.022, 0.014, 0.01), Vector3(-0.04, 0.022, -0.108), face_detail)
	_box(_head, "RightEye", Vector3(0.022, 0.014, 0.01), Vector3(0.04, 0.022, -0.108), face_detail)
	_box(_head, "NoseShadow", Vector3(0.022, 0.052, 0.012), Vector3(0.0, -0.02, -0.111), _material(palette.skin_shadow))
	_box(_head, "LeftBrow", Vector3(0.05, 0.012, 0.01), Vector3(-0.04, 0.053, -0.106), face_detail, Vector3(0.0, 0.0, -0.08))
	_box(_head, "RightBrow", Vector3(0.05, 0.012, 0.01), Vector3(0.04, 0.053, -0.106), face_detail, Vector3(0.0, 0.0, 0.08))
	_box(_head, "Mouth", Vector3(0.065, 0.012, 0.01), Vector3(0.0, -0.075, -0.107), _material(Color(0.22, 0.075, 0.055)))
	if faction == Faction.JAPANESE:
		_build_japanese_headgear(_head, uniform_dark)
	else:
		_build_red_army_headgear(_head, uniform_dark)

	_left_arm = _limb("LeftArm", Vector3(-0.27, 1.43, 0.0), uniform, uniform_dark, skin)
	_right_arm = _limb("RightArm", Vector3(0.27, 1.43, 0.0), uniform, uniform_dark, skin)
	_left_leg = _leg("LeftLeg", Vector3(-0.105, 0.84, 0.0), uniform_dark, boot)
	_right_leg = _leg("RightLeg", Vector3(0.105, 0.84, 0.0), uniform_dark, boot)
	_left_forearm = _left_arm.get_node("ForearmPivot") as Node3D
	_right_forearm = _right_arm.get_node("ForearmPivot") as Node3D
	_left_lower_leg = _left_leg.get_node("LowerLegPivot") as Node3D
	_right_lower_leg = _right_leg.get_node("LowerLegPivot") as Node3D
	_rig.scale = Vector3.ONE * model_scale

func update_pose(delta: float, velocity: Vector3, movement_mode: int, stance: int, aimed: bool, firing: bool, dead: bool, weapon_family := "bolt_rifle", blind_fire := false) -> void:
	if _rig == null:
		return
	_time += delta
	_hit_time = maxf(0.0, _hit_time - delta)
	if dead:
		current_pose_name = "death"
		_death_blend = move_toward(_death_blend, 1.0, delta * 2.6)
		_rig.rotation.x = lerpf(0.0, -PI * 0.5, _death_blend)
		_rig.position.y = lerpf(0.0, 0.24, _death_blend)
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := speed > 0.12
	var running := movement_mode == 2 and moving
	var cycle_speed := 10.5 if running else 7.0
	var stride := sin(_time * cycle_speed) * (0.82 if running else 0.48) if moving else 0.0
	_left_leg.rotation.x = stride
	_right_leg.rotation.x = -stride
	_left_lower_leg.rotation = Vector3(maxf(0.0, -stride) * 0.72, 0.0, 0.0)
	_right_lower_leg.rotation = Vector3(maxf(0.0, stride) * 0.72, 0.0, 0.0)
	_left_arm.rotation = Vector3(-stride * 0.5, 0.0, 0.08)
	_right_arm.rotation = Vector3(stride * 0.5, 0.0, -0.08)
	_left_forearm.rotation = Vector3(0.08, 0.0, 0.0)
	_right_forearm.rotation = Vector3(0.08, 0.0, 0.0)
	_torso.position.y = 1.17 + (absf(sin(_time * cycle_speed)) * 0.045 if moving else sin(_time * 1.7) * 0.008)
	_torso.rotation = Vector3.ZERO
	_torso.rotation.z = sin(_time * cycle_speed) * 0.035 if moving else 0.0
	current_pose_name = "run" if running else ("walk" if moving else "idle")
	if weapon_family != "melee" and not aimed:
		_left_arm.rotation = Vector3(0.62, 0.0, 0.42)
		_right_arm.rotation = Vector3(0.72, 0.0, -0.28)
		_left_forearm.rotation = Vector3(0.52, 0.12, 0.0)
		_right_forearm.rotation = Vector3(0.38, -0.08, 0.0)
		current_pose_name = "low_ready_move" if moving else "low_ready"
	if aimed:
		if weapon_family == "pistol":
			_left_arm.rotation = Vector3(1.35, 0.0, 0.72)
			_right_arm.rotation = Vector3(1.42, 0.0, -0.42)
			_left_forearm.rotation = Vector3(0.28, -0.18, 0.0)
			_right_forearm.rotation = Vector3(0.18, 0.12, 0.0)
		elif weapon_family == "melee":
			_left_arm.rotation = Vector3(0.55, 0.0, 0.35)
			_right_arm.rotation = Vector3(-0.4, 0.0, -0.65)
			_left_forearm.rotation = Vector3(0.62, 0.0, 0.0)
			_right_forearm.rotation = Vector3(0.78, 0.0, 0.0)
		else:
			_left_arm.rotation = Vector3(1.18, 0.0, 0.56)
			_right_arm.rotation = Vector3(1.3, 0.0, -0.36)
			_left_forearm.rotation = Vector3(0.64, 0.12, 0.0)
			_right_forearm.rotation = Vector3(0.44, -0.08, 0.0)
		_torso.rotation.y = -0.08
		current_pose_name = "aim"
	if blind_fire:
		_left_arm.rotation = Vector3(2.05, 0.0, 0.48)
		_right_arm.rotation = Vector3(2.18, 0.0, -0.3)
		_left_forearm.rotation = Vector3(0.48, 0.0, 0.0)
		_right_forearm.rotation = Vector3(0.36, 0.0, 0.0)
		_torso.rotation.x = -0.12
		current_pose_name = "cover_blind_fire"
	if firing:
		_right_arm.rotation.x -= 0.22
		_torso.rotation.x = -0.08
		if not blind_fire:
			current_pose_name = "aim_fire" if aimed else "hip_fire"
	var stance_scale_y := 1.0
	var stance_offset_y := 0.0
	if stance == 1:
		stance_scale_y = 0.82
		stance_offset_y = -0.14
		if not blind_fire:
			current_pose_name = "crouch_%s" % current_pose_name
	elif stance == 2:
		stance_scale_y = 1.0
		stance_offset_y = 0.42
		_rig.rotation.x = -PI * 0.5
		_left_arm.rotation = Vector3(2.72, 0.0, 0.45)
		_right_arm.rotation = Vector3(2.8, 0.0, -0.32)
		_left_forearm.rotation = Vector3(0.48, 0.0, 0.0)
		_right_forearm.rotation = Vector3(0.42, 0.0, 0.0)
		current_pose_name = "prone_fire" if firing else ("prone_move" if moving else ("prone_aim" if aimed else "prone_idle"))
	else:
		_rig.rotation.x = 0.0
	_rig.scale = Vector3(model_scale, model_scale * stance_scale_y, model_scale)
	_rig.position.y = stance_offset_y
	if _hit_time <= 0.0:
		_restore_material_colors()

func get_weapon_pivot_pose(weapon_family: String, stance: int, aimed: bool, blind_fire: bool) -> Transform3D:
	var position := Vector3(-0.12, 0.16, -0.48)
	var rotation := Vector3(-0.06, 0.0, 0.0)
	if weapon_family == "pistol":
		position = Vector3(-0.15, 0.18, -0.2)
		rotation = Vector3(-0.02, 0.0, 0.0)
	elif weapon_family == "lmg":
		position = Vector3(-0.12, 0.1, -0.5)
	elif weapon_family == "melee":
		position = Vector3(0.02, -0.08, -0.22)
		rotation = Vector3(-0.25, 0.18, -0.55)
	elif not aimed:
		position = Vector3(-0.1, -0.02, -0.32)
		rotation = Vector3(-0.18, 0.0, 0.0)
	if stance == 1:
		position.y -= 0.22
	if stance == 2:
		position = Vector3(-0.1, -0.68, -0.72)
		rotation = Vector3(0.0, 0.0, 0.0)
	if blind_fire:
		position = Vector3(-0.12, 0.48, -0.46)
		rotation = Vector3(-0.12, 0.0, 0.04)
	return Transform3D(Basis.from_euler(rotation), position)

func get_current_pose_name() -> String:
	return current_pose_name

func play_hit(_location := "body") -> void:
	_hit_time = 0.14
	for material in _materials:
		var base: Color = _base_colors.get(material, material.albedo_color)
		material.albedo_color = base.lerp(Color(0.62, 0.035, 0.018), 0.24)

func play_death() -> void:
	_death_blend = 0.001
	_hit_time = 0.0
	_restore_material_colors()
	if _rig != null:
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_rig, "rotation:x", -PI * 0.5, 0.48)
		tween.tween_property(_rig, "position:y", 0.24, 0.48)

func detach_limb(location: String, impulse_direction: Vector3) -> bool:
	if _detached.get(location, false):
		return false
	var limb := _get_limb(location)
	if limb == null or not is_inside_tree():
		return false
	_detached[location] = true
	limb.visible = false
	_add_severed_stump(location, limb.global_position)
	_spawn_sever_burst(limb.global_position, impulse_direction)
	var detached := RigidBody3D.new()
	detached.name = "Detached_%s" % location
	detached.mass = 1.4 if location == "head" else 2.2
	detached.collision_layer = 0
	detached.collision_mask = 1
	var mesh_instance := MeshInstance3D.new()
	var detached_size := Vector3(0.27, 0.31, 0.24) if location == "head" else Vector3(0.16, 0.55, 0.16)
	if location == "head":
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.135
		head_mesh.height = 0.27
		head_mesh.radial_segments = 8
		head_mesh.rings = 3
		head_mesh.material = _material(_get_palette().skin)
		mesh_instance.mesh = head_mesh
		var headgear := MeshInstance3D.new()
		var headgear_mesh := SphereMesh.new()
		headgear_mesh.radius = 0.17
		headgear_mesh.height = 0.12
		headgear_mesh.radial_segments = 8
		headgear_mesh.rings = 2
		headgear_mesh.material = _material(_get_palette().uniform_dark)
		headgear.mesh = headgear_mesh
		headgear.position.y = 0.13
		detached.add_child(headgear)
	else:
		var limb_mesh := CylinderMesh.new()
		limb_mesh.height = 0.55
		limb_mesh.top_radius = 0.08
		limb_mesh.bottom_radius = 0.065
		limb_mesh.radial_segments = 6
		limb_mesh.material = _material(_get_palette().uniform)
		mesh_instance.mesh = limb_mesh
	detached.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = detached_size
	shape.shape = box_shape
	detached.add_child(shape)
	get_tree().current_scene.add_child(detached)
	detached.global_transform = limb.global_transform
	detached.apply_central_impulse(impulse_direction.normalized() * 3.8 + Vector3.UP * 2.3)
	detached.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 1.6)
	get_tree().create_timer(8.0).timeout.connect(func():
		if is_instance_valid(detached):
			detached.queue_free()
	)
	return true

func _add_severed_stump(location: String, world_position: Vector3) -> void:
	var stump := MeshInstance3D.new()
	stump.name = "SeveredStump_%s" % location
	var mesh := SphereMesh.new()
	mesh.radius = 0.085 if location != "head" else 0.105
	mesh.height = 0.055
	mesh.radial_segments = 8
	mesh.rings = 2
	mesh.material = _wound_material(Color(0.31, 0.012, 0.008))
	stump.mesh = mesh
	_rig.add_child(stump)
	stump.global_position = world_position

func _spawn_sever_burst(world_position: Vector3, direction: Vector3) -> void:
	if get_tree().current_scene == null:
		return
	var particles := GPUParticles3D.new()
	particles.name = "SeverBurst"
	particles.amount = 20
	particles.lifetime = 0.48
	particles.one_shot = true
	particles.explosiveness = 1.0
	var particle_mesh := BoxMesh.new()
	particle_mesh.size = Vector3(0.045, 0.045, 0.045)
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.albedo_color = Color(0.38, 0.012, 0.008)
	particle_mesh.material = particle_material
	particles.draw_pass_1 = particle_mesh
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = (direction.normalized() + Vector3.UP * 0.28).normalized() if not direction.is_zero_approx() else Vector3.UP
	process_material.spread = 62.0
	process_material.initial_velocity_min = 2.5
	process_material.initial_velocity_max = 5.2
	process_material.gravity = Vector3(0.0, -9.8, 0.0)
	particles.process_material = process_material
	get_tree().current_scene.add_child(particles)
	particles.global_position = world_position
	particles.emitting = true
	get_tree().create_timer(0.9).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func add_bullet_wound(hit_position: Vector3, impact_normal: Vector3, location := "body") -> Node3D:
	if _rig == null or not is_inside_tree():
		return null
	while _bullet_wounds.size() >= maximum_bullet_wounds:
		var oldest: Node3D = _bullet_wounds.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var target_part := _torso if location == "body" else _get_limb(location)
	if target_part == null or bool(_detached.get(location, false)):
		target_part = _torso
	var normal := impact_normal.normalized()
	if normal.is_zero_approx():
		normal = (hit_position - global_position - Vector3.UP).normalized()
	if normal.is_zero_approx():
		normal = Vector3.BACK
	var wound := Node3D.new()
	wound.name = "BulletWound_%02d" % _bullet_wounds.size()
	target_part.add_child(wound)
	wound.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), hit_position + normal * 0.012)
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.052
	rim_mesh.bottom_radius = 0.052
	rim_mesh.height = 0.009
	rim_mesh.radial_segments = 8
	rim_mesh.material = _wound_material(Color(0.035, 0.025, 0.022))
	rim.mesh = rim_mesh
	wound.add_child(rim)
	var center := MeshInstance3D.new()
	var center_mesh := CylinderMesh.new()
	center_mesh.top_radius = 0.029
	center_mesh.bottom_radius = 0.029
	center_mesh.height = 0.013
	center_mesh.radial_segments = 7
	center_mesh.material = _wound_material(Color(0.22, 0.018, 0.012))
	center.mesh = center_mesh
	center.position.y = 0.006
	wound.add_child(center)
	_bullet_wounds.append(wound)
	return wound

func get_bullet_wound_count() -> int:
	var valid_count := 0
	for wound in _bullet_wounds:
		if is_instance_valid(wound) and not wound.is_queued_for_deletion():
			valid_count += 1
	return valid_count

func is_limb_detached(location: String) -> bool:
	return bool(_detached.get(location, false))

func _get_limb(location: String) -> Node3D:
	match location:
		"head": return _head
		"left_arm": return _left_arm
		"right_arm": return _right_arm
		"left_leg": return _left_leg
		"right_leg": return _right_leg
	return null

func _limb(limb_name: String, position: Vector3, uniform: Material, uniform_dark: Material, skin: Material) -> Node3D:
	var limb := Node3D.new()
	limb.name = limb_name
	limb.position = position
	_rig.add_child(limb)
	_ellipsoid(limb, "ShoulderCap", Vector3(0.135, 0.145, 0.145), Vector3(0.0, -0.015, 0.0), uniform, 12)
	_tapered(limb, "UpperSleeve", 0.31, 0.088, 0.066, Vector3(0.0, -0.16, 0.0), uniform, 12)
	_ellipsoid(limb, "Elbow", Vector3(0.085, 0.085, 0.09), Vector3(0.0, -0.325, 0.0), uniform_dark, 12)
	var forearm := Node3D.new()
	forearm.name = "ForearmPivot"
	forearm.position = Vector3(0.0, -0.325, 0.0)
	limb.add_child(forearm)
	_tapered(forearm, "LowerSleeve", 0.3, 0.074, 0.052, Vector3(0.0, -0.16, 0.0), uniform, 12)
	_ellipsoid(forearm, "Wrist", Vector3(0.06, 0.065, 0.065), Vector3(0.0, -0.315, 0.0), uniform_dark, 10)
	_ellipsoid(forearm, "Hand", Vector3(0.068, 0.1, 0.074), Vector3(0.0, -0.37, -0.01), skin, 12)
	return limb

func _leg(limb_name: String, position: Vector3, uniform: Material, boot: Material) -> Node3D:
	var limb := Node3D.new()
	limb.name = limb_name
	limb.position = position
	_rig.add_child(limb)
	_ellipsoid(limb, "Hip", Vector3(0.13, 0.135, 0.14), Vector3(0.0, -0.02, 0.0), uniform, 12)
	_tapered(limb, "UpperTrouser", 0.39, 0.105, 0.078, Vector3(0.0, -0.19, 0.0), uniform, 12)
	_ellipsoid(limb, "Knee", Vector3(0.095, 0.1, 0.1), Vector3(0.0, -0.405, -0.005), uniform, 12)
	var lower_leg := Node3D.new()
	lower_leg.name = "LowerLegPivot"
	lower_leg.position = Vector3(0.0, -0.405, 0.0)
	limb.add_child(lower_leg)
	_tapered(lower_leg, "LowerTrouser", 0.34, 0.084, 0.06, Vector3(0.0, -0.18, 0.0), uniform, 12)
	_ellipsoid(lower_leg, "Ankle", Vector3(0.074, 0.09, 0.08), Vector3(0.0, -0.36, 0.0), boot, 10)
	_ellipsoid(lower_leg, "Boot", Vector3(0.115, 0.17, 0.21), Vector3(0.0, -0.415, -0.055), boot, 12)
	return limb

func _shaped_torso(parent: Node3D, part_name: String, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var rings := [
		Vector3(0.18, -0.42, 0.115),
		Vector3(0.205, -0.25, 0.13),
		Vector3(0.195, -0.08, 0.125),
		Vector3(0.25, 0.12, 0.15),
		Vector3(0.29, 0.285, 0.16),
		Vector3(0.17, 0.36, 0.115),
	]
	var segments := 12
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for ring_index in range(rings.size() - 1):
		var lower: Vector3 = rings[ring_index]
		var upper: Vector3 = rings[ring_index + 1]
		for segment in segments:
			var next_segment := (segment + 1) % segments
			var angle_a := TAU * float(segment) / float(segments)
			var angle_b := TAU * float(next_segment) / float(segments)
			var lower_a := Vector3(cos(angle_a) * lower.x, lower.y, sin(angle_a) * lower.z)
			var lower_b := Vector3(cos(angle_b) * lower.x, lower.y, sin(angle_b) * lower.z)
			var upper_a := Vector3(cos(angle_a) * upper.x, upper.y, sin(angle_a) * upper.z)
			var upper_b := Vector3(cos(angle_b) * upper.x, upper.y, sin(angle_b) * upper.z)
			var u_a := float(segment) / float(segments)
			var u_b := float(segment + 1) / float(segments)
			var v_a := float(ring_index) / float(rings.size() - 1)
			var v_b := float(ring_index + 1) / float(rings.size() - 1)
			_add_surface_vertex(surface, lower_a, Vector2(u_a, v_a))
			_add_surface_vertex(surface, upper_a, Vector2(u_a, v_b))
			_add_surface_vertex(surface, upper_b, Vector2(u_b, v_b))
			_add_surface_vertex(surface, lower_a, Vector2(u_a, v_a))
			_add_surface_vertex(surface, upper_b, Vector2(u_b, v_b))
			_add_surface_vertex(surface, lower_b, Vector2(u_b, v_a))
	surface.generate_normals()
	part.mesh = surface.commit()
	parent.add_child(part)
	return part

func _add_surface_vertex(surface: SurfaceTool, vertex: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(vertex)

func _build_japanese_headgear(parent: Node3D, cloth: Material) -> void:
	var helmet := MeshInstance3D.new()
	helmet.name = "Type90Helmet"
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.18
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = cloth
	helmet.mesh = mesh
	helmet.position = Vector3(0.0, 0.155, 0.0)
	parent.add_child(helmet)
	_tapered(parent, "HelmetRim", 0.035, 0.18, 0.175, Vector3(0.0, 0.13, 0.0), cloth, 12)
	_box(parent, "NeckFlapBack", Vector3(0.16, 0.15, 0.025), Vector3(0.0, 0.015, 0.115), cloth)
	_box(parent, "NeckFlapLeft", Vector3(0.025, 0.135, 0.105), Vector3(-0.112, 0.005, 0.055), cloth)
	_box(parent, "NeckFlapRight", Vector3(0.025, 0.135, 0.105), Vector3(0.112, 0.005, 0.055), cloth)
	_box(parent, "HelmetChinStrap", Vector3(0.012, 0.2, 0.012), Vector3(0.092, -0.045, -0.09), _material(Color(0.075, 0.055, 0.04)), Vector3(0.0, 0.0, -0.18))

func _build_red_army_headgear(parent: Node3D, cloth: Material) -> void:
	_tapered(parent, "Pilotka", 0.13, 0.125, 0.145, Vector3(0.0, 0.16, 0.005), cloth, 10)
	_box(parent, "CapFold", Vector3(0.2, 0.035, 0.018), Vector3(0.0, 0.18, -0.115), cloth)
	_box(parent, "RedStar", Vector3(0.045, 0.045, 0.015), Vector3(0.0, 0.18, -0.13), _material(Color(0.5, 0.025, 0.02)))

func _box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	parent.add_child(part)
	return part

func _tapered(parent: Node3D, part_name: String, height: float, top_radius: float, bottom_radius: float, position: Vector3, material: Material, segments := 6) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material
	part.mesh = mesh
	part.position = position
	parent.add_child(part)
	return part

func _ellipsoid(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material, segments := 8) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = maxi(2, segments / 2)
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.scale = size
	parent.add_child(part)
	return part

func _material(color: Color, metallic := 0.0, surface_style := "solid") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.48 if surface_style == "metal" else (0.7 if surface_style == "leather" else 0.86)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if surface_style != "solid":
		material.albedo_texture = _get_surface_texture(surface_style)
	if surface_style in ["fabric", "skin", "leather"]:
		material.emission_enabled = true
		material.emission = color.darkened(0.6)
		material.emission_energy_multiplier = 0.16
	_materials.append(material)
	_base_colors[material] = color
	return material

static func _get_surface_texture(surface_style: String) -> Texture2D:
	if _surface_texture_cache.has(surface_style):
		return _surface_texture_cache[surface_style]
	var image := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var noise := float(posmod(x * 37 + y * 59 + x * y * 11, 101)) / 100.0 - 0.5
			var value := 1.0
			match surface_style:
				"fabric":
					var weave := 0.025 if x % 4 == 0 else (-0.02 if y % 4 == 0 else 0.0)
					value = 0.94 + weave + noise * 0.055
				"skin":
					value = 0.98 + noise * 0.035
					if posmod(x * 13 + y * 29, 211) == 0:
						value -= 0.09
				"leather":
					value = 0.9 + sin(float(x * 3 + y * 7) * 0.13) * 0.035 + noise * 0.065
				"hair":
					value = 0.78 + float(posmod(x + y * 3, 9)) * 0.018 + noise * 0.04
				"metal":
					value = 0.82 + noise * 0.08
					if posmod(x * 5 + y * 17, 173) == 0:
						value = 1.08
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_surface_texture_cache[surface_style] = texture
	return texture

func _wound_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

func _restore_material_colors() -> void:
	for material in _materials:
		material.albedo_color = _base_colors.get(material, material.albedo_color)

func _get_palette() -> Dictionary:
	match faction:
		Faction.RED_ARMY:
			return {"uniform": Color("686e58"), "uniform_dark": Color("3f493f"), "skin": Color("ad8065"), "skin_shadow": Color("674a3e")}
		Faction.BLUE_ALLY:
			return {"uniform": Color("596c67"), "uniform_dark": Color("374542"), "skin": Color("ad8065"), "skin_shadow": Color("674a3e")}
		_:
			return {"uniform": Color("756e4e"), "uniform_dark": Color("484a39"), "skin": Color("aa7b60"), "skin_shadow": Color("65483c")}

static func create_red_army_shoulder_texture(weapon_definition := {}) -> Texture2D:
	return create_red_army_shoulder_animation_set(weapon_definition).get("ready") as Texture2D

static func create_red_army_shoulder_animation_set(weapon_definition := {}) -> Dictionary:
	var cache_key := "%s|%s|%s|%s" % [
		String(weapon_definition.get("family", "bolt_rifle")),
		String(weapon_definition.get("model", "long_rifle")),
		String(weapon_definition.get("wood_color", "70452b")),
		String(weapon_definition.get("metal_color", "24282b")),
	]
	if _shoulder_animation_cache.has(cache_key):
		return _shoulder_animation_cache[cache_key]
	var animation_set := {}
	for state in SHOULDER_ANIMATION_FRAMES:
		var frame_count: int = SHOULDER_ANIMATION_FRAMES[state]
		var strip := Image.create(SHOULDER_FRAME_SIZE.x * frame_count, SHOULDER_FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
		strip.fill(Color(0, 0, 0, 0))
		for frame_index in frame_count:
			var frame := Image.create(SHOULDER_FRAME_SIZE.x, SHOULDER_FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
			frame.fill(Color(0, 0, 0, 0))
			var phase := float(frame_index) / float(maxi(1, frame_count - 1))
			_draw_animated_shoulder_frame(frame, weapon_definition, state, phase)
			_add_shoulder_surface_detail(frame)
			strip.blit_rect(frame, Rect2i(Vector2i.ZERO, SHOULDER_FRAME_SIZE), Vector2i(frame_index * SHOULDER_FRAME_SIZE.x, 0))
		animation_set[state] = ImageTexture.create_from_image(strip)
	_shoulder_animation_cache[cache_key] = animation_set
	_shoulder_texture_cache[cache_key] = animation_set["ready"]
	return animation_set

static func _draw_animated_shoulder_frame(image: Image, weapon_definition: Dictionary, state: String, phase: float) -> void:
	var family := String(weapon_definition.get("family", "bolt_rifle"))
	var breath := sin(phase * TAU)
	var vertical_offset := breath * (1.0 if state in ["ready", "aim"] else 0.0)
	var points := _get_shoulder_weapon_points(state, phase, family)
	var muzzle_point := points.muzzle as Vector2
	var grip := points.grip as Vector2
	var support := points.support as Vector2

	var outline := Color("0b0e0d")
	var coat_shadow := Color("202722")
	var coat_dark := Color("333d35")
	var coat := Color("555f50")
	var coat_light := Color("6b7460")
	var leather := Color("211914")
	var skin_shadow := Color("6a4637")
	var skin := Color("a8755c")

	# Far arm first. The torso below occludes it, so it cannot appear through the soldier's back.
	var far_shoulder := Vector2(126, 120 + vertical_offset)
	var far_elbow := Vector2(157, 161 + vertical_offset)
	if state == "reload":
		far_elbow = Vector2(151, 178)
	_draw_thick_line(image, far_shoulder, far_elbow, 31.0, outline)
	_draw_thick_line(image, far_shoulder, far_elbow, 20.0, coat_dark)
	_draw_thick_line(image, far_elbow, grip, 24.0, outline)
	_draw_thick_line(image, far_elbow, grip, 14.0, coat_shadow)

	# Asymmetric back and near shoulder create a rear three-quarter silhouette instead of a frontal paper doll.
	_fill_polygon(image, PackedVector2Array([
		Vector2(-22, 139 + vertical_offset), Vector2(18, 111 + vertical_offset),
		Vector2(67, 95 + vertical_offset), Vector2(116, 105 + vertical_offset),
		Vector2(154, 137 + vertical_offset), Vector2(146, 336), Vector2(-22, 336),
	]), outline)
	_fill_polygon(image, PackedVector2Array([
		Vector2(-14, 143 + vertical_offset), Vector2(23, 119 + vertical_offset),
		Vector2(66, 104 + vertical_offset), Vector2(108, 113 + vertical_offset),
		Vector2(143, 141 + vertical_offset), Vector2(136, 336), Vector2(-14, 336),
	]), coat_dark)
	_fill_polygon(image, PackedVector2Array([
		Vector2(-12, 145 + vertical_offset), Vector2(25, 121 + vertical_offset),
		Vector2(56, 108 + vertical_offset), Vector2(49, 336), Vector2(-12, 336),
	]), coat)
	_fill_polygon(image, PackedVector2Array([
		Vector2(20, 121 + vertical_offset), Vector2(46, 110 + vertical_offset),
		Vector2(42, 224), Vector2(8, 232),
	]), coat_light)
	_draw_thick_line(image, Vector2(21, 118 + vertical_offset), Vector2(111, 335), 12.0, outline)
	_draw_thick_line(image, Vector2(23, 120 + vertical_offset), Vector2(111, 335), 6.0, leather)
	_draw_thick_line(image, Vector2(-4, 252), Vector2(138, 252), 12.0, outline)
	_draw_thick_line(image, Vector2(-4, 251), Vector2(138, 251), 6.0, leather)

	var head_center := Vector2(74 if state in ["aim", "fire"] else 66, 65 + vertical_offset)
	_fill_polygon(image, PackedVector2Array([
		head_center + Vector2(-27, 26), head_center + Vector2(-8, 48),
		head_center + Vector2(18, 45), head_center + Vector2(31, 24),
	]), outline)
	_fill_polygon(image, PackedVector2Array([
		head_center + Vector2(-20, 25), head_center + Vector2(-5, 39),
		head_center + Vector2(13, 37), head_center + Vector2(23, 23),
	]), coat_shadow)
	_fill_ellipse(image, head_center + Vector2(17, 18), Vector2(14, 20), outline)
	_fill_ellipse(image, head_center + Vector2(18, 18), Vector2(9, 15), skin_shadow)
	_fill_ellipse(image, head_center, Vector2(35, 38), outline)
	_fill_ellipse(image, head_center + Vector2(1, -2), Vector2(29, 31), coat_shadow)
	_fill_ellipse(image, head_center + Vector2(0, -20), Vector2(43, 17), outline)
	_fill_ellipse(image, head_center + Vector2(0, -22), Vector2(37, 12), coat_dark)
	_fill_polygon(image, PackedVector2Array([
		head_center + Vector2(-42, -18), head_center + Vector2(42, -18),
		head_center + Vector2(49, -11), head_center + Vector2(-50, -11),
	]), outline)
	_fill_polygon(image, PackedVector2Array([
		 head_center + Vector2(-38, -17), head_center + Vector2(39, -17),
		 head_center + Vector2(44, -13), head_center + Vector2(-45, -13),
	]), coat_dark)
	_draw_thick_line(image, head_center + Vector2(19, -6), head_center + Vector2(25, 29), 3.0, leather)

	# The near sleeve crosses the chest, while the weapon remains visibly in front of the sleeve.
	var near_shoulder := Vector2(15, 143 + vertical_offset)
	var near_elbow := Vector2(23, 206 + vertical_offset)
	if state in ["aim", "fire"]:
		near_elbow = Vector2(48, 188 + vertical_offset)
	elif state == "reload":
		near_elbow = Vector2(59, 218)
	_draw_thick_line(image, near_shoulder, near_elbow, 38.0, outline)
	_draw_thick_line(image, near_shoulder, near_elbow, 25.0, coat_shadow)
	_draw_thick_line(image, near_elbow, support, 24.0, outline)
	_draw_thick_line(image, near_elbow, support, 13.0, coat)
	_draw_animated_shoulder_weapon(image, weapon_definition, state, phase, points)
	_fill_ellipse(image, grip, Vector2(9, 8), skin_shadow)
	_fill_ellipse(image, grip + Vector2(1, -2), Vector2(6, 5), skin)
	_fill_ellipse(image, support, Vector2(9, 8), skin_shadow)
	_fill_ellipse(image, support + Vector2(1, -2), Vector2(6, 5), skin)

	_draw_thick_line(image, Vector2(75, 109), Vector2(82, 335), 3.0, coat_shadow)
	_draw_thick_line(image, Vector2(119, 126), Vector2(128, 335), 2.0, coat_light.darkened(0.25))
	# A dark foreground shoulder edge reinforces that the camera is behind the actor.
	_fill_polygon(image, PackedVector2Array([
		Vector2(-18, 183), Vector2(13, 151), Vector2(33, 219), Vector2(24, 336), Vector2(-18, 336),
	]), Color("121714"))
	if state == "fire" and phase < 0.68 and family != "melee":
		var flash_size := 15.0 * (1.0 - phase * 0.6)
		_fill_polygon(image, PackedVector2Array([
			muzzle_point + Vector2(-2, -flash_size), muzzle_point + Vector2(flash_size * 1.7, 0),
			muzzle_point + Vector2(-2, flash_size), muzzle_point + Vector2(3, 0),
		]), Color("f6c34a"))
		_fill_ellipse(image, muzzle_point, Vector2(5, 5), Color("fff2b2"))

static func _get_shoulder_weapon_points(state: String, phase: float, family: String) -> Dictionary:
	var stock := Vector2(38, 204)
	var receiver := Vector2(129, 171)
	var muzzle_point := Vector2(247, 128)
	var grip := Vector2(139, 179)
	var support := Vector2(182, 151)
	if state == "aim" or state == "fire":
		stock = Vector2(73, 169)
		receiver = Vector2(143, 141)
		muzzle_point = Vector2(252, 104)
		grip = Vector2(148, 153)
		support = Vector2(187, 126)
	if state == "fire":
		var recoil := sin(phase * PI)
		stock += Vector2(-recoil * 7.0, recoil * 2.0)
		receiver += Vector2(-recoil * 8.0, -recoil * 3.0)
		muzzle_point += Vector2(-recoil * 9.0, -recoil * 8.0)
		grip += Vector2(-recoil * 7.0, -recoil * 2.0)
		support += Vector2(-recoil * 8.0, -recoil * 4.0)
	elif state == "reload":
		stock = Vector2(49, 203)
		receiver = Vector2(135, 176)
		muzzle_point = Vector2(246, 154)
		grip = Vector2(143, 188)
		var hand_action := sin(phase * PI)
		if family in ["smg", "lmg"]:
			support = Vector2(154, 196).lerp(Vector2(141, 222), hand_action)
		else:
			support = Vector2(169, 164).lerp(Vector2(147, 157), hand_action)
	if family == "pistol":
		stock = Vector2(130, 174)
		receiver = Vector2(177, 145)
		muzzle_point = Vector2(236, 125)
		grip = Vector2(160, 172)
		support = Vector2(174, 161)
		if state == "reload":
			receiver = Vector2(171, 163)
			muzzle_point = Vector2(226, 151)
			grip = Vector2(158, 184)
			support = Vector2(150, 207).lerp(Vector2(164, 181), phase)
	elif family == "melee":
		stock = Vector2(105, 205)
		receiver = Vector2(153, 157)
		muzzle_point = Vector2(224, 72)
		grip = Vector2(145, 165)
		support = Vector2(121, 189)
	return {"stock": stock, "receiver": receiver, "muzzle": muzzle_point, "grip": grip, "support": support}

static func _draw_animated_shoulder_weapon(image: Image, weapon_definition: Dictionary, state: String, phase: float, points: Dictionary) -> void:
	var family := String(weapon_definition.get("family", "bolt_rifle"))
	var model := String(weapon_definition.get("model", "long_rifle"))
	var wood := Color.from_string("#%s" % String(weapon_definition.get("wood_color", "70452b")), Color("70452b"))
	var metal := Color.from_string("#%s" % String(weapon_definition.get("metal_color", "24282b")), Color("24282b"))
	var outline := Color("090c0c")
	var stock := points.stock as Vector2
	var receiver := points.receiver as Vector2
	var muzzle_point := points.muzzle as Vector2
	if family == "pistol":
		_draw_thick_line(image, receiver, muzzle_point, 16.0, outline)
		_draw_thick_line(image, receiver + Vector2(2, -1), muzzle_point, 8.0, metal)
		_draw_thick_line(image, receiver, stock + Vector2(8, 26), 13.0, outline)
		_draw_thick_line(image, receiver, stock + Vector2(8, 26), 7.0, wood)
	elif family == "melee":
		_draw_thick_line(image, stock, receiver, 16.0, outline)
		_draw_thick_line(image, stock, receiver, 9.0, wood)
		_draw_thick_line(image, receiver, muzzle_point, 19.0 if model == "dadao" else 10.0, outline)
		_draw_thick_line(image, receiver, muzzle_point, 11.0 if model == "dadao" else 5.0, metal)
	else:
		_draw_thick_line(image, stock, receiver, 26.0, outline)
		_draw_thick_line(image, stock + Vector2(3, -1), receiver, 16.0, wood)
		_draw_thick_line(image, receiver, muzzle_point, 12.0, outline)
		_draw_thick_line(image, receiver, muzzle_point, 6.0, metal)
		_fill_ellipse(image, receiver, Vector2(16, 11), outline)
		_fill_ellipse(image, receiver, Vector2(11, 7), metal)
		if family == "smg":
			if model == "drum_smg":
				_fill_ellipse(image, receiver + Vector2(5, 18), Vector2(21, 20), outline)
				_fill_ellipse(image, receiver + Vector2(5, 18), Vector2(15, 14), metal)
			else:
				_draw_thick_line(image, receiver + Vector2(2, 5), receiver + Vector2(6, 37), 15.0, metal)
		elif family == "lmg":
			if model == "pan_lmg":
				_fill_ellipse(image, receiver + Vector2(-3, -12), Vector2(28, 9), outline)
				_fill_ellipse(image, receiver + Vector2(-3, -13), Vector2(21, 5), metal)
			else:
				_fill_polygon(image, PackedVector2Array([receiver + Vector2(-8, -20), receiver + Vector2(12, -23), receiver + Vector2(14, 4), receiver + Vector2(-7, 5)]), metal)
		elif family == "sniper_rifle":
			_draw_thick_line(image, receiver + Vector2(-6, -14), receiver.lerp(muzzle_point, 0.36) + Vector2(0, -14), 9.0, outline)
			_draw_thick_line(image, receiver + Vector2(-4, -14), receiver.lerp(muzzle_point, 0.35) + Vector2(0, -14), 4.0, metal.lightened(0.18))
		if state == "reload":
			var reload_hand := points.support as Vector2
			if family in ["smg", "lmg"]:
				_fill_polygon(image, PackedVector2Array([reload_hand + Vector2(-8, -20), reload_hand + Vector2(9, -20), reload_hand + Vector2(7, 17), reload_hand + Vector2(-9, 17)]), metal)
			else:
				_fill_rect(image, Rect2i(Vector2i(int(reload_hand.x - 5), int(reload_hand.y - 14)), Vector2i(10, 21)), Color("b49b63"))

static func _draw_shoulder_body(image: Image) -> void:
	var outline := Color("111513")
	var coat_dark := Color("343c34")
	var coat := Color("626852")
	var coat_light := Color("7b7f62")
	var leather := Color("211a14")
	var skin_dark := Color("704d3e")
	var skin := Color("b48265")
	# Long coat tails and tapered torso establish an adult silhouette before equipment is layered on top.
	_fill_polygon(image, PackedVector2Array([Vector2(64, 207), Vector2(112, 207), Vector2(108, 335), Vector2(53, 335)]), outline)
	_fill_polygon(image, PackedVector2Array([Vector2(70, 214), Vector2(108, 214), Vector2(103, 331), Vector2(61, 331)]), coat)
	_fill_polygon(image, PackedVector2Array([Vector2(111, 207), Vector2(158, 207), Vector2(174, 335), Vector2(116, 335)]), outline)
	_fill_polygon(image, PackedVector2Array([Vector2(117, 214), Vector2(153, 214), Vector2(165, 331), Vector2(121, 331)]), coat_dark)
	_fill_polygon(image, PackedVector2Array([Vector2(43, 101), Vector2(72, 82), Vector2(132, 82), Vector2(176, 104), Vector2(164, 225), Vector2(50, 225)]), outline)
	_fill_polygon(image, PackedVector2Array([Vector2(51, 105), Vector2(75, 91), Vector2(129, 91), Vector2(167, 108), Vector2(156, 216), Vector2(58, 216)]), coat)
	_fill_polygon(image, PackedVector2Array([Vector2(55, 111), Vector2(76, 96), Vector2(90, 216), Vector2(61, 216)]), coat_light)
	_fill_polygon(image, PackedVector2Array([Vector2(133, 94), Vector2(165, 109), Vector2(155, 216), Vector2(137, 216)]), coat_dark)
	# Back of the head, neck and field cap use rounded high-resolution shapes rather than square pixels.
	_fill_ellipse(image, Vector2(104, 72), Vector2(18, 20), outline)
	_fill_ellipse(image, Vector2(104, 72), Vector2(12, 16), skin_dark)
	_fill_ellipse(image, Vector2(104, 69), Vector2(10, 12), skin)
	_fill_ellipse(image, Vector2(104, 46), Vector2(31, 32), Color("242824"))
	_fill_ellipse(image, Vector2(104, 30), Vector2(42, 19), outline)
	_fill_ellipse(image, Vector2(104, 27), Vector2(36, 14), coat_dark)
	_fill_polygon(image, PackedVector2Array([Vector2(63, 35), Vector2(145, 35), Vector2(155, 43), Vector2(54, 43)]), outline)
	_fill_polygon(image, PackedVector2Array([Vector2(66, 36), Vector2(142, 36), Vector2(148, 40), Vector2(60, 40)]), coat_dark)
	# Collar, belt, shoulder strap and seams add scale cues at close range.
	_fill_polygon(image, PackedVector2Array([Vector2(76, 91), Vector2(101, 112), Vector2(91, 128), Vector2(66, 99)]), coat_dark)
	_fill_polygon(image, PackedVector2Array([Vector2(129, 91), Vector2(105, 112), Vector2(116, 128), Vector2(143, 98)]), coat_dark)
	_draw_thick_line(image, Vector2(84, 94), Vector2(130, 215), 10.0, leather)
	_draw_thick_line(image, Vector2(58, 190), Vector2(157, 190), 13.0, outline)
	_draw_thick_line(image, Vector2(61, 190), Vector2(154, 190), 7.0, leather)
	_draw_thick_line(image, Vector2(103, 115), Vector2(104, 213), 4.0, coat_dark)
	_draw_thick_line(image, Vector2(75, 139), Vector2(92, 137), 3.0, coat_dark)
	_draw_thick_line(image, Vector2(127, 137), Vector2(145, 139), 3.0, coat_dark)
	# Bent sleeves frame the weapon while keeping the center of the screen clear.
	_draw_thick_line(image, Vector2(55, 113), Vector2(43, 202), 31.0, outline)
	_draw_thick_line(image, Vector2(55, 116), Vector2(47, 199), 21.0, coat_dark)
	_draw_thick_line(image, Vector2(160, 112), Vector2(179, 160), 31.0, outline)
	_draw_thick_line(image, Vector2(158, 115), Vector2(174, 158), 21.0, coat)
	_draw_thick_line(image, Vector2(174, 158), Vector2(150, 182), 25.0, outline)
	_draw_thick_line(image, Vector2(171, 160), Vector2(151, 179), 16.0, coat_dark)
	_fill_ellipse(image, Vector2(151, 181), Vector2(11, 10), skin_dark)
	_fill_ellipse(image, Vector2(151, 178), Vector2(8, 7), skin)
	_fill_ellipse(image, Vector2(177, 157), Vector2(10, 10), skin_dark)
	_fill_ellipse(image, Vector2(177, 154), Vector2(7, 7), skin)

static func _add_shoulder_surface_detail(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a < 0.98:
				continue
			var luminance := color.get_luminance()
			if luminance < 0.07 or luminance > 0.72:
				continue
			var grain := (float(posmod(x * 17 + y * 31 + x * y * 3, 37)) / 36.0 - 0.5) * 0.028
			image.set_pixel(x, y, Color(
				clampf(color.r + grain, 0.0, 1.0),
				clampf(color.g + grain, 0.0, 1.0),
				clampf(color.b + grain, 0.0, 1.0),
				color.a
			))

static func _draw_shoulder_weapon(image: Image, weapon_definition: Dictionary) -> void:
	var family := String(weapon_definition.get("family", "bolt_rifle"))
	var model := String(weapon_definition.get("model", "long_rifle"))
	var wood := Color.from_string("#%s" % String(weapon_definition.get("wood_color", "70452b")), Color("70452b"))
	var metal := Color.from_string("#%s" % String(weapon_definition.get("metal_color", "24282b")), Color("24282b"))
	var outline := Color("0d1111")
	if family == "pistol":
		_draw_thick_line(image, Vector2(166, 158), Vector2(223, 143), 15.0, outline)
		_draw_thick_line(image, Vector2(169, 157), Vector2(222, 144), 8.0, metal)
		_draw_thick_line(image, Vector2(169, 158), Vector2(162, 184), 11.0, wood)
		return
	if family == "melee":
		if model == "dadao":
			_draw_thick_line(image, Vector2(151, 181), Vector2(181, 137), 13.0, wood)
			_draw_thick_line(image, Vector2(181, 137), Vector2(221, 64), 20.0, outline)
			_draw_thick_line(image, Vector2(184, 135), Vector2(222, 65), 12.0, metal)
			_fill_polygon(image, PackedVector2Array([Vector2(213, 70), Vector2(229, 52), Vector2(237, 72), Vector2(220, 80)]), metal)
		else:
			_draw_thick_line(image, Vector2(151, 181), Vector2(183, 137), 12.0, wood)
			_draw_thick_line(image, Vector2(183, 137), Vector2(220, 91), 8.0, metal)
		return
	_draw_thick_line(image, Vector2(70, 204), Vector2(139, 178), 24.0, outline)
	_draw_thick_line(image, Vector2(74, 201), Vector2(140, 177), 15.0, wood)
	_draw_thick_line(image, Vector2(137, 178), Vector2(178, 163), 18.0, outline)
	_draw_thick_line(image, Vector2(141, 176), Vector2(178, 163), 11.0, metal)
	_draw_thick_line(image, Vector2(176, 163), Vector2(237, 139), 9.0, outline)
	_draw_thick_line(image, Vector2(178, 162), Vector2(237, 139), 4.0, metal)
	if family == "smg":
		_draw_thick_line(image, Vector2(151, 179), Vector2(155, 213), 13.0, metal)
		if model == "drum_smg":
			_fill_ellipse(image, Vector2(151, 190), Vector2(25, 23), outline)
			_fill_ellipse(image, Vector2(151, 190), Vector2(18, 17), metal)
	elif family == "lmg":
		_draw_thick_line(image, Vector2(132, 180), Vector2(178, 163), 22.0, metal)
		_draw_thick_line(image, Vector2(154, 180), Vector2(158, 221), 16.0, outline)
		if model == "pan_lmg":
			_fill_ellipse(image, Vector2(143, 160), Vector2(28, 9), outline)
			_fill_ellipse(image, Vector2(143, 159), Vector2(21, 5), metal)
		else:
			_fill_polygon(image, PackedVector2Array([Vector2(145, 155), Vector2(162, 150), Vector2(169, 185), Vector2(151, 191)]), metal)
	elif family == "shotgun":
		_draw_thick_line(image, Vector2(181, 169), Vector2(237, 148), 4.0, wood)
	elif family == "sniper_rifle":
		_draw_thick_line(image, Vector2(137, 161), Vector2(184, 144), 10.0, outline)
		_draw_thick_line(image, Vector2(141, 160), Vector2(181, 145), 5.0, metal)

static func _draw_thick_line(image: Image, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	var direction := (to - from).normalized()
	if direction.is_zero_approx():
		_fill_ellipse(image, from, Vector2(width * 0.5, width * 0.5), color)
		return
	var normal := Vector2(-direction.y, direction.x) * width * 0.5
	_fill_polygon(image, PackedVector2Array([from + normal, to + normal, to - normal, from - normal]), color)
	_fill_ellipse(image, from, Vector2(width * 0.5, width * 0.5), color)
	_fill_ellipse(image, to, Vector2(width * 0.5, width * 0.5), color)

static func _fill_ellipse(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	var min_x := maxi(0, int(floor(center.x - radius.x)))
	var max_x := mini(image.get_width() - 1, int(ceil(center.x + radius.x)))
	var min_y := maxi(0, int(floor(center.y - radius.y)))
	var max_y := mini(image.get_height() - 1, int(ceil(center.y + radius.y)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var normalized := Vector2((float(x) - center.x) / radius.x, (float(y) - center.y) / radius.y)
			if normalized.length_squared() <= 1.0:
				image.set_pixel(x, y, color)

static func _fill_polygon(image: Image, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var min_y := image.get_height() - 1
	var max_y := 0
	for point in points:
		min_y = mini(min_y, int(floor(point.y)))
		max_y = maxi(max_y, int(ceil(point.y)))
	min_y = maxi(0, min_y)
	max_y = mini(image.get_height() - 1, max_y)
	for y in range(min_y, max_y + 1):
		var intersections: Array[float] = []
		for index in points.size():
			var first := points[index]
			var second := points[(index + 1) % points.size()]
			if (first.y <= y and second.y > y) or (second.y <= y and first.y > y):
				intersections.append(first.x + (float(y) - first.y) * (second.x - first.x) / (second.y - first.y))
		intersections.sort()
		for index in range(0, intersections.size() - 1, 2):
			var start_x := maxi(0, int(ceil(intersections[index])))
			var end_x := mini(image.get_width() - 1, int(floor(intersections[index + 1])))
			for x in range(start_x, end_x + 1):
				image.set_pixel(x, y, color)

static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			image.set_pixel(x, y, color)
