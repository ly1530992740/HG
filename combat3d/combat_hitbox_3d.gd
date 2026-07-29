extends Area3D
class_name CombatHitbox3D

@export_enum("body", "head") var hit_location := "body"
@export var damage_multiplier := 1.0

func receive_shot(base_damage: int, hit_position: Vector3, instigator: Node) -> void:
	var actor := get_parent()
	if actor != null and actor.has_method("receive_hit"):
		actor.receive_hit(roundi(float(base_damage) * damage_multiplier), hit_location, hit_position, instigator)

