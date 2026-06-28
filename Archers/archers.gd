extends CharacterBody2D

# === EXPORTS ===
@export var arrow_scene: PackedScene = preload("res://Archers/arrow.tscn")
@export var arrow_speed: float = 800.0
@export var tracking_interval: float = 0.1
@export var fire_cooldown: float = 1.0  # Seconds between shots

# === NODES ===
@onready var attack_area: Area2D = $"attack zone"
@onready var shoot_point: Marker2D = $Marker2D
@onready var anim: AnimatedSprite2D = $anim
@onready var shooting_arrow: AudioStreamPlayer = $soundfx/ShootingArrow

# === STATE ===
var target: Node2D = null
var candidates: Array[Node2D] = []
var tracking_timer: float = 0.0
var cooldown_timer: float = 0.0

# === READY ===
func _ready() -> void:
	z_index = 5
	anim.play("idle")
	_scan_for_new_targets()

# === AREA SIGNALS ===
func _on_attack_zone_body_entered(body: Node2D) -> void:
	if not body.is_in_group("goblin"):
		return

	if body not in candidates:
		candidates.append(body)
		_connect_death_signal(body)

	_pick_best_target()

func _on_attack_zone_body_exited(body: Node2D) -> void:
	if body in candidates:
		candidates.erase(body)
	if body == target:
		_release_target()
		_pick_best_target()

# === TARGET MANAGEMENT ===
func _pick_best_target() -> void:
	var best: Node2D = null
	var best_dist: float = INF

	for goblin in candidates:
		if not is_instance_valid(goblin):
			continue
		if TargetManager.is_taken(goblin):
			continue

		var dist = global_position.distance_to(goblin.global_position)
		if dist < best_dist:
			best_dist = dist
			best = goblin

	if best == null and candidates.size() > 0:
		best = candidates[0]

	if best and best != target:
		_set_target(best)
	elif best == null:
		_release_target()

func _set_target(new_target: Node2D) -> void:
	if target != null:
		_release_target()

	target = new_target
	TargetManager.assign(target, self)
	anim.play("idle")

func _release_target() -> void:
	if target:
		TargetManager.release(target)
	target = null
	anim.play("idle")
	cooldown_timer = 0.0

func _on_target_died(dead_target: Node2D) -> void:
	if dead_target == target:
		_release_target()
		_pick_best_target()

	if dead_target in candidates:
		candidates.erase(dead_target)

# === PROCESS ===
func _physics_process(delta: float) -> void:
	# Validate target
	if target == null or not is_instance_valid(target):
		_pick_best_target()
		return

	update_facing()

	# Update timers
	tracking_timer -= delta
	cooldown_timer -= delta

	if tracking_timer <= 0.0:
		tracking_timer = tracking_interval
		_scan_for_new_targets()

	if cooldown_timer <= 0.0:
		shoot()
		cooldown_timer = fire_cooldown

# === SHOOT WITH PREDICTIVE AIM ===
func shoot() -> void:
	if target == null or not is_instance_valid(target):
		return

	anim.play("shoot")

	var arrow: Node2D = arrow_scene.instantiate()
	get_parent().add_child(arrow)
	arrow.global_position = shoot_point.global_position
	arrow.z_index = 5

	if arrow.has_method("launch"):
		shooting_arrow.play()
		var predicted_pos = _predict_target_position(target, arrow_speed)
		arrow.launch(predicted_pos, arrow_speed)

# === PREDICTIVE TARGET POSITION ===
@warning_ignore("shadowed_variable")
func _predict_target_position(target: Node2D, projectile_speed: float) -> Vector2:
	if not target.has_method("get_velocity"):
		return target.global_position

	var target_vel: Vector2 = target.get_velocity()
	var to_target: Vector2 = target.global_position - shoot_point.global_position

	var a: float = target_vel.length_squared() - projectile_speed * projectile_speed
	var b: float = 2.0 * to_target.dot(target_vel)
	var c: float = to_target.length_squared()

	var discriminant: float = b*b - 4*a*c
	if discriminant < 0.0 or abs(a) < 0.001:
		return target.global_position

	var t1 = (-b + sqrt(discriminant)) / (2*a)
	var t2 = (-b - sqrt(discriminant)) / (2*a)
	var t = max(t1, t2, 0.0)

	return target.global_position + target_vel * t

# === FACING ===
func update_facing() -> void:
	if target == null:
		return
	anim.flip_h = target.global_position.x < global_position.x

# === SCAN FOR NEW TARGETS ===
func _scan_for_new_targets() -> void:
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("goblin") and body not in candidates:
			candidates.append(body)
			_connect_death_signal(body)

func _connect_death_signal(goblin: Node2D) -> void:
	if goblin.has_signal("died") and not goblin.is_connected("died", Callable(self, "_on_target_died")):
		goblin.died.connect(Callable(self, "_on_target_died").bind(goblin))
