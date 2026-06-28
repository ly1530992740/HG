extends CharacterBody2D
# --------------------------------------------------
# ENUMS
# --------------------------------------------------
enum State { IDLE, RUN, USE, DEAD }

# --------------------------------------------------
# EXPORTS
# --------------------------------------------------
@export var speed := 300.0
@export var max_life := 100
@export var knockback_force := 320.0
@export var use_duration := 0.5
@export var tool_cooldown := 0.5  # Cooldown between tool uses

@export var repair_effect_scene := preload("res://unit/Monks/heal_effect.tscn")
@export var skull_scene := preload("res://Materiels/skull/skull.tscn")

# --------------------------------------------------
# INPUT CONSTANTS (CLEAN)
# --------------------------------------------------
const INPUT_RIGHT := "move_right"
const INPUT_LEFT := "move_left"
const INPUT_DOWN := "move_down"
const INPUT_UP := "move_up"

# --------------------------------------------------
# NODE REFERENCES
# --------------------------------------------------
@onready var anim: AnimatedSprite2D = $anim
@onready var hitbox: Area2D = $hitbox
@onready var detector_zone: Area2D = $"dectector zone"
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var select_indicator: Label = $"select indicator"
@onready var use_timer: Timer = $UseTimer
@onready var marker_2d: Marker2D = $Marker2D


@onready var click_audio: AudioStreamPlayer = $"sound fx/click_audio"
@onready var death_audio: AudioStreamPlayer = $"sound fx/death_audio"
@onready var hit_audio: AudioStreamPlayer = $"sound fx/hit_audio"


# --------------------------------------------------
# STATE VARIABLES
# --------------------------------------------------
var state: State = State.IDLE

var active := false          # monk selected / controllable
var busy := false            # Using tool
var action_lock := false     # External lock (animations, stun, etc)
var is_guarding := false
var can_use_tool := true     # Cooldown system

var life: int
var knockback_velocity := Vector2.ZERO
var last_input_dir := Vector2.DOWN


# =====================================================
# UI VISIBILITY (HP / SHIELD)
# =====================================================
var ui_visible := false
var ui_hide_delay := 2.5   # seconds without damage
var ui_timer := 0.0


# --------------------------------------------------
# READY
# --------------------------------------------------
func _ready() -> void:
	GlobalPlayer.register_pawn(self)
	progress_bar.visible = false
	z_index = 4
	scale = Vector2(0.7, 0.7)
	life = max_life
	progress_bar.max_value = max_life
	progress_bar.value = life

	use_timer.wait_time = use_duration
	use_timer.one_shot = true



# --------------------------------------------------
# INPUT (UI ONLY)
# --------------------------------------------------
func _input(event: InputEvent) -> void:
	if not active or state == State.DEAD:
		return

	# Tool usage
	if event.is_action_pressed("attack_knight"):
		spawn_attack_effect()

# --------------------------------------------------
# PHYSICS LOOP
# --------------------------------------------------
func _physics_process(delta: float) -> void:
	if active==true:
		GlobalPlayer.active_player_position=global_position

	# Handle combat UI auto-hide
	if ui_visible:
		ui_timer += delta
		if ui_timer >= ui_hide_delay:
			ui_visible = false
		
			var tween := create_tween()
			tween.tween_property(progress_bar, "modulate:a", 0.0, 0.3)


	if state == State.DEAD:
		return

	# Knockback always has priority
	if knockback_velocity.length() > 1:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, delta * 900)
		move_and_slide()
		update_animation()
		return

	if active and not busy:
		handle_movement()
	else:
		velocity = Vector2.ZERO
		if not busy:
			state = State.IDLE

	move_and_slide()
	update_animation()

# --------------------------------------------------
# MOVEMENT LOGIC (ARROW KEYS ONLY)
# --------------------------------------------------
func handle_movement() -> void:
	if action_lock or is_guarding:
		velocity = Vector2.ZERO
		state = State.IDLE
		return

	var input_vector := Vector2.ZERO
	
	if Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1
	if Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1
	if Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1
	if Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1

	if input_vector == Vector2.ZERO:
		velocity = Vector2.ZERO
		state = State.IDLE
		return

	last_input_dir = input_vector.normalized()
	velocity = last_input_dir * speed
	state = State.RUN
	flip_sprite(last_input_dir)



# --------------------------------------------------
# SPRITE FLIP
# --------------------------------------------------
func flip_sprite(dir: Vector2) -> void:
	if dir.x != 0:
		anim.flip_h = dir.x < 0

# --------------------------------------------------
# HITBOX (DAMAGE)
# --------------------------------------------------
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("explo"):
		take_damage(10, area.global_position)
		hit_audio.play()

# --------------------------------------------------
# EFFECTS
# --------------------------------------------------
func spawn_attack_effect() -> void:
	var fx := repair_effect_scene.instantiate()
	fx.global_position = marker_2d.global_position
	fx.scale=Vector2(1.0,1.0)
	get_parent().add_child(fx)
	fx.z_index=z_index-1


# --------------------------------------------------
# DAMAGE / FEEDBACK
# --------------------------------------------------
func take_damage(amount: int, from_pos: Vector2) -> void:
	show_combat_ui()
	life -= amount
	if GlobalPlayer.camera_shake_func.is_valid():
		GlobalPlayer.camera_shake_func.call()
	
	progress_bar.value = life
	knockback_velocity = (global_position - from_pos).normalized() * knockback_force

	red_flash()

	if life <= 0:
		die()

func red_flash() -> void:
	anim.modulate = Color.RED
	await get_tree().create_timer(0.12).timeout
	anim.modulate = Color.WHITE

#func camera_shake() -> void:
#	for i in range(6):
#		camera.offset = Vector2(randf_range(-6, 6), randf_range(-6, 6))
#		await get_tree().create_timer(0.02).timeout
#	camera.offset = Vector2.ZERO

# --------------------------------------------------
# DEATH
# --------------------------------------------------
signal died(pawn)

func die():
	if state == State.DEAD:
		return

	emit_signal("died", self)

	state = State.DEAD
	active = false
	busy = true

	if not death_audio.playing:
		death_audio.play()

	spawn_skull()
	await fade_out()
	queue_free()


func spawn_skull() -> void:
	var skull := skull_scene.instantiate()
	skull.global_position = global_position
	get_parent().add_child(skull)
	skull.scale = Vector2(0.5, 0.5)

func fade_out() -> void:
	var tween := create_tween()
	tween.tween_property(anim, "modulate:a", 0.0, 0.6)
	await tween.finished

# --------------------------------------------------
# ANIMATION HANDLER
# --------------------------------------------------
func update_animation() -> void:
	if state == State.USE:
		anim.play("repair")
	elif state == State.IDLE:
		anim.play("idle")
	elif state == State.RUN:
		anim.play("run")
	elif state == State.DEAD:
		anim.play("idle")


# --------------------------------------------------
# ACTIVATE / DEACTIVATE PAWN
# --------------------------------------------------
func activate_this_pawn():
	if GlobalPlayer.active_player and GlobalPlayer.active_player != self:
		if GlobalPlayer.active_player.has_method("deactivate"):
			GlobalPlayer.active_player.deactivate()
	GlobalPlayer.active_player = self

	active = true
	GlobalPlayer.active_player_position=global_position
	set_process(true)
	update_selection_indicator()

func deactivate():
	active = false
	set_process(false)
	update_selection_indicator()
	select_indicator.visible = false

func update_selection_indicator():
	select_indicator.visible = active

# --------------------------------------------------
# DETECTOR ZONE SIGNAL (INTERACTION)
# --------------------------------------------------
func _on_dectector_zone_area_entered(area: Area2D) -> void:
	if area.is_in_group("heal"):
		show_combat_ui()
		life = max_life

# --------------------------------------------------
# BUTTON SIGNAL (UI)
# --------------------------------------------------
func _on_button_pressed() -> void:
	GlobalPlayer.set_active_pawn(self)
	click_audio.play()

func _on_use_timer_timeout() -> void:
	busy = false
	can_use_tool = true
	state = State.IDLE
	update_animation()

func get_health_percentage() -> float:
	return float(life) / float(max_life)

func get_health() -> int:
	return life  # or whatever your health variable is

func get_max_health() -> int:
	return max_life  # or whatever your max health variable is

func show_combat_ui():
	ui_visible = true
	ui_timer = 0.0
	
	progress_bar.visible = true

	
	progress_bar.modulate.a = 1.0

func activate_from_global():
	active = true
	set_process(true)
	select_indicator.visible = true
	GlobalPlayer.active_player_position = global_position
