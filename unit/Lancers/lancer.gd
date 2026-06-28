extends CharacterBody2D

# --- NODE REFERENCES ---
@onready var anim: AnimatedSprite2D = $anim
@onready var marker_2d: Marker2D = $Marker2D
@onready var button: Button = $Button
@onready var select_indicator: Label = $"select indicator"
@onready var life_bar: ProgressBar = $ProgressBar
@onready var shieldbar: ProgressBar = $shieldbar

# --- STATE VARIABLES ---
var is_active: bool = false
var current_state: String = "idle" # idle, run, attack, guard, dead
var action_lock: bool = false
var action_lock_time: float = 0.0
var last_input_dir: Vector2 = Vector2.DOWN

# --- HEALTH / KNOCKBACK ---
var max_life: int = 100
var life: int = 100
var is_hit: bool = false
var knockback_force: float = 300.0
var hit_flash_time: float = 0.2
var hit_flash_timer: float = 0.0
var hit_cooldown: float = 0.5
var hit_cooldown_timer: float = 0.0

# --- ATTACK COOLDOWN ---
var attack_cooldown: float = 0.5
var attack_timer: float = 0.0

# --- ATTACK EFFECT ---
var attack_effect_scene = preload("res://unit/player/attack_effect.tscn")
var attack_effect_cooldown: float = 0.3
var attack_effect_timer: float = 0.0

# --- GUARD / SHIELD ---
const INPUT_GUARD := "guard"
var is_guarding := false
var guard_duration := 3.0
var guard_timer := 0.0
var guard_cooldown := 2.5
var guard_cooldown_timer := 0.0

var max_guard_stamina := 50
var guard_stamina := 50
var guard_regen_delay := 1.0
var guard_regen_tick := 0.7
var guard_regen_amount := 1
var guard_regen_timer := 0.0
var guard_regen_tick_timer := 0.0

# --- INPUT KEYS ---
const INPUT_MOVE_UP = "up"
const INPUT_MOVE_DOWN = "down"
const INPUT_MOVE_LEFT = "left"
const INPUT_MOVE_RIGHT = "right"
const INPUT_ATTACK = "attack_knight"

# --- GLOBAL PLAYER SINGLETON ---
var global_player := GlobalPlayer

# --- READY ---
func _ready():
	z_index = 4
	scale = Vector2(0.7, 0.7)
	button.pressed.connect(_on_button_pressed)
	update_selection_indicator()
	set_process(false)

	life_bar.max_value = max_life
	life_bar.value = life

	shieldbar.max_value = max_guard_stamina
	shieldbar.value = guard_stamina
	shieldbar.visible = true

# --- BUTTON ---
func _on_button_pressed():
	activate_this_lancer()

# --- ACTIVATE / DEACTIVATE ---
func activate_this_lancer():
	if GlobalPlayer.active_player != null:
		GlobalPlayer.active_player.deactivate()
	GlobalPlayer.active_player = self
	is_active = true
	set_process(true)
	update_selection_indicator()
	play_state("idle")

func deactivate():
	is_active = false
	set_process(false)
	update_selection_indicator()
	play_state("idle")
	action_lock = false

# --- CAMERA CONTROL ---
func activate_camera():
	pass

# --- STATE MACHINE ---
func play_state(state_name: String):
	if current_state == state_name:
		return
	current_state = state_name
	match state_name:
		"idle": anim.play("idle")
		"run": anim.play("run")
		"attack down": anim.play("attack down")
		"attack down side": anim.play("attack down side")
		"attack side": anim.play("attack side")
		"attack up": anim.play("attack up")
		"attack up side": anim.play("attack up side")
		"guard": anim.play("guard")
		"dead": anim.play("die")

# --- ANIMATION UPDATER (PRIORITIZE ATTACK / GUARD) ---
func update_animation():
	if current_state == "dead" or is_hit:
		return
	elif is_guarding:
		if current_state != "guard":
			play_state("guard")
	elif action_lock: 
		# Do not override attack animations while action_lock is active
		pass
	elif velocity.length() > 0:
		play_state("run")
		flip_sprite(last_input_dir)
	else:
		play_state("idle")

# --- PROCESS ---
func _process(delta):
	if not is_active or current_state == "dead":
		return

	# Timers
	if action_lock:
		action_lock_time -= delta
		if action_lock_time <= 0:
			action_lock = false

	if attack_timer > 0:
		attack_timer -= delta
	if attack_effect_timer > 0:
		attack_effect_timer -= delta
	if guard_cooldown_timer > 0:
		guard_cooldown_timer -= delta
	if hit_cooldown_timer > 0:
		hit_cooldown_timer -= delta

	# Guard duration
	if is_guarding:
		guard_timer -= delta
		if guard_timer <= 0:
			end_guard()

	# Shield regen (tick-based)
	if not is_guarding:
		if guard_regen_timer > 0:
			guard_regen_timer -= delta
		else:
			guard_regen_tick_timer -= delta
			if guard_regen_tick_timer <= 0:
				guard_regen_tick_timer = guard_regen_tick
				guard_stamina = min(guard_stamina + guard_regen_amount, max_guard_stamina)

	shieldbar.value = guard_stamina
	shieldbar.visible = true

	# Hit flash
	if is_hit:
		hit_flash_timer -= delta
		modulate = Color(1,0,0,1) if hit_flash_timer > 0 else Color(1,1,1,1)
		if hit_flash_timer <= 0:
			is_hit = false
			update_animation()

	# Guard input
	if Input.is_action_just_pressed(INPUT_GUARD):
		try_start_guard()

	# Attack input
	if not action_lock and not is_guarding and attack_timer <= 0 and Input.is_action_just_pressed(INPUT_ATTACK):
		start_attack()
		attack_timer = attack_cooldown

	# Movement input
	var input_vector = Vector2(
		Input.get_action_strength(INPUT_MOVE_RIGHT) - Input.get_action_strength(INPUT_MOVE_LEFT),
		Input.get_action_strength(INPUT_MOVE_DOWN) - Input.get_action_strength(INPUT_MOVE_UP)
	)
	if input_vector != Vector2.ZERO:
		last_input_dir = input_vector.normalized()

	if not action_lock and not is_hit:
		if input_vector != Vector2.ZERO:
			velocity = input_vector * 200
		else:
			velocity = Vector2.ZERO
		move_and_slide()

	update_animation()

	# Guard flip
	if is_guarding:
		if Input.is_action_pressed(INPUT_MOVE_LEFT):
			anim.flip_h = true
		elif Input.is_action_pressed(INPUT_MOVE_RIGHT):
			anim.flip_h = false

	# Check explosions
	for explo in get_tree().get_nodes_in_group("explo"):
		if explo.global_position.distance_to(global_position) < 32 and hit_cooldown_timer <= 0:
			take_damage(10, explo.global_position - global_position)
			hit_cooldown_timer = hit_cooldown

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
	update_animation()

# --- ATTACK ---
func start_attack():
	var attack_dir = get_attack_direction()
	var chosen_attack = ""
	match attack_dir:
		"up":
			chosen_attack = "attack up"
		"down":
			chosen_attack = "attack down"
		"side":
			chosen_attack = "attack side"
			if last_input_dir.x < 0:
				anim.flip_h = true
			else:
				anim.flip_h = false
	play_state(chosen_attack)
	action_lock = true
	action_lock_time = 0.4
	spawn_attackeffect()

func get_attack_direction() -> String:
	var dir = last_input_dir
	if abs(dir.x) > abs(dir.y):
		return "side"
	elif dir.y < 0:
		return "up"
	elif dir.y > 0:
		return "down"
	return "down"

# --- FLIP SPRITE ---
func flip_sprite(dir: Vector2):
	if dir.x < 0: anim.flip_h = true
	elif dir.x > 0: anim.flip_h = false

# --- DAMAGE / KNOCKBACK ---
func take_damage(amount: int, knockback_dir: Vector2):
	if current_state == "dead":
		return

	if is_guarding:
		guard_stamina = max(guard_stamina - amount, 0)
		guard_regen_timer = guard_regen_delay
		guard_regen_tick_timer = guard_regen_tick
		shieldbar.value = guard_stamina
		velocity = -knockback_dir.normalized() * knockback_force * 0.35
		move_and_slide()
		return

	life = max(life - amount, 0)
	life_bar.value = life
	is_hit = true
	hit_flash_timer = hit_flash_time
	action_lock = true
	action_lock_time = 0.2

	if life <= 0:
		die()
		return

	velocity = -knockback_dir.normalized() * knockback_force
	move_and_slide()

# --- CAMERA SHAKE ---
#func camera_shake(strength: float):
#	var tween = create_tween()
#	camera.offset = Vector2.ZERO
#	tween.tween_property(camera, "offset", Vector2(randf_range(-strength,strength), randf_range(-strength,strength)), 0.05)
#	tween.tween_property(camera, "offset", Vector2.ZERO, 0.1)

# --- NO GUARD FEEDBACK ---
func flash_no_guard():
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(0.855,0.573,0.0,1), 0.08)
	tween.tween_property(self, "modulate", Color(1,1,1,1), 0.12)

# --- DEATH ---
func die():
	life = 0
	life_bar.value = 0
	current_state = "dead"
	action_lock = true
	set_process(false)

	var skull_scene = preload("res://Materiels/skull/skull.tscn")
	var skull = skull_scene.instantiate()
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

# --- SPAWN ATTACK EFFECT ---
func spawn_attackeffect():
	if attack_effect_timer > 0:
		return
	attack_effect_timer = attack_effect_cooldown

	var spawned_attackeffect = attack_effect_scene.instantiate()
	get_parent().add_child(spawned_attackeffect)
	spawned_attackeffect.global_position = global_position

	if last_input_dir.x < 0:
		spawned_attackeffect.scale.x = -abs(spawned_attackeffect.scale.x)
	else:
		spawned_attackeffect.scale.x = abs(spawned_attackeffect.scale.x)

# --- HITBOX ---
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("explo") and hit_cooldown_timer <= 0:
		var dir := area.global_position - global_position
		take_damage(10, dir)
		hit_cooldown_timer = hit_cooldown
	elif area.is_in_group("heal"):
		life = min(life + 1, max_life)
		life_bar.value = life
