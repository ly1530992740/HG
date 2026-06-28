extends Node2D

@onready var music: AudioStreamPlayer = $music
@onready var click: AudioStreamPlayer = $click


# Add this UI node to show error message (can be a Label under the main scene)
@onready var label_error: Label =$"New/Label error"  # create a Label node named "InvalidLabel" in your scene
@onready var error_timer: Timer =$"New/error timer" # create a Timer node named "InvalidTimer"


# Buttons
@onready var attack_btn: Button = $New/buttons/attack_btn
@onready var tool_btn: Button = $New/buttons/tool_btn
@onready var guard_btn: Button = $New/buttons/guard_btn
@onready var pause_btn: Button = $New/buttons/pause_btn
@onready var resume_btn: Button = $New/buttons/resume_btn


# Labels dictionary (keys match your InputMap actions!)
var labels := {}

# Flash timer for “Press a key”
@onready var flash_timer: Timer = $"New/flash timer"
var flash_state := true

# Input state
var waiting_for_input := false
var current_action := ""
var current_label: Label = null


# File path
const SAVE_PATH := "user://keybinds.cfg"
# Blocked keys
const BLOCKED_KEYS = [
	16777221, 32, 9, 16777217, 16777219, 16777223, 16777248, 16777249, 16777251
]



func _ready() -> void:
	music.play()
	# Build labels dictionary
	labels = {
	"attack_knight": $New/buttons/attack_btn/label_attack,
	"tools": $New/buttons/tool_btn/label_tool,
	"guard": $New/buttons/guard_btn/label_guard,
	"pause": $New/buttons/pause_btn/label_pause,
	"resume": $New/buttons/resume_btn/label_resume
}


	# Connect buttons
	attack_btn.pressed.connect(func(): _start_rebinding("attack_knight"))
	tool_btn.pressed.connect(func(): _start_rebinding("tools"))
	guard_btn.pressed.connect(func(): _start_rebinding("guard"))
	pause_btn.pressed.connect(func(): _start_rebinding("pause"))
	resume_btn.pressed.connect(func(): _start_rebinding("resume"))

	# Flash timer
	flash_timer.wait_time = 0.3
	flash_timer.timeout.connect(_on_flash_timer_timeout)

	# Load saved keybinds (or defaults)
	_load_keybinds()
	_update_all_labels()





func _on_quit_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/Menu_select.tscn")


var vol: bool = false
func _on_mute_pressed() -> void:
	click.play()
	vol = !vol
	if vol==true:
		music.volume_db=-80
	elif vol==false:
		music.volume_db=-5

func _exit_tree() -> void:
	music.stop()


func _start_rebinding(action: String) -> void:
	if waiting_for_input:
		return
	current_action = action
	current_label = labels[action]
	waiting_for_input = true
	current_label.text = "Press a key..."
	current_label.visible = true
	flash_state = true
	flash_timer.start()


func _on_flash_timer_timeout() -> void:
	if current_label:
		flash_state = !flash_state
		current_label.visible = flash_state



func _unhandled_input(event: InputEvent) -> void:
	if not waiting_for_input:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var new_keycode = event.keycode

		# Block reserved keys
		if new_keycode in BLOCKED_KEYS:
			_show_invalid_key()
			return

		# Check if already used by another custom action
		for action in labels.keys():
			for old_event in InputMap.action_get_events(action):
				if old_event is InputEventKey and old_event.keycode == new_keycode:
					# If trying to reassign the same key to another action → reject
					if action != current_action:
						_show_invalid_key()
						return

		# Clear current action and assign new key
		InputMap.action_erase_events(current_action)
		var new_event := InputEventKey.new()
		new_event.keycode = new_keycode
		InputMap.action_add_event(current_action, new_event)

		# Update UI
		_update_all_labels()
		_save_keybinds()

		# Reset input state
		waiting_for_input = false
		current_label.visible = true
		current_label = null
		current_action = ""
		flash_timer.stop()
		#_set_all_buttons_enabled(true)



func _update_all_labels() -> void:
	for action in labels.keys():
		_update_label(action)


func _update_label(action: String) -> void:
	@warning_ignore("shadowed_variable_base_class")
	var name = "None"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			name = OS.get_keycode_string(event.keycode)
			break
	labels[action].text = name


func _save_keybinds() -> void:
	var config = ConfigFile.new()
	for action in labels.keys():
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				config.set_value("inputs", action, event.keycode)
	config.save(SAVE_PATH)


func _load_keybinds() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err != OK:
		print("No saved keybinds found, using default.")
		return

	for action in labels.keys():
		if config.has_section_key("inputs", action):
			var keycode = config.get_value("inputs", action)
			var event := InputEventKey.new()
			event.keycode = keycode
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)

func _show_invalid_key():
	label_error.text = "Invalid key!"
	label_error.modulate = Color.WHITE
	label_error.visible = true
	error_timer.start()

func _on_error_timer_timeout() -> void:
	label_error.visible = false
