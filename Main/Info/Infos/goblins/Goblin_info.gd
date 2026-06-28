extends Node2D
#=======
#Labels
#=======
@onready var tool_info_1: Label = $Tools/sword/Tool01/Tool_info1
@onready var tool_info_2: Label = $Tools/shield/Tool02/Tool_info2

#========
#Nodes
#========
@onready var music: AudioStreamPlayer = $music
@onready var click: AudioStreamPlayer = $click
@onready var swoosh: AudioStreamPlayer = $swoosh

func _ready() -> void:
	music.play()

func _on_quit_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/Info/Info.tscn")

var vol: bool = false
func _on_mute_pressed() -> void:
	click.play()
	vol = !vol
	if vol==true:
		music.volume_db=-80
	elif vol==false:
		music.volume_db=-5
