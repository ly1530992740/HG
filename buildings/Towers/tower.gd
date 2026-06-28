extends StaticBody2D

# ==================================================
# NODES
# ==================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var marker2D: Marker2D = $Marker2D
@onready var collision: CollisionShape2D = $shape
@onready var explo_detector: Area2D = $ExploDetector
@onready var repair_detector: Area2D = $RepairDetector
@onready var placement_checker: Area2D = $PlacementChecker
var collision_disabled : bool = false

@onready var destroyed_fx: AudioStreamPlayer = $destroyed_fx
@onready var construct_fx: AudioStreamPlayer = $construct_fx
@onready var place_fx: AudioStreamPlayer = $place_fx
@onready var drop_fx: AudioStreamPlayer = $drop_fx

# ==================================================
# EXPORTS
# ==================================================
@export var construction_time: float = 2.0
@export var max_life: int = 6
@export var repair_time: float = 4.0
var is_dead: bool = false
# ==================================================
# CONSTANTS
# ==================================================
const FINAL_SCALE := Vector2(0.7, 0.7)
const DOUBLE_CLICK_TIME := 0.3

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
var hit_flash_timer := 0.0

# ==================================================
# ARCHERS
# ==================================================
var archer_black := preload("res://Archers/Black archer.tscn")
var archer_blue := preload("res://Archers/Blue archer.tscn")
var archer_purple := preload("res://Archers/purple archer.tscn")
var archer_red := preload("res://Archers/red archer.tscn")
var archer_yellow := preload("res://Archers/yellow archer.tscn")
var spawned_archer: Node2D = null

# ==================================================
# TIMERS / TWEENS
# ==================================================
var tween: Tween
var construct_timer: Timer
var repair_timer: Timer
var hit_tween: Tween
var repair_tween: Tween

# ==================================================
# MOVEMENT / DRAG
# ==================================================
var is_moving := false
var movement_valid := true
var drag_offset := Vector2.ZERO
var original_position := Vector2.ZERO
var overlapping_objects_count := 0

# ==================================================
# DOUBLE CLICK
# ==================================================
var last_click_time := 0.0

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

	placement_checker.monitoring = false
	placement_checker.monitorable = true



	load_upgrades()
	apply_upgrades()
	update_upgrade_labels()


	upgrade_health.pressed.connect(func(): upgrade_stat("health"))
	upgrade_repairtime.pressed.connect(func(): upgrade_stat("repair"))


	enter_construct_state(true)



# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			is_hit = false
			anim.modulate = Color.WHITE

	if is_moving:
		global_position = get_global_mouse_position() - drag_offset
		_update_movement_color()

# ==================================================
# INPUT
# ==================================================
@warning_ignore("unused_parameter")
func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:

		var now = Time.get_ticks_msec() / 1000.0
		if now - last_click_time <= DOUBLE_CLICK_TIME:
			if state == STATE_IDLE:
				start_moving()
		last_click_time = now

func _unhandled_input(event):
	if not is_moving:
		return

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and not event.pressed:
		_finalize_movement()

# ==================================================
# MOVEMENT
# ==================================================
func start_moving() -> void:
	update_collision_logic()
	is_moving = true
	original_position = global_position
	drag_offset = get_global_mouse_position() - global_position
	overlapping_objects_count = 0
	movement_valid = true
	place_fx.play()

	# 🔥 REMOVE ARCHER WHEN MOVEMENT STARTS
	if spawned_archer:
		spawned_archer.queue_free()
		spawned_archer = null

	# 🔥 FULLY DISABLE COLLISION WHILE MOVING
	collision.disabled = true
	placement_checker.monitoring = true


func _finalize_movement() -> void:
	if movement_valid:
		_reset_after_movement()
	else:
		create_tween() \
			.tween_property(self, "global_position", original_position, 0.25) \
			.finished.connect(_reset_after_movement)

func _reset_after_movement() -> void:
	update_collision_logic()
	is_moving = false
	overlapping_objects_count = 0
	movement_valid = true
	drop_fx.play()

	placement_checker.monitoring = false
	collision.disabled = false
	anim.modulate = Color.WHITE

	# 🔥 RESPAWN ARCHER AFTER VALID PLACEMENT
	if state == STATE_IDLE:
		spawn_archer()

# ==================================================
# PLACEMENT CHECKER
# ==================================================
func _handle_overlap(node: Node, entered: bool) -> void:
	if not is_moving:
		return

	if node == self or is_ancestor_of(node):
		return

	if node.is_in_group("houses") or node.is_in_group("block_building"):
		overlapping_objects_count += 1 if entered else -1
		overlapping_objects_count = max(0, overlapping_objects_count)

func _on_placement_checker_area_entered(area: Area2D) -> void:
	_handle_overlap(area.get_parent(), true)

func _on_placement_checker_area_exited(area: Area2D) -> void:
	_handle_overlap(area.get_parent(), false)

func _on_placement_checker_body_entered(body: Node) -> void:
	_handle_overlap(body, true)

func _on_placement_checker_body_exited(body: Node) -> void:
	_handle_overlap(body, false)

func _update_movement_color() -> void:
	if not is_moving:
		return

	movement_valid = overlapping_objects_count == 0
	anim.modulate = Color.GREEN if movement_valid else Color.RED

# ==================================================
# STATES
# ==================================================
@warning_ignore("unused_parameter")
func enter_construct_state(first_spawn := true) -> void:
	state = STATE_CONSTRUCT
	is_under_construction = true
	construct_progress = 0.0

	anim.play("construct")
	scale = FINAL_SCALE
	collision.disabled = true
	update_collision_logic()

	# IMPORTANT:
	# building waits here until repair effect is detected


func enter_idle_state() -> void:
	update_collision_logic()
	state = STATE_IDLE
	life = max_life
	anim.play("idle")
	construct_fx.stop()
	scale = FINAL_SCALE
	collision.disabled = false
	spawn_archer()

signal died(building: Node2D)
func enter_destroyed_state() -> void:
	update_collision_logic()
	is_dead = true
	emit_signal("died") # make sure your goblins are connected to this
	emit_signal("died", self)
	if state == STATE_DESTROYED:
		return

	state = STATE_DESTROYED
	anim.play("destroyed")
	destroyed_fx.play()



	# Remove spawned archer
	if spawned_archer:
		spawned_archer.queue_free()
		spawned_archer = null
	# Update groups
	remove_from_group("building")
	add_to_group("damaged_buildings")

# ==================================================
# DAMAGE
# ==================================================
func _on_explo_detector_area_entered(area: Area2D) -> void:
	if state == STATE_IDLE and area.is_in_group("explo"):
		take_damage(1)

func take_damage(amount: int) -> void:
	life -= amount
	is_hit = true
	hit_flash_timer = 0.15
	flash_red_once()
	if life <= 0:
		enter_destroyed_state()

func flash_red_once() -> void:
	if hit_tween and hit_tween.is_running():
		hit_tween.kill()
	hit_tween = create_tween()
	hit_tween.tween_property(anim, "modulate", Color.RED, 0.05)
	hit_tween.tween_property(anim, "modulate", Color.WHITE, 0.08)

# ==================================================
# REPAIR SYSTEM
# ==================================================
func _on_repair_detector_area_entered(area: Area2D) -> void:
	if not area.is_in_group("repair_effect"):
		return

	if state == STATE_CONSTRUCT:
		build_progress()
	elif state == STATE_DESTROYED:
		start_repair()

func build_progress() -> void:
	if not is_under_construction:
		return

	if repair_timer:
		return # already building

	flash_green_once()
	construct_fx.play()
	

	repair_timer = Timer.new()
	repair_timer.wait_time = construction_time
	repair_timer.one_shot = true
	add_child(repair_timer)
	repair_timer.timeout.connect(_finish_construction)
	repair_timer.start()

func _finish_construction() -> void:
	is_under_construction = false

	if repair_timer:
		repair_timer.queue_free()
		repair_timer = null

	enter_idle_state()


func start_repair() -> void:
	if state != STATE_DESTROYED:
		return
	
	# Play green flash effect when repair starts
	flash_green_once()
	
	state = STATE_CONSTRUCT
	anim.play("construct")
	construct_fx.play()
	
	# Start repair timer
	repair_timer = Timer.new()
	repair_timer.wait_time = repair_time
	repair_timer.one_shot = true
	add_child(repair_timer)
	repair_timer.timeout.connect(finish_repair)
	repair_timer.start()
	
	# Optional: Show continuous green pulse during repair
	# You can uncomment this if you want a pulsing effect during the entire repair
	# show_repair_pulse()

func finish_repair() -> void:
	is_dead = true
	# Play green flash effect when repair finishes
	flash_green_once()
	
	if repair_timer:
		repair_timer.queue_free()
	
	enter_idle_state()
	
	# Re-enable collision
	collision.disabled=false
	
	# Update groups
	add_to_group("building")
	remove_from_group("damaged_buildings")

func flash_green_once() -> void:
	# Stop any existing repair tween
	if repair_tween and repair_tween.is_running():
		repair_tween.kill()
	
	# Create green flash effect
	repair_tween = create_tween()
	repair_tween.tween_property(anim, "modulate", Color.GREEN, 0.1)
	repair_tween.tween_property(anim, "modulate", Color.WHITE, 0.15)

# Optional: For a continuous pulsing effect during repair
func show_repair_pulse() -> void:
	if repair_tween and repair_tween.is_running():
		repair_tween.kill()
	
	repair_tween = create_tween()
	repair_tween.tween_property(anim, "modulate", Color(0.6, 1.0, 0.6, 1.0), 0.3)  # Light green
	repair_tween.tween_property(anim, "modulate", Color.GREEN, 0.3)  # Bright green
	repair_tween.set_loops()

# ==================================================
# SPAWN ARCHER
# ==================================================
func spawn_archer() -> void:
	if spawned_archer:
		return

	var scene: PackedScene
	match Global.choosed_colour.to_lower():
		"black": scene = archer_black
		"blue": scene = archer_blue
		"purple": scene = archer_purple
		"red": scene = archer_red
		"yellow": scene = archer_yellow
		_: return

	spawned_archer = scene.instantiate()
	add_child(spawned_archer)
	spawned_archer.global_position = marker2D.global_position

var last_collision_state: bool = false

func update_collision_logic():
	var new_disabled = (state == STATE_CONSTRUCT) or (state == STATE_DESTROYED) or is_moving
	if new_disabled != collision_disabled:
		collision_disabled = new_disabled
		if collision:
			collision.disabled = collision_disabled





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
@onready var upgrade_repairtime: Button = $"updater/repair time_up/upgrade_repairtime"
@onready var upgrade_constructiontime: Button = $"updater/construction time_up/upgrade_constructiontime"

@onready var health_label: Label = $updater/health_up/upgrade_health/Label
@onready var repair_label: Label = $"updater/repair time_up/upgrade_repairtime/Label"
@onready var construct_label: Label = $"updater/construction time_up/upgrade_constructiontime/Label"


func apply_upgrades():
	max_life = 6 + upgrade_levels.health * 2
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
