extends Node2D

@onready var music: AudioStreamPlayer = $music
@onready var click: AudioStreamPlayer = $click

func _ready() -> void:
	music.play()

func _on_start_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	#get_tree().change_scene_to_file("res://Tutorials/pawn tutorials/pawntutorial1.tscn")
	tutomanager.start_game()
	music.stop()

func _on_quit_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
	music.stop()

var vol: bool = false
func _on_mute_pressed() -> void:
	click.play()
	vol = !vol
	if vol==true:
		music.volume_db=-80
	elif vol==false:
		music.volume_db=-5

func _on_store_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	OS.shell_open("https://itch.io/dashboard")

func _on_info_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Main/Info/Info.tscn")
	music.stop()

func _exit_tree() -> void:
	music.stop()
