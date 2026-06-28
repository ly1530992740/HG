extends AnimatedSprite2D

func _ready() -> void:
	play("sp")
func _on_animation_finished() -> void:
	await get_tree().create_timer(0.3).timeout
	queue_free()
