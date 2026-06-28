extends Area2D

@onready var anim: AnimatedSprite2D = $anim
@onready var collision: CollisionShape2D = $CollisionShape2D
@export var resource_type := "gold"
var reserved := false
var collected := false

func _ready():
	z_index = 4
	anim.play("sp")
	await anim.animation_finished
	anim.play("idle")

func _on_body_entered(body):
	if collected:
		return

	if body.is_in_group("pawn"):
		collected = true
		collect()

func collect():
	# Add gold
	Global.add_gold(2)

	# Disable collision immediately
	collision.disabled = true

	# Optional: stop or change animation
	# anim.play("collect")

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
