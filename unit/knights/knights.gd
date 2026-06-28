extends CharacterBody2D

# --- NODE REFERENCES ---
@onready var anim: AnimatedSprite2D = $anim
@onready var button: Button = $Button
@onready var select_indicator: Label = $"select indicator"
@onready var life_bar: ProgressBar = $ProgressBar
@onready var shieldbar: ProgressBar = $shieldbar
@onready var attack_effect_spawn: Node2D = $AttackEffectSpawn  # Node to spawn attack effect

# --- STATE ---
var is_active := false
var current_state := "idle" # idle, run, attack, guard, dead
var action_lock := false
var action_lock_time := 0.0
var last_input_dir := Vector2.DOWN

# --- HEALTH ---
var max_life := 100
var life := 100

# --- HIT FLASH ---
var is_hit := false
var hit_flash_time := 0.2
var hit_flash_timer := 0.0

# --- KNOCKBACK ---
var knockback_force := 300.0
var guard_knockback_multiplier := 0.35

# --- ATTACK ---
var attack_cooldown := 0.5
var attack_timer := 0.0

# --- ATTACK EFFECT ---
var attack_effect_scene := preload("res://unit/player/attack_effect.tscn")  # Your attack effect scene
var attack_effect_cooldown := 0.3
var attack_effect_timer := 0.0

# --- GUARD ---
const INPUT_GUARD := "guard"
var is_guarding := false
var guard_duration := 2.0
var guard_timer := 0.0
var guard_cooldown := 2.5
var guard_cooldown_timer := 0.0

# --- GUARD STAMINA / SHIELD ---
var max_guard_stamina := 50
var guard_stamina := 50

# Regen tuning
var guard_regen_delay := 1.0           # delay after hit before regen starts
var guard_regen_tick := 0.7            # tick interval
var guard_regen_amount := 1            # shield gain per tick
var guard_regen_timer := 0.0           # countdown before regen starts
var guard_regen_tick_timer := 0.0      # timer for ticks

# --- INPUT ---
const INPUT_MOVE_LEFT := "left"
const INPUT_MOVE_RIGHT := "right"
const INPUT_MOVE_UP := "up"
const INPUT_MOVE_DOWN := "down"
const INPUT_ATTACK := "attack_knight"

# --- READY ---
func _ready():
	z_index = 4
	scale = Vector2(0.7, 0.7)
	set_process(false)

	life_bar.max_value = max_life
	life_bar.value = life

	shieldbar.max_value = max_guard_stamina
	shieldbar.value = guard_stamina
	shieldbar.visible = true  # Always visible

# --- ACTIVATE / DEACTIVATE ---
func _on_button_pressed():
	if GlobalPlayer.active_player and GlobalPlayer.active_player != self:
		if GlobalPlayer.active_player.has_method("deactivate"):
			GlobalPlayer.active_player.deactivate()
	GlobalPlayer.active_player = self

	is_active = true
	set_process(true)
	update_selection_indicator()

func deactivate():
	is_active = false
	set_process(false)
	update_selection_indicator()

# --- PROCESS ---
func _process(delta):
	if not is_active or current_state == "dead":
		return

	# Action lock
	if action_lock:
		action_lock_time -= delta
		if action_lock_time <= 0:
			action_lock = false

	# Timers
	if attack_timer > 0:
		attack_timer -= delta
	if guard_cooldown_timer > 0:
		guard_cooldown_timer -= delta
	if attack_effect_timer > 0:
		attack_effect_timer -= delta

	# Guard duration
	if is_guarding:
		guard_timer -= delta
		if guard_timer <= 0:
			end_guard()

	# Shield regen (tick-based)
	if not is_guarding:
		if guard_regen_timer > 0.0:
			guard_regen_timer -= delta
		else:
			guard_regen_tick_timer -= delta
			if guard_regen_tick_timer <= 0.0:
				guard_regen_tick_timer = guard_regen_tick
				guard_stamina += guard_regen_amount
				if guard_stamina > max_guard_stamina:
					guard_stamina = max_guard_stamina

	# Update shield bar
	shieldbar.value = guard_stamina
	shieldbar.visible = true  # Always visible

	# Hit flash
	if is_hit:
		hit_flash_timer -= delta
		modulate = Color(1, 0, 0, 1) if hit_flash_timer > 0 else Color(1, 1, 1, 1)
		if hit_flash_timer <= 0:
			is_hit = false

	# Input
	if Input.is_action_just_pressed(INPUT_GUARD):
		try_start_guard()

	if not action_lock and not is_guarding and attack_timer <= 0 and Input.is_action_just_pressed(INPUT_ATTACK):
		start_attack()
		attack_timer = attack_cooldown

	# Movement
	if not action_lock and not is_guarding:
		var input_vector := Vector2(
			Input.get_action_strength(INPUT_MOVE_RIGHT) - Input.get_action_strength(INPUT_MOVE_LEFT),
			Input.get_action_strength(INPUT_MOVE_DOWN) - Input.get_action_strength(INPUT_MOVE_UP)
		)

		if input_vector != Vector2.ZERO:
			last_input_dir = input_vector.normalized()
			velocity = input_vector * 200
			move_and_slide()
			play_state("run")
			flip_sprite(input_vector)
		else:
			play_state("idle")

	# Guard flip only
	if is_guarding:
		if Input.is_action_pressed(INPUT_MOVE_LEFT):
			anim.flip_h = true
		elif Input.is_action_pressed(INPUT_MOVE_RIGHT):
			anim.flip_h = false

# --- STATE ---
func play_state(state: String):
	if current_state == state:
		return
	current_state = state
	anim.play(state)

# --- GUARD ---
func try_start_guard():
	if guard_stamina <= 0:
		flash_no_guard()
		return
	if is_guarding or guard_cooldown_timer > 0 or action_lock:
		return
	start_guard()

func start_guard():
	is_guarding = true
	guard_timer = guard_duration
	guard_cooldown_timer = guard_cooldown
	action_lock = true
	action_lock_time = guard_duration
	velocity = Vector2.ZERO
	play_state("guard")

func end_guard():
	is_guarding = false
	action_lock = false
	play_state("idle")

# --- ATTACK ---
func start_attack():
	var chosen_attack := "attack1" if randi() % 2 == 0 else "attack2"
	play_state(chosen_attack)
	action_lock = true
	action_lock_time = 0.4
	spawn_attack_effect()

# --- SPAWN ATTACK EFFECT ---
func spawn_attack_effect():
	if attack_effect_timer > 0:
		return  # still on cooldown
	attack_effect_timer = attack_effect_cooldown

	var effect_instance = attack_effect_scene.instantiate()
	get_parent().add_child(effect_instance)

	effect_instance.global_position = global_position

	if anim.flip_h:
		effect_instance.scale.x = -abs(effect_instance.scale.x)
	else:
		effect_instance.scale.x = abs(effect_instance.scale.x)

# --- DAMAGE ---
func take_damage(amount: int, knockback_dir: Vector2):
	if current_state == "dead":
		return

	if is_guarding:
		guard_stamina -= amount
		if guard_stamina < 0:
			guard_stamina = 0
		guard_regen_timer = guard_regen_delay
		guard_regen_tick_timer = guard_regen_tick
		shieldbar.value = guard_stamina

		velocity = -knockback_dir.normalized() * knockback_force * guard_knockback_multiplier
		move_and_slide()
		return

	life -= amount
	life = max(life, 0)
	life_bar.value = life

	is_hit = true
	hit_flash_timer = hit_flash_time

	if life <= 0:
		die()
		return

	velocity = -knockback_dir.normalized() * knockback_force
	move_and_slide()

# --- CAMERA SHAKE ---
#func camera_shake(strength: float):
#	var tween := create_tween()
#	camera.offset = Vector2.ZERO
#	tween.tween_property(camera, "offset", Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.05)
#	tween.tween_property(camera, "offset", Vector2.ZERO, 0.1)

# --- NO GUARD FEEDBACK ---
func flash_no_guard():
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 0.506, 0.231, 1.0), 0.08)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.12)

# --- DEATH ---
func die():
	current_state = "dead"
	set_process(false)
	var skull_scene := preload("res://Materiels/skull/skull.tscn")
	var skull := skull_scene.instantiate()
	get_parent().add_child(skull)
	skull.global_position = global_position
	skull.scale = Vector2(0.6, 0.6)
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	await get_tree().create_timer(0.3).timeout
	queue_free()

# --- UI ---
func update_selection_indicator():
	select_indicator.visible = is_active

# --- FLIP ---
func flip_sprite(dir: Vector2):
	if dir.x < 0:
		anim.flip_h = true
	elif dir.x > 0:
		anim.flip_h = false

# --- HITBOX ---
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("explo"):
		var dir := area.global_position - global_position
		take_damage(10, dir)

	if area.is_in_group("heal"):
		life = min(life + 1, max_life)
		life_bar.value = life
