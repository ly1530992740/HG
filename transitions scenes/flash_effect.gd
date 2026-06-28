extends Node2D

@export var flash_speed := 0.08
@export var flash_count := 10
@export var flash_color := Color(1, 1, 1)
@export var light_energy := 2.5
@export var scale_boost := 1.15

@onready var sprite: Sprite2D = $Sprite2D
@onready var light: PointLight2D = $PointLight2D
@onready var timer: Timer = $Timer

var step := 0
var original_color: Color
var original_scale: Vector2
var original_light_energy: float

func _ready():
	original_color = sprite.modulate
	original_scale = scale
	original_light_energy = light.energy

	timer.wait_time = flash_speed
	timer.timeout.connect(_on_flash_step)

func start_flash():
	step = 0
	timer.start()

func _on_flash_step():
	var on := step % 2 == 0

	if on:
		sprite.modulate = flash_color
		scale = original_scale * scale_boost
		light.energy = light_energy
	else:
		sprite.modulate = original_color
		scale = original_scale
		light.energy = original_light_energy

	step += 1

	if step >= flash_count:
		_reset()

func _reset():
	sprite.modulate = original_color
	scale = original_scale
	light.energy = original_light_energy
	timer.stop()
