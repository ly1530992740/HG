extends Node2D

# In your level scene script
@onready var timer_label: Label = $ui/ui/Panel/TimerLabel

#=====================================
# AUDIO AND MUSIC
#=====================================
@onready var music: AudioStreamPlayer = $Audio/music
@onready var sea: AudioStreamPlayer = $Audio/sea
@onready var fight: AudioStreamPlayer = $Audio/fight
@onready var click: AudioStreamPlayer = $Audio/click

# game over buttons
@onready var retry: Button = $"ui/ui/Game over/retry"
@onready var game_over: Panel = $"ui/ui/Game over"

func _ready():
	get_tree().paused = false          # ✅ ADDED (safety)
	Global.game_over = false
	music.play()
	sea.play()


var last_wave_state := false
func _process(_delta):
	if Global.wave_active != last_wave_state:
		last_wave_state = Global.wave_active

		if Global.wave_active:
			music.stop()
			fight.play()
		else:
			fight.stop()
			music.play()

	if Global.current_wave >= Global.max_waves:
		timer_label.text = "All waves completed"
		return

	var remaining: float = Global.wave_interval - Global.wave_timer
	var minutes: int = int(remaining / 60)
	var seconds: int = int(remaining) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]

	# check for game over state
	if Global.game_over == true:
		await get_tree().create_timer(0.2).timeout
		game_over.show()
		get_tree().paused = true


func _on_info_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/Info/Info.tscn")


var vol: bool = false
func _on_mute_btn_pressed() -> void:
	click.play()
	vol = !vol
	if vol == true:
		music.volume_db = -80
	elif vol == false:
		music.volume_db = -5


func _on_quit_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/player/Menu_player.tscn")


func _on_setting_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/settings/settings.tscn")


# buttons signals
func _on_retry_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout

	get_tree().paused = false          # ✅ CRITICAL FIX
	Global.reset_game()                # ✅ CRITICAL FIX
	get_tree().reload_current_scene()
