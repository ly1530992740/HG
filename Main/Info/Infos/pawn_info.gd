extends Node2D
#=======
#Labels
#=======
@onready var tool_info_1: Label = $Tools/hammer/Tool01/Tool_info1
@onready var tool_info_2: Label = $Tools/axe/Tool02/Tool_info2
@onready var tool_info_3: Label = $Tools/knife/Tool03/Tool_info3
@onready var tool_info_4: Label = $Tools/pickaxe/Tool04/Tool_info4

#========
#Nodes
#========
@onready var music: AudioStreamPlayer = $music
@onready var click: AudioStreamPlayer = $click
@onready var swoosh: AudioStreamPlayer = $swoosh

func _ready() -> void:
	music.play()

#show each label informations
func _on_hammer_mouse_entered() -> void:
	tool_info_1.show()
	swoosh.play()
func _on_axe_mouse_entered() -> void:
	tool_info_2.show()
	swoosh.play()
func _on_knife_mouse_entered() -> void:
	tool_info_3.show()
	swoosh.play()
func _on_pickaxe_mouse_entered() -> void:
	tool_info_4.show()
	swoosh.play()

#hide each label informations
func _on_hammer_mouse_exited() -> void:
	tool_info_1.hide()
func _on_axe_mouse_exited() -> void:
	tool_info_2.hide()
func _on_knife_mouse_exited() -> void:
	tool_info_3.hide()
func _on_pickaxe_mouse_exited() -> void:
	tool_info_4.hide()


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
