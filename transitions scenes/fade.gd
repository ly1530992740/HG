extends Node2D

@export var fade_duration: float = 1.0   # seconds

@onready var sprite: Sprite2D = $fade/Sprite2D

var elapsed: float = 0.0
var fading: bool = false

func _ready() -> void:
	# Start fully black
	sprite.modulate = Color(0, 0, 0, 1)


func start_fade() -> void:
	elapsed = 0.0
	fading = true


func _process(delta: float) -> void:
	if !fading:
		return

	elapsed += delta

	var alpha := 1.0 - (elapsed / fade_duration)
	alpha = clamp(alpha, 0.0, 1.0)

	sprite.modulate = Color(0, 0, 0, alpha)

	if alpha <= 0.0:
		fading = false
		queue_free()
