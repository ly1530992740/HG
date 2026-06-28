extends Node2D

# tags to know which level i'm on
const LEVEL_ID := 1   # change to 2, 3, 4...
var level_completed: bool = false

@onready var timer_label: Label = $ui/ui/Panel/TimerLabel

#=====================================
# AUDIO AND MUSIC
#=====================================
@onready var music: AudioStreamPlayer = $Audio/music
@onready var sea: AudioStreamPlayer = $Audio/sea
@onready var fight: AudioStreamPlayer = $Audio/fight
@onready var click: AudioStreamPlayer = $Audio/click

@onready var level_starting: AudioStreamPlayer = $"voice overs/level starting"
@onready var level_ending: AudioStreamPlayer = $"voice overs/level ending"
@onready var sea_bg: TextureRect = $sea

# game over buttons
@onready var retry: Button = $"ui/ui/Game over/retry"
@onready var game_over: Panel = $"ui/ui/Game over"
@onready var next_level_btn: Button = $"ui/ui/Panel/player/unit construction/next_level_btn"
@onready var info_label: Label = $ui/ui/Panel/InfoLabel

func _ready() -> void:
	Global.max_waves+=LEVEL_ID
	target_zoom = camera_2d.zoom


	var Info_color=get_selection_color()
	
	info_label.add_theme_color_override("font_color",Info_color)
	
	sea_bg.texture = preload("res://Textures/Terrain/Tileset/Water Background color.png")
	Global.wave_ended.connect(_on_wave_ended)

	level_starting.play()
	next_level_btn.hide()

	Global.init_level_state()
	Global.set_current_level(LEVEL_ID)
	#Global.level_exit_unlocked = false   # ⭐ NEW

	get_tree().paused = false
	Global.game_over = false

	music.play()
	sea.play()

var last_wave_state := false
func _process(_delta):

	camera_2d.zoom = camera_2d.zoom.lerp(
		target_zoom,
		zoom_speed * _delta
	)
	# Smooth camera zoom
	camera_2d.zoom = camera_2d.zoom.lerp(target_zoom, zoom_speed * _delta)


	if Global.wave_active != last_wave_state:
		last_wave_state = Global.wave_active
		if Global.wave_active:
			music.stop()
			fight.play()
		else:
			fight.stop()
			music.play()

	if level_completed:
		return

	if Global.current_wave >= Global.max_waves:
		info_label.text = "destroy all goblin's houses to complete the level"
		timer_label.text = "All waves completed"

	# ⭐ LEVEL COMPLETE CONDITION
	if Global.current_wave >= Global.max_waves and Global.Goblin_house >= 3:
		complete_level()
		return

	# Timer UI
	var remaining: float = Global.wave_interval - Global.wave_timer
	var minutes: int = int(remaining / 60)
	var seconds: int = int(remaining) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]

	# Game over
	if Global.game_over:
		await get_tree().create_timer(0.2).timeout
		game_over.show()
		get_tree().paused = true
		Global.save_game()

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
	if vol:
		music.volume_db = -80
	else:
		music.volume_db = -5


func _on_quit_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/player/Menu_player.tscn")


func _on_setting_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/settings/settings.tscn")


func _on_retry_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.5).timeout

	get_tree().paused = false
	Global.reset_game()
	get_tree().reload_current_scene()


# ⭐ UPDATED COMPLETE LEVEL
func complete_level() -> void:
	if level_completed:
		return

	level_completed = true
	Global.level_exit_unlocked = true   # unlock gate

	Global.save_game()

	timer_label.text = "task completed"
	info_label.text = "Go north and find the gate"
	next_level_btn.hide()


func go_to_next_level() -> void:
	get_tree().change_scene_to_file("res://Levels/level2/level2.tscn")


func _on_next_level_btn_pressed() -> void:
	Global.save_game()
	click.play()
	await get_tree().create_timer(0.5).timeout
	go_to_next_level()


func _on_wave_ended(wave_number: int) -> void:
	if wave_number == Global.max_waves:
		if not level_ending.playing:
			level_ending.play()
		timer_label.text = "All waves completed"


# =====================
# COLOR FROM GLOBAL
# =====================
func get_selection_color() -> Color:
	match Global.choosed_colour:
		"black":
			return Color.BLACK
		"red":
			return Color.RED
		"blue":
			return Color.BLUE
		"green":
			return Color.GREEN
		_:
			return Color.WHITE

@onready var camera_2d: Camera2D = $selectionbox/Camera2D

#==============================================
# Camera setup
#==============================================
@onready var zoom_in: Button = $"ui/ui/Panel/player/unit resources/zoom in"
@onready var zoom_out: Button = $"ui/ui/Panel/player/unit resources/zoom out"



var zoom_step: float = 0.05
var min_zoom: float = 0.1   # farthest (zoomed OUT)
var max_zoom: float = 0.8   # closest (zoomed IN)

var zoom_speed: float = 8.0   # smoothness

var target_zoom: Vector2

func _on_zoom_in_pressed() -> void:
	if not Global.wave_active:
		click.play()

		var new_zoom = target_zoom.x - zoom_step
		new_zoom = clamp(new_zoom, min_zoom, max_zoom)
		target_zoom = Vector2(new_zoom, new_zoom)

	target_zoom.x = max(target_zoom.x, 0.05)
	target_zoom.y = max(target_zoom.y, 0.05)

func _on_zoom_out_pressed() -> void:

	if not Global.wave_active:
		click.play()

		var new_zoom = target_zoom.x + zoom_step
		new_zoom = clamp(new_zoom, min_zoom, max_zoom)
		target_zoom = Vector2(new_zoom, new_zoom)


	target_zoom.x = max(target_zoom.x, 0.05)
	target_zoom.y = max(target_zoom.y, 0.05)
