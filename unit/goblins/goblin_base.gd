extends CharacterBody2D
class_name GoblinBase

enum State { IDLE, CHASE, ATTACK, HIT, DEAD }

static var reserved_targets: Dictionary = {}
static var active_enemies: Array[CharacterBody2D] = []

const MAX_ATTACKERS_PER_TARGET := 2
const STEAL_DISTANCE := 80.0
const SEPARATION_RADIUS := 120.0
const SEPARATION_FORCE := 140.0
const DETOUR_DISTANCE := 60.0

@export var max_health := 6
@export var health := 6
@export var SPEED := 220.0
@export var STOP_DISTANCE := 130.0
@export var ATTACK_DISTANCE := 80.0
@export var KNOCKBACK_FORCE := 300.0
@export var KNOCKBACK_DECAY := 0.85
@export var target_groups: Array[String] = ["player", "castle", "building"]

@onready var anim: AnimatedSprite2D = get_node_or_null("anim")
@onready var nav: NavigationAgent2D = get_node_or_null("NavigationAgent2D")
@onready var hurt_timer: Timer = get_node_or_null("hurt")
@onready var flash_timer: Timer = get_node_or_null("flash")
@onready var predictcast: ShapeCast2D = get_node_or_null("PredictCast")
@onready var hit_audio: AudioStreamPlayer = get_node_or_null("sound fx/hit_sword_audio")
@onready var death_audio: AudioStreamPlayer = get_node_or_null("sound fx/death_audio")

var state: State = State.IDLE
var knockback_velocity := Vector2.ZERO
var is_flashing := false
var targets: Array[Node2D] = []
var current_target: Node2D = null
var last_move_dir := Vector2.DOWN
var stuck_timer := 0.0
var stuck_threshold := 0.3
var last_position := Vector2.ZERO

func _ready() -> void:
	z_index = 3
	add_to_group("goblin")
	health = max_health
	active_enemies.append(self)

	if nav:
		nav.path_desired_distance = 6.0
		nav.target_desired_distance = 6.0

	recheck_targets()

func _exit_tree() -> void:
	active_enemies.erase(self)
	release_target()
	rebalance_pack()
	cleanup_reserved_targets()

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if knockback_velocity.length() > 1.0:
		velocity = knockback_velocity
		knockback_velocity *= KNOCKBACK_DECAY
	else:
		knockback_velocity = Vector2.ZERO

	if state == State.IDLE or state == State.ATTACK:
		recheck_targets()

	validate_target()

	match state:
		State.IDLE:
			idle_state()
		State.CHASE:
			chase_state()
		State.ATTACK:
			attack_state()
		State.HIT:
			hit_state()

	if state in [State.IDLE, State.CHASE]:
		velocity += separation_vector() * SEPARATION_FORCE
		detect_stuck(delta)

	avoid_obstacles(delta)
	move_and_slide()

func idle_state() -> void:
	velocity = Vector2.ZERO
	if anim:
		anim.play("idle")

func chase_state() -> void:
	if not validate_target():
		return

	var distance_to_target := global_position.distance_to(current_target.global_position)
	if distance_to_target <= STOP_DISTANCE or distance_to_target <= ATTACK_DISTANCE:
		state = State.ATTACK
		return

	var direction := (current_target.global_position - global_position).normalized()
	if nav:
		nav.target_position = current_target.global_position
		var next_point := nav.get_next_path_position()
		direction = (next_point - global_position).normalized()

	last_move_dir = direction
	velocity = direction * SPEED

	if anim:
		anim.flip_h = direction.x < 0.0
		anim.play("run")

func attack_state() -> void:
	velocity = Vector2.ZERO
	state = State.CHASE if current_target else State.IDLE

func hit_state() -> void:
	if health <= 0:
		die()
		return

	state = State.CHASE if current_target else State.IDLE

func add_target(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if not targets.has(target):
		targets.append(target)
	choose_best_target()

func remove_target(target: Node2D) -> void:
	targets.erase(target)
	if current_target == target:
		release_target()
		choose_best_target()

func choose_best_target() -> void:
	var best_target: Node2D = null
	var best_dist := INF

	for target in targets:
		if not is_instance_valid(target):
			continue

		var attackers: Array = reserved_targets.get(target, [])
		var distance := global_position.distance_to(target.global_position)

		if attackers.size() < MAX_ATTACKERS_PER_TARGET:
			if distance < best_dist:
				best_dist = distance
				best_target = target
		else:
			for enemy in attackers:
				if is_instance_valid(enemy) and distance + STEAL_DISTANCE < enemy.global_position.distance_to(target.global_position):
					best_dist = distance
					best_target = target
					break

	assign_target(best_target)

func assign_target(target: Node2D) -> void:
	if current_target == target:
		return

	release_target()

	if target == null:
		state = State.IDLE
		return

	if not reserved_targets.has(target):
		reserved_targets[target] = []
	reserved_targets[target].append(self)
	current_target = target
	state = State.CHASE

func release_target() -> void:
	if current_target == null:
		return

	if reserved_targets.has(current_target):
		reserved_targets[current_target].erase(self)
		if reserved_targets[current_target].is_empty():
			reserved_targets.erase(current_target)

	current_target = null

func rebalance_pack() -> void:
	for enemy in active_enemies:
		if enemy == self:
			continue
		if is_instance_valid(enemy) and enemy.has_method("choose_best_target"):
			enemy.choose_best_target()

func cleanup_reserved_targets() -> void:
	for target in reserved_targets.keys():
		reserved_targets[target] = reserved_targets[target].filter(is_instance_valid)
		if reserved_targets[target].is_empty():
			reserved_targets.erase(target)

func validate_target() -> bool:
	if current_target == null:
		state = State.IDLE
		return false

	if not is_instance_valid(current_target):
		release_target()
		state = State.IDLE
		choose_best_target()
		return false

	return true

func recheck_targets() -> void:
	for group_name in target_groups:
		for target in get_tree().get_nodes_in_group(group_name):
			if target is Node2D:
				add_target(target)

func separation_vector() -> Vector2:
	var force := Vector2.ZERO
	for enemy in active_enemies:
		if enemy == self or not is_instance_valid(enemy):
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance > 0.0 and distance < SEPARATION_RADIUS:
			force += (global_position - enemy.global_position).normalized() * (1.0 - distance / SEPARATION_RADIUS)
	return force.normalized() if force.length() > 0.0 else Vector2.ZERO

func take_damage(damage: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEAD:
		return

	health = max(0, health - damage)

	if hit_audio and not hit_audio.playing:
		hit_audio.play()

	if source_position != Vector2.ZERO:
		var away := global_position - source_position
		if away != Vector2.ZERO:
			knockback_velocity = away.normalized() * KNOCKBACK_FORCE

	state = State.HIT
	start_flashing()
	if hurt_timer:
		hurt_timer.start(0.3)

	if health <= 0:
		die()

func start_flashing() -> void:
	if is_flashing or anim == null:
		return

	is_flashing = true
	if flash_timer:
		flash_timer.start(0.1)

	var tween := create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.05)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.05)
	tween.set_loops(3)

func die() -> void:
	if state == State.DEAD:
		return

	state = State.DEAD
	release_target()
	rebalance_pack()
	cleanup_reserved_targets()

	if death_audio and not death_audio.playing:
		death_audio.play()

	queue_free()

func avoid_obstacles(_delta: float) -> void:
	if predictcast == null:
		return

	if not predictcast.is_enabled():
		predictcast.enabled = true

	if velocity.length() <= 0.0:
		return

	predictcast.global_rotation = velocity.angle()
	predictcast.force_update_transform()

	if predictcast.is_colliding():
		var normal := predictcast.get_collision_normal(0)
		var slide_dir := velocity - normal * velocity.dot(normal)
		if slide_dir.length() < 0.1:
			slide_dir = Vector2(-normal.y, normal.x) * DETOUR_DISTANCE
		velocity = slide_dir.normalized() * SPEED

func detect_stuck(delta: float) -> void:
	if last_position.distance_to(global_position) < 1.0:
		stuck_timer += delta
	else:
		stuck_timer = 0.0

	last_position = global_position

	if stuck_timer > stuck_threshold:
		unstuck()

func unstuck() -> void:
	if velocity != Vector2.ZERO:
		velocity = Vector2(-velocity.y, velocity.x).normalized() * SPEED
	stuck_timer = 0.0

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("attackeffect") or area.is_in_group("arrow"):
		take_damage(1, area.global_position)
		area.queue_free()

func _on_hurt_timeout() -> void:
	knockback_velocity = Vector2.ZERO
	if state != State.DEAD:
		state = State.CHASE if current_target else State.IDLE

func _on_flash_timeout() -> void:
	is_flashing = false
	if anim:
		anim.modulate = Color.WHITE

func _on_detect_area_body_entered(body: Node2D) -> void:
	if _is_valid_target_body(body):
		add_target(body)

func _on_detect_area_body_exited(body: Node2D) -> void:
	if _is_valid_target_body(body):
		remove_target(body)

func _on_targeter_area_body_entered(body: Node2D) -> void:
	if _is_valid_target_body(body):
		add_target(body)

func _on_targeter_area_body_exited(body: Node2D) -> void:
	if _is_valid_target_body(body):
		remove_target(body)

func _is_valid_target_body(body: Node2D) -> bool:
	for group_name in target_groups:
		if body.is_in_group(group_name):
			if body.has_method("is_destroyed") and body.is_destroyed():
				return false
			return true
	return false
