extends AnimatedSprite2D

var dammage=15
func _ready() -> void:
	z_index = 5

func _on_animation_finished() -> void:
	queue_free()

func apply_damage(dmg:int):
	dmg=dammage
	if dmg:
		pass


func _on_attack_effect_body_entered(body: Node2D) -> void:
	if body.is_in_group("goblinbuildings"):
		if body.has_method("take_damages"):
			body.take_damage(30)
