extends Panel

@onready var selector: Sprite2D = $selector

# Construction buttons
@onready var buttons = [
	$BuildHouse1Btn,
	$BuildHouse2Btn,
	$BuildHouse3Btn,
	$BuildTowerBtn,
	$BuildmonasteryBtn,
	$BuildbarracksBtn,
	$BuildarcheryBtn
]

# Markers for selector placement
@onready var markers = [
	$BuildHouse1Btn/Marker2D,
	$BuildHouse2Btn/Marker2D,
	$BuildHouse3Btn/Marker2D,
	$BuildTowerBtn/Marker2D,
	$BuildmonasteryBtn/Marker2D,
	$BuildbarracksBtn/Marker2D,
	$BuildarcheryBtn/Marker2D
]

# Visual building icons (sprites / texture nodes)
@onready var icons = [
$BuildHouse1Btn/anim,
 $BuildHouse2Btn/anim,
 $BuildHouse3Btn/anim,
 $BuildTowerBtn/anim,
 $BuildmonasteryBtn/anim,
 $BuildbarracksBtn/anim,
 $BuildarcheryBtn/anim
]

# Define real costs here
var costs = [
	{"gold": 20, "wood": 30},
	{"gold": 25, "wood": 35},
	{"gold": 30, "wood": 40},
	{"gold": 40, "wood": 60},
	{"gold": 35, "wood": 50},
	{"gold": 45, "wood": 70},
	{"gold": 50, "wood": 80}
]

signal build_requested(building_name: String)


func _ready() -> void:
	# Connect all button signals dynamically
	for i in buttons.size():
		buttons[i].pressed.connect(_on_any_button_pressed.bind(i))


func _on_any_button_pressed(index: int) -> void:
	var icon = icons[index]

	# Move selector
	selector.global_position = markers[index].global_position

	# Scale bump for click feel
	_scale_bump(icon)


	if Global.gold>0 or Global.wood>0 :
		# Try to consume
		if Global.gold>0 or Global.wood>0 :
			var building = buttons[index].name
			Global.pawn_tool = building
			emit_signal("build_requested", building)

			_flash_green(icon)
		elif Global.gold<=0 or Global.wood<=0:
			_flash_red(icon)
	elif Global.gold<=0 or Global.wood<=0 :
		_flash_red(icon)


# ============================
# TWEEN EFFECTS
# ============================

func _scale_bump(node) -> void:
	var tween = create_tween()
	var original = node.scale

	tween.tween_property(node, "scale", original * 3.15, 0.08)
	tween.tween_property(node, "scale", original, 0.12)


func _flash_green(node) -> void:
	var original = node.modulate

	var tween = create_tween()

	tween.tween_property(node, "modulate", Color.GREEN, 0.15)
	tween.tween_property(node, "modulate", original, 0.15)

	await tween.finished



func _flash_red(node) -> void:
	var original = node.modulate

	var tween = create_tween()

	tween.tween_property(node, "modulate", Color.RED, 0.15)
	tween.tween_property(node, "modulate", original, 0.15)

	await tween.finished
