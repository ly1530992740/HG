extends Control

@onready var anim: AnimatedSprite2D = $Mask/Items/anim
@onready var left_button: TextureButton = $LeftButton
@onready var right_button: TextureButton = $RightButton

@onready var click: AudioStreamPlayer = $"../../../click"
@onready var swoosh: AudioStreamPlayer = $"../../../swoosh"

var animations := ["black", "red", "blue", "yellow", "purple"]
var current_index := 0
var is_animating := false

const SLIDE_DISTANCE := 80
const TRANSITION_TIME := 0.25


func _ready():
	anim.play(animations[current_index])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("left"):
		if is_animating:
			return
		change_player(-1)
		click.play()
		swoosh.play()
	if event.is_action_pressed("right"):
		if is_animating:
			return
		change_player(1)
		click.play()
		swoosh.play()

func _on_left_button_pressed() -> void:
	if is_animating:
		return
	change_player(-1)
func _on_right_button_pressed() -> void:
	if is_animating:
		return
	change_player(1)


func change_player(direction: int) -> void:
	is_animating = true

	var old_pos := anim.position
	var exit_dir := -direction

	# EXIT animation (slide + fade)
	var tween := create_tween()
	tween.tween_property(
		anim,
		"position",
		old_pos + Vector2(exit_dir * SLIDE_DISTANCE, 0),
		TRANSITION_TIME
	)
	tween.parallel().tween_property(anim, "modulate:a", 0.0, TRANSITION_TIME)

	await tween.finished

	# Change animation index
	current_index = (current_index + direction) % animations.size()
	if current_index < 0:
		current_index = animations.size() - 1

	anim.play(animations[current_index])

	# Reset for entrance
	anim.position = old_pos + Vector2(direction * SLIDE_DISTANCE, 0)
	anim.modulate.a = 0.0

	# ENTRANCE animation
	var tween_in := create_tween()
	tween_in.tween_property(anim, "position", old_pos, TRANSITION_TIME)
	tween_in.parallel().tween_property(anim, "modulate:a", 1.0, TRANSITION_TIME)

	await tween_in.finished
	is_animating = false
func _on_mute_pressed() -> void:
	pass # Replace with function body.

func _on_quit_btn_pressed() -> void:
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Main/Menu_select.tscn")

func _on_choose_pressed() -> void:
	Global.choosed_colour = animations[current_index]
	Global.save_colour()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Levels/level1/level1.tscn")
