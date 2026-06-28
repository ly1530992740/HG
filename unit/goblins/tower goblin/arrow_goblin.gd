extends Area2D

@onready var anim: AnimatedSprite2D = $Anim
@onready var arrow: Area2D = $"."  # <-- Not used in your code? Maybe the Area2D itself

# Physics
var velocity: Vector2 = Vector2.ZERO
var stuck: bool = false
var stuck_body: Node2D = null
var stick_offset: Vector2 = Vector2.ZERO

# Groups that can be hit
@export var stick_groups: Array = ["player","building"]

# Arrow lifespan in seconds
@export var lifespan: float = 0.3

func _ready() -> void:
	# Start lifespan timer
	_start_lifespan_timer()

# Launch arrow directly toward target
func launch(target_position: Vector2, speed: float) -> void:
	velocity = (target_position - global_position).normalized() * speed
	rotation = velocity.angle()

func _physics_process(delta: float) -> void:
	if stuck:
		if is_instance_valid(stuck_body):
			global_position = stuck_body.global_position + stick_offset
		return

	global_position += velocity * delta
	rotation = velocity.angle()

func _on_body_entered(body: Node2D) -> void:
	if stuck:
		return

	var can_stick: bool = false
	for group in stick_groups:
		if body.is_in_group(group) or body.name == group:
			can_stick = true
			break

	if not can_stick:
		return

	stuck = true
	stuck_body = body
	velocity = Vector2.ZERO
	stick_offset = global_position - body.global_position

	_fade_and_die()

# --- Lifespan system ---
func _start_lifespan_timer() -> void:
	# Wait for lifespan duration, then fade and free if not stuck
	await get_tree().create_timer(lifespan).timeout
	if not stuck:
		_fade_and_die()

func _fade_and_die() -> void:
	await get_tree().create_timer(0.15).timeout
	spawn_explosion()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.finished.connect(queue_free)

func spawn_explosion():
	await get_tree().create_timer(0.1).timeout
	var explo := preload("res://Materiels/explosion/explosion.tscn").instantiate()
	get_parent().add_child(explo)
	explo.global_position = global_position
	explo.z_index = 5
	queue_free()
