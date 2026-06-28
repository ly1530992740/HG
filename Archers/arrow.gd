extends Area2D

@onready var anim: AnimatedSprite2D = $Anim
@onready var arrow: Area2D = $"."  # Not used but kept if needed

# Physics
var velocity: Vector2 = Vector2.ZERO
var stuck: bool = false
var stuck_body: Node2D = null
var stick_offset: Vector2 = Vector2.ZERO

# Groups that can be hit
@export var stick_groups: Array = ["goblin","goblinbuildings"]

# Arrow lifespan in seconds
@export var lifespan: float = 0.35

func _ready() -> void:
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
	rotation = velocity.angle()  # Keep arrow pointing toward movement

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
	if body.is_in_group("goblin"):
		if body.has_method("take_damage"):
			body.take_damage(1, arrow.global_position)
	if body.is_in_group("goblinbuildings"):
		if body.has_method("take_damages"):
			body.take_damage(30)

	_fade_and_die()

# --- Lifespan system ---
func _start_lifespan_timer() -> void:
	await get_tree().create_timer(lifespan).timeout
	if not stuck:
		_fade_and_die()

func _fade_and_die() -> void:
	await get_tree().create_timer(0.15).timeout
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.finished.connect(queue_free) 
