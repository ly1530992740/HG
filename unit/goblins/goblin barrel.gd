extends CharacterBody2D

# =================================================
# PACK SYSTEM (GLOBAL, SHARED)
# =================================================
static var reserved_targets: Dictionary = {}   # target -> Array[CharacterBody2D]
static var goblins: Array[CharacterBody2D] = []

const MAX_GOBLINS_PER_TARGET: int = 4
const STEAL_DISTANCE: float = 80.0
const SEPARATION_RADIUS: float = 120.0
const SEPARATION_FORCE: float = 140.0

# =========================
# NODES
# =========================
@onready var anim: AnimatedSprite2D = $anim
@onready var nav: NavigationAgent2D = $NavigationAgent2D
@onready var detect_area: Area2D = $detect_area
@onready var hurtbox: Area2D = $hurtbox
@onready var hurt_timer: Timer = $hurt
@onready var flash_timer: Timer = $flash
@onready var targeter_area: Area2D = $targeter_area
@onready var predictcast: ShapeCast2D = $PredictCast
@onready var hit_attackfx: AudioStreamPlayer = $"sound fx/hit_attackfx"


# =========================
# CONSTANTS
# =========================
@export var SPEED: float = 500.0
const ATTACK_DISTANCE: float = 40.0
const KNOCKBACK_FORCE: float = 300.0
const KNOCKBACK_DECAY: float = 0.85
const DETOUR_DISTANCE: float = 60.0

# =========================
# STATE MACHINE
# =========================
enum State { IDLE, CHASE, ATTACK, HIT, DEAD }
var state: State = State.IDLE

# =========================
# VARIABLES
# =========================
@export var health: int = 3
var knockback_velocity: Vector2 = Vector2.ZERO
var is_flashing: bool = false

var targets: Array[Node2D] = []
var current_target: Node2D = null
var exploded: bool = false   # To prevent double explosions

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
	z_index = 3
	goblins.append(self)

	nav.path_desired_distance = 6.0
	nav.target_desired_distance = 6.0

	# Add all players initially
	for p in get_tree().get_nodes_in_group("player"):
		add_target(p)


func _exit_tree() -> void:
	goblins.erase(self)
	release_target()
	rebalance_pack()

# =================================================
# TARGET / PACK LOGIC
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

	# Step 1: try player targets
	for t in targets:
		if not is_instance_valid(t):
			continue

		@warning_ignore("shadowed_variable")
		var attackers: Array = reserved_targets.get(t, [])
		var d: float = global_position.distance_to(t.global_position)

		if attackers.size() < MAX_GOBLINS_PER_TARGET:
			if d < best_dist:
				best_dist = d
				best_target = t
		else:
			for g in attackers:
				if not is_instance_valid(g):
					continue
				if d + STEAL_DISTANCE < g.global_position.distance_to(t.global_position):
					best_dist = d
					best_target = t
					break

	# Step 2: fallback to castles if no player targets exist
	if best_target == null or targets.is_empty():
		var castles: Array = get_tree().get_nodes_in_group("castle")
		if castles.size() > 0:
			best_target = castles[-1]  # last castle in group
			if not targets.has(best_target):
				targets.append(best_target)

	# Step 3: if no castle, explode
	if best_target == null:
		explode()
		return

	assign_target(best_target)

func assign_target(t: Node2D) -> void:
	if current_target == t:
		return

	release_target()

	if t != null:
		if not reserved_targets.has(t):
			reserved_targets[t] = []
		var arr: Array = reserved_targets[t] as Array
		arr.append(self)
		reserved_targets[t] = arr

		current_target = t
		state = State.CHASE
	else:
		state = State.IDLE

func release_target() -> void:
	if current_target == null:
		return

	if reserved_targets.has(current_target):
		var arr: Array = reserved_targets[current_target] as Array
		arr.erase(self)
		if arr.is_empty():
			reserved_targets.erase(current_target)
		else:
			reserved_targets[current_target] = arr

	current_target = null

func rebalance_pack() -> void:
	for g in goblins:
		if g == self:
			continue
		if is_instance_valid(g) and g.state != State.DEAD:
			g.choose_best_target()

func validate_target() -> bool:
	if current_target == null:
		state = State.IDLE
		return false

	if not is_instance_valid(current_target):
		release_target()
		state = State.IDLE
		return false

	return true

# =================================================
# MAIN LOOP
# =================================================
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Apply knockback decay
	if knockback_velocity.length() > 1:
		velocity = knockback_velocity
		knockback_velocity *= KNOCKBACK_DECAY

	validate_target()

	match state:
		State.IDLE:
			if targets.is_empty():
				explode()
				return
			idle_state()
		State.CHASE:
			chase_state()
		State.ATTACK:
			attack_state()
		State.HIT:
			hit_state()

	# Combine separation and movement with knockback
	if state in [State.IDLE, State.CHASE]:
		velocity += separation_vector() * SEPARATION_FORCE

	avoid_obstacles(delta)
	
# --- STUCK DETECTION ---
	if state in [State.CHASE, State.IDLE]:
		detect_stuck(delta)

	move_and_slide()

# =================================================
# STATES
# =================================================
func idle_state() -> void:
	anim.play("idle")

func chase_state() -> void:
	if not validate_target():
		return

	nav.target_position = current_target.global_position
	var next_point: Vector2 = nav.get_next_path_position()
	var dir: Vector2 = (next_point - global_position).normalized()

	velocity = dir * SPEED
	anim.flip_h = dir.x < 0
	anim.play("run")

	if global_position.distance_to(current_target.global_position) <= ATTACK_DISTANCE:
		state = State.ATTACK

func attack_state() -> void:
	if state == State.DEAD:
		return

	velocity = Vector2.ZERO
	anim.play("attack")
	anim.animation_finished.connect(_on_attack_finished)

func _on_attack_finished() -> void:
	if anim.animation_finished.is_connected(_on_attack_finished):
		anim.animation_finished.disconnect(_on_attack_finished)
	state = State.CHASE if current_target else State.IDLE

func hit_state() -> void:
	anim.play("hit" if anim.sprite_frames.has_animation("hit") else "idle")
	hurt_timer.start(0.3)

	if health <= 0:
		explode()
	else:
		state = State.CHASE if current_target else State.IDLE

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
# =================================================
func take_damage(damage: int, source_position: Vector2) -> void:
	if state == State.DEAD:
		return

	health -= damage
	if not hit_attackfx.playing:
		hit_attackfx.play()
	knockback_velocity = (global_position - source_position).normalized() * KNOCKBACK_FORCE
	state = State.HIT
	start_flashing()
	hurt_timer.start(0.3)

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
# HURTBOX
# =================================================
func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("attackeffect") or area.is_in_group("arrow"):
		take_damage(1, area.global_position)
		area.queue_free()

# =================================================
# TIMERS
# =================================================
func _on_hurt_timeout() -> void:
	knockback_velocity = Vector2.ZERO

func _on_flash_timeout() -> void:
	is_flashing = false
	anim.modulate = Color.WHITE

# =================================================
# DETECT AREA (EXPLOSION)
# =================================================
func _on_detect_area_body_entered(body: Node2D) -> void:
	if exploded:
		return
	if body.is_in_group("player"):
		add_target(body)
		var t = Timer.new()
		t.one_shot = true
		t.wait_time = 0.2
		add_child(t)
		t.timeout.connect(func() -> void:
			t.queue_free()
			explode()
		)
		t.start()

func _on_detect_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		remove_target(body)

# =================================================
# TARGETER AREA
# =================================================
func _on_targeter_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	if current_target == null:
		add_target(body)
		return

	var current_dist: float = global_position.distance_to(current_target.global_position)
	var new_dist: float = global_position.distance_to(body.global_position)

	if new_dist + STEAL_DISTANCE < current_dist:
		add_target(body)

func _on_targeter_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		remove_target(body)

# =================================================
# OBSTACLE AVOIDANCE
# =================================================
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
# EXPLOSION / DEATH
# =================================================
func explode() -> void:
	if state == State.DEAD or exploded:
		return

	exploded = true
	state = State.DEAD
	release_target()
	rebalance_pack()

	var e = preload("res://Materiels/explosion/explosion.tscn").instantiate()
	get_parent().add_child(e)
	e.global_position = global_position
	e.scale = Vector2(1.5, 1.5)
	e.z_index = 5

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
