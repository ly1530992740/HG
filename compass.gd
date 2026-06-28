extends Sprite2D

@onready var cursor: Sprite2D = $"."

# Possible rotation angles (degrees)
var rotation_choices := [30, 45, 60, 75, 90]

func _ready():
	randomize()
	pulse_rotation()


func pulse_rotation():
	while true:
		# Pick random angle
		var angle = rotation_choices.pick_random()

		# Random direction (+ or -)
		if randi() % 2 == 0:
			angle *= -1

		# Convert to radians (Godot uses radians)
		var target_rotation = deg_to_rad(angle)

		var tween = create_tween()

		# Rotate toward target
		tween.tween_property(
			cursor,
			"rotation",
			target_rotation,
			0.8
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		# Rotate back to normal
		tween.tween_property(
			cursor,
			"rotation",
			0.0,
			0.8
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		# Wait until tween finishes before next random rotation
		await tween.finished
