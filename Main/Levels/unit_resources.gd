extends Panel

@onready var label_gold: Label = $"GIdle/Label gold"
@onready var label_wood: Label = $"WIdle/Label wood"
@onready var label_meat: Label = $"MIdle/Label meat"

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	update_labels()
	check_resources()

func update_labels():
	label_gold.text = " " + str(Global.gold)
	label_wood.text = " " + str(Global.wood)
	label_meat.text = " " + str(Global.meat)

func check_resources():
	check_resource(
		label_gold,
		Global.gold,
		Global.max_gold
	)

	check_resource(
		label_wood,
		Global.wood,
		Global.max_wood
	)

	check_resource(
		label_meat,
		Global.meat,
		Global.max_meat
	)

func check_resource(label: Label, value: int, max_value: int):
	# NORMAL STATE
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)

	# MIN RESOURCE (RED)
	if value <= 0:
		label.add_theme_color_override("font_color", Color.RED)
		label.add_theme_color_override("font_outline_color", Color.BLACK)

	# MAX RESOURCE (GREEN)
	elif value >= max_value:
		label.add_theme_color_override("font_color", Color.GREEN)
		label.add_theme_color_override("font_outline_color", Color.BLACK)


func flash_label_red(label: Label):
	var tween := create_tween()
	tween.set_loops(3)

	tween.tween_property(
		label,
		"theme_override_colors/font_color",
		Color.RED,
		0.1
	)

	tween.tween_property(
		label,
		"theme_override_colors/font_color",
		Color.WHITE,
		0.1
	)
