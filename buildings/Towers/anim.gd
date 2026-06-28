extends AnimatedSprite2D

var image_black=preload("res://Textures/Buildings/Black Buildings/Tower.png")
var image_blue=preload("res://Textures/Buildings/Blue Buildings/Tower.png")
var image_purple=preload("res://Textures/Buildings/Purple Buildings/Tower.png")
var image_red=preload("res://Textures/Buildings/Red Buildings/Tower.png")
var image_yellow=preload("res://Textures/Buildings/Yellow Buildings/Tower.png")

func _ready() -> void:
	Global.load_colour()
	if Global.choosed_colour=="black":
		sprite_frames.clear("idle")
		sprite_frames.add_frame("idle",image_black)
		play("idle")
	if Global.choosed_colour=="blue":
		sprite_frames.clear("idle")
		sprite_frames.add_frame("idle",image_blue)
		play("idle")
	if Global.choosed_colour=="purple":
		sprite_frames.clear("idle")
		sprite_frames.add_frame("idle",image_purple)
		play("idle")
	if Global.choosed_colour=="red":
		sprite_frames.clear("idle")
		sprite_frames.add_frame("idle",image_red)
		play("idle")
	if Global.choosed_colour=="yellow":
		sprite_frames.clear("idle")
		sprite_frames.add_frame("idle",image_yellow)
		play("idle")
