extends AnimatedSprite2D

@onready var fire: AnimatedSprite2D = $"."
@onready var fire_: AudioStreamPlayer = $"fire tnt"


func _ready() -> void:
	z_index = 6
	fire.play("sp")
	fire_.play()
	await get_tree().create_timer(3.0).timeout
	fade()
	fire_.stop()


func fade():
		# Scale + fade effect
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.5)

	# Scale up
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.5)

	# Remove after animation
	tween.finished.connect(queue_free)
