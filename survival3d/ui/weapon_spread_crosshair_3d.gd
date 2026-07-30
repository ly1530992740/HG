extends Control
class_name WeaponSpreadCrosshair3D

@export_range(2.0, 20.0, 0.5) var minimum_gap_pixels := 5.0
@export_range(4.0, 100.0, 1.0) var maximum_gap_pixels := 54.0
@export_range(3.0, 24.0, 0.5) var arm_length_pixels := 9.0
@export_range(1.0, 6.0, 0.5) var line_width_pixels := 2.0
@export var line_color := Color(0.96, 0.96, 0.92, 0.96)
@export var outline_color := Color(0.04, 0.05, 0.05, 0.9)

var _player: ThirdPersonPlayer3D
var _spread_degrees := 0.0
var _reload_progress := 0.0
var _hit_flash := 0.0
var _headshot_flash := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if _player == null:
		return
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		queue_redraw()
	visible = _hit_flash > 0.0 or _player.is_reloading or (_player.is_aiming() and _player.is_shoulder_view())
	set_spread_degrees(_player.get_current_spread_degrees())
	var next_reload_progress := _player.get_reload_progress()
	if not is_equal_approx(_reload_progress, next_reload_progress):
		_reload_progress = next_reload_progress
		queue_redraw()

func bind_player(player: ThirdPersonPlayer3D) -> void:
	_player = player
	if _player != null and not _player.shot_resolved.is_connected(_on_shot_resolved):
		_player.shot_resolved.connect(_on_shot_resolved)
	visible = player != null and (player.is_reloading or (player.is_aiming() and player.is_shoulder_view()))
	queue_redraw()

func set_spread_degrees(value: float) -> void:
	var next_value := maxf(0.0, value)
	if is_equal_approx(_spread_degrees, next_value):
		return
	_spread_degrees = next_value
	queue_redraw()

func get_current_gap_pixels() -> float:
	var viewport_height := get_viewport_rect().size.y
	var field_of_view := 68.0
	if _player != null and _player.camera_director != null:
		field_of_view = _player.camera_director.shoulder_fov
	return calculate_gap_pixels(_spread_degrees, viewport_height, field_of_view)

func calculate_gap_pixels(spread_degrees: float, viewport_height: float, field_of_view_degrees: float) -> float:
	var half_view := maxf(1.0, viewport_height) * 0.5
	var projection_scale := half_view / tan(deg_to_rad(maxf(1.0, field_of_view_degrees)) * 0.5)
	var angular_radius := tan(deg_to_rad(maxf(0.0, spread_degrees))) * projection_scale
	return clampf(minimum_gap_pixels + angular_radius, minimum_gap_pixels, maximum_gap_pixels)

func _draw() -> void:
	var center := size * 0.5
	var gap := get_current_gap_pixels()
	var outline_width := line_width_pixels + 2.0
	_draw_arms(center, gap, outline_width, outline_color)
	_draw_arms(center, gap, line_width_pixels, line_color)
	draw_circle(center, 1.5, outline_color)
	draw_circle(center, 0.75, line_color)
	if _player != null and _player.is_reloading:
		_draw_reload_progress(center)
	if _hit_flash > 0.0:
		_draw_hit_marker(center)

func _on_shot_resolved(result: Dictionary) -> void:
	var collider := result.get("collider") as Node
	if not collider is CombatHitbox3D:
		return
	_hit_flash = 0.18
	_headshot_flash = (collider as CombatHitbox3D).hit_location == "head"
	queue_redraw()

func _draw_hit_marker(center: Vector2) -> void:
	var color := Color(1.0, 0.28, 0.16, clampf(_hit_flash / 0.18, 0.0, 1.0)) if _headshot_flash else Color(0.96, 0.96, 0.92, clampf(_hit_flash / 0.18, 0.0, 1.0))
	var radius := 8.0
	for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_line(center + direction * (radius - 3.0), center + direction * radius, color, 2.0, true)

func _draw_reload_progress(center: Vector2) -> void:
	var radius := minimum_gap_pixels + arm_length_pixels + 5.0
	var start_angle := -PI * 0.5
	draw_arc(center, radius, 0.0, TAU, 40, outline_color, 5.0, true)
	draw_arc(center, radius, start_angle, start_angle + TAU * _reload_progress, 40, line_color, 2.5, true)

func _draw_arms(center: Vector2, gap: float, width: float, color: Color) -> void:
	draw_line(center + Vector2(-gap - arm_length_pixels, 0.0), center + Vector2(-gap, 0.0), color, width, true)
	draw_line(center + Vector2(gap, 0.0), center + Vector2(gap + arm_length_pixels, 0.0), color, width, true)
	draw_line(center + Vector2(0.0, -gap - arm_length_pixels), center + Vector2(0.0, -gap), color, width, true)
	draw_line(center + Vector2(0.0, gap), center + Vector2(0.0, gap + arm_length_pixels), color, width, true)
