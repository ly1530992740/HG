extends StaticBody2D

# ==================================================
# NODES
# ==================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var marker1: Marker2D = $Marker2D
@onready var collision1: CollisionShape2D = $CollisionShape2D
@onready var explo_detector: Area2D = $ExploDetector
@onready var repair_detector: Area2D = $RepairDetector
@onready var placement_checker: Area2D = $PlacementChecker
var collision_disabled : bool = false

@onready var destroyed_fx: AudioStreamPlayer = $destroyed_fx
@onready var construct_fx: AudioStreamPlayer = $construct_fx
@onready var place_fx: AudioStreamPlayer = $place_fx
@onready var drop_fx: AudioStreamPlayer = $drop_fx
var is_dead: bool = false
# ==================================================
# EXPORTS
# ==================================================
@export var construction_time: float = 3.0
@export var max_life: int = 6
@export var repair_time: float = 3.0
@export var lancer_capacity: int = 1
@export var spawn_radius: float = 40.0
@export var repair_gold_cost := 30
@export var repair_wood_cost := 20
@export var repair_health_amount: int = 2  # Health restored per repair

# ==================================================
# CONSTANTS
# ==================================================
const FINAL_SCALE := Vector2(0.7, 0.7)
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
# LIFE / HIT / REPAIR
# ==================================================
var life: int
var is_hit := false
var hit_flash_time := 0.15
var hit_flash_timer := 0.0
var is_being_repaired := false
var hit_tween: Tween
var repair_tween: Tween

# ==================================================
# Lancers
# ==================================================
var lancer_black := preload("res://unit/pawn_/pawn black.tscn")
var lancer_blue := preload("res://unit/pawn_/pawn blue.tscn")
var lancer_purple := preload("res://unit/pawn_/pawn purple.tscn")
var lancer_red := preload("res://unit/pawn_/pawn red.tscn")
var lancer_yellow := preload("res://unit/pawn_/pawn yellow.tscn")
var spawned_lancers := [] # store all spawned lancers

# ==================================================
# TIMERS / TWEENS
# ==================================================
var tween: Tween
var construct_timer: Timer
var repair_timer: Timer

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
	z_index = 5
	scale = Vector2(0.8, 0.8)
	Global.load_colour()
	life = max_life
	add_to_group("houses")
	input_pickable = true
	collision1.disabled = false

	placement_checker.monitoring = false
	placement_checker.monitorable = true
	load_upgrades()
	apply_upgrades()
	update_upgrade_labels()


	upgrade_health.pressed.connect(func(): upgrade_stat("health"))
	upgrade_capacity.pressed.connect(func(): upgrade_stat("capacity"))
	upgrade_repairtime.pressed.connect(func(): upgrade_stat("repair"))
	upgrade_constructiontime.pressed.connect(func(): upgrade_stat("construct"))


	enter_construct_state(false)

# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
	# Attempt to spawn lancers if meat is available and we haven't reached capacity
	if state == STATE_IDLE and spawned_lancers.size() < lancer_capacity and Global.can_spawn_pawn():
		spawn_lancers()
	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			is_hit = false
			anim.modulate = Color.WHITE
	
	if movement_colliding:
		movement_collision_timer -= delta
		if movement_collision_timer <= 0:
			movement_colliding = false
			_update_movement_color()
	
	if is_moving and not is_awaiting_placement:
		var mouse_pos = get_global_mouse_position()
		global_position = mouse_pos - drag_offset
		_check_movement_collisions()

# ==================================================
# INPUT HANDLER
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
	start_moving()

# ==================================================
# MOVEMENT FUNCTIONS
# ==================================================
func start_moving() -> void:
	update_collision_logic()
	original_position = global_position
	is_moving = true
	is_awaiting_placement = false
	movement_valid = true
	movement_colliding = false
	overlapping_objects_count = 0
	drag_offset = get_global_mouse_position() - global_position

	collision1.disabled = true
	place_fx.play()

	placement_checker.monitoring = true
	if anim:
		anim.modulate = Color.WHITE
	is_selected = false

func _finalize_movement() -> void:
	if !movement_valid:
		var return_tween = create_tween()
		return_tween.tween_property(self, "global_position", original_position, 0.3)
		return_tween.tween_callback(_reset_after_movement)
	else:
		_reset_after_movement()

func _reset_after_movement() -> void:
	update_collision_logic()
	is_moving = false
	is_awaiting_placement = false
	movement_valid = true
	drop_fx.play()
	movement_colliding = false
	overlapping_objects_count = 0
	placement_checker.monitoring = false
	if anim:
		anim.modulate = Color.WHITE
	input_pickable = true
	collision1.disabled = false

func _cancel_movement() -> void:
	var return_tween = create_tween()
	return_tween.tween_property(self, "global_position", original_position, 0.3)
	return_tween.tween_callback(_reset_after_movement)

# ==================================================
# PLACEMENT CHECKER SIGNAL HANDLERS
# ==================================================
func _on_placement_checker_area_entered(area: Area2D) -> void:
	if not is_moving: return
	var parent = area.get_parent()
	if parent and parent != self:
		if parent.is_in_group("houses") or parent.is_in_group("block_building"):
			overlapping_objects_count += 1
			_update_collision_state()

func _on_placement_checker_area_exited(area: Area2D) -> void:
	if not is_moving: return
	var parent = area.get_parent()
	if parent and parent != self:
		if parent.is_in_group("houses") or parent.is_in_group("block_building"):
			overlapping_objects_count = max(0, overlapping_objects_count - 1)
			_update_collision_state()

func _on_placement_checker_body_entered(body: Node) -> void:
	if not is_moving: return
	if body != self:
		if body.is_in_group("houses") or body.is_in_group("block_building"):
			overlapping_objects_count += 1
			_update_collision_state()

func _on_placement_checker_body_exited(body: Node) -> void:
	if not is_moving: return
	if body != self:
		if body.is_in_group("houses") or body.is_in_group("block_building"):
			overlapping_objects_count = max(0, overlapping_objects_count - 1)
			_update_collision_state()

func _update_collision_state() -> void:
	if not is_moving: return
	movement_valid = (overlapping_objects_count == 0)
	_update_movement_color()
	if not movement_valid and not movement_colliding:
		movement_colliding = true
		movement_collision_timer = 0.2
		if anim:
			anim.modulate = Color.RED

func _check_movement_collisions() -> void:
	if not is_moving or is_awaiting_placement: return
	movement_valid = (overlapping_objects_count == 0)
	_update_movement_color()

func _update_movement_color() -> void:
	if not is_moving or movement_colliding or is_awaiting_placement: return
	if anim:
		anim.modulate = Color.GREEN if movement_valid else Color.RED

func _unhandled_input(event: InputEvent) -> void:
	if is_moving and event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if is_awaiting_placement:
				_finalize_movement()
			else:
				is_awaiting_placement = true
				_update_movement_color()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_cancel_movement()

# ==================================================
# TIMERS / TWEENS UTIL
# ==================================================
func clear_timers_and_tweens() -> void:
	if tween and tween.is_running(): tween.kill()
	tween = null
	if construct_timer: construct_timer.queue_free(); construct_timer = null
	if repair_timer: repair_timer.queue_free(); repair_timer = null

# ==================================================
# STATE FUNCTIONS
# ==================================================
func enter_construct_state(auto_build := false) -> void:
	clear_timers_and_tweens()

	state = STATE_CONSTRUCT
	is_under_construction = true
	construct_progress = 0.0

	anim.play("construct")
	scale = FINAL_SCALE
	input_pickable = false
	collision1.disabled = true

	if auto_build:
		start_construction_progress()

func start_construction_progress():
	if not is_under_construction:
		return

	if repair_timer:
		repair_timer.queue_free()

	repair_timer = Timer.new()
	repair_timer.wait_time = 0.2
	repair_timer.one_shot = false
	add_child(repair_timer)
	repair_timer.timeout.connect(_construct_tick)
	repair_timer.start()
	construct_fx.play()

func _construct_tick():
	if state != STATE_CONSTRUCT:
		return

	construct_progress += 0.2

	# visual scaling progress
	var ratio = clamp(construct_progress / construction_time, 0.0, 1.0)
	scale = FINAL_SCALE * ratio

	if construct_progress >= construction_time:
		is_under_construction = false
		enter_idle_state()


func _on_construct_finished() -> void:
	enter_idle_state()
	update_collision_logic()

func enter_idle_state() -> void:
	construct_fx.stop()
	update_collision_logic()
	clear_timers_and_tweens()
	state = STATE_IDLE
	life = max_life
	scale = FINAL_SCALE
	anim.play("idle")
	collision1.disabled = false
	input_pickable = true
	is_moving = false
	is_awaiting_placement = false
	movement_valid = true
	movement_colliding = false
	overlapping_objects_count = 0
	placement_checker.monitoring = false
	if anim:
		anim.modulate = Color.WHITE

	spawned_lancers.clear()
	spawn_lancers()

signal died(building: Node2D)
func enter_destroyed_state() -> void:
	update_collision_logic()
	is_dead = true
	emit_signal("died") # make sure your goblins are connected to this
	emit_signal("died", self)
	if state == STATE_DESTROYED: return
	clear_timers_and_tweens()
	state = STATE_DESTROYED
	anim.play("destroyed")
	destroyed_fx.play()
	input_pickable = false
	is_moving = false
	is_awaiting_placement = false
	overlapping_objects_count = 0
	remove_from_group("building")
	add_to_group("damaged_buildings")
	is_selected = false
# ==================================================
# DAMAGE
# ==================================================
func _on_explo_detector_area_entered(area: Area2D) -> void:
	if state != STATE_IDLE: return
	if area.is_in_group("explo"):
		take_damage(1)

func take_damage(amount: int) -> void:
	life -= amount
	is_hit = true

	flash_red_once()

	if life <= 0:
		enter_destroyed_state()

func flash_red_once() -> void:
	# Stop previous flash if it exists
	if hit_tween and hit_tween.is_running():
		hit_tween.kill()

	anim.modulate = Color.WHITE

	hit_tween = create_tween()
	hit_tween.tween_property(anim, "modulate", Color.RED, 0.05)
	hit_tween.tween_property(anim, "modulate", Color.WHITE, 0.08)

# ==================================================
# SIMPLE REPAIR SYSTEM
# ==================================================
func _on_repair_detector_area_entered(area: Area2D) -> void:
	if not area.is_in_group("repair_effect"):
		return

	# BUILD if under construction
	if state == STATE_CONSTRUCT:
		start_construction_progress()
		return

	start_repair()

func start_repair() -> void:
	# Don't repair if already at full health or being repaired
	if life >= max_life or is_being_repaired:
		return
	
	# Start repair process
	is_being_repaired = true
	
	# Check if destroyed or just damaged
	if state == STATE_DESTROYED:
		_repair_destroyed()
	else:
		_repair_damaged()

func _repair_damaged() -> void:
	# Instant repair for damaged buildings
	life = min(life + repair_health_amount, max_life)
	
	# Visual feedback
	flash_green_once()
	construct_fx.play()
	
	# Reset repair state
	is_being_repaired = false
	
	# Make sure we're in idle state if fully repaired
	if life == max_life and state != STATE_IDLE:
		enter_idle_state()

func _repair_destroyed() -> void:
	# Green flash when repair starts
	flash_green_once()
	
	# Start construction animation with scaling
	state = STATE_CONSTRUCT
	anim.play("construct")
	construct_fx.play()
	
	# Scale from zero to final scale
	scale = Vector2.ZERO
	input_pickable = false
	
	# Create tween for scaling animation
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "scale", FINAL_SCALE, repair_time)
	
	# Create timer for destroyed building repair
	repair_timer = Timer.new()
	repair_timer.wait_time = repair_time
	repair_timer.one_shot = true
	add_child(repair_timer)
	repair_timer.timeout.connect(_on_destroyed_repair_finished)
	repair_timer.start()

func _on_destroyed_repair_finished() -> void:
	is_dead = true
	# Green flash when repair completes
	flash_green_once()
	
	# Rebuild completely
	life = max_life
	is_being_repaired = false
	enter_idle_state()
	collision1.disabled=false

func show_repair_effect() -> void:
	# Visual effect for repair
	@warning_ignore("shadowed_variable")
	var repair_tween = create_tween()
	repair_tween.tween_property(anim, "modulate", Color.GREEN, 0.2)
	repair_tween.tween_property(anim, "modulate", Color.WHITE, 0.2)
	repair_tween.set_loops(int(repair_time / 0.4))  # Loop for the duration of repair

func flash_green_once() -> void:
	if repair_tween and repair_tween.is_running():
		repair_tween.kill()
	
	repair_tween = create_tween()
	repair_tween.tween_property(anim, "modulate", Color.GREEN, 0.1)
	repair_tween.tween_property(anim, "modulate", Color.WHITE, 0.15)

# ==================================================
# LANCER DEATH HANDLER
# ==================================================
func _on_lancer_died(lancer) -> void:
	if spawned_lancers.has(lancer):
		spawned_lancers.erase(lancer)

# ==================================================
# SPAWN LANCERS
# ==================================================
func spawn_lancers() -> void:
	# Check if we reached capacity
	if spawned_lancers.size() >= lancer_capacity:
		return
	
	# Determine available meat
	var meat_available = Global.meat
	if meat_available <= 0:
		return
	
	# Determine how many lancers we can actually spawn
	var remaining_capacity = lancer_capacity - spawned_lancers.size()
	var spawn_count = min(remaining_capacity, meat_available)
	if spawn_count <= 0:
		return
	
	var lancer_scene: PackedScene
	match Global.choosed_colour.to_lower():
		"black": lancer_scene = lancer_black
		"blue": lancer_scene = lancer_blue
		"purple": lancer_scene = lancer_purple
		"red": lancer_scene = lancer_red
		"yellow": lancer_scene = lancer_yellow
		_:
			return

	var half = int(ceil(spawn_count / 2.0))
	_spawn_lancers_around_marker(marker1.global_position, half, lancer_scene)

func _spawn_lancers_around_marker(center: Vector2, count: int, lancer_scene: PackedScene) -> void:

	var spacing_x := 32.0   # distance between soldiers horizontally
	var spacing_y := 36.0   # distance between rows
	var units_per_row := 4   # medieval line width

	for i in range(count):

		var new_lancer = lancer_scene.instantiate()
		get_parent().add_child(new_lancer)

		new_lancer.z_index = 4
		new_lancer.scale = Vector2(0.7, 0.7)

		# ===== FORMATION POSITION =====
		@warning_ignore("integer_division")
		var row = i / units_per_row
		var column = i % units_per_row

		# center the formation
		var formation_width = (units_per_row - 1) * spacing_x

		var offset_x = column * spacing_x - formation_width / 2
		var offset_y = row * spacing_y

		new_lancer.global_position = center + Vector2(offset_x, offset_y)

		spawned_lancers.append(new_lancer)
		new_lancer.died.connect(_on_lancer_died)

		Global.consume_meat(1)

var last_collision_state: bool = false

func update_collision_logic():
	var new_disabled = (state == STATE_CONSTRUCT) or (state == STATE_DESTROYED) or is_moving
	if new_disabled != collision_disabled:
		collision_disabled = new_disabled
		if collision1:
			collision1.disabled = collision_disabled



var construct_progress: float = 0.0
var is_under_construction := true



var upgrade_levels = {
	"health": 0,
	"capacity": 0,
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
@onready var upgrade_capacity: Button = $updater/capacity_up/upgrade_capacity
@onready var upgrade_repairtime: Button = $"updater/repair time_up/upgrade_repairtime"
@onready var upgrade_constructiontime: Button = $"updater/construction time_up/upgrade_constructiontime"

@onready var health_label: Label = $updater/health_up/upgrade_health/Label
@onready var capacity_label: Label = $updater/capacity_up/upgrade_capacity/Label
@onready var repair_label: Label = $"updater/repair time_up/upgrade_repairtime/Label"
@onready var construct_label: Label = $"updater/construction time_up/upgrade_constructiontime/Label"


func apply_upgrades():
	max_life = 6 + upgrade_levels.health * 2
	#lancer_capacity =upgrade_levels.capacity * 1
	repair_time = max(0.8, 3.0 - upgrade_levels.repair * 0.4)
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
		"capacity":
			scale_bump(capacity_label)
		"repair":
			scale_bump(repair_label)
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

	# REPAIR
	if upgrade_levels["repair"] >= MAX_UPGRADE_LEVEL:
		repair_label.text = "MAX UPGRADED"
		upgrade_repairtime.disabled = true
	else:
		repair_label.text = "Repair +" + str(upgrade_levels["repair"])
		upgrade_repairtime.disabled = false


	# capacity
	if upgrade_levels["capacity"] >= MAX_UPGRADE_LEVEL:
		capacity_label.text = "MAX UPGRADED"
		upgrade_capacity.disabled = true
	else:
		capacity_label.text = "Unit +" + str(upgrade_levels["capacity"])
		upgrade_capacity.disabled = false


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
