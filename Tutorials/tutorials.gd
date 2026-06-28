extends Node2D

# =============================
# UI
# =============================
@onready var timer_label: Label = $ui/ui/Panel/TimerLabel
@onready var skip_button: Button = $ui_instruct/Node2D/SkipButton
@onready var instruction_label: Label = $ui_instruct/Node2D/InstructionLabel

# =============================
# AUDIO
# =============================
@onready var music: AudioStreamPlayer = $Audio/music
@onready var sea: AudioStreamPlayer = $Audio/sea
@onready var fight: AudioStreamPlayer = $Audio/fight
@onready var click: AudioStreamPlayer = $Audio/click
@onready var sea_bg: TextureRect = $sea

# voice over instruction
@onready var voice_over: AudioStreamPlayer = $"voice/voice over"


var last_wave_state := false
var muted := false


func _ready():
	sea_bg.texture=preload("res://Textures/Terrain/Tileset/Water Background color.png")
	voice_over.play()
	voice_over.finished.connect(_on_voice_over_finished)
	Global.meat=50
	Global.wood=50
	Global.gold=50
	# Instruction starts semi-transparent
	instruction_label.modulate.a = 0.5
	instruction_label.text="pass"

	# Skip disabled at start
	skip_button.disabled = true

	# Start audio
	music.play()
	sea.play()

	# Enable skip after 5s
	await get_tree().create_timer(1.5).timeout
	_enable_skip()


func _enable_skip():
	# Fade instruction to full alpha
	var tween := create_tween()
	tween.tween_property(instruction_label, "modulate:a", 1.0, 0.5)

	skip_button.disabled = false


func _process(_delta):
	# Handle wave audio switching
	#if Global.wave_active != last_wave_state:
	#	last_wave_state = Global.wave_active

		#if Global.wave_active:
		#	music.stop()
		#	fight.play()
		#else:
		#	fight.stop()
		#	music.play()

	# Timer display
	#if Global.current_wave >= Global.max_waves:
	#	timer_label.text = "All waves completed"
	#	return

#	var remaining := Global.wave_interval - Global.wave_timer
#	var minutes := int(remaining / 60)
#	var seconds := int(remaining) % 60
	timer_label.text =""


# =============================
# BUTTONS
# =============================

func _on_skip_button_pressed():
	click.play()
	skip_button.disabled = true
	tutomanager.next_step()



func _on_info_btn_pressed():
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/Info/Info.tscn")


func _on_mute_btn_pressed():
	click.play()
	muted = !muted

	var volume := -80 if muted else -5
	music.volume_db = volume
	sea.volume_db = volume
	fight.volume_db = volume
	voice_over.volume_db = volume



func _on_quit_btn_pressed():
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/player/Menu_player.tscn")


func _on_setting_btn_pressed():
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/settings/settings.tscn")

func _on_voice_over_finished():
	await get_tree().create_timer(1.5).timeout
	voice_over.play()

func _exit_tree():
	if voice_over.finished.is_connected(_on_voice_over_finished):
		voice_over.finished.disconnect(_on_voice_over_finished)
