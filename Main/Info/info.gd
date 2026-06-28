extends Node2D

# ===============================
# Audio
# ===============================
@onready var music: AudioStreamPlayer = $music
@onready var click: AudioStreamPlayer = $click

# ===============================
# Button → Scene mapping
# (Button node name : scene path)
# ===============================
var info_scenes := {
	"archer_info_btn": "res://Main/Info/Infos/archer_info.tscn",
	"monk_info_btn": "res://Main/Info/Infos/pawn_info.tscn",
	"knight_info_btn": "res://Main/Info/Infos/knight_info.tscn",
	"lancer_info_btn": "res://Main/Info/Infos/lancer_info.tscn",
	"pawn_info_btn": "res://Main/Info/Infos/pawn_info.tscn",
	"archery_info_btn":"res://Main/Info/Infos/buildings/archery_info.tscn" ,
	"barracks_info_btn":"res://Main/Info/Infos/buildings/barracks_info.tscn" ,
	"castle_info_btn": "res://Main/Info/Infos/buildings/castle_info.tscn",
	"house1_info_btn":"res://Main/Info/Infos/buildings/house1_info.tscn" ,
	"house2_info_btn": "res://Main/Info/Infos/buildings/house2_info.tscn",
	"house3_info_btn": "res://Main/Info/Infos/buildings/house3_info.tscn",
	"monastery_info_btn":"res://Main/Info/Infos/buildings/monastery_info.tscn" ,
	"tower_info_btn": "res://Main/Info/Infos/buildings/tower_info.tscn",
	"goblin_buildings_info_btn":"res://Main/Info/Infos/goblins/Goblins_buildings_info.tscn" ,
	"Goblinbarrel_info_btn": "res://Main/Info/Infos/goblins/goblin_barrel_info.tscn",
	"Goblintnt_info_btn":"res://Main/Info/Infos/goblins/goblin_tnt_info.tscn" ,
	"Goblintorch_info_btn":"res://Main/Info/Infos/goblins/goblin_torch_info.tscn" 
}

var vol := false

# ===============================
# Ready
# ===============================
func _ready() -> void:
	music.play()
	_connect_info_buttons()

# ===============================
# Connect all buttons automatically
# ===============================
func _connect_info_buttons() -> void:
	for button_name in info_scenes.keys():
		var btn := find_child(button_name, true, false)
		if btn and btn is Button:
			btn.pressed.connect(
				_on_info_button_pressed.bind(info_scenes[button_name])
			)

# ===============================
# Generic info button handler
# ===============================
func _on_info_button_pressed(scene_path: String) -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file(scene_path)

# ===============================
# Mute button
# ===============================
func _on_mute_pressed() -> void:
	click.play()
	vol = !vol
	music.volume_db = -80 if vol else -5

# ===============================
# Quit button
# ===============================
func _on_quit_btn_pressed() -> void:
	click.play()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/Menu_select.tscn")

# ===============================
# Cleanup
# ===============================
func _exit_tree() -> void:
	music.stop()
