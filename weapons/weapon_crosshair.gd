extends Node2D
class_name WeaponCrosshair

@export var minimum_radius := 9.0
@export var maximum_radius := 58.0
@export var pixels_per_spread_degree := 3.6

var weapon: FirearmWeapon = null
var wielder: Node2D = null
var current_radius := 12.0

func setup(new_weapon: FirearmWeapon, new_wielder: Node2D) -> void:
	weapon = new_weapon
	wielder = new_wielder
	top_level = true
	z_index = 200
	queue_redraw()

func _process(delta: float) -> void:
	if weapon == null or wielder == null or not is_instance_valid(weapon) or not is_instance_valid(wielder):
		queue_free()
		return
	visible = bool(wielder.get("active")) and int(wielder.get("state")) != 3
	if not visible:
		return
	global_position = get_global_mouse_position()
	var target_radius := _get_target_radius()
	current_radius = lerpf(current_radius, target_radius, minf(1.0, delta * 14.0))
	queue_redraw()

func _draw() -> void:
	var color := Color(0.95, 0.98, 1.0, 0.95)
	var shadow := Color(0.0, 0.0, 0.0, 0.8)
	var corner_length := 7.0
	var thickness := 2.0
	_draw_brackets(current_radius + 1.0, corner_length, shadow, thickness + 2.0)
	_draw_brackets(current_radius, corner_length, color, thickness)
	draw_circle(Vector2.ZERO, 2.0, shadow)
	draw_circle(Vector2.ZERO, 1.0, color)

func _draw_brackets(radius: float, length: float, color: Color, width: float) -> void:
	draw_line(Vector2(-radius, -radius), Vector2(-radius + length, -radius), color, width)
	draw_line(Vector2(-radius, -radius), Vector2(-radius, -radius + length), color, width)
	draw_line(Vector2(radius, -radius), Vector2(radius - length, -radius), color, width)
	draw_line(Vector2(radius, -radius), Vector2(radius, -radius + length), color, width)
	draw_line(Vector2(-radius, radius), Vector2(-radius + length, radius), color, width)
	draw_line(Vector2(-radius, radius), Vector2(-radius, radius - length), color, width)
	draw_line(Vector2(radius, radius), Vector2(radius - length, radius), color, width)
	draw_line(Vector2(radius, radius), Vector2(radius, radius - length), color, width)

func _get_target_radius() -> float:
	if weapon.weapon_data == null:
		return minimum_radius
	var spread_multiplier := 1.0
	if wielder.has_method("get_weapon_spread_multiplier"):
		spread_multiplier = float(wielder.get_weapon_spread_multiplier())
	var spread_degrees := weapon.weapon_data.spread_degrees * spread_multiplier
	if weapon.weapon_data.projectile_count > 1:
		spread_degrees += weapon.weapon_data.projectile_spread_degrees * 0.5
	return clampf(minimum_radius + spread_degrees * pixels_per_spread_degree, minimum_radius, maximum_radius)
