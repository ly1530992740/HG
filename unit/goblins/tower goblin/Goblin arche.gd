extends CharacterBody2D

# === EXPORT VARIABLES ===
@export var arrow_scene=preload("res://unit/goblins/tower goblin/arrow goblin.tscn")
@export var arrow_speed: float = 500.0
@export var tracking_interval: float = 0.1

# === NODE REFERENCES ===
@onready var attack_area: Area2D = $"attack zone"
@onready var shoot_point: Marker2D = $Marker2D
@onready var cooldown: Timer = $cooldown
@onready var anim: AnimatedSprite2D = $anim
@onready var throw_audio: AudioStreamPlayer = $soundfx/throw_audio
@onready var hit_audio: AudioStreamPlayer = $soundfx/hit_audio

# === INTERNAL STATE ===
var target: Node2D = null
var tracking_timer: float = 0.0

var player_is_dead := false

# === READY ===
func _ready() -> void:
	z_index = 3
	anim.play("idle")

# === AREA2D SIGNALS ===
func _on_attack_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = body

func _on_attack_zone_body_exited(body: Node2D) -> void:
	if body == target:
		target = null
		cooldown.stop()
		anim.play("idle")

# === COOLDOWN HANDLER ===
func _on_cooldown_timeout() -> void:
	if target:
		shoot()
		cooldown.start()

# === TRACK TARGET AND AUTO-SHOOT ===
func _physics_process(delta: float) -> void:
	if target == null:
		if anim.animation != "idle":
			anim.play("idle")
		return

	update_facing()

	tracking_timer -= delta
	if tracking_timer <= 0.0:
		tracking_timer = tracking_interval

		if cooldown.is_stopped():
			shoot()
			cooldown.start()


# === SHOOT FUNCTION ===
func shoot() -> void:
	if target == null:
		return

	anim.play("shoot")

	var arrow: Node2D = arrow_scene.instantiate()
	get_parent().add_child(arrow)
	arrow.global_position = shoot_point.global_position
	arrow.z_index = 4

	if arrow.has_method("launch"):
		throw_audio.play()
		arrow.launch(target.global_position, arrow_speed)

func update_facing() -> void:
	if target == null:
		return

	anim.flip_h = target.global_position.x < global_position.x
