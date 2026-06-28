extends CharacterBody2D

# =====================================================
# NODES
# =====================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var shape: CollisionShape2D = $shape
@onready var detector_zone: Area2D = $"dectector zone"
@onready var hitbox: Area2D = $hitbox
@onready var hp_bar: ProgressBar = $ProgressBar
@onready var shieldbar: ProgressBar =$shieldbar
@onready var button: Button = $Button
@onready var select_indicator: Label = $"select indicator"
@onready var nav: NavigationAgent2D = $NavigationAgent2D
@onready var avoid_cast: ShapeCast2D = $PredictCast

@onready var click_audio: AudioStreamPlayer = $"sound fx/click_audio"
@onready var death_audio: AudioStreamPlayer = $"sound fx/death_audio"
@onready var hit_audio: AudioStreamPlayer = $"sound fx/hit_audio"
@onready var sword_audio: AudioStreamPlayer = $"sound fx/sword_audio"
@onready var shield_audio: AudioStreamPlayer = $"sound fx/shield_audio"

var attack_effect_active := false  # prevents multiple simultaneous effects


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

const ATTACK_RANGE := 10.0


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

const ALLY_PUSH_RADIUS := 28.0
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
@export var max_life := 300
@export var life := 300

@export var max_guard := 200
@export var guard_stamina := 200

@export var speed := 700.0
@export var attack_damage := 15
@export var attack_cooldown := 1.0

# =====================================================
# CONTROL
# =====================================================
var selected := false
var stop_distance := 10.0

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



# =====================================================
# READY
# =====================================================
func _ready():
	z_index=4
	scale=Vector2(0.7,0.7)
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

func reset_random_shield_timer():
	random_shield_timer = 0.0
	next_shield_time = randf_range(MIN_RANDOM_SHIELD_TIME, MAX_RANDOM_SHIELD_TIME)


# =====================================================
# FSM CORE  ✅ FIX
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
	movement_priority = true
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
	if state == State.ATTACK and is_instance_valid(target):
		update_facing((target.global_position - global_position).normalized())
	if state == State.RUN:
		check_stuck(delta)
		
	# Update random shield timer
	if random_shield_enabled and not guard_locked and state != State.GUARD and state != State.DEAD:
		random_shield_timer += delta
		if random_shield_timer >= next_shield_time:  # ← FIXED TYPO HERE
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
			state_idle()
		State.RUN:
			state_run()
		State.ATTACK:
			pass
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
# STATES
# =====================================================
func state_idle():
	anim.play("idle")

	# Always try to acquire targets in idle state
	acquire_target()
	if target:
		start_attack()


func state_run():
	anim.play("run")

	# If we have a target, chase it
	if is_instance_valid(target):
		nav.target_position = target.global_position

		var dist := global_position.distance_to(target.global_position)
		if dist <= ATTACK_RANGE:
			stop_navigation()
			velocity = Vector2.ZERO
			change_state(State.ATTACK)
			start_attack()
			return

	# Normal movement
	if nav.distance_to_target() <= stop_distance:
		velocity = Vector2.ZERO
		manual_mode = false
		movement_priority = false
		change_state(State.IDLE)
		return

	var dir := (nav.get_next_path_position() - global_position).normalized()
	update_facing(dir)
	nav.set_velocity(dir * speed)



# =====================================================
# ATTACK (HARD LOCK)
# =====================================================
func start_attack():
	if action_locked or not is_instance_valid(target):
		return

	action_locked = true
	change_state(State.ATTACK)

	stop_navigation()

	facing_dir = (target.global_position - global_position).normalized()
	update_facing(facing_dir)

	attack_loop()
func attack_loop() -> void:
	if attack_effect_active:
		return  # another attack effect is already running

	attack_effect_active = true

	while is_instance_valid(target):
		if not (target.is_in_group("goblin") or target.is_in_group("goblinbuildings")):
			break

		# ✅ Face the target correctly
		var dir := (target.global_position - global_position).normalized()
		update_facing(dir)

		# Play attack animation
		anim.play(pick_attack_anim())
		if not sword_audio.playing:
			sword_audio.play()

		# Spawn damage / attack effect
		if target.is_in_group("goblin"):
			apply_damage(target)
		else:
			apply_damage_building(target)

		# Wait for cooldown before next attack
		await get_tree().create_timer(attack_cooldown).timeout

	# Attack finished, unlock
	reset_combat()
	change_state(State.IDLE)
	attack_effect_active = false



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
	anim.play("guard")

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
# TARGETING
# =====================================================
func acquire_target(delta := 0.0):
	if is_instance_valid(target):
		target_lock_time += delta
		if target_lock_time < TARGET_LOCK_DURATION:
			return
	else:
		target_lock_time = 0.0

	var closest: Node2D = null
	var dist := INF

	for body in detector_zone.get_overlapping_bodies():
		if (body.is_in_group("goblin") or body.is_in_group("goblinbuildings")):
			var d = global_position.distance_to(body.global_position)
			if d < dist:
				dist = d
				closest = body

	target = closest
	target_lock_time = 0.0


func face_closest_goblin():
	var closest: Node2D = null
	var dist := INF

	for body in detector_zone.get_overlapping_bodies():
		if (body.is_in_group("goblin") or body.is_in_group("goblinbuildings")):
			var d := global_position.distance_to(body.global_position)
			if d < dist:
				dist = d
				closest = body

	if closest:
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
		guard_stamina -= amount
		if not shield_audio.playing:
			shield_audio.play()
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
# ATTACK EFFECT
# =====================================================
func apply_damage(enemy: Node2D):
	if enemy.has_method("take_damage"):
		enemy.take_damage(attack_damage, enemy.global_position - global_position)
func apply_damage_building(enemy: Node2D):
	if enemy.has_method("take_damage"):
		enemy.take_damage(attack_damage)

func pick_attack_anim() -> String:
	return "attack1" if randf() < 0.5 else "attack2"

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
	set_selected(!selected)
	click_audio.play()
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
		life=max_life
		show_combat_ui()

# =====================================================
# DEATH
# =====================================================
signal died(knight: Node2D)

func die() -> void:
	emit_signal("died", self)
	stop_navigation()
	anim.play("die")
	death_audio.play()

	shape.disabled = true
	hitbox.monitoring = false
	set_selected(false)

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
		is_instance_valid(nav) and
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




# Add with other control variables
var movement_priority := false  # When true, will finish moving before attacking

func _on_dectector_zone_body_entered(body):
	if movement_priority or action_locked or state == State.DEAD:
		return

	if body.is_in_group("goblin") or body.is_in_group("goblinbuildings"):
		target = body
		manual_mode = false

		# Start chasing
		nav.target_position = body.global_position
		change_state(State.RUN)


# In other player units' scripts, add:
func get_health_percentage() -> float:
	return float(life) / float(max_life)
func get_health() -> int:
	return life  # or whatever your health variable is

func get_max_health() -> int:
	return max_life  # or whatever your max health variable is

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
