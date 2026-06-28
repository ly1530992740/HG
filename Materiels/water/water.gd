extends Area2D

# ==================================================
# SETTINGS
# ==================================================
@onready var sprite_2d: Sprite2D = $Sprite2D

# Splash scene
@export var water_splash_scene: PackedScene = preload("res://Materiels/water/watersplash.tscn")

# Delay before sinking starts (player really steps into water)
@export var enter_delay: float = 0.25

# Duration of drowning animation
@export var drown_time: float = 0.8

# How much the body sinks downward
@export var sink_distance: float = 20.0

# Final scale before disappearing
@export var final_scale: Vector2 = Vector2(0.1, 0.1)


func _process(delta: float) -> void:
	sprite_2d.hide()
	if delta:
		pass

# ==================================================
# BODY ENTER
# ==================================================
func _on_body_entered(body: Node2D) -> void:

	#  affect player group
	if !body.is_in_group("player"):
		return

	# Prevent multiple drowning triggers
	if body.get_meta("is_drowning", false):
		return

	body.set_meta("is_drowning", true)

	start_drowning(body)

	# affect Goblin group
	if !body.is_in_group("goblin"):
		return

	# Prevent multiple drowning triggers
	if body.get_meta("is_drowning", false):
		return

	body.set_meta("is_drowning", true)

	start_drowning(body)

# ==================================================
# DROWNING LOGIC
# ==================================================
func start_drowning(body: Node2D) -> void:

	# ----------------------------------------------
	# Disable player movement safely
	# ----------------------------------------------
	if body.has_method("set_physics_process"):
		body.set_physics_process(false)

	if body.has_method("set_process"):
		body.set_process(false)

	# Optional: stop velocity if CharacterBody2D
	if "velocity" in body:
		body.velocity = Vector2.ZERO


	# ----------------------------------------------
	# Play drowning animation if exists
	# ----------------------------------------------
	if body.has_node("anim"):
		var anim = body.get_node("anim")
		if anim.has_method("play"):
			anim.play("drown")


	# ----------------------------------------------
	# Create Tween (smooth sinking)
	# ----------------------------------------------
	var tween: Tween = create_tween()
	tween.set_parallel(false)

	# Small delay so body enters water naturally
	tween.tween_interval(enter_delay)

	# Target position (sink downward)
	var target_position := body.global_position + Vector2(0, sink_distance)

	# SCALE DOWN
	tween.tween_property(
		body,
		"scale",
		final_scale,
		drown_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# MOVE DOWN (parallel animation)
	tween.parallel().tween_property(
		body,
		"global_position",
		target_position,
		drown_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Optional slight rotation for realism
	tween.parallel().tween_property(
		body,
		"rotation",
		deg_to_rad(10),
		drown_time
	)

	# ----------------------------------------------
	# When drowning finished
	# ----------------------------------------------
	tween.finished.connect(func():
		spawn_water_splash(body.global_position)
		body.queue_free()
	)


# ==================================================
# SPAWN SPLASH EFFECT
# ==================================================
func spawn_water_splash(pos: Vector2) -> void:

	if water_splash_scene == null:
		return

	var splash = water_splash_scene.instantiate()

	# Add to current scene instead of water node
	get_tree().current_scene.add_child(splash)

	splash.global_position = pos
	splash.scale=Vector2(1.5,1.5)
