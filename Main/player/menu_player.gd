extends Node2D

@onready var music: AudioStreamPlayer = $music
@onready var click: AudioStreamPlayer = $click
@onready var swoosh: AudioStreamPlayer = $swoosh

@onready var quit_btn: Button = $"UI/buttons/quit btn"
@onready var mute: Button = $UI/buttons/mute
@onready var choose: Button = $"UI/panel/Carousel/Mask/Items/choose icon/choose"
@onready var left_button: TextureButton = $UI/panel/Carousel/LeftButton
@onready var right_button: TextureButton = $UI/panel/Carousel/rightButton


func _ready() -> void:
	music.play()
	quit_btn.pressed.connect(_on_quit_btn_pressed)
	mute.pressed.connect(_on_mute_pressed)
	choose.pressed.connect(_on_choose_pressed)
	left_button.pressed.connect(_on_left_button_pressed)
	right_button.pressed.connect(_on_right_button_pressed)

var vol: bool = false
func _on_mute_pressed() -> void:
	click.play()
	vol = !vol
	if vol==true:
		music.volume_db=-80
	elif vol==false:
		music.volume_db=-5

func _on_quit_btn_pressed() -> void:
	click.play()

func _on_choose_pressed() -> void:
	click.play()

func _exit_tree() -> void:
	music.stop()

func _on_left_button_pressed() -> void:
	click.play()
	swoosh.play()
func _on_right_button_pressed() -> void:
	click.play()
	swoosh.play()
