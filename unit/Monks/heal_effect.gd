extends Area2D
@onready var anim: AnimatedSprite2D = $anim

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	z_index=5
	anim.play("default")
	await anim.animation_finished
	queue_free()
