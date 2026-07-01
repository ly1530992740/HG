extends CharacterBody2D
class_name FirearmTestEnemy

@warning_ignore("unused_signal")
signal health_changed(current_health: int, max_health: int)
@warning_ignore("unused_signal")
signal died

@export var max_health: int = 6
@export var move_speed: float = 35.0
@export var follow_player: bool = true
@export var follow_stop_distance: float = 220.0
@export var knockback_force: float = 140.0

var health: int
var knockback_velocity := Vector2.ZERO

@onready var body: Polygon2D = $Body
@onready var health_bar: ProgressBar = $HealthBar
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	add_to_group("goblin")
	health = max_health
	_update_health_view()
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	if health <= 0:
		return

	if knockback_velocity.length() > 1.0:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, delta * 700.0)
	else:
		velocity = _get_ai_velocity()

	if velocity.x != 0.0:
		body.scale.x = -1.0 if velocity.x < 0.0 else 1.0

	move_and_slide()

func take_damage(damage: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if health <= 0:
		return

	health = max(0, health - damage)
	if source_position != Vector2.ZERO:
		var away_from_hit := global_position - source_position
		if away_from_hit != Vector2.ZERO:
			knockback_velocity = away_from_hit.normalized() * knockback_force

	_update_health_view()
	_flash_hit()
	health_changed.emit(health, max_health)

	if health <= 0:
		_die()

func _get_ai_velocity() -> Vector2:
	if not follow_player:
		return Vector2.ZERO

	var target := _get_player_target()
	if target == null:
		return Vector2.ZERO

	var to_target := target.global_position - global_position
	if to_target.length() <= follow_stop_distance:
		return Vector2.ZERO

	return to_target.normalized() * move_speed

func _get_player_target() -> Node2D:
	var candidate: Node = GlobalPlayer.active_player
	if candidate is Node2D and is_instance_valid(candidate):
		return candidate
	return null

func _update_health_view() -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	status_label.text = "AI  HP %d/%d" % [health, max_health]

func _flash_hit() -> void:
	body.color = Color(1.0, 0.25, 0.18, 1.0)
	var tween := create_tween()
	tween.tween_property(body, "color", Color(0.86, 0.22, 0.16, 1.0), 0.12)

func _die() -> void:
	died.emit()
	queue_free()
