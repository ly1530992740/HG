extends StaticBody2D

# =========================
# CONSTANTS
# =========================
const GOLD_SCENE := preload("res://Materiels/Gold/goldstone3.tscn")
const RESTORE_TIME := 20.0
const HIT_COOLDOWN := 0.5

# =========================
# NODES
# =========================
@onready var mine_zone: Area2D = $"mine zone"
@onready var anim: AnimatedSprite2D = $anim
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var health_bar: ProgressBar = $health_bar
@onready var rock_audio: AudioStreamPlayer = $rock_audio

# =========================
# VARIABLES
# =========================
var max_life := 5
var current_life := max_life
var is_regenerating := false
var can_take_damage := true

var restore_timer: Timer
var hit_cooldown_timer: Timer

# =========================
# READY
# =========================
func _ready() -> void:
	z_index = 4
	add_to_group("block_building")

	setup_restore_timer()
	setup_hit_cooldown()

	health_bar.max_value = max_life
	health_bar.value = current_life
	health_bar.visible = false

	mine_zone.area_entered.connect(_on_mine_zone_area_entered)

# =========================
# TIMER SETUP
# =========================
func setup_restore_timer() -> void:
	restore_timer = Timer.new()
	restore_timer.one_shot = true
	restore_timer.wait_time = RESTORE_TIME
	add_child(restore_timer)
	restore_timer.timeout.connect(_on_restore_timer_timeout)

func setup_hit_cooldown() -> void:
	hit_cooldown_timer = Timer.new()
	hit_cooldown_timer.one_shot = true
	hit_cooldown_timer.wait_time = HIT_COOLDOWN
	add_child(hit_cooldown_timer)
	hit_cooldown_timer.timeout.connect(func(): can_take_damage = true)

# =========================
# PLAYER INTERACTION
# =========================
func _on_mine_zone_area_entered(area: Area2D) -> void:
	if not can_take_damage:
		return

	if area.is_in_group("attackeffect") and Global.pawn_tool == "pickaxe":
		take_damage()

# =========================
# DAMAGE SYSTEM
# =========================
func take_damage() -> void:
	if current_life <= 0 or is_regenerating:
		return

	can_take_damage = false
	hit_cooldown_timer.start()

	current_life -= 1
	rock_audio.play()
	health_bar.visible = true
	health_bar.value = current_life

	spawn_gold()
	play_hit_feedback()
	update_transparency()

	if current_life <= 0:
		handle_depletion()


# =========================
# VISUAL FEEDBACK
# =========================
func play_hit_feedback() -> void:
	anim.modulate = Color.RED
	anim.create_tween().tween_property(anim, "modulate", Color.WHITE, 0.25)

func handle_depletion() -> void:
	is_regenerating = true
	health_bar.visible = false

	# Disable collisions
	collision_shape.disabled = true
	mine_zone.monitoring = false

	# Depleted visual
	anim.modulate = Color(1, 0.3, 0.3, 0.5)
	update_transparency()

	restore_timer.start()


# =========================
# GOLD SPAWN
# =========================
func spawn_gold() -> void:
	var gold_count := randi_range(1, 3)

	for i in range(gold_count):
		var gold = GOLD_SCENE.instantiate()
		get_parent().add_child(gold)

		var offset := Vector2(
			randf_range(-35, 35),
			randf_range(75, 105)
		)

		gold.global_position = global_position + offset
		gold.rotation = randf_range(-PI, PI)
		gold.z_index = 4

# =========================
# RESTORATION SYSTEM
# =========================
func _on_restore_timer_timeout() -> void:
	current_life = max_life
	is_regenerating = false
	can_take_damage = true

	health_bar.value = current_life

	# Enable collisions again
	collision_shape.disabled = false
	mine_zone.monitoring = true

	# Restoration feedback
	anim.modulate = Color.GREEN
	anim.create_tween().tween_property(anim, "modulate", Color.WHITE, 0.5)

	update_transparency()


# =========================
# CLEANUP
# =========================
func _exit_tree() -> void:
	if restore_timer:
		restore_timer.queue_free()
	if hit_cooldown_timer:
		hit_cooldown_timer.queue_free()

func _on_mine_zone_body_entered(body: Node2D) -> void:
	if not can_take_damage:
		return

	if body.is_in_group("attackeffect") and Global.pawn_tool == "pickaxe":
		take_damage()

func update_transparency() -> void:
	if current_life < max_life:
		# Semi-transparent while not fully restored
		anim.modulate.a = 0.5
	else:
		# Fully restored
		anim.modulate.a = 1.0
