extends AnimatedSprite2D

@onready var explosion_audio: AudioStreamPlayer = $explosion
@onready var explosion: AnimatedSprite2D = $"."
var pos
 
func _ready() -> void:
	explosion_audio.play()
	z_index = 6
	explosion.animation="sp"
	scale=Vector2(2,2)

func _on_animation_finished() -> void:
	queue_free()


func _on_explo_body_entered(body: Node2D) -> void:
	if body.is_in_group("building"):
		pos=body.global_position
		fire()

func fire():
	var scene=preload("res://Materiels/fire/fire.tscn")
	var _scene=scene.instantiate()
	get_parent().add_child(_scene)
	_scene.global_position=pos
	_scene.z_index=6
