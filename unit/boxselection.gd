extends Node2D

var dragging := false
var drag_start := Vector2.ZERO
var drag_end := Vector2.ZERO

@onready var camera: Camera2D = $Camera2D


var selection_rect := Rect2()


func _ready():
	camera.make_current()
	# assign the function to the autoload variable
	GlobalPlayer.camera_shake_func = camera_shake
	z_index=7

@warning_ignore("unused_parameter")
func _physics_process(delta: float) -> void:
	if GlobalPlayer.active_player:
		camera.global_position=GlobalPlayer.active_player_position
	else:
		if GlobalPlayer.castle_position:
			camera.global_position=GlobalPlayer.castle_position
		else:
			camera.global_position=GlobalPlayer.active_player_position

# =====================
# INPUT
# =====================
func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			start_drag()
		else:
			end_drag()

	if event is InputEventMouseMotion and dragging:
		drag_end = get_global_mouse_position()
		update_selection_rect()
		queue_redraw()
# =====================
# DRAG LOGIC
# =====================
func start_drag():
	dragging = true
	drag_start = get_global_mouse_position()
	drag_end = drag_start

func end_drag():
	dragging = false
	update_selection_rect()
	select_units()
	queue_redraw()

# =====================
# RECT UPDATE
# =====================
func update_selection_rect():
	selection_rect = Rect2(
		drag_start,
		drag_end - drag_start
	).abs()

# =====================
# DRAW
# =====================
func _draw():
	if not dragging:
		return

	var color := get_selection_color()
	draw_rect(selection_rect, color, false, 2)
	draw_rect(selection_rect, Color(color.r, color.g, color.b, 0.15), true)

# =====================
# COLOR FROM GLOBAL
# =====================
func get_selection_color() -> Color:
	match Global.choosed_colour:
		"black":
			return Color.BLACK
		"red":
			return Color.RED
		"blue":
			return Color.BLUE
		"green":
			return Color.GREEN
		_:
			return Color.WHITE

# =====================
# UNIT SELECTION
# =====================
func select_units():
	# Deselect all first
	for unit in get_tree().get_nodes_in_group("selectable"):
		unit.set_selected(false)

	for unit in get_tree().get_nodes_in_group("selectable"):
		if selection_rect.has_point(unit.global_position):
			unit.set_selected(true)

func camera_shake() -> void:
	for i in range(6):
		if is_instance_valid(i):
			camera.offset = Vector2(randf_range(-6, 6), randf_range(-6, 6))
			await get_tree().create_timer(0.02).timeout
		else:
			pass
	camera.offset = Vector2.ZERO
