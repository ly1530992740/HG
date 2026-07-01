extends CharacterBody2D
# --------------------------------------------------
# ENUMS
# --------------------------------------------------
enum Tool { HAND, HAMMER, PICKAXE, AXE, KNIFE, GUN }
enum State { IDLE, RUN, USE, DEAD }

# --------------------------------------------------
# EXPORTS
# --------------------------------------------------
@export var speed := 300.0
@export var max_life := 100
@export var knockback_force := 320.0
@export var use_duration := 0.5
@export var tool_cooldown := 0.5  # Cooldown between tool uses

@export var attack_effect_scene := preload("res://unit/player/attack_effect.tscn")
@export var attack_repair_scene := preload("res://unit/pawn_/repair_effect.tscn")
@export var skull_scene := preload("res://Materiels/skull/skull.tscn")
@export var enable_player_firearm := true
@export var firearm_data: WeaponData
@export var firearm_muzzle_offset := Vector2(24, -8)

const DEFAULT_PROJECTILE_SCENE := preload("res://weapons/projectile.tscn")

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
@onready var detector_zone: Area2D = $detector_zone
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var select_indicator: Label = $"select indicator"
@onready var use_timer: Timer = $UseTimer
@onready var marker_2d: Marker2D = $Marker2D
@onready var toolbox_panel: Panel = $Control

@onready var hammer_btn: Button = $Control/Hammer
@onready var pickaxe_btn: Button = $Control/Pickaxe
@onready var axe_btn: Button = $Control/Axe
@onready var hand_btn: Button = $Control/hand
@onready var knife_btn: Button = $Control/Knife


@onready var hammer_audio: AudioStreamPlayer = $"sound fx/hammer_audio"
@onready var knife_audio: AudioStreamPlayer = $"sound fx/knife_audio"
@onready var pickaxe: AudioStreamPlayer = $"sound fx/pickaxe"
@onready var axe: AudioStreamPlayer = $"sound fx/axe"
@onready var equip_audio: AudioStreamPlayer = $"sound fx/equip_audio"
@onready var click_audio: AudioStreamPlayer = $"sound fx/click_audio"
@onready var death_audio: AudioStreamPlayer = $"sound fx/death_audio"
@onready var hit_audio: AudioStreamPlayer = $"sound fx/hit_audio"


# --------------------------------------------------
# STATE VARIABLES
# --------------------------------------------------
var state: State = State.IDLE
var current_tool: Tool = Tool.HAND

var active := false          # Pawn selected / controllable
var busy := false            # Using tool
var action_lock := false     # External lock (animations, stun, etc)
var is_guarding := false
var can_use_tool := true     # Cooldown system

var life: int
var knockback_velocity := Vector2.ZERO
var last_input_dir := Vector2.DOWN
var firearm_weapon: FirearmWeapon
var firearm_muzzle: Marker2D
var firearm_tool_button: Button

# Inventory
var collected := {
	"wood": 0,
	"stone": 0,
	"meat": 0
}

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

	toolbox_panel.z_index=7
	z_index = 4
	scale = Vector2(0.7, 0.7)
	life = max_life
	progress_bar.max_value = max_life
	progress_bar.value = life

	toolbox_panel.hide()
	use_timer.wait_time = use_duration
	use_timer.one_shot = true
	_setup_firearm()
	_setup_firearm_tool_button()

# --------------------------------------------------
# PICKUP RESOURCE FUNCTION
# --------------------------------------------------
func pickup_resource(resource_node) -> void:
	var resource_type = resource_node.resource_type
	if resource_type in collected:
		collected[resource_type] += 1
		print("Collected ", resource_type, ": ", collected[resource_type])
		# Call the resource's collect function
		if resource_node.has_method("collect"):
			resource_node.collect()
		else:
			resource_node.queue_free()

# --------------------------------------------------
# AUTO-PICKUP WHEN RESOURCE ENTERS ZONE
# --------------------------------------------------
func _on_resource_entered(area: Area2D) -> void:
	# Check if it's a collectible resource
	if area.has_method("collect") :#and area.has_property("resource_type"):
		if not area.collected:
			var resource_type = area.resource_type
			# Auto-collect if we're using the right tool
			if (resource_type == "wood" and current_tool == Tool.AXE) or \
			   (resource_type == "stone" and current_tool == Tool.PICKAXE) or \
			   (resource_type == "meat" and current_tool == Tool.KNIFE):
				pickup_resource(area)

# --------------------------------------------------
# INPUT (UI ONLY)
# --------------------------------------------------
func _input(event: InputEvent) -> void:
	if not active or state == State.DEAD:
		return

	# Toggle toolbox with T key
	if event.is_action_pressed("tools"):
		toolbox_panel.visible = !toolbox_panel.visible
		get_viewport().set_input_as_handled()

	# Tool usage
	if event.is_action_pressed("attack_knight"):
		use_current_tool()
		hide_toolbox_if_visible()

	if event.is_action_released("attack_knight") and current_tool == Tool.GUN and firearm_weapon:
		firearm_weapon.stop_attack()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("fire_weapon"):
		_fire_weapon_at_mouse()
		get_viewport().set_input_as_handled()

	if event.is_action_released("fire_weapon") and firearm_weapon:
		firearm_weapon.stop_attack()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("reload_weapon"):
		if firearm_weapon:
			firearm_weapon.reload()
		get_viewport().set_input_as_handled()

# --------------------------------------------------
# HIDE TOOLBOX IF VISIBLE
# --------------------------------------------------
func hide_toolbox_if_visible() -> void:
	if toolbox_panel.visible:
		toolbox_panel.hide()


# --------------------------------------------------
# PHYSICS LOOP
# --------------------------------------------------
func _physics_process(delta: float) -> void:
	if active==true:
		GlobalPlayer.active_player_position=global_position
		if firearm_weapon and firearm_weapon.trigger_held:
			firearm_weapon.update_trigger_target(get_global_mouse_position())
	if active and not busy:
		if _is_move_input_pressed():
				hide_toolbox_if_visible()

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
	_update_firearm_muzzle()

# --------------------------------------------------
# MOVEMENT LOGIC (ARROW KEYS ONLY)
# --------------------------------------------------
func handle_movement() -> void:
	if action_lock or is_guarding:
		velocity = Vector2.ZERO
		state = State.IDLE
		return

	var input_vector := _get_move_input_vector()

	if input_vector == Vector2.ZERO:
		velocity = Vector2.ZERO
		state = State.IDLE
		return

	last_input_dir = input_vector.normalized()
	velocity = last_input_dir * speed
	state = State.RUN
	flip_sprite(last_input_dir)
	_update_firearm_muzzle()

func _is_move_input_pressed() -> bool:
	return Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_LEFT) or \
		Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_UP) or \
		Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_A) or \
		Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_W)

func _get_move_input_vector() -> Vector2:
	var input_vector := Vector2.ZERO

	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		input_vector.x += 1
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		input_vector.x -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		input_vector.y += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		input_vector.y -= 1

	return input_vector

# --------------------------------------------------
# FIREARM TEST HOOK
# --------------------------------------------------
func _setup_firearm() -> void:
	if not enable_player_firearm:
		return

	firearm_muzzle = Marker2D.new()
	firearm_muzzle.name = "WeaponMuzzle"
	firearm_muzzle.position = firearm_muzzle_offset
	add_child(firearm_muzzle)

	var data := firearm_data if firearm_data != null else _make_default_firearm_data()

	firearm_weapon = FirearmWeapon.new()
	firearm_weapon.name = "FirearmWeapon"
	firearm_weapon.weapon_data = data
	firearm_weapon.muzzle_path = NodePath("../WeaponMuzzle")
	add_child(firearm_weapon)
	firearm_weapon.equip(self)

func _setup_firearm_tool_button() -> void:
	if not enable_player_firearm or toolbox_panel == null:
		return

	firearm_tool_button = toolbox_panel.get_node_or_null("Gun") as Button
	if firearm_tool_button == null:
		firearm_tool_button = Button.new()
		firearm_tool_button.name = "Gun"
		firearm_tool_button.z_index = 1
		firearm_tool_button.offset_left = 131.33333
		firearm_tool_button.offset_top = 232.0
		firearm_tool_button.offset_right = 195.33333
		firearm_tool_button.offset_bottom = 296.0
		firearm_tool_button.text = "GUN"
		firearm_tool_button.tooltip_text = "Gun"
		firearm_tool_button.focus_mode = Control.FOCUS_NONE
		firearm_tool_button.add_theme_font_size_override("font_size", 15)
		_copy_button_styles(hand_btn, firearm_tool_button)
		toolbox_panel.add_child(firearm_tool_button)

	if not firearm_tool_button.pressed.is_connected(_on_gun_pressed):
		firearm_tool_button.pressed.connect(_on_gun_pressed)

func _copy_button_styles(source: Button, target: Button) -> void:
	if source == null or target == null:
		return

	for style_name in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		var stylebox := source.get_theme_stylebox(style_name)
		if stylebox:
			target.add_theme_stylebox_override(style_name, stylebox)

func _make_default_firearm_data() -> WeaponData:
	var data := WeaponData.new()
	data.weapon_name = "Prototype Rifle"
	data.damage = 2
	data.fire_mode = WeaponData.FireMode.SEMI_AUTO
	data.fire_cooldown = 0.35
	data.spread_degrees = 2.0
	data.magazine_size = 6
	data.reserve_ammo = 24
	data.reload_time = 1.2
	data.projectile_scene = DEFAULT_PROJECTILE_SCENE
	data.projectile_speed = 1300.0
	data.projectile_lifetime = 0.45
	data.hit_groups = ["goblin", "goblinbuildings"]
	return data

func _fire_weapon_at_mouse() -> void:
	if firearm_weapon == null:
		return

	var target_position := get_global_mouse_position()
	_face_firearm_target(target_position)
	firearm_weapon.start_trigger(target_position)

func _face_firearm_target(target_position: Vector2) -> void:
	var dir := target_position - global_position
	if abs(dir.x) > 0.1:
		anim.flip_h = dir.x < 0
	_update_firearm_muzzle()

func _update_firearm_muzzle() -> void:
	if firearm_muzzle == null:
		return

	var x_sign := -1.0 if anim.flip_h else 1.0
	firearm_muzzle.position = Vector2(abs(firearm_muzzle_offset.x) * x_sign, firearm_muzzle_offset.y)

# --------------------------------------------------
# USE CURRENT TOOL WITH Q KEY (WITH COOLDOWN)
# --------------------------------------------------
func use_current_tool() -> void:
	if busy or state == State.DEAD or not active or not can_use_tool:
		return
	
	# Start tool action based on current tool
	match current_tool:
		Tool.HAMMER:
			repeat_tool_action(Tool.HAMMER, "", "hammer", 3)
		Tool.PICKAXE:
			repeat_tool_action(Tool.PICKAXE, "stone", "pickaxe", 5)
		Tool.AXE:
			repeat_tool_action(Tool.AXE, "wood", "axe", 5)
		Tool.KNIFE:
			repeat_tool_action(Tool.KNIFE, "meat", "knife", 1)
		Tool.HAND:
			repeat_tool_action(Tool.HAND, "", "hand", 1)
		Tool.GUN:
			_fire_weapon_at_mouse()


# --------------------------------------------------
# REPEAT TOOL ACTION
# --------------------------------------------------
@warning_ignore("unused_parameter")
func repeat_tool_action(tool: Tool, collect_type: String, tool_name: String, times: int) -> void:
	busy = true
	can_use_tool = false
	state = State.USE
	current_tool = tool

	for i in range(times):
		spawn_tool_effect()                     # Spawn effect
		if collect_type != "" and detector_zone != null:
			collect_nearby_resources(collect_type)  # Collect resources if applicable

		update_animation()                        # Play animation

		# Wait for the cooldown before next repetition
		await get_tree().create_timer(tool_cooldown).timeout

	# After repeating 4 times
	can_use_tool = true
	busy = false
	state = State.IDLE
	update_animation()

func spawn_tool_effect() -> void:
	if current_tool == Tool.HAMMER:
		spawn_repair_effect()
	else:
		spawn_attack_effect()


# --------------------------------------------------
# COLLECT NEARBY RESOURCES
# --------------------------------------------------
func collect_nearby_resources(resource_type: String) -> void:
	if detector_zone == null:
		return
	
	var overlapping_areas = detector_zone.get_overlapping_areas()
	for area in overlapping_areas:
		if area.has_method("collect"):# and area.has_property("resource_type"):
			if area.resource_type == resource_type and not area.collected:
				pickup_resource(area)
				return

# --------------------------------------------------
# PICKUP FUNCTION
# --------------------------------------------------
func pick_nearby_items() -> void:
	if detector_zone == null:
		return
	
	var overlapping_areas = detector_zone.get_overlapping_areas()
	for area in overlapping_areas:
		if area.has_method("collect") and area.has_property("resource_type"):
			if not area.collected:
				var resource_type = area.resource_type
				if resource_type in collected:
					pickup_resource(area)

# --------------------------------------------------
# SPRITE FLIP
# --------------------------------------------------
func flip_sprite(dir: Vector2) -> void:
	if dir.x != 0:
		anim.flip_h = dir.x < 0

# --------------------------------------------------
# TOOL SELECTION / ACTIVATION (UI ONLY)
# --------------------------------------------------
func set_tool_and_activate(tool: Tool) -> void:
	if busy:
		return
	if active:
		current_tool = tool

func set_active() -> void:
	active = true
	toolbox_panel.show()

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
	var fx := attack_effect_scene.instantiate()
	fx.global_position = marker_2d.global_position
	fx.scale=Vector2(0.2,0.2)
	get_parent().add_child(fx)
	
	match current_tool:
		Tool.HAMMER: 
			fx.scale = Vector2(0.2, 0.2)
			hammer_audio.play()
			await get_tree().create_timer(0.5).timeout
			hammer_audio.stop()
		Tool.KNIFE: 
			fx.scale = Vector2(0.2, 0.2)
			knife_audio.play()
		Tool.AXE: 
			fx.scale = Vector2(0.2, 0.2)
			axe.play()
		Tool.PICKAXE: 
			fx.scale = Vector2(0.2, 0.2)
			pickaxe.play()
		Tool.HAND: 
			fx.scale = Vector2(0.2, 0.2)

func spawn_repair_effect() -> void:
	var fx := attack_repair_scene.instantiate()
	fx.global_position = marker_2d.global_position
	fx.scale=Vector2(0.3,0.3)
	fx.z_index=10
	get_parent().add_child(fx)
	
	match current_tool:
		Tool.HAMMER:
			fx.scale = Vector2(0.5, 0.5)
			hammer_audio.play()
			await get_tree().create_timer(0.5).timeout
			hammer_audio.stop()

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
	var suffix := ""
	match current_tool:
		Tool.HAMMER: suffix = "hammer"
		Tool.PICKAXE: suffix = "pickaxe"
		Tool.AXE: suffix = "axe"
		Tool.KNIFE: suffix = "knife"
		Tool.GUN: suffix = ""
		Tool.HAND: suffix = ""

	if state == State.USE:
		if suffix == "":
			pass
		else:
			anim.play("use_" + suffix)
	elif state == State.IDLE:
		if suffix == "":
			anim.play("idle")
		else:
			anim.play("idle_" + suffix)
	elif state == State.RUN:
		if suffix == "":
			anim.play("run")
		else:
			anim.play("run_" + suffix)
	elif state == State.DEAD:
		anim.play("dead")

# --------------------------------------------------
# UI BUTTON SIGNALS
# --------------------------------------------------
func _on_hammer_pressed() -> void:
	set_tool_and_activate(Tool.HAMMER)
	hide_toolbox_if_visible()
	Global.pawn_tool="hammer"
	equip_audio.play()

func _on_pickaxe_pressed() -> void:
	set_tool_and_activate(Tool.PICKAXE)
	hide_toolbox_if_visible()
	Global.pawn_tool="pickaxe"
	equip_audio.play()
func _on_axe_pressed() -> void:
	set_tool_and_activate(Tool.AXE)
	hide_toolbox_if_visible()
	Global.pawn_tool="axe"
	equip_audio.play()

func _on_knife_pressed() -> void:
	set_tool_and_activate(Tool.KNIFE)
	hide_toolbox_if_visible()
	Global.pawn_tool="knife"
	equip_audio.play()

func _on_hand_pressed() -> void:
	set_tool_and_activate(Tool.HAND)
	hide_toolbox_if_visible()
	Global.pawn_tool="hand"
	equip_audio.play()

func _on_gun_pressed() -> void:
	set_tool_and_activate(Tool.GUN)
	hide_toolbox_if_visible()
	Global.pawn_tool="gun"
	equip_audio.play()

func scale_bump(node) -> void:
	var tween = create_tween()
	var original = node.scale

	tween.tween_property(node, "scale", original * 3.15, 0.08)
	tween.tween_property(node, "scale", original, 0.12)

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
	toolbox_panel.show()
	update_selection_indicator()

func deactivate():
	active = false
	set_process(false)
	toolbox_panel.hide()
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
	toolbox_panel.show()
	select_indicator.visible = true
	GlobalPlayer.active_player_position = global_position
