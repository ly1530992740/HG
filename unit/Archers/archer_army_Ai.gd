extends CharacterBody2D

# =====================================================
# NODES
# =====================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var shape: CollisionShape2D = $shape
@onready var detector_zone: Area2D = $"dectector zone"
@onready var hitbox: Area2D = $hitbox
@onready var hp_bar: ProgressBar = $ProgressBar
@onready var shieldbar: ProgressBar = $shieldbar
@onready var button: Button = $Button
@onready var select_indicator: Label = $"select indicator"
@onready var nav: NavigationAgent2D = $NavigationAgent2D
@onready var shoot_point: Marker2D = $ShootPoint
@onready var avoid_cast: ShapeCast2D = $PredictCast

@onready var shooting_arrow: AudioStreamPlayer = $ShootingArrow
@onready var click_audio: AudioStreamPlayer = $"sound fx/click_audio"
@onready var death_audio: AudioStreamPlayer = $"sound fx/death_audio"
@onready var hit_audio: AudioStreamPlayer = $"sound fx/hit_audio"
@onready var shield_audio: AudioStreamPlayer = $"sound fx/shield_audio"

# =====================================================
# UI VISIBILITY (HP / SHIELD)
# =====================================================
var ui_visible := false
var ui_hide_delay := 1.5   # seconds without damage
var ui_timer := 0.0

# =====================================================
# RANDOM SHIELD
# =====================================================
var random_shield_enabled := true  # Can be toggled
const MIN_RANDOM_SHIELD_TIME := 3.0
const MAX_RANDOM_SHIELD_TIME := 8.0
var random_shield_timer := 0.0
var next_shield_time := 0.0

# Also add to take_damage to activate shield when health is low
const LOW_HP_SHIELD_THRESHOLD := 0.3  # 30% health

# =====================================================
# STATES
# =====================================================
enum State { IDLE, RUN, ATTACK, GUARD, DEAD }
var state: State = State.IDLE

# =====================================================
# STUCK & AVOIDANCE (BOOSTED)
# =====================================================
var last_position: Vector2
var stuck_timer := 0.0

const STUCK_TIME := 0.18      # was 0.4 → reacts faster
const MIN_MOVE_DIST := 5.0   # was 2.0 → detects stuck earlier

var avoiding := false
var avoid_dir := Vector2.ZERO

const AVOID_FORCE := 1.4     # was 0.6 → stronger side push

const ALLY_PUSH_RADIUS := 10.0
const ALLY_PUSH_FORCE := 900.0
const STUCK_PULSE_FORCE := 1200.0

#==================================
# target locker
#===================================
var target_lock_time := 0.0
const TARGET_LOCK_DURATION := 0.6

# =====================================================
# STATS
# =====================================================
@export var max_life := 200
@export var life := 200

@export var max_guard := 50
@export var guard_stamina := 50

@export var speed := 600.0
@export var attack_damage := 15
@export var attack_cooldown := 1.0

# =====================================================
# CONTROL
# =====================================================
var selected := false
var stop_distance := 60.0

# =====================================================
# COMBAT
# =====================================================
var target: Node2D = null
var action_locked := false
var facing_dir := Vector2.RIGHT

# Guard
const GUARD_DURATION := 1.5
var guard_timer := 0.0
var guard_locked := false
var knockback_force := 180.0
var guard_knockback_multiplier := 0.4
var guard_cooldown := false
const GUARD_COOLDOWN_TIME := 2.5

var manual_mode := false


# Projectile
var arrow_scene = preload("res://Archers/arrow.tscn") # <-- Replace with your arrow scene
var attack_timer: Timer
var target_check_timer: Timer  # New: Timer for periodic target validation

# =====================================================
# READY
# =====================================================
func _ready():
	z_index = 4
	scale = Vector2(0.7, 0.7)
	add_to_group("selectable")
	hp_bar.visible = false
	shieldbar.visible = false

	hp_bar.max_value = max_life
	shieldbar.max_value = max_guard
	update_bars()

	select_indicator.visible = false


	nav.avoidance_enabled = true
	nav.max_speed = speed
	nav.velocity_computed.connect(_on_nav_velocity)
	last_position = global_position

	# Improve avoidance prediction
	nav.path_desired_distance = 6.0
	nav.target_desired_distance = stop_distance
	nav.avoidance_enabled = true
	nav.radius = 12
	nav.neighbor_distance = 50
	nav.max_neighbors = 10
	
	# Initialize random shield timer
	reset_random_shield_timer()

	# Attack Timer
	attack_timer = Timer.new()
	add_child(attack_timer)
	attack_timer.wait_time = attack_cooldown
	attack_timer.one_shot = false
	attack_timer.autostart = false
	attack_timer.connect("timeout", Callable(self, "_on_attack_timer_timeout"))
	
	# Target Check Timer - NEW: For periodic target validation
	target_check_timer = Timer.new()
	add_child(target_check_timer)
	target_check_timer.wait_time = 0.3  # Check every 0.3 seconds
	target_check_timer.one_shot = false
	target_check_timer.autostart = true
	target_check_timer.connect("timeout", Callable(self, "_check_current_target"))

func reset_random_shield_timer():
	random_shield_timer = 0.0
	next_shield_time = randf_range(MIN_RANDOM_SHIELD_TIME, MAX_RANDOM_SHIELD_TIME)

# =====================================================
# SIMPLE TARGET VALIDATION - FIXED VERSION
# =====================================================
func is_target_valid(target_node: Node2D) -> bool:
	# SIMPLE CHECK: If target is null or not valid, return false
	if target_node == null:
		return false
	
	# Check if node is still in the scene tree
	if not target_node.is_inside_tree():
		return false
	
	# Check if target is in valid groups
	if not target_node.is_in_group("goblin") and not target_node.is_in_group("goblinbuildings"):
		return false
	
	return true

# Check if target is within detector zone
func is_target_in_range(target_node: Node2D) -> bool:
	if target_node == null:
		return false
	
	# Simple check: see if target is in overlapping bodies
	var overlapping_bodies = detector_zone.get_overlapping_bodies()
	
	# Check if target is in the list
	for body in overlapping_bodies:
		if body == target_node:
			return true
	
	return false

# Check if target exists and can be attacked
func can_attack_target() -> bool:
	if target == null:
		return false
	
	# Basic checks
	if not is_target_valid(target):
		return false
	
	if not is_target_in_range(target):
		return false
	
	# All checks passed
	return true

func _check_current_target():
	# Simple check: if we have a target but can't attack it, clear it
	if target != null and not can_attack_target():
		target = null
		if attack_timer and attack_timer.is_stopped() == false:
			attack_timer.stop()
		reset_combat()
		if state == State.ATTACK:
			change_state(State.IDLE)

# =====================================================
# FSM CORE
# =====================================================
func change_state(new_state: State) -> void:
	if state == State.DEAD:
		return
	if state == new_state:
		return
	state = new_state

# =====================================================
# INPUT
# =====================================================
func _unhandled_input(event):
	if not selected or state == State.DEAD:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		issue_move(get_global_mouse_position())

func issue_move(pos: Vector2):
	reset_combat()
	target = null
	manual_mode = true
	resume_navigation()

	# 🎯 Spread destination
	var offset := Vector2(
		randf_range(-20, 20),
		randf_range(-20, 20)
	)

	nav.target_position = pos + offset
	change_state(State.RUN)
	set_selected(false)

# =====================================================
# PROCESS
# =====================================================
func _physics_process(delta):
	if state == State.RUN:
		check_stuck(delta)
		
	# Update random shield timer
	if random_shield_enabled and not guard_locked and state != State.GUARD and state != State.DEAD:
		random_shield_timer += delta
		if random_shield_timer >= next_shield_time:
			try_activate_random_shield()
	
	# Handle combat UI auto-hide
	if ui_visible:
		ui_timer += delta
		if ui_timer >= ui_hide_delay:
			ui_visible = false
			var tween := create_tween()
			tween.tween_property(hp_bar, "modulate:a", 0.0, 0.3)
			tween.tween_property(shieldbar, "modulate:a", 0.0, 0.3)

	if guard_locked:
		return

	match state:
		State.IDLE:
			state_idle(delta)  # Pass delta to idle state
		State.RUN:
			state_run(delta)   # Pass delta to run state
		State.ATTACK:
			# Simple check: if we can't attack target, stop
			if not can_attack_target():
				target = null
				if attack_timer.is_stopped() == false:
					attack_timer.stop()
				reset_combat()
				change_state(State.IDLE)
		State.GUARD:
			state_guard(delta)

func try_activate_random_shield():
	# Only activate if not already in guard, not attacking, and not on cooldown
	if action_locked or guard_cooldown or guard_stamina < 20:
		return
		
	# Random chance to activate (70% chance)
	if randf() < 0.7:
		start_guard()
		reset_random_shield_timer()

# =====================================================
# STATES - FIXED VERSION (WILL SHOOT PROPERLY)
# =====================================================
func state_idle(delta: float):
	anim.play("idle")
	
	# Update target lock time
	target_lock_time += delta
	
	# Always try to acquire targets in idle state (but not too often)
	if target_lock_time >= 0.5:  # Check every 0.5 seconds
		acquire_target()
		target_lock_time = 0.0
	
	# If we have a valid target and can attack, start attacking
	if target != null and can_attack_target() and not action_locked:
		start_attack()

func state_run(delta: float):
	anim.play("run")
	
	# Update target lock time
	target_lock_time += delta
	
	# Check if we should attack any target in range while moving
	if not manual_mode:  # If not in strict manual mode, allow target acquisition
		if target_lock_time >= 0.3:  # Check every 0.3 seconds while running
			acquire_target()
			target_lock_time = 0.0
			if target != null and can_attack_target():
				stop_navigation()
				velocity = Vector2.ZERO
				change_state(State.IDLE)
				start_attack()
				return
	
	if nav.is_navigation_finished() and nav.distance_to_target() > stop_distance * 2:
		# Path failed → re-roll target
		nav.target_position += Vector2(
			randf_range(-64, 64),
			randf_range(-64, 64)
		)

	if nav.distance_to_target() <= stop_distance:
		velocity = Vector2.ZERO
		manual_mode = false
		change_state(State.IDLE)
		return

	var dir := (nav.get_next_path_position() - global_position).normalized()
	avoid_cast.target_position = dir * 18
	update_facing(dir)
	nav.set_velocity(dir * speed)

# =====================================================
# SHOOT ATTACK (RANGED) - FIXED VERSION
# =====================================================
func start_attack():
	if action_locked:
		return
	
	# Simple check: can we attack target?
	if not can_attack_target():
		reset_combat()
		change_state(State.IDLE)
		return

	action_locked = true
	change_state(State.ATTACK)

	stop_navigation()
	update_facing((target.global_position - global_position).normalized())
	
	# Play shoot animation and spawn arrow immediately
	anim.play("shoot")
	spawn_arrow()  # Spawn arrow immediately, not waiting for animation

	# Start continuous shooting
	if not attack_timer.is_stopped():
		attack_timer.stop()
	attack_timer.start()

func _on_attack_timer_timeout():
	# Simple check: can we continue attacking?
	if not can_attack_target():
		attack_timer.stop()
		reset_combat()
		change_state(State.IDLE)
		return
	
	if can_attack_target():
		update_facing((target.global_position - global_position).normalized())
		anim.play("shoot")
		spawn_arrow()  # Spawn arrow immediately
	else:
		attack_timer.stop()
		reset_combat()
		change_state(State.IDLE)

func spawn_arrow():
	# Double-check before shooting
	if not can_attack_target():
		return
		
	var arrow = arrow_scene.instantiate()
	get_parent().add_child(arrow)
	arrow.global_position = shoot_point.global_position
	arrow.z_index = 5
	arrow.scale = scale
	# Launch arrow toward target
	if arrow.has_method("launch"):
		if not shooting_arrow.playing:
			shooting_arrow.play()
		arrow.launch(target.global_position, 800) # 800 = speed

# =====================================================
# GUARD (HARD LOCK)
# =====================================================
func start_guard():
	if action_locked:
		return
	action_locked = true
	guard_timer = 0.0
	change_state(State.GUARD)
	stop_navigation()
	anim.play("idle")

func state_guard(delta):
	guard_timer += delta
	guard_stamina = min(guard_stamina + int(25 * delta), max_guard)
	update_bars()

	face_closest_goblin()

	if guard_timer >= GUARD_DURATION:
		reset_combat()
		reset_random_shield_timer()  # Reset after guard ends
		change_state(State.IDLE)

# =====================================================
# TARGETING - SIMPLIFIED
# =====================================================
@warning_ignore("unused_parameter")
func acquire_target(delta := 0.0):
	# Clear target if it's no longer valid
	if target != null and not can_attack_target():
		target = null
		return

	var closest: Node2D = null
	var dist := INF

	for body in detector_zone.get_overlapping_bodies():
		# Skip if body is null or not in the right groups
		if body == null:
			continue
		
		# Check if body is still in the scene tree
		if not body.is_inside_tree():
			continue
		
		# Check if body is in valid groups
		if not body.is_in_group("goblin") and not body.is_in_group("goblinbuildings"):
			continue
		
		# Calculate distance
		var d = global_position.distance_to(body.global_position)
		if d < dist:
			dist = d
			closest = body

	target = closest

func face_closest_goblin():
	var closest: Node2D = null
	var dist := INF
	for body in detector_zone.get_overlapping_bodies():
		# Skip if body is null
		if body == null:
			continue
		
		# Check groups
		if body.is_in_group("goblin") or body.is_in_group("goblinbuildings"):
			# Check if still in tree
			if not body.is_inside_tree():
				continue
			
			var d := global_position.distance_to(body.global_position)
			if d < dist:
				dist = d
				closest = body
	
	if closest != null:
		update_facing((closest.global_position - global_position).normalized())

# =====================================================
# NAVIGATION
# =====================================================
func stop_navigation():
	if nav == null:
		return

	nav.set_velocity(Vector2.ZERO)
	nav.avoidance_enabled = false

func resume_navigation():
	nav.avoidance_enabled = true

func _on_nav_velocity(v: Vector2):
	if state != State.RUN:
		return

	var final_velocity := v

	# Obstacle avoidance (ShapeCast)
	if avoid_cast.is_colliding():
		var normal := avoid_cast.get_collision_normal(0)
		var side := Vector2(-normal.y, normal.x)
		final_velocity += side * speed * AVOID_FORCE

	# Ally separation force
	final_velocity += apply_ally_separation()

	velocity = final_velocity.limit_length(speed * 1.2)
	move_and_slide()

# =====================================================
# DAMAGE
# =====================================================
func take_damage(amount: int, dir: Vector2):
	show_combat_ui()
	if state == State.DEAD:
		return

	# =============================
	# GUARD ABSORBS DAMAGE
	# =============================
	if state == State.GUARD and guard_stamina > 0:
		# Shield absorbs damage completely - NO LIFE DAMAGE
		if not shield_audio.playing:
			shield_audio.play()
		guard_stamina -= amount
		update_bars()

		# Apply knockback even with shield
		velocity = -dir.normalized() * knockback_force * guard_knockback_multiplier
		update_facing(-dir)
		move_and_slide()
		
		# Reset random shield timer when using guard
		reset_random_shield_timer()

		if guard_stamina <= 0:
			guard_stamina = 0
			guard_timer = GUARD_DURATION
		return

	# =============================
	# LOW HP AUTO-GUARD (if shield has stamina)
	# =============================
	if life <= max_life * LOW_HP_SHIELD_THRESHOLD \
	and not action_locked \
	and not guard_cooldown \
	and guard_stamina > 20:
		start_guard()
		start_guard_cooldown()
		return

	# =============================
	# NORMAL DAMAGE (only if not guarding)
	# =============================
	life -= amount
	if GlobalPlayer.camera_shake_func.is_valid():
		GlobalPlayer.camera_shake_func.call()
	update_bars()
	flash_red()

	velocity = -dir.normalized() * knockback_force
	update_facing(-dir)
	move_and_slide()

	# Trigger random shield timer reset on taking damage
	if random_shield_enabled:
		reset_random_shield_timer()

	if life <= 0:
		die()

func start_guard_cooldown():
	guard_cooldown = true
	await get_tree().create_timer(GUARD_COOLDOWN_TIME).timeout
	guard_cooldown = false

# =====================================================
# RESET COMBAT
# =====================================================
func reset_combat():
	action_locked = false
	target = null
	guard_timer = 0.0
	resume_navigation()
	
	# Don't reset random shield timer here - only reset when guard ends
	# This prevents interrupting the random shield cycle

# =====================================================
# VISUALS
# =====================================================
func update_facing(dir: Vector2):
	if abs(dir.x) > 0.01:
		anim.flip_h = dir.x < 0

func flash_red():
	anim.modulate = Color(1, 0.2, 0.2)
	await get_tree().create_timer(0.1).timeout
	anim.modulate = Color.WHITE

func update_bars():
	hp_bar.value = life
	shieldbar.value = guard_stamina

# =====================================================
# SELECTION
# =====================================================
func set_selected(v: bool):
	selected = v
	select_indicator.visible = v

func _on_button_pressed():
	click_audio.play()
	set_selected(!selected)
	if selected:
		manual_mode = true

# =====================================================
# HITBOX
# =====================================================
func _on_hitbox_area_entered(area):
	if area.is_in_group("explo"):
		take_damage(30, area.global_position - global_position)
		if not hit_audio.playing:
			hit_audio.play()
	if area.is_in_group("heal"):
		life = max_life
		show_combat_ui()

# =====================================================
# DETECTOR ZONE - SIMPLIFIED
# =====================================================
func _on_dectector_zone_body_entered(body):
	# Don't interrupt if we're in manual movement mode
	if manual_mode and state == State.RUN:
		return
	
	# Skip if body is null
	if body == null:
		return
	
	if (body.is_in_group("goblin") or body.is_in_group("goblinbuildings")) and not action_locked:
		# Check if body is still in tree
		if not body.is_inside_tree():
			return
			
		# Clear any movement command
		target = body
		manual_mode = false  # Override manual mode
		stop_navigation()
		velocity = Vector2.ZERO
		
		# Only change state if we're not already attacking or guarding
		if state != State.ATTACK and state != State.GUARD:
			change_state(State.IDLE)
		
		# Start attack if not already attacking
		if state != State.ATTACK:
			start_attack()

# =====================================================
# DEATH
# =====================================================
signal died(lancer)
func die():
	emit_signal("died", self)
	change_state(State.DEAD)
	stop_navigation()
	anim.play("die")
	shape.disabled = true
	hitbox.monitoring = false
	set_selected(false)
	if attack_timer:
		attack_timer.stop()
	if target_check_timer:
		target_check_timer.stop()
	
	var skull := preload("res://Materiels/skull/skull.tscn").instantiate()
	get_parent().add_child(skull)
	skull.global_position = global_position
	skull.scale = Vector2(0.6, 0.6)

		# --- SAFE AUDIO DETACH ---
	if not death_audio.playing:
		death_audio.play()


	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	await tween.finished
	queue_free()

func can_use_navigation() -> bool:
	return (
		nav != null and
		nav.is_inside_tree() and
		state == State.RUN
	)

func check_stuck(delta):
	var moved_dist := global_position.distance_to(last_position)

	if moved_dist < MIN_MOVE_DIST and state == State.RUN:
		stuck_timer += delta
	else:
		stuck_timer = 0.0

	last_position = global_position

	if stuck_timer >= STUCK_TIME:
		resolve_stuck()
		stuck_timer = 0.0

func resolve_stuck():
	# Strong axis-aligned escape pulse
	var axis := Vector2.ZERO

	if randf() < 0.5:
		axis.x = -1 if randf() < 0.5 else 1
	else:
		axis.y = -1 if randf() < 0.5 else 1

	velocity = axis * STUCK_PULSE_FORCE
	move_and_slide()

	# Slightly offset navigation target to force repath
	nav.target_position += axis * randf_range(24, 48)

func apply_ally_separation() -> Vector2:
	var push := Vector2.ZERO

	for body in detector_zone.get_overlapping_bodies():
		if body == self:
			continue
		if body.is_in_group("selectable"): # same kind units
			var diff := global_position - body.global_position
			var dist := diff.length()

			if dist > 0 and dist < ALLY_PUSH_RADIUS:
				push += diff.normalized() * (ALLY_PUSH_FORCE / max(dist, 4))

	return push

func show_combat_ui():
	ui_visible = true
	ui_timer = 0.0
	
	hp_bar.visible = true
	shieldbar.visible = true
	
	hp_bar.modulate.a = 1.0
	shieldbar.modulate.a = 1.0

func get_health_percentage() -> float:
	return float(life) / float(max_life)
