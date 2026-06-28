extends Panel

# --------------------------------------------------
# NODE REFERENCES
# --------------------------------------------------
@onready var timer: Timer = $Timer
@onready var loading_bar: TextureRect = $loading

# --------------------------------------------------
# READY
# --------------------------------------------------
func _ready() -> void:
	randomize()

	# Ensure starting size
	loading_bar.size = Vector2(0, 64)

	# Start the timer if not already running
	if not timer.is_stopped():
		timer.stop()
	timer.start()

# --------------------------------------------------
# TIMER
# --------------------------------------------------
func _on_timer_timeout() -> void:
	var increments = [
		Vector2(20, 0),
		Vector2(40, 0),
		Vector2(100, 0),
		Vector2(80, 0)
	]

	# Increase loading bar width randomly
	loading_bar.size += increments.pick_random()

	# Check completion
	if loading_bar.size.x >= 850:
		loading_bar.size.x = 850
		timer.stop()

		await get_tree().create_timer(0.001).timeout
		get_tree().change_scene_to_file(
			"res://Main/Main  Menu/Main Menu.tscn"
		)
