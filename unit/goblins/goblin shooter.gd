extends "res://unit/goblins/goblin_base.gd"

@export var detect_range := 420.0
@export var attack_range := 330.0
@export var keep_distance := 230.0
@export var fire_cooldown := 0.85
@export var projectile_damage := 1
@export var projectile_speed := 1000.0
@export var projectile_lifetime := 0.7
@export var spread_degrees := 4.0
@export var hit_groups: Array[String] = ["player", "pawn"]

const PROJECTILE_SCENE := preload("res://weapons/enemy_bullet.tscn")

var target: Node2D = null
var fire_timer := 0.0
var hp_bar: ProgressBar
var body_visual: Polygon2D
var gun_visual: Polygon2D
var muzzle: Marker2D

func _ready() -> void:
	max_health = 8
	SPEED = 220.0
	STOP_DISTANCE = keep_distance
	ATTACK_DISTANCE = attack_range
	target_groups = []
	super._ready()

	if anim:
		anim.visible = false

	_setup_visual()
	_setup_hp_bar()
	_find_player_target()

func _physics_process(delta: float) -> void:
	fire_timer = max(0.0, fire_timer - delta)
	_find_player_target()
	_update_ai_state()
	super._physics_process(delta)
	_update_visual()
	_update_hp_bar()

func _find_player_target() -> void:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node2D and is_instance_valid(node):
			var dist := global_position.distance_to(node.global_position)
			if dist < best_dist and dist <= detect_range:
				best = node
				best_dist = dist
	target = best
	current_target = target

func _update_ai_state() -> void:
	if state == State.DEAD or state == State.HIT:
		return

	if target == null:
		state = State.IDLE
		return

	var distance := global_position.distance_to(target.global_position)
	if distance <= attack_range:
		state = State.ATTACK
	elif distance <= detect_range:
		state = State.CHASE
	else:
		state = State.IDLE

func chase_state() -> void:
	if target == null:
		velocity = Vector2.ZERO
		return

	var to_target := target.global_position - global_position
	var distance := to_target.length()
	if distance <= keep_distance:
		velocity = Vector2.ZERO
		return

	if nav:
		nav.target_position = target.global_position
		var next_point := nav.get_next_path_position()
		velocity = (next_point - global_position).normalized() * SPEED
	else:
		velocity = to_target.normalized() * SPEED

func attack_state() -> void:
	if target == null:
		velocity = Vector2.ZERO
		return

	var to_target := target.global_position - global_position
	var distance := to_target.length()

	if distance < keep_distance * 0.75:
		velocity = -to_target.normalized() * SPEED * 0.65
	elif distance > attack_range * 0.9:
		velocity = to_target.normalized() * SPEED * 0.5
	else:
		velocity = Vector2.ZERO

	if fire_timer <= 0.0:
		_fire_bullet_at(target.global_position)
		fire_timer = fire_cooldown

func _fire_bullet_at(target_position: Vector2) -> void:
	if not is_inside_tree():
		return

	var origin := muzzle.global_position if muzzle else global_position
	var direction := (target_position - origin).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	var spread := deg_to_rad(spread_degrees)
	direction = direction.rotated(randf_range(-spread, spread)).normalized()

	var projectile := PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin

	if projectile.has_method("launch"):
		projectile.launch({
			"direction": direction,
			"speed": projectile_speed,
			"damage": projectile_damage,
			"lifetime": projectile_lifetime,
			"shooter": self,
			"hit_groups": hit_groups,
			"knockback": 0.0
		})

func _setup_visual() -> void:
	body_visual = Polygon2D.new()
	body_visual.name = "VisualBody"
	body_visual.color = Color(0.72, 0.16, 0.16, 1.0)
	body_visual.polygon = PackedVector2Array([
		Vector2(0, -22), Vector2(16, -8), Vector2(15, 14),
		Vector2(0, 23), Vector2(-15, 14), Vector2(-16, -8)
	])
	body_visual.z_index = 4
	add_child(body_visual)

	gun_visual = Polygon2D.new()
	gun_visual.name = "VisualGun"
	gun_visual.color = Color(0.25, 0.25, 0.25, 1.0)
	gun_visual.polygon = PackedVector2Array([
		Vector2(0, -3), Vector2(32, -3), Vector2(32, 3), Vector2(0, 3)
	])
	gun_visual.z_index = 5
	add_child(gun_visual)

	muzzle = Marker2D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector2(34, 0)
	add_child(muzzle)

func _update_visual() -> void:
	if target == null or body_visual == null or gun_visual == null or muzzle == null:
		return

	var dir := target.global_position - global_position
	var facing := -1.0 if dir.x < 0.0 else 1.0
	body_visual.scale.x = facing
	gun_visual.scale.x = facing
	gun_visual.position.x = 0.0 if facing > 0.0 else -32.0
	muzzle.position.x = 34.0 if facing > 0.0 else -34.0

func _setup_hp_bar() -> void:
	hp_bar = ProgressBar.new()
	hp_bar.name = "EnemyHPBar"
	hp_bar.max_value = max_health
	hp_bar.value = health
	hp_bar.show_percentage = false
	hp_bar.position = Vector2(-28, -48)
	hp_bar.size = Vector2(56, 8)
	hp_bar.z_index = 10
	add_child(hp_bar)

func _update_hp_bar() -> void:
	if hp_bar == null or not is_instance_valid(hp_bar):
		return
	hp_bar.max_value = max_health
	hp_bar.value = health
	hp_bar.visible = health > 0

func start_flashing() -> void:
	if body_visual == null:
		super.start_flashing()
		return
	body_visual.color = Color(1.0, 0.25, 0.15, 1.0)
	var tween := create_tween()
	tween.tween_property(body_visual, "color", Color(0.72, 0.16, 0.16, 1.0), 0.12)
