extends Sprite2D

@onready var cursor: Sprite2D = $"."

func _ready():
	pulse()

func pulse():
	var tween = create_tween()
	tween.set_loops() # infinite loop

	# Scale up
	tween.tween_property(
		cursor,
		"scale",
		Vector2(1.2, 1.2),
		0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Scale back down
	tween.tween_property(
		cursor,
		"scale",
		Vector2(1.0, 1.0),
		0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
