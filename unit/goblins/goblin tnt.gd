extends CharacterBody2D

# =================================================
# PACK SYSTEM (GLOBAL)
# =================================================
static var reserved_targets: Dictionary = {} # target -> Array[goblins]
static var goblins: Array[CharacterBody2D] = []

const MAX_GOBLINS_PER_TARGET: int = 2
const STEAL_DISTANCE: float = 80.0
const SEPARATION_RADIUS: float = 120.0
const SEPARATION_FORCE: float = 140.0
const ATTACK_DELAY := 0.4

# =================================================
# NODES
# =================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var nav: NavigationAgent2D = $NavigationAgent2D
@onready var detect_area: Area2D = $detect_area
@onready var targeter_area: Area2D = $targeter_area
@onready var hurtbox: Area2D = $hurtbox
@onready var hurt_timer: Timer = $hurt
@onready var attack_timer: Timer = $attack_timer
@onready var flash_timer: Timer = $flash
@onready var predictcast: ShapeCast2D = $PredictCast
@onready var hit_sword_audio: AudioStreamPlayer = $"sound fx/hit_sword_audio"
@onready var throw_audio: AudioStreamPlayer = $"sound fx/throw_audio"
@onready var death_audio: AudioStreamPlayer = $"sound fx/death_audio"

var attack_sound_played := false
# =================================================
# CONSTANTS / EXPORTS
# =================================================
@export var SPEED: float = 400.0
@export var STOP_DISTANCE: float = 140.0
@export var ATTACK_DISTANCE: float = 50.0
@export var KNOCKBACK_FORCE: float = 300.0
@export var KNOCKBACK_DECAY: float = 0.85
@export var PREDICTION_TIME: float = 0.3
@export var tnt_cooldown: float = 1.5

# Preload TNT and explosion scenes
static var tnt_scene = preload("res://Materiels/TNT/tnt.tscn")
static var explosion_scene = preload("res://Materiels/skull/skull.tscn")

# =================================================
# STATE MACHINE
# =================================================
enum State { IDLE, CHASE, ATTACK, HIT, DEAD }
var state: State = State.IDLE
var building_is_dead := false
# =================================================
# VARIABLES
# =================================================
var is_attacking := false

@export var health: int = 6
var knockback_velocity: Vector2 = Vector2.ZERO
var is_flashing: bool = false

var targets: Array[Node2D] = []
var current_target: Node2D = null
var directional: Vector2 = Vector2.ZERO

var tnt_timer: float = 0.0
var body_in_range

# =========================
# STUCK / AVOIDANCE
# =========================
var stuck_timer: float = 0.0
var stuck_threshold: float = 0.3       # seconds to consider stuck
var last_position: Vector2 = Vector2.ZERO


# =========================
# READY / EXIT
# =========================
func _ready() -> void:
	_physics_process(false)
	await get_tree().create_timer(0.5).timeout
	_physics_process(false)
	z_index = 3
	goblins.append(self)
	nav.path_desired_distance = 6.0
	nav.target_desired_distance = 6.0

	for p in get_tree().get_nodes_in_group("player"):
		add_target(p)



func _exit_tree() -> void:
	goblins.erase(self)
	release_target()
	rebalance_pack()
	cleanup_reserved_targets()

# =================================================
# TARGET SYSTEM
# =================================================
func add_target(t: Node2D) -> void:
	if not is_instance_valid(t):
		return
	if not targets.has(t):
		targets.append(t)
	choose_best_target()

func remove_target(t: Node2D) -> void:
	targets.erase(t)
	if current_target == t:
		release_target()
		choose_best_target()

func choose_best_target() -> void:
	var best_target: Node2D = null
	var best_dist: float = INF
	for t in targets:
		if not is_instance_valid(t):
			continue
		var d: float = global_position.distance_to(t.global_position)
		@warning_ignore("shadowed_variable")
		var attackers: Array = reserved_targets.get(t, [])
		if attackers.size() < MAX_GOBLINS_PER_TARGET:
			if d < best_dist:
				best_dist = d
				best_target = t
		else:
			for g in attackers:
				if not is_instance_valid(g):
					continue
				if d + STEAL_DISTANCE < g.global_position.distance_to(t.global_position):
					best_target = t
					best_dist = d
	assign_target(best_target)

func assign_target(t: Node2D) -> void:
	if current_target == t:
		return

	release_target()

	if t != null:
		if not reserved_targets.has(t):
			reserved_targets[t] = []

		reserved_targets[t].append(self)
		current_target = t
		state = State.CHASE
		building_is_dead = false

		# 🔥 CONNECT BUILDING DEATH SIGNAL
		if t.is_in_group("building") and t.has_signal("died"):
			t.died.connect(_on_building_died.bind(t))
	else:
		state = State.IDLE


func release_target() -> void:
	if current_target == null:
		return
	if reserved_targets.has(current_target):
		reserved_targets[current_target].erase(self)
		if reserved_targets[current_target].is_empty():
			reserved_targets.erase(current_target)
	current_target = null

func rebalance_pack() -> void:
	for g in goblins:
		if g == self:
			continue
		if is_instance_valid(g) and g.state != State.DEAD:
			g.choose_best_target()

func cleanup_reserved_targets() -> void:
	for target in reserved_targets.keys():
		reserved_targets[target] = reserved_targets[target].filter(is_instance_valid)
		if reserved_targets[target].is_empty():
			reserved_targets.erase(target)

func validate_target() -> bool:
	if not is_instance_valid(current_target):
		release_target()
		state = State.IDLE
		choose_best_target()
		return false
	return true

# =================================================
# PHYSICS / AI LOOP
# =================================================
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	tnt_timer = max(0.0, tnt_timer - delta)

	if knockback_velocity.length() > 1:
		velocity = knockback_velocity
		knockback_velocity *= KNOCKBACK_DECAY
	else:
		knockback_velocity = Vector2.ZERO

	if state == State.IDLE:
		recheck_players()
	if state == State.ATTACK:
		recheck_players()

	validate_target()

	match state:
		State.IDLE: idle_state()
		State.CHASE: chase_state()
		State.ATTACK: attack_state()
		State.HIT: hit_state()
# --- STUCK DETECTION ---
	if state in [State.CHASE, State.IDLE]:
		detect_stuck(delta)

	move_and_slide()
	avoid_obstacles(delta)


# =================================================
# STATES
# =================================================
func idle_state() -> void:
	anim.play("idle")
	velocity = separation_vector() * SEPARATION_FORCE

func chase_state() -> void:
	var dist := global_position.distance_to(current_target.global_position)
	if not validate_target():
		return
	var distance_to_target: float = global_position.distance_to(current_target.global_position)
	if distance_to_target <= STOP_DISTANCE:
		state = State.ATTACK
		return
	if dist <= ATTACK_DISTANCE and not is_attacking:
		is_attacking = true
		state = State.ATTACK
		attack_timer.start(ATTACK_DELAY)
		return

	nav.target_position = current_target.global_position
	var next_point: Vector2 = nav.get_next_path_position()
	var dir: Vector2 = (next_point - global_position).normalized()
	directional = dir
	velocity = dir * SPEED
	anim.flip_h = dir.x < 0
	anim.play("run")

func attack_state() -> void:
	if building_is_dead:
		state = State.IDLE
		choose_best_target()
		return

	velocity = Vector2.ZERO
	anim.play("attack")
	if tnt_timer <= 0:
		var target_velocity: Vector2 = Vector2.ZERO
		if current_target.has_method("velocity"):
			target_velocity = current_target.velocity
		var predicted_pos: Vector2 = current_target.global_position + target_velocity * PREDICTION_TIME
		if body_in_range==true and not building_is_dead==true:
			throw_tnt(predicted_pos)
		tnt_timer = tnt_cooldown

	# Wait safely with validity check
	await get_tree().create_timer(0.2).timeout
	if state != State.DEAD:
		validate_target()
		if state != State.ATTACK:
			state = State.CHASE

func _on_attack_timeout() -> void:
	if not validate_target():
		exit_attack()
		return

	# 🔊 PLAY SOUND ONCE
	throw_audio.play()

	# 💣 DO DAMAGE / THROW TNT ONCE
	do_attack()

	exit_attack()
	state = State.CHASE


func hit_state() -> void:
	if health <= 0:
		explode()

# =================================================
# SEPARATION
# =================================================
func separation_vector() -> Vector2:
	var force: Vector2 = Vector2.ZERO
	for g in goblins:
		if g == self or not is_instance_valid(g):
			continue
		var dist: float = global_position.distance_to(g.global_position)
		if dist > 0 and dist < SEPARATION_RADIUS:
			force += (global_position - g.global_position).normalized() * (1.0 - dist / SEPARATION_RADIUS)
	return force.normalized() if force.length() > 0 else Vector2.ZERO

# =================================================
# DAMAGE
# =========================f========================
func take_damage(damage: int, source_position: Vector2) -> void:
	if state == State.DEAD:
		return
	health -= damage
	if not hit_sword_audio.playing:
		hit_sword_audio.play()

	knockback_velocity = (global_position - source_position).normalized() * KNOCKBACK_FORCE
	state = State.HIT
	start_flashing()
	hurt_timer.start(0.3)

	if health <= 0:
		explode()

func start_flashing() -> void:
	if is_flashing:
		return
	is_flashing = true
	flash_timer.start(0.1)
	var t = create_tween()
	t.tween_property(anim, "modulate", Color.RED, 0.05)
	t.tween_property(anim, "modulate", Color.WHITE, 0.05)
	t.set_loops(3)

# =================================================
# SIGNALS
# =================================================
func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("attackeffect") or area.is_in_group("arrow"):
		take_damage(1, area.global_position)
		area.queue_free()

func _on_hurt_timeout() -> void:
	state = State.CHASE

func _on_flash_timeout() -> void:
	is_flashing = false
	anim.modulate = Color.WHITE

func _on_detect_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.is_in_group("castle") or body.is_in_group("building"):
		if body.has_method("is_destroyed"):
			if body.is_destroyed():
				return # skip destroyed buildings
		add_target(body)
		body_in_range = true

func _on_detect_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.is_in_group("castle") or body.is_in_group("building"):
		remove_target(body)
		body_in_range = false

func _on_targeter_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.is_in_group("castle") or body.is_in_group("building"):
		if body.has_method("is_destroyed"):
			if body.is_destroyed():
				return
		add_target(body)

func _on_targeter_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.is_in_group("castle") or body.is_in_group("building"):
		remove_target(body)



# =================================================
# OBSTACLE AVOIDANCE
# =================================================
const DETOUR_DISTANCE: float = 60.0
@warning_ignore("unused_parameter")
func avoid_obstacles(delta: float) -> void:
	if not predictcast.is_enabled():
		predictcast.enabled = true

	# Point ShapeCast in movement direction
	if velocity.length() > 0:
		predictcast.global_rotation = velocity.angle()
		predictcast.force_update_transform()

		if predictcast.is_colliding():
			var n: Vector2 = predictcast.get_collision_normal(0)
			var slide_dir: Vector2 = velocity - n * velocity.dot(n)

			if slide_dir.length() < 0.1:
				slide_dir = Vector2(-n.y, n.x) * DETOUR_DISTANCE

			velocity = slide_dir.normalized() * SPEED




# =================================================
# TNT THROW
# =================================================
func throw_tnt(target_pos: Vector2) -> void:
	if state == State.DEAD:
		return
	var tnt = tnt_scene.instantiate()
	get_parent().add_child(tnt)
	tnt.scale = Vector2(0.6, 0.6)
	tnt.throw(global_position, target_pos)

# =================================================
# SMART RECHECK
# =================================================
func recheck_players() -> void:
	for p in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("castle") + get_tree().get_nodes_in_group("castle"):
		if is_instance_valid(p):
			add_target(p)
	for p in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(p):
			add_target(p)


# =================================================
# EXPLOSION / DEATH
# =================================================
func explode() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	release_target()
	rebalance_pack()
	cleanup_reserved_targets()
	
		# --- SAFE AUDIO DETACH ---
	if not death_audio.playing:
		death_audio.play()

	var e = explosion_scene.instantiate()
	get_parent().add_child(e)
	e.global_position = global_position
	e.scale = Vector2(0.5, 0.5)
	e.z_index = 5
	play_death_sound()
	queue_free()



func detect_stuck(delta: float) -> void:
	if last_position.distance_to(global_position) < 1.0:
		stuck_timer += delta
	else:
		stuck_timer = 0.0

	last_position = global_position

	if stuck_timer > stuck_threshold:
		# Try unstuck
		unstuck()

func unstuck() -> void:
	# Rotate velocity by 90 degrees to try detouring
	velocity = Vector2(-velocity.y, velocity.x).normalized() * SPEED
	stuck_timer = 0.0



var attackers: Array = []

func can_accept_attacker() -> bool:
	return attackers.size() < 2

func add_attacker(knight):
	if knight not in attackers:
		attackers.append(knight)

func remove_attacker(knight):
	attackers.erase(knight)

func set_target(building: Node2D) -> void:
	building.died.connect(_on_building_died)
func _on_building_died(building: Node2D) -> void:
	if building != current_target:
		return

	building_is_dead = true

	# 🚫 STOP ATTACKING
	release_target()
	targets.erase(building)

	state = State.IDLE
	choose_best_target()

func exit_attack():
	is_attacking = false
	attack_sound_played = false

func do_attack():
	if tnt_timer > 0.0:
		return

	var target_velocity := Vector2.ZERO
	if current_target is CharacterBody2D:
		target_velocity = current_target.velocity

	var predicted := current_target.global_position + target_velocity * PREDICTION_TIME
	throw_tnt(predicted)
	tnt_timer = tnt_cooldown

func play_death_sound():
	var s := AudioStreamPlayer2D.new()
	s.stream = death_audio.stream
	s.global_position = global_position
	get_parent().add_child(s)
	s.play()
	s.finished.connect(s.queue_free)
