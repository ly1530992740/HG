extends StaticBody2D

# =========================
# STATES
# =========================
enum TreeState {
	IDLE,
	CHOPPING,
	CHOPPED,
	GROWING
}

var state: TreeState = TreeState.IDLE
var life=3

# =========================
# NODES
# =========================
@onready var anim: AnimatedSprite2D = $anim
@onready var tree_trunk: Area2D = $tree_trunk
@onready var body: CollisionShape2D = $body
@onready var chopped: CollisionShape2D = $chopped
@onready var cut_audio: AudioStreamPlayer = $cut_audio


# =========================
# CONSTANTS
# =========================
const CHOP_TIME := 1.0
const REGROW_TIME := 15.0
const GROW_TIME := 1.2
const WOOD_SCENE := preload("res://Materiels/wood/wood.tscn")


# =========================
# READY
# =========================
func _ready() -> void:
	scale=Vector2(1.1, 1.1)
	z_index = 5
	add_to_group("trees")
	randomize()
	set_state(TreeState.IDLE)


# =========================
# PLAYER INTERACTION
# =========================
func _on_tree_trunk_area_entered(area: Area2D) -> void:
	if area.is_in_group("attackeffect") and Global.pawn_tool=="axe":
		try_chop()
		life-=1
		red_flash()
		area.queue_free()
		cut_audio.play()
		#await get_tree().create_timer(1.95).timeout
		#cut_audio.stop()


@warning_ignore("shadowed_variable")
func _on_tree_trunk_body_entered(body: Node2D) -> void:
	if body.is_in_group("attackeffect") and Global.pawn_tool=="axe":
		try_chop()
		life-=1


# =========================
# STATE CONTROL
# =========================
func set_state(new_state: TreeState) -> void:
	state = new_state

	match state:
		TreeState.IDLE:
			anim.play("idle")
			scale=Vector2(1.1, 1.1)
			modulate.a = 1.0
			body.disabled = false
			chopped.disabled = true

		TreeState.CHOPPING:
			anim.play("chopping")
			body.disabled = false
			chopped.disabled = true

		TreeState.CHOPPED:
			anim.play("chopped")
			body.disabled = true
			chopped.disabled = false

		TreeState.GROWING:
			anim.play("idle")
			body.disabled = true
			chopped.disabled = true


# =========================
# CHOP LOGIC
# =========================
func try_chop() -> void:
	if life<=0:
		if state != TreeState.IDLE:
			return

		set_state(TreeState.CHOPPING)

		await get_tree().create_timer(CHOP_TIME).timeout

		set_state(TreeState.CHOPPED)

		spawn_wood()
		start_regrow_timer()


# =========================
# WOOD SPAWN (NATURAL)
# =========================
func spawn_wood() -> void:
	var wood_count := randi_range(8, 12)

	for i in range(wood_count):
		var wood = WOOD_SCENE.instantiate()
		get_parent().add_child(wood)

		var x_offset := randf_range(-35, 35)
		var y_offset := randf_range(75, 105)

		wood.global_position = global_position + Vector2(x_offset, y_offset)
		wood.rotation = randf_range(-PI, PI)
		wood.z_index = 4


# =========================
# REGROW SYSTEM
# =========================
func start_regrow_timer() -> void:
	await get_tree().create_timer(REGROW_TIME).timeout
	start_growing()


func start_growing() -> void:
	set_state(TreeState.GROWING)

	# Start small & invisible
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(self, "scale", Vector2(1.1, 1.1), GROW_TIME)
	tween.parallel().tween_property(self, "modulate:a", 1.0, GROW_TIME)

	await tween.finished

	set_state(TreeState.IDLE)

func red_flash() -> void:
	if anim.animation=="chopping":
		anim.modulate = Color.RED
		await get_tree().create_timer(0.12).timeout
		anim.modulate = Color.WHITE
