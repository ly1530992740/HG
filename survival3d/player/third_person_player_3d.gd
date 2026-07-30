extends CharacterBody3D
class_name ThirdPersonPlayer3D

const DAMAGE_RULES_3D := preload("res://combat3d/combat_damage_rules_3d.gd")

signal ammo_changed(current: int, reserve: int)
signal shot_resolved(result: Dictionary)
signal health_changed(current: int, maximum: int)
signal weapon_changed(weapon_id: String)
signal stamina_changed(current: float, maximum: float)
signal stance_changed(stance: Stance)
signal movement_mode_changed(mode: MoveMode)
signal cover_state_changed(in_cover: bool, peeking: bool)
signal reload_state_changed(active: bool, progress: float)
signal died

enum Stance { STAND, CROUCH, PRONE }
enum MoveMode { WALK, QUIET, RUN }

const TRACER_SPEED_BASELINE := 90.0

@export var move_speed := 5.2
@export var run_speed := 7.2
@export var quiet_speed := 2.0
@export var crouch_speed := 2.6
@export var prone_speed := 1.3
@export var aimed_move_multiplier := 0.55
@export var acceleration := 22.0
@export var rotation_speed := 13.0
@export var max_stamina := 100.0
@export var run_stamina_cost_per_second := 22.0
@export var stamina_recovery_per_second := 16.0
@export var stamina_recovery_delay := 1.2
@export var stamina_required_to_resume_run := 25.0
@export var magazine_size := 24
@export var starting_reserve_ammo := 96
@export var fire_interval := 0.12
@export var reload_duration := 2.0
@export var body_damage := 34
@export var maximum_range := 90.0
@export var tracer_speed := TRACER_SPEED_BASELINE * 0.65
@export var tracer_length := 0.5
@export var hip_spread_degrees := 3.5
@export var aimed_spread_degrees := 0.12
@export var aimed_initial_spread_degrees := 1.6
@export var aim_settle_time := 0.8
@export var recoil_per_shot_degrees := 0.55
@export var max_recoil_spread_degrees := 3.8
@export var recoil_recovery_per_second := 2.4
@export var automatic_fire := false
@export var blind_fire_spread_degrees := 10.0
@export var cover_enter_distance := 2.6
@export_flags_3d_physics var shot_collision_mask := 9
@export var max_health := 100
@export var invulnerable := false
@export var shoulder_back_texture: Texture2D
@export_range(0.002, 0.01, 0.00025) var shoulder_sprite_pixel_size := 0.0035
@export var shoulder_sprite_offset := Vector2(-10.0, 8.0)

@export_category("俯视2.5D表现")
@export_range(4, 16, 1) var top_down_direction_steps := 8
@export_range(2.0, 15.0, 1.0) var top_down_pose_fps := 8.0

@onready var visual: Sprite3D = $Visual
@onready var voxel_visual: VoxelSoldierVisual3D = $VoxelVisual
@onready var muzzle: Marker3D = $WeaponPivot/Muzzle
@onready var actor_collision: CollisionShape3D = $Collision
@onready var body_hitbox: Area3D = $BodyHitbox
@onready var body_hitbox_shape: CollisionShape3D = $BodyHitbox/Shape
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var weapon_model_root: Node3D = $WeaponPivot/WeaponModelRoot

var camera_director: CameraDirector3D
var current_ammo := 0
var reserve_ammo := 0
var health: int:
	get: return health_component.current if is_instance_valid(health_component) else 0
var current_weapon_id := "rifle"
var unlocked_weapons := PackedStringArray(["rifle"])
var weapon_ammo_state: Dictionary = {}
var dead := false
var fire_cooldown := 0.0
var is_reloading := false
var reload_elapsed := 0.0
var logical_forward := Vector3.FORWARD
var stance: Stance = Stance.STAND
var movement_mode: MoveMode = MoveMode.WALK
var stamina: float:
	get: return stamina_component.current if is_instance_valid(stamina_component) else 0.0
var active_cover: TacticalCover3D
var active_cover_slot: Marker3D
var cover_peeking := false
var _animation_time := 0.0
var _top_down_texture: Texture2D
var accuracy_component: PlayerAccuracyComponent3D
var ballistics_component: PlayerBallisticsComponent3D
var health_component: HealthComponent3D
var stamina_component: StaminaComponent3D
var weapon_feedback_component: WeaponFeedback3D
var shoulder_animator: ShoulderSpriteAnimator3D
var weapon_definition: Dictionary = {}
var shoulder_animation_set: Dictionary = {}
var _last_fire_msec := -100000
var blind_fire_active := false
var _top_down_sprite_pixel_size := 0.015
var _top_down_sprite_offset := Vector2.ZERO
var _top_down_pose_accumulator := 0.0

func _ready() -> void:
	add_to_group("player3d")
	add_to_group("combatant3d")
	var registry := BattlefieldRegistry3D.find(get_tree())
	if registry != null:
		registry.register_node(self)
	_top_down_texture = visual.texture
	_top_down_sprite_pixel_size = visual.pixel_size
	_top_down_sprite_offset = visual.offset
	_setup_runtime_components()
	health_component.configure(max_health)
	stamina_component.configure(max_stamina, run_stamina_cost_per_second, stamina_recovery_per_second, stamina_recovery_delay, stamina_required_to_resume_run)
	_make_stance_shapes_unique()
	_apply_stance_geometry()
	_apply_weapon_profile(current_weapon_id, true)
	logical_forward = -global_transform.basis.z
	call_deferred("_bind_camera")
	ammo_changed.emit(current_ammo, reserve_ammo)
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	stance_changed.emit(stance)
	movement_mode_changed.emit(movement_mode)

func _exit_tree() -> void:
	exit_cover()
	if camera_director != null and camera_director.is_shoulder_view():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_Q:
			cycle_weapon(-1)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_E:
			cycle_weapon(1)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_C:
			toggle_cover()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_CTRL and not is_in_cover():
			set_stance(Stance.STAND if stance == Stance.CROUCH else Stance.CROUCH)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_Z:
			exit_cover()
			set_stance(Stance.STAND if stance == Stance.PRONE else Stance.PRONE)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("aim_weapon"):
		set_aiming(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("aim_weapon"):
		set_aiming(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_camera_view"):
		camera_director.toggle_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fire_weapon"):
		try_fire()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload_weapon"):
		reload()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector3.ZERO
		return
	if (active_cover != null or active_cover_slot != null) and not is_in_cover():
		exit_cover()
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	_update_reload(delta)
	_update_accuracy(delta)
	if automatic_fire and Input.is_action_pressed("fire_weapon"):
		try_fire()
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var input := _get_move_input()
	var move_direction := Vector3.ZERO
	if camera_director != null:
		move_direction = camera_director.get_movement_right() * input.x - camera_director.get_movement_forward() * input.y
	else:
		move_direction = Vector3(input.x, 0.0, input.y)
	move_direction = move_direction.normalized()
	if is_in_cover() and move_direction.length_squared() > 0.001:
		exit_cover()

	_update_movement_state(delta, move_direction.length_squared() > 0.001)
	var speed_multiplier := aimed_move_multiplier if is_aiming() else 1.0
	var desired_velocity := move_direction * get_current_move_speed() * speed_multiplier
	velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)

	var facing := move_direction
	if camera_director != null and camera_director.is_shoulder_view():
		facing = camera_director.get_flat_forward()
	elif is_aiming() and camera_director != null:
		var aim_ray := camera_director.get_aim_ray(camera_director.get_aim_screen_position())
		facing = get_top_down_aim_point(aim_ray.origin, aim_ray.direction) - global_position
		facing.y = 0.0
	if facing.length_squared() > 0.001:
		logical_forward = facing.normalized()
		var target_yaw := atan2(-logical_forward.x, -logical_forward.z)
		if camera_director != null and camera_director.is_shoulder_view():
			rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rotation_speed * delta))
		else:
			rotation.y = _quantize_top_down_yaw(target_yaw)

	move_and_slide()
	_update_sprite(delta, move_direction.length_squared() > 0.01)

func set_aiming(enabled: bool) -> void:
	if camera_director != null:
		camera_director.set_aiming(enabled)

func is_aiming() -> bool:
	return camera_director != null and camera_director.is_aiming()

func is_shoulder_view() -> bool:
	return camera_director != null and camera_director.is_shoulder_view()

func is_in_cover() -> bool:
	return is_instance_valid(active_cover) and is_instance_valid(active_cover_slot)

func is_cover_peeking() -> bool:
	return is_in_cover() and cover_peeking

func toggle_cover() -> bool:
	if is_in_cover():
		cover_peeking = not cover_peeking
		set_stance(Stance.STAND if cover_peeking else Stance.CROUCH)
		cover_state_changed.emit(true, cover_peeking)
		return true
	return try_enter_nearest_cover()

func try_enter_nearest_cover() -> bool:
	var nearest_cover: TacticalCover3D
	var nearest_slot: Marker3D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("cover3d"):
		if not candidate is TacticalCover3D:
			continue
		var cover := candidate as TacticalCover3D
		var slot := cover.get_nearest_available_slot(self)
		if slot == null:
			continue
		var distance := global_position.distance_to(slot.global_position)
		if distance <= cover_enter_distance and distance < nearest_distance:
			nearest_cover = cover
			nearest_slot = slot
			nearest_distance = distance
	if nearest_cover == null or nearest_slot == null or not nearest_cover.reserve_specific_slot(self, nearest_slot):
		return false
	active_cover = nearest_cover
	active_cover_slot = nearest_slot
	global_position = nearest_slot.global_position
	velocity = Vector3.ZERO
	cover_peeking = false
	set_stance(Stance.CROUCH)
	_set_movement_mode(MoveMode.WALK)
	cover_state_changed.emit(true, false)
	return true

func exit_cover() -> void:
	if is_instance_valid(active_cover):
		active_cover.release_slot(self)
	var was_in_cover := active_cover != null or active_cover_slot != null
	active_cover = null
	active_cover_slot = null
	cover_peeking = false
	if was_in_cover and stance == Stance.CROUCH:
		set_stance(Stance.STAND)
	if was_in_cover:
		cover_state_changed.emit(false, false)

func set_stance(new_stance: Stance) -> void:
	if stance == new_stance:
		return
	stance = new_stance
	if stance != Stance.STAND and movement_mode == MoveMode.RUN:
		_set_movement_mode(MoveMode.WALK)
	_apply_stance_geometry()
	stance_changed.emit(stance)

func get_current_move_speed() -> float:
	match stance:
		Stance.CROUCH:
			return crouch_speed
		Stance.PRONE:
			return prone_speed
	match movement_mode:
		MoveMode.RUN:
			return run_speed
		MoveMode.QUIET:
			return quiet_speed
	return move_speed

func get_visibility_multiplier() -> float:
	var multiplier := 1.0
	match stance:
		Stance.CROUCH:
			multiplier *= 0.72
		Stance.PRONE:
			multiplier *= 0.48
	if movement_mode == MoveMode.QUIET:
		multiplier *= 0.72
	elif movement_mode == MoveMode.RUN:
		multiplier *= 1.18
	if is_in_cover() and not cover_peeking:
		multiplier *= 0.5
	return multiplier

func get_stance_label() -> String:
	if is_in_cover():
		return "掩体探身" if cover_peeking else "掩体盲射"
	return ["站立", "下蹲", "卧倒"][int(stance)]

func get_movement_mode_label() -> String:
	return ["行走", "静步", "跑步"][int(movement_mode)]

func try_fire() -> Dictionary:
	if camera_director == null:
		return {"fired": false, "reason": "no_camera"}
	var ray := camera_director.get_aim_ray(camera_director.get_aim_screen_position())
	var camera_origin := ray.get("origin", global_position) as Vector3
	var camera_direction := ray.get("direction", logical_forward) as Vector3
	var aim_point := Vector3.ZERO
	if is_shoulder_view():
		aim_point = ballistics_component.ray_endpoint(self, camera_origin, camera_direction, maximum_range, shot_collision_mask, [get_rid()])
	else:
		aim_point = get_top_down_aim_point(camera_origin, camera_direction)
	return fire_at_world_point(aim_point)

func get_top_down_aim_point(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	var fire_origin := _get_fire_origin(false)
	if absf(ray_direction.y) <= 0.0001:
		return fire_origin + logical_forward * maximum_range
	var distance_to_plane := (fire_origin.y - ray_origin.y) / ray_direction.y
	if distance_to_plane < 0.0:
		return fire_origin + logical_forward * maximum_range
	var cursor_position := ray_origin + ray_direction * distance_to_plane
	var flat_direction := cursor_position - fire_origin
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.0001:
		flat_direction = logical_forward
	return fire_origin + flat_direction.normalized() * maximum_range

func fire_at_world_point(world_point: Vector3) -> Dictionary:
	if is_reloading:
		return {"fired": false, "reason": "reloading"}
	if fire_cooldown > 0.0:
		return {"fired": false, "reason": "cooldown"}
	if current_ammo <= 0:
		if weapon_feedback_component != null:
			weapon_feedback_component.play_empty()
		return {"fired": false, "reason": "empty"}

	current_ammo -= 1
	_last_fire_msec = Time.get_ticks_msec()
	fire_cooldown = fire_interval
	ammo_changed.emit(current_ammo, reserve_ammo)
	var blind_fire := is_in_cover() and not cover_peeking
	blind_fire_active = blind_fire
	_apply_weapon_pose(blind_fire)
	var origin := _get_fire_origin(blind_fire)
	var shot_distance := maximum_range
	var direction := (world_point - origin).normalized()
	if direction == Vector3.ZERO:
		direction = logical_forward
	var top_down_fire := not is_shoulder_view()
	if top_down_fire:
		direction.y = 0.0
		direction = direction.normalized() if direction.length_squared() > 0.0001 else logical_forward
		logical_forward = direction
		rotation.y = _quantize_top_down_yaw(atan2(-logical_forward.x, -logical_forward.z))
	var spread_degrees := get_current_spread_degrees(blind_fire)
	var spread := deg_to_rad(spread_degrees)
	direction = ballistics_component.apply_spread(direction, spread)
	var result := ballistics_component.perform_shot(self, origin, direction, shot_distance, shot_collision_mask, body_damage, weapon_definition)
	accuracy_component.report_shot(recoil_per_shot_degrees, max_recoil_spread_degrees)
	if camera_director != null:
		camera_director.add_weapon_recoil(
			float(weapon_definition.get("camera_kick", recoil_per_shot_degrees)),
			float(weapon_definition.get("camera_yaw", 0.3)),
			0.035 if String(weapon_definition.get("family", "")) in ["bolt_rifle", "shotgun", "lmg"] else 0.02
		)
	result["fired"] = true
	result["origin"] = origin
	result["blind_fire"] = blind_fire
	result["spread_degrees"] = spread_degrees
	result["shot_distance"] = shot_distance
	result["target_point"] = world_point
	result["direction"] = direction
	result["end"] = result.get("position", origin + direction * shot_distance)
	ballistics_component.spawn_tracer(self, origin, result["end"] as Vector3, tracer_speed, tracer_length)
	if weapon_feedback_component != null:
		weapon_feedback_component.play_fire(direction, result)
		var collider := result.get("collider") as Node
		if collider is CombatHitbox3D:
			weapon_feedback_component.play_hit_confirm((collider as CombatHitbox3D).hit_location == "head")
	if shoulder_animator != null:
		shoulder_animator.notify_fire(String(weapon_definition.get("family", "bolt_rifle")))
	shot_resolved.emit(result)
	return result

func reload() -> bool:
	if is_reloading or current_ammo >= magazine_size or reserve_ammo <= 0:
		return false
	is_reloading = true
	reload_elapsed = 0.0
	set_aiming(false)
	if shoulder_animator != null:
		shoulder_animator.notify_reload_started()
	reload_state_changed.emit(true, 0.0)
	if weapon_feedback_component != null:
		weapon_feedback_component.play_reload()
	return true

func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	reload_elapsed = 0.0
	reload_state_changed.emit(false, 0.0)

func get_reload_progress() -> float:
	if not is_reloading:
		return 0.0
	return clampf(reload_elapsed / maxf(0.01, reload_duration), 0.0, 1.0)

func _update_reload(delta: float) -> void:
	if not is_reloading:
		return
	reload_elapsed += delta
	var progress := get_reload_progress()
	if shoulder_animator != null and is_shoulder_view():
		shoulder_animator.update_animation(0.0, is_aiming(), true, progress, false)
	reload_state_changed.emit(true, progress)
	if progress < 1.0:
		return
	var amount := mini(magazine_size - current_ammo, reserve_ammo)
	current_ammo += amount
	reserve_ammo -= amount
	is_reloading = false
	reload_elapsed = 0.0
	ammo_changed.emit(current_ammo, reserve_ammo)
	reload_state_changed.emit(false, 1.0)

func set_weapon(weapon_id: String) -> bool:
	if weapon_id.is_empty():
		return false
	cancel_reload()
	_store_weapon_ammo()
	if not unlocked_weapons.has(weapon_id):
		unlocked_weapons.append(weapon_id)
	current_weapon_id = weapon_id
	_apply_weapon_profile(weapon_id, not weapon_ammo_state.has(weapon_id))
	if weapon_ammo_state.has(weapon_id):
		var state: Dictionary = weapon_ammo_state[weapon_id]
		current_ammo = int(state.get("magazine", current_ammo))
		reserve_ammo = int(state.get("reserve", reserve_ammo))
	ammo_changed.emit(current_ammo, reserve_ammo)
	weapon_changed.emit(current_weapon_id)
	return true

func cycle_weapon(direction: int) -> void:
	if unlocked_weapons.is_empty():
		return
	var index := unlocked_weapons.find(current_weapon_id)
	if index < 0:
		index = 0
	set_weapon(unlocked_weapons[posmod(index + signi(direction), unlocked_weapons.size())])

func receive_weapon_pickup(weapon_id: String, ammo_amount: int) -> bool:
	var already_owned := unlocked_weapons.has(weapon_id)
	set_weapon(weapon_id)
	if already_owned:
		reserve_ammo += maxi(0, ammo_amount)
	else:
		reserve_ammo = maxi(reserve_ammo, ammo_amount)
	ammo_changed.emit(current_ammo, reserve_ammo)
	return true

func receive_ammo_pickup(amount: int) -> void:
	reserve_ammo += maxi(0, amount)
	ammo_changed.emit(current_ammo, reserve_ammo)

func receive_hit(damage: int, hit_location: String, hit_position: Vector3, instigator: Node, weapon_metadata := {}) -> void:
	if dead or invulnerable or damage <= 0:
		return
	if not DAMAGE_RULES_3D.can_damage(instigator, self):
		return
	if not health_component.apply_damage(damage):
		return
	if voxel_visual != null and String(weapon_metadata.get("family", "")) != "melee":
		voxel_visual.add_bullet_wound(hit_position, weapon_metadata.get("impact_normal", Vector3.ZERO) as Vector3, hit_location)
	health_changed.emit(health, health_component.maximum)
	if health <= 0:
		dead = true
		cancel_reload()
		set_aiming(false)
		if camera_director != null:
			camera_director.set_shoulder_view(false)
		died.emit()

func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * _get_aim_height()

func get_combat_team() -> int:
	return int(Soldier3D.Team.PLAYER)

func is_combat_alive() -> bool:
	return not dead and health_component.is_alive()

func _store_weapon_ammo() -> void:
	weapon_ammo_state[current_weapon_id] = {"magazine": current_ammo, "reserve": reserve_ammo}

func _apply_weapon_profile(weapon_id: String, reset_ammo: bool) -> void:
	weapon_definition = WeaponCatalog3D.get_definition(weapon_id)
	shoulder_animation_set = VoxelSoldierVisual3D.create_red_army_shoulder_animation_set(weapon_definition)
	shoulder_back_texture = shoulder_animation_set.get("ready") as Texture2D
	if shoulder_animator != null:
		shoulder_animator.set_animation_set(shoulder_animation_set)
	magazine_size = int(weapon_definition.get("magazine_size", 5))
	fire_interval = float(weapon_definition.get("fire_interval", 0.2))
	reload_duration = float(weapon_definition.get("reload_duration", 2.0))
	body_damage = int(weapon_definition.get("damage", 28))
	maximum_range = float(weapon_definition.get("maximum_range", 38.0))
	hip_spread_degrees = float(weapon_definition.get("hip_spread", 3.5))
	aimed_spread_degrees = float(weapon_definition.get("aimed_spread", 0.18))
	aimed_initial_spread_degrees = float(weapon_definition.get("aimed_initial_spread", 1.6))
	aim_settle_time = float(weapon_definition.get("aim_settle_time", 0.8))
	recoil_per_shot_degrees = float(weapon_definition.get("recoil_per_shot", 0.55))
	max_recoil_spread_degrees = float(weapon_definition.get("max_recoil", 3.8))
	recoil_recovery_per_second = float(weapon_definition.get("recoil_recovery", 2.4))
	automatic_fire = bool(weapon_definition.get("automatic", false))
	if weapon_feedback_component != null:
		weapon_feedback_component.configure(weapon_definition)
	accuracy_component.reset_aim()
	accuracy_component.reset_recoil()
	if reset_ammo:
		current_ammo = magazine_size
		reserve_ammo = int(weapon_definition.get("starting_reserve", maxi(starting_reserve_ammo, magazine_size * 3)))

func get_weapon_display_name() -> String:
	return String(weapon_definition.get("display_name", WeaponCatalog3D.get_display_name(current_weapon_id)))

func _bind_camera() -> void:
	camera_director = get_tree().get_first_node_in_group("third_person_camera") as CameraDirector3D
	if camera_director == null:
		push_error("ThirdPersonPlayer3D could not find the third_person_camera group.")
		return
	if not camera_director.aim_mode_changed.is_connected(_on_aim_mode_changed):
		camera_director.aim_mode_changed.connect(_on_aim_mode_changed)
	if not camera_director.view_mode_changed.is_connected(_on_view_mode_changed):
		camera_director.view_mode_changed.connect(_on_view_mode_changed)
	_on_aim_mode_changed(camera_director.is_aiming())
	_on_view_mode_changed(camera_director.is_shoulder_view())

func _on_aim_mode_changed(_enabled: bool) -> void:
	accuracy_component.reset_aim()

func _on_view_mode_changed(shoulder_view: bool) -> void:
	if visual == null:
		return
	if shoulder_view:
		shoulder_animator.set_active(true, is_aiming())
	else:
		shoulder_animator.set_active(false)
		visual.texture = _top_down_texture
		visual.hframes = 8
		visual.vframes = 1
		rotation.y = _quantize_top_down_yaw(rotation.y)
	visual.pixel_size = shoulder_sprite_pixel_size if shoulder_view else _top_down_sprite_pixel_size
	visual.offset = shoulder_sprite_offset if shoulder_view else _top_down_sprite_offset
	visual.visible = shoulder_view
	if voxel_visual != null:
		voxel_visual.visible = not shoulder_view
	if weapon_pivot != null:
		weapon_pivot.visible = not shoulder_view
	visual.frame = 0
	_animation_time = 0.0

func _get_fire_origin(blind_fire: bool) -> Vector3:
	if blind_fire:
		_apply_weapon_pose(true)
	return muzzle.global_position

func _update_movement_state(delta: float, moving: bool) -> void:
	var requested_mode := MoveMode.WALK
	if Input.is_key_pressed(KEY_ALT):
		requested_mode = MoveMode.QUIET
	elif Input.is_key_pressed(KEY_SHIFT) and stance == Stance.STAND and not is_aiming() and stamina_component.can_run():
		requested_mode = MoveMode.RUN
	_set_movement_mode(requested_mode)
	_update_stamina(delta, moving)

func _update_stamina(delta: float, moving: bool) -> void:
	var running := movement_mode == MoveMode.RUN
	if stamina_component.process(delta, running, moving):
		stamina_changed.emit(stamina, stamina_component.maximum)
	if running and not stamina_component.can_run():
		_set_movement_mode(MoveMode.WALK)

func _set_movement_mode(new_mode: MoveMode) -> void:
	if movement_mode == new_mode:
		return
	movement_mode = new_mode
	movement_mode_changed.emit(movement_mode)

func _make_stance_shapes_unique() -> void:
	if actor_collision.shape != null:
		actor_collision.shape = actor_collision.shape.duplicate()
	if body_hitbox_shape.shape != null:
		body_hitbox_shape.shape = body_hitbox_shape.shape.duplicate()

func _apply_stance_geometry() -> void:
	var actor_height := 1.8
	var body_height := 1.15
	var center_height := 0.9
	var body_center := 0.92
	var head_height := 1.7
	var visual_height := 1.0
	var visual_scale_y := 1.0
	var weapon_offset_y := 0.0
	match stance:
		Stance.CROUCH:
			actor_height = 1.22
			body_height = 0.82
			center_height = 0.61
			body_center = 0.61
			head_height = 1.05
			visual_height = 0.68
			visual_scale_y = 0.72
			weapon_offset_y = -0.34
		Stance.PRONE:
			actor_height = 0.72
			body_height = 0.66
			center_height = 0.36
			body_center = 0.36
			head_height = 0.55
			visual_height = 0.39
			visual_scale_y = 0.45
			weapon_offset_y = -0.68
	if actor_collision.shape is CapsuleShape3D:
		(actor_collision.shape as CapsuleShape3D).height = actor_height
	if body_hitbox_shape.shape is CapsuleShape3D:
		(body_hitbox_shape.shape as CapsuleShape3D).height = body_height
	actor_collision.position.y = center_height
	body_hitbox.position.y = body_center
	head_hitbox.position.y = head_height
	visual.position.y = visual_height
	visual.scale.y = visual_scale_y
	weapon_pivot.position.y = weapon_offset_y

func _get_aim_height() -> float:
	match stance:
		Stance.CROUCH:
			return 0.98
		Stance.PRONE:
			return 0.5
	return 1.25

func _get_move_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y += 1.0
	return input.normalized()

func _update_accuracy(delta: float) -> void:
	accuracy_component.process(delta, is_aiming(), recoil_recovery_per_second)

func get_current_spread_degrees(blind_fire := false) -> float:
	return accuracy_component.get_spread(
		blind_fire,
		is_aiming(),
		hip_spread_degrees,
		blind_fire_spread_degrees,
		aimed_initial_spread_degrees,
		aimed_spread_degrees,
		aim_settle_time
	)

func _setup_runtime_components() -> void:
	var components := get_node_or_null("Components")
	if components == null:
		components = Node.new()
		components.name = "Components"
		add_child(components)
	accuracy_component = PlayerAccuracyComponent3D.new()
	accuracy_component.name = "Accuracy"
	components.add_child(accuracy_component)
	ballistics_component = PlayerBallisticsComponent3D.new()
	ballistics_component.name = "Ballistics"
	components.add_child(ballistics_component)
	health_component = HealthComponent3D.new()
	health_component.name = "Health"
	components.add_child(health_component)
	stamina_component = StaminaComponent3D.new()
	stamina_component.name = "Stamina"
	components.add_child(stamina_component)
	weapon_feedback_component = WeaponFeedback3D.new()
	weapon_feedback_component.name = "WeaponFeedback"
	components.add_child(weapon_feedback_component)
	weapon_feedback_component.setup(self, weapon_model_root, muzzle)
	shoulder_animator = ShoulderSpriteAnimator3D.new()
	shoulder_animator.name = "ShoulderSpriteAnimator"
	components.add_child(shoulder_animator)
	shoulder_animator.setup(visual)

func _update_sprite(delta: float, moving: bool) -> void:
	if visual == null:
		return
	var firing := Time.get_ticks_msec() - _last_fire_msec < 150
	if is_shoulder_view():
		shoulder_animator.update_animation(delta, is_aiming(), is_reloading, get_reload_progress(), moving)
		visual.flip_h = false
		_apply_weapon_pose(blind_fire_active)
		return
	if moving:
		_animation_time += delta
		visual.frame = int(_animation_time * 10.0) % maxi(1, visual.hframes)
	else:
		_animation_time = 0.0
	if not firing:
		blind_fire_active = false
	if voxel_visual != null:
		_top_down_pose_accumulator += delta
		var frame_duration := 1.0 / maxf(1.0, top_down_pose_fps)
		var stepped_delta := 0.0
		if _top_down_pose_accumulator >= frame_duration:
			var elapsed_frames := floori(_top_down_pose_accumulator / frame_duration)
			stepped_delta = float(elapsed_frames) * frame_duration
			_top_down_pose_accumulator -= stepped_delta
		voxel_visual.update_pose(stepped_delta, velocity, int(movement_mode), int(stance), is_aiming(), firing, dead, String(weapon_definition.get("family", "bolt_rifle")), blind_fire_active)
	_apply_weapon_pose(blind_fire_active)
	visual.frame = 0
	if camera_director != null:
		visual.flip_h = logical_forward.dot(camera_director.get_flat_right()) < 0.0

func _quantize_top_down_yaw(yaw: float) -> float:
	var step := TAU / float(maxi(1, top_down_direction_steps))
	return snappedf(yaw, step)

func get_top_down_facing_index() -> int:
	var steps := maxi(1, top_down_direction_steps)
	var step := TAU / float(steps)
	return posmod(roundi(rotation.y / step), steps)

func _apply_weapon_pose(blind_fire := false) -> void:
	if voxel_visual == null or weapon_pivot == null:
		return
	weapon_pivot.transform = voxel_visual.get_weapon_pivot_pose(
		String(weapon_definition.get("family", "bolt_rifle")),
		int(stance),
		is_aiming(),
		blind_fire
	)
