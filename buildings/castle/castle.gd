extends StaticBody2D

# ==================================================
# NODES
# ==================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var marker1: Marker2D = $left
@onready var marker2: Marker2D = $right
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var explo_detector: Area2D = $ExploDetector
@onready var placement_checker: Area2D = $PlacementChecker
@onready var marker_2d: Marker2D = $Marker2D
@onready var destroyed_fx: AudioStreamPlayer = $destroyed_fx
@onready var construct_fx: AudioStreamPlayer = $construct_fx

# ==================================================
# EXPORTS
# ==================================================
@export var construction_time: float = 2.0
@export var max_life: int = 10

# ==================================================
# CONSTANTS
# ==================================================
const FINAL_SCALE := Vector2(0.8, 0.8)
const DOUBLE_CLICK_TIME := 0.3 # seconds

# ==================================================
# STATES
# ==================================================
enum {
	STATE_CONSTRUCT,
	STATE_IDLE,
	STATE_DESTROYED
}
var state := STATE_CONSTRUCT

# ==================================================
# LIFE / HIT
# ==================================================
var life: int
var is_hit := false
var hit_flash_time := 0.15
var hit_flash_timer := 0.0

# ==================================================
# ARCHERS / KNIGHTS (UNCHANGED)
# ==================================================
var archer_black := preload("res://Archers/Black archer.tscn")
var archer_blue := preload("res://Archers/Blue archer.tscn")
var archer_purple := preload("res://Archers/purple archer.tscn")
var archer_red := preload("res://Archers/red archer.tscn")
var archer_yellow := preload("res://Archers/yellow archer.tscn")
var spawned_archer1: Node2D = null
var spawned_archer2: Node2D = null

var knight_black := preload("res://unit/pawn_/pawn black.tscn")
var knight_blue := preload("res://unit/pawn_/pawn blue.tscn")
var knight_purple := preload("res://unit/pawn_/pawn purple.tscn")
var knight_red := preload("res://unit/pawn_/pawn red.tscn")
var knight_yellow := preload("res://unit/pawn_/pawn yellow.tscn")
var spawned_knight: Node2D = null

# ==================================================
# TIMERS / TWEENS
# ==================================================
var tween: Tween
var construct_timer: Timer
var spawn_timer: Timer

# ==================================================
# MOVEMENT / DRAG
# ==================================================
var is_moving := false
var is_awaiting_placement := false
var movement_colliding := false
var movement_collision_timer := 0.0
var movement_valid := true
var drag_offset := Vector2.ZERO
var original_position := Vector2.ZERO
var overlapping_objects_count := 0

# ==================================================
# DOUBLE CLICK
# ==================================================
var last_click_time := 0.0
var is_selected := false

# ==================================================
# READY
# ==================================================
func _ready() -> void:
	state = STATE_CONSTRUCT
	GlobalPlayer.castle_position=global_position
	z_index = 5
	Global.load_colour()
	life = max_life
	add_to_group("houses")
	input_pickable = true
	collision.disabled = false

	# Set up placement checker for movement
	placement_checker.monitoring = false  # Start disabled
	placement_checker.monitorable = true
	


	load_upgrades()
	apply_upgrades()
	update_upgrade_labels()


	upgrade_health.pressed.connect(func(): upgrade_stat("health"))




	enter_construct_state()

# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
	# Handle hit flash
	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			is_hit = false
			anim.modulate = Color.WHITE
	
	# Handle movement collision flash
	if movement_colliding:
		movement_collision_timer -= delta
		if movement_collision_timer <= 0:
			movement_colliding = false
			_update_movement_color()
	
	# Update position while moving
	if is_moving and not is_awaiting_placement:
		var mouse_pos = get_global_mouse_position()
		global_position = mouse_pos - drag_offset
		
		# Check for collisions using placement checker
		_check_movement_collisions()

# ==================================================
# INPUT HANDLER (DOUBLE CLICK & DRAG)
# ==================================================
@warning_ignore("unused_parameter")
func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var now = Time.get_ticks_msec() / 1000.0
			if now - last_click_time <= DOUBLE_CLICK_TIME:
				_on_double_click()
			else:
				_on_single_click()
			last_click_time = now
		else:
			if is_awaiting_placement:
				_finalize_movement()
			elif is_moving:
				_cancel_movement()

func _on_single_click() -> void:
	is_selected = true
	if anim:
		anim.modulate = Color(1, 1, 1, 1)

func _on_double_click() -> void:
	if state != STATE_IDLE:
		return
	#start_moving()

# ==================================================
# MOVEMENT FUNCTIONS
# ==================================================
func start_moving() -> void:
	original_position = global_position
	is_moving = true
	is_awaiting_placement = false
	movement_valid = true
	movement_colliding = false
	overlapping_objects_count = 0
	drag_offset = get_global_mouse_position() - global_position
	
	# DISABLE main collision shape while moving
	collision.disabled = true
	
	# ENABLE placement checker for collision detection
	placement_checker.monitoring = true
	
	# Store original modulate
	if anim:
		anim.modulate = Color.WHITE
	is_selected = false

func _finalize_movement() -> void:
	if !movement_valid:
		# Can't place here, return to original position
		var return_tween = create_tween()
		return_tween.tween_property(self, "global_position", original_position, 0.3)
		return_tween.tween_callback(_reset_after_movement)
	else:
		# Valid position, finalize
		_reset_after_movement()

func _reset_after_movement() -> void:
	is_moving = false
	is_awaiting_placement = false
	movement_valid = true
	movement_colliding = false
	overlapping_objects_count = 0
	
	# DISABLE placement checker
	placement_checker.monitoring = false
	
	if anim:
		anim.modulate = Color.WHITE
	
	# Re-enable input and RE-ENABLE collision shape
	input_pickable = true
	collision.disabled = false

func _cancel_movement() -> void:
	# Return to original position
	var return_tween = create_tween()
	return_tween.tween_property(self, "global_position", original_position, 0.3)
	return_tween.tween_callback(_reset_after_movement)

# ==================================================
# PLACEMENT CHECKER SIGNAL HANDLERS
# ==================================================
func _on_placement_checker_area_entered(area: Area2D) -> void:
	if not is_moving:
		return
	
	var parent = area.get_parent()
	if parent and parent != self:
		# Check if it's a building or blocked area
		if parent.is_in_group("houses") or parent.is_in_group("block_building"):
			overlapping_objects_count += 1
			_update_collision_state()

func _on_placement_checker_area_exited(area: Area2D) -> void:
	if not is_moving:
		return
	
	var parent = area.get_parent()
	if parent and parent != self:
		# Check if it was a building or blocked area
		if parent.is_in_group("houses") or parent.is_in_group("block_building"):
			overlapping_objects_count = max(0, overlapping_objects_count - 1)
			_update_collision_state()

func _on_placement_checker_body_entered(body: Node) -> void:
	if not is_moving:
		return
	
	if body != self:
		# Check if it's a building or blocked area
		if body.is_in_group("houses") or body.is_in_group("block_building"):
			overlapping_objects_count += 1
			_update_collision_state()

func _on_placement_checker_body_exited(body: Node) -> void:
	if not is_moving:
		return
	
	if body != self:
		# Check if it was a building or blocked area
		if body.is_in_group("houses") or body.is_in_group("block_building"):
			overlapping_objects_count = max(0, overlapping_objects_count - 1)
			_update_collision_state()

func _update_collision_state() -> void:
	if not is_moving:
		return
	
	# Debug: Uncomment to see overlap count
	# print("Overlapping objects: ", overlapping_objects_count)
	
	# Valid if no overlapping objects
	movement_valid = (overlapping_objects_count == 0)
	
	# Update visual feedback
	_update_movement_color()
	
	# Flash red if colliding
	if not movement_valid and not movement_colliding:
		movement_colliding = true
		movement_collision_timer = 0.2
		if anim:
			anim.modulate = Color.RED

# ==================================================
# COLLISION DETECTION FOR MOVEMENT (Using placement checker)
# ==================================================
func _check_movement_collisions() -> void:
	if !is_moving or is_awaiting_placement:
		return
	
	# Update movement validity based on current overlap count
	movement_valid = (overlapping_objects_count == 0)
	
	# Update visual feedback
	_update_movement_color()

func _update_movement_color() -> void:
	if !is_moving or movement_colliding or is_awaiting_placement:
		return
	
	if anim:
		if movement_valid:
			anim.modulate = Color.GREEN
		else:
			anim.modulate = Color.RED

# ==================================================
# GLOBAL INPUT HANDLING FOR MOVEMENT
# ==================================================
func _unhandled_input(event: InputEvent) -> void:
	if is_moving and event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if is_awaiting_placement:
				_finalize_movement()
			else:
				# First click release - wait for placement
				is_awaiting_placement = true
				_update_movement_color()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			# Right click cancels movement
			_cancel_movement()

# ==================================================
# UTILITY: CLEAR TIMERS/TWEENS
# ==================================================
func clear_timers_and_tweens() -> void:
	if tween and tween.is_running():
		tween.kill()
	tween = null

	if construct_timer:
		construct_timer.queue_free()
		construct_timer = null

	if spawn_timer:
		spawn_timer.queue_free()
		spawn_timer = null


# ==================================================
# STATE FUNCTIONS
# ==================================================
func enter_construct_state() -> void:
	clear_timers_and_tweens()
	state = STATE_CONSTRUCT
	anim.play("construct")
	construct_fx.play()
	scale = Vector2.ZERO
	collision.disabled = true
	input_pickable = false

	tween = create_tween()
	tween.tween_property(self, "scale", FINAL_SCALE, construction_time)

	construct_timer = Timer.new()
	construct_timer.wait_time = construction_time
	construct_timer.one_shot = true
	add_child(construct_timer)
	construct_timer.timeout.connect(_on_construct_finished)
	construct_timer.start()

func _on_construct_finished() -> void:
	enter_idle_state()
	add_to_group("castle")
	construct_fx.stop()

func enter_idle_state() -> void:
	clear_timers_and_tweens()
	state = STATE_IDLE
	life = max_life
	scale = FINAL_SCALE
	anim.play("idle")
	collision.disabled = false
	input_pickable = true
	
	# Reset movement variables
	is_moving = false
	is_awaiting_placement = false
	movement_valid = true
	movement_colliding = false
	overlapping_objects_count = 0
	
	# Ensure placement checker is disabled
	placement_checker.monitoring = false
	
	if anim:
		anim.modulate = Color.WHITE

	spawn_archer()
	spawn_knight()

func enter_destroyed_state() -> void:
	if state == STATE_DESTROYED or Global.game_over:
		return

	state = STATE_DESTROYED
	Global.game_over = true

	is_selected = false

	# =========================
	# DISABLE DAMAGE IMMEDIATELY
	# =========================
	collision.disabled = true
	explo_detector.monitoring = false
	placement_checker.monitoring = false
	placement_checker.monitorable = false
	input_pickable = false

	emit_signal("died", self)

	# =========================
	# CLEAR TIMERS
	# =========================
	clear_timers_and_tweens()

	# =========================
	# VISUAL / AUDIO
	# =========================
	anim.play("destroyed")
	destroyed_fx.play()
	remove_from_group("castle")

	# =========================
	# DISABLE SPAWNED UNITS COLLISION
	# =========================
	if spawned_knight and spawned_knight.has_node("CollisionShape2D"):
		spawned_knight.get_node("CollisionShape2D").disabled = true

	if spawned_archer1 and spawned_archer1.has_node("CollisionShape2D"):
		spawned_archer1.get_node("CollisionShape2D").disabled = true

	if spawned_archer2 and spawned_archer2.has_node("CollisionShape2D"):
		spawned_archer2.get_node("CollisionShape2D").disabled = true

	# =========================
	# REMOVE UNITS
	# =========================
	if spawned_archer1:
		spawned_archer1.queue_free()
		spawned_archer1 = null

	if spawned_archer2:
		spawned_archer2.queue_free()
		spawned_archer2 = null

	if spawned_knight:
		spawned_knight.queue_free()
		spawned_knight = null

	# =========================
	# RESET MOVEMENT FLAGS
	# =========================
	is_moving = false
	is_awaiting_placement = false
	overlapping_objects_count = 0



# ==================================================
# DAMAGE
# ==================================================
func _on_explo_detector_area_entered(area: Area2D) -> void:
	if state != STATE_IDLE:
		return
	if area.is_in_group("explo"):
		take_damage(1)

func take_damage(amount: int) -> void:
	if state != STATE_IDLE:
		return

	life -= amount
	life = max(life, 0)

	is_hit = true
	flash_red_once()

	if life <= 0:
		enter_destroyed_state()



var hit_tween: Tween
func flash_red_once() -> void:
	# Stop previous flash if it exists
	if hit_tween and hit_tween.is_running():
		hit_tween.kill()

	anim.modulate = Color.WHITE

	hit_tween = create_tween()
	hit_tween.tween_property(anim, "modulate", Color.RED, 0.05)
	hit_tween.tween_property(anim, "modulate", Color.WHITE, 0.08)

# ==================================================
# SPAWN ARCHER
# ==================================================
func spawn_archer() -> void:
	if spawned_archer1 != null:
		return
	if spawned_archer2 != null:
		return

	var archer_scene: PackedScene
	match Global.choosed_colour.to_lower():
		"black": archer_scene = archer_black
		"blue": archer_scene = archer_blue
		"purple": archer_scene = archer_purple
		"red": archer_scene = archer_red
		"yellow": archer_scene = archer_yellow
		_:
			return

	spawned_archer1 = archer_scene.instantiate()
	spawned_archer2 = archer_scene.instantiate()
	add_child(spawned_archer1)
	add_child(spawned_archer2)
	spawned_archer1.global_position = marker1.global_position
	spawned_archer2.global_position = marker2.global_position
	spawned_archer1.z_index = 5
	spawned_archer1.scale = Vector2(0.7, 0.7)
	spawned_archer2.z_index = 5
	spawned_archer2.scale = Vector2(0.7, 0.7)
# ==================================================
 #SPAWN KNIGHTS
# ==================================================
func spawn_knight() -> void:
	if not Global.can_spawn_pawn():
		return

	if spawned_knight != null:
		return

	var knight_scene: PackedScene

	match Global.choosed_colour.to_lower():
		"black": knight_scene = knight_black
		"blue": knight_scene = knight_blue
		"purple": knight_scene = knight_purple
		"red": knight_scene = knight_red
		"yellow": knight_scene = knight_yellow
		_:
			return

	spawned_knight = knight_scene.instantiate()
	get_parent().add_child(spawned_knight)

	spawned_knight.global_position = marker_2d.global_position
	spawned_knight.scale = Vector2(0.7, 0.7)
	spawned_knight.z_index = 4

	# ⭐ IMPORTANT — detect death automatically
	spawned_knight.tree_exited.connect(_on_knight_died)

func _on_knight_died() -> void:
	spawned_knight = null

	# Do not respawn if castle destroyed
	if state != STATE_IDLE:
		return

	# Optional delay before respawn
	if is_instance_valid(self):
		await get_tree().create_timer(2.0).timeout

	spawn_knight()

var construct_progress: float = 0.0
var is_under_construction := true



var upgrade_levels = {
	"health": 0,
	"repair": 0,
	"construct": 0
}

const MAX_UPGRADE_LEVEL := 5
const SAVE_PATH := "user://building_upgrades.save"



#=============================================================
# upgraders and save system
#==============================================================

@onready var upgrade: Button = $upgrade # button used to show() or hide() the updater Node2D

@onready var updater: Node2D = $updater # node used to hide and show the UI or updater panel and sutff

@onready var upgrade_health: Button = $updater/health_up/upgrade_health
@onready var upgrade_constructiontime: Button = $"updater/construction time_up/upgrade_constructiontime"

@onready var health_label: Label = $updater/health_up/upgrade_health/Label
@onready var construct_label: Label = $"updater/construction time_up/upgrade_constructiontime/Label"


func apply_upgrades():
	max_life = 6 + upgrade_levels.health * 2
	construction_time = max(1.0, 3.0 - upgrade_levels.construct * 0.4)

func _toggle_updater():
	updater.visible = !updater.visible

func upgrade_stat(stat:String):

	if upgrade_levels[stat] >= MAX_UPGRADE_LEVEL:
		return

	# example cost
	if Global.gold < 10:
		return

	Global.gold -= 10
	upgrade_levels[stat] += 1

	apply_upgrades()
	save_upgrades()
	update_upgrade_labels()


	match stat:
		"health":
			scale_bump(health_label)
		"construct":
			scale_bump(construct_label)


func save_upgrades():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var(upgrade_levels)

func load_upgrades():
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	upgrade_levels = file.get_var()


func _on_upgrade_pressed() -> void:
	_toggle_updater()

func scale_bump(node: Control) -> void:
	if node == null:
		return

	var tweeny = create_tween()
	var original := node.scale

	tweeny.tween_property(node, "scale", original * 1.15, 0.08)
	tweeny.tween_property(node, "scale", original, 0.12)

func update_upgrade_labels():

	# HEALTH
	if upgrade_levels["health"] >= MAX_UPGRADE_LEVEL:
		health_label.text = "MAX UPGRADED"
		upgrade_health.disabled = true
	else:
		health_label.text = "Health +" + str(upgrade_levels["health"])
		upgrade_health.disabled = false

	# CONSTRUCT
	if upgrade_levels["construct"] >= MAX_UPGRADE_LEVEL:
		construct_label.text = "MAX UPGRADED"
		upgrade_constructiontime.disabled = true
	else:
		construct_label.text = "Build +" + str(upgrade_levels["construct"])
		upgrade_constructiontime.disabled = false


var updater_tween: Tween
func show_updater():
	if updater_tween and updater_tween.is_running():
		updater_tween.kill()

	show_updater()
	updater.modulate.a = 0.0

	updater_tween = create_tween()
	updater_tween.tween_property(updater, "modulate:a", 1.0, 0.18)
func hide_updater():
	if not updater.visible:
		return

	if updater_tween and updater_tween.is_running():
		updater_tween.kill()

	updater_tween = create_tween()
	updater_tween.tween_property(updater, "modulate:a", 0.0, 0.15)
	updater_tween.tween_callback(func():
		hide_updater()
		updater.modulate.a = 1.0
	)

func _on_hider_timeout() -> void:
	updater.visible=false
