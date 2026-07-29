extends Node3D
class_name CameraDirector3D

signal aim_mode_changed(enabled: bool)
signal view_mode_changed(shoulder_view: bool)

@export var player_path: NodePath
@export var top_down_offset := Vector3(0.0, 14.0, 14.0)
@export var top_down_size := 19.0
@export var shoulder_distance := 3.2
@export var shoulder_height := 1.55
@export var shoulder_offset := 0.65
@export var shoulder_fov := 68.0
@export var transition_speed := 8.0
@export var mouse_sensitivity := 0.0025
@export_range(-80.0, -5.0, 1.0) var minimum_pitch_degrees := -55.0
@export_range(5.0, 80.0, 1.0) var maximum_pitch_degrees := 35.0
@export_flags_3d_physics var camera_collision_mask := 1

@onready var camera: Camera3D = $Camera3D

var player: CharacterBody3D
var aiming := false
var shoulder_view := false
var yaw := 0.0
var pitch := deg_to_rad(-8.0)
var _blend := 0.0

func _ready() -> void:
	player = get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		push_error("CameraDirector3D requires a CharacterBody3D player_path.")
		return
	yaw = player.rotation.y
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = top_down_size
	camera.current = true
	_snap_to_top_down()

func _unhandled_input(event: InputEvent) -> void:
	if shoulder_view and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * mouse_sensitivity
		pitch = clampf(
			pitch - motion.relative.y * mouse_sensitivity,
			deg_to_rad(minimum_pitch_degrees),
			deg_to_rad(maximum_pitch_degrees)
		)

func _process(delta: float) -> void:
	if player == null:
		return
	var target_blend := 1.0 if shoulder_view else 0.0
	_blend = move_toward(_blend, target_blend, transition_speed * delta)
	var top_transform := _get_top_down_transform()
	var shoulder_transform := _get_shoulder_transform()
	var desired := top_transform.interpolate_with(shoulder_transform, smoothstep(0.0, 1.0, _blend))
	desired.origin = _resolve_camera_collision(_get_focus_position(), desired.origin)
	global_transform = global_transform.interpolate_with(desired, 1.0 - exp(-14.0 * delta))

	if _blend >= 0.45:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = shoulder_fov
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = top_down_size

func set_aiming(enabled: bool) -> void:
	if aiming == enabled:
		return
	aiming = enabled
	aim_mode_changed.emit(aiming)

func is_aiming() -> bool:
	return aiming

func toggle_view() -> void:
	set_shoulder_view(not shoulder_view)

func set_shoulder_view(enabled: bool) -> void:
	if shoulder_view == enabled:
		return
	shoulder_view = enabled
	if shoulder_view and player != null:
		yaw = player.rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if shoulder_view else Input.MOUSE_MODE_VISIBLE
	view_mode_changed.emit(shoulder_view)

func is_shoulder_view() -> bool:
	return shoulder_view

func get_flat_forward() -> Vector3:
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	forward.y = 0.0
	return forward.normalized()

func get_flat_right() -> Vector3:
	return get_flat_forward().cross(Vector3.UP).normalized()

func get_movement_forward() -> Vector3:
	return get_flat_forward() if shoulder_view else Vector3.FORWARD

func get_movement_right() -> Vector3:
	return get_flat_right() if shoulder_view else Vector3.RIGHT

func get_aim_ray(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position).normalized()
	return {"origin": origin, "direction": direction}

func get_aim_screen_position() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5 if shoulder_view else get_viewport().get_mouse_position()

func _snap_to_top_down() -> void:
	global_transform = _get_top_down_transform()

func _get_focus_position() -> Vector3:
	return player.global_position + Vector3.UP * 1.05

func _get_top_down_transform() -> Transform3D:
	var focus := _get_focus_position()
	var offset := top_down_offset
	if offset.length_squared() <= 0.001:
		offset = Vector3(0.0, 14.0, 14.0)
	var camera_position := focus + offset
	return Transform3D(Basis.IDENTITY, camera_position).looking_at(focus, Vector3.UP)

func _get_shoulder_transform() -> Transform3D:
	var focus := _get_focus_position()
	var flat_forward := get_flat_forward()
	var right := get_flat_right()
	var aim_direction := flat_forward.rotated(right, pitch).normalized()
	var camera_position := focus - aim_direction * shoulder_distance + right * shoulder_offset + Vector3.UP * (shoulder_height - 1.05)
	return Transform3D(Basis.IDENTITY, camera_position).looking_at(focus + aim_direction * 20.0, Vector3.UP)

func _resolve_camera_collision(focus: Vector3, desired_position: Vector3) -> Vector3:
	if get_world_3d() == null:
		return desired_position
	var query := PhysicsRayQueryParameters3D.create(focus, desired_position, camera_collision_mask)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired_position
	return (hit.get("position", desired_position) as Vector3) + (hit.get("normal", Vector3.UP) as Vector3) * 0.22
