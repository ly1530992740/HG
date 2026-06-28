extends StaticBody2D

# ==================================================
# NODES
# ==================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var marker2D: Marker2D = $Marker2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var explo_detector: Area2D = $ExploDetector
@onready var repair_detector: Area2D = $RepairDetector
@onready var placement_checker: Area2D = $PlacementChecker

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
@export var pawn_capacity: int = 0
@export var spawn_interval: float = 2.0
@export var min_spawn_distance: float = 40.0

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
# PAWNS
# ==================================================
var pawn_black := preload("res://unit/pawn_/pawn black.tscn")
var pawn_blue := preload("res://unit/pawn_/pawn blue.tscn")
var pawn_purple := preload("res://unit/pawn_/pawn purple.tscn")
var pawn_red := preload("res://unit/pawn_/pawn red.tscn")
var pawn_yellow := preload("res://unit/pawn_/pawn yellow.tscn")

var spawned_pawns: Array[Node2D] = []

# ==================================================
# TIMERS
# ==================================================
var tween: Tween
var construct_timer: Timer
var spawn_timer: Timer
var repair_timer: Timer

# ==================================================
# MOVEMENT / PLACEMENT
# ==================================================
var is_moving := false
var drag_offset := Vector2.ZERO
var original_position := Vector2.ZERO
var overlapping_objects := 0
var placement_valid := true

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
	life = 0
	add_to_group("houses")
	input_pickable = true
	collision.disabled = false

	placement_checker.monitoring = false
	placement_checker.monitorable = true

	placement_checker.area_entered.connect(_on_placement_area_entered)
	placement_checker.area_exited.connect(_on_placement_area_exited)
	placement_checker.body_entered.connect(_on_placement_body_entered)
	placement_checker.body_exited.connect(_on_placement_body_exited)

	explo_detector.area_entered.connect(_on_explo_area_entered)

	enter_destroyed_state()

# ==================================================
# PROCESS
# ==================================================
@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	if state == STATE_IDLE and spawned_pawns.size() < pawn_capacity and Global.can_spawn_pawn():
		spawn_pawn()

	if is_moving:
		global_position = get_global_mouse_position() - drag_offset
		_update_placement_color()

# ==================================================
# INPUT
# ==================================================
@warning_ignore("unused_parameter")
func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var now := Time.get_ticks_msec() / 1000.0
		if now - last_click_time <= DOUBLE_CLICK_TIME:
			_try_start_moving()
		last_click_time = now

func _unhandled_input(event: InputEvent) -> void:
	if not is_moving:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finalize_placement()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_movement()

# ==================================================
# MOVEMENT
# ==================================================
func _try_start_moving() -> void:
	if state != STATE_IDLE:
		return

	is_moving = true
	original_position = global_position
	drag_offset = get_global_mouse_position() - global_position
	overlapping_objects = 0
	placement_valid = true
	place_fx.play()

	collision.disabled = true
	placement_checker.monitoring = true
	anim.modulate = Color.GREEN

func _finalize_placement() -> void:
	if placement_valid:
		_end_movement()
	else:
		var t := create_tween()
		t.tween_property(self, "global_position", original_position, 0.25)
		t.finished.connect(_end_movement)

func _cancel_movement() -> void:
	var t := create_tween()
	t.tween_property(self, "global_position", original_position, 0.25)
	t.finished.connect(_end_movement)

func _end_movement() -> void:
	is_moving = false
	placement_checker.monitoring = false
	collision.disabled = false
	anim.modulate = Color.WHITE
	drop_fx.play()

# ==================================================
# PLACEMENT CHECKER
# ==================================================
func _on_placement_area_entered(area: Area2D) -> void:
	var p := area.get_parent()
	if p != self and (p.is_in_group("houses") or p.is_in_group("block_building")):
		overlapping_objects += 1

func _on_placement_area_exited(area: Area2D) -> void:
	var p := area.get_parent()
	if p != self and (p.is_in_group("houses") or p.is_in_group("block_building")):
		overlapping_objects = max(0, overlapping_objects - 1)

func _on_placement_body_entered(body: Node) -> void:
	if body != self and (body.is_in_group("houses") or body.is_in_group("block_building")):
		overlapping_objects += 1

func _on_placement_body_exited(body: Node) -> void:
	if body != self and (body.is_in_group("houses") or body.is_in_group("block_building")):
		overlapping_objects = max(0, overlapping_objects - 1)

func _update_placement_color() -> void:
	placement_valid = overlapping_objects == 0
	anim.modulate = Color.GREEN if placement_valid else Color.RED

# ==================================================
# STATE FLOW
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
	construct_timer.timeout.connect(enter_idle_state)
	construct_timer.start()

func enter_idle_state() -> void:
	clear_timers_and_tweens()
	state = STATE_IDLE
	life = max_life
	scale = FINAL_SCALE
	anim.play("idle")
	construct_fx.stop()
	collision.disabled = false
	input_pickable = true
	start_spawn_timer()

func enter_destroyed_state() -> void:
	if state == STATE_DESTROYED:
		return
	clear_timers_and_tweens()
	state = STATE_DESTROYED
	anim.play("destroyed")
	destroyed_fx.play()
	collision.disabled = true
	input_pickable = false
	repair_detector.monitoring = true
	repair_detector.monitorable = true
	remove_from_group("building")
	add_to_group("damaged_buildings")


# ==================================================
# SPAWN PAWN
# ==================================================
func start_spawn_timer() -> void:
	if spawn_timer:
		spawn_timer.queue_free()

	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.autostart = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(spawn_pawn)

func spawn_pawn() -> void:
	if spawned_pawns.size() >= pawn_capacity or not Global.can_spawn_pawn():
		return

	var pawn_scene: PackedScene
	match Global.choosed_colour.to_lower():
		"black": pawn_scene = pawn_black
		"blue": pawn_scene = pawn_blue
		"purple": pawn_scene = pawn_purple
		"red": pawn_scene = pawn_red
		"yellow": pawn_scene = pawn_yellow
		_: return

	var pawn = pawn_scene.instantiate()
	get_parent().add_child(pawn)
	pawn.z_index=4
	pawn.scale=Vector2(0.7,0.7)
	pawn.global_position = marker2D.global_position
	spawned_pawns.append(pawn)
	Global.consume_meat(1)

# ==================================================
# DAMAGE / REPAIR
# ==================================================
func _on_explo_area_entered(area: Area2D) -> void:
	if state == STATE_IDLE and area.is_in_group("explo"):
		take_damage(1)

func take_damage(amount: int) -> void:
	life -= amount
	if life <= 0:
		enter_destroyed_state()


func _finish_repair() -> void:
	var fresh = preload("res://buildings/Houses/house1.tscn").instantiate()
	get_parent().add_child(fresh)
	add_to_group("building")
	construct_fx.stop()
	remove_from_group("damaged_buildings")
	fresh.global_position = global_position
	queue_free()

# ==================================================
# CLEANUP
# ==================================================
func clear_timers_and_tweens() -> void:
	if tween and tween.is_running():
		tween.kill()
	if construct_timer:
		construct_timer.queue_free()
	if spawn_timer:
		spawn_timer.queue_free()
	if repair_timer:
		repair_timer.queue_free()

func repair_now() -> void:
	if repair_timer:
		repair_timer.queue_free()
		repair_timer = null
	if state != STATE_DESTROYED:
		return

	if repair_timer:
		return # already repairing

	anim.play("construct")
	construct_fx.play()

	repair_timer = Timer.new()
	repair_timer.wait_time = repair_time
	repair_timer.one_shot = true
	add_child(repair_timer)

	repair_timer.timeout.connect(_finish_repair)
	repair_timer.start()


func _on_repair_detector_area_entered(area: Area2D) -> void:
	if area.is_in_group("repair_effect"):
		repair_now()
