extends Area2D

@export var resource_type := "wood"
var reserved := false
@onready var anim: AnimatedSprite2D = $anim
@onready var collision: CollisionShape2D = $CollisionShape2D
var collected := false

func _ready():
	z_index = 4
	anim.play("sp")
	await anim.animation_finished
	anim.play("idle")
	

func _on_area_entered(body):
	if collected:
		return

	if body.is_in_group("pawn"):
		collected = true
		collect()

func collect():
	# Add wood
	Global.add_wood(2)

	# Disable collision immediately
	collision.disabled = true

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
