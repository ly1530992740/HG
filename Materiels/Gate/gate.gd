extends Area2D

var fade_scene = preload("res://transitions scenes/fade.tscn")
@onready var sprite_2d: Sprite2D = $Sprite2D

func _ready() -> void:
	sprite_2d.hide()

func _on_body_entered(body):

	if not body.is_in_group("player"):
		return

	# Gate locked
	if !Global.level_exit_unlocked:
		return

	enter_next_level()


func enter_next_level():

	var fade = fade_scene.instantiate()
	get_tree().current_scene.add_child(fade)
	fade.start_fade()

	await get_tree().create_timer(0.6).timeout

	var next_level := Global.current_level_id + 1

	if Global.LEVEL_SCENES.has(next_level):
		Global.current_level_id = next_level
		get_tree().change_scene_to_file(
			Global.LEVEL_SCENES[next_level]
		)
