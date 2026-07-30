extends Area3D
class_name CombatHitbox3D

const DAMAGE_RULES_3D := preload("res://combat3d/combat_damage_rules_3d.gd")

@export_enum("body", "head", "left_arm", "right_arm", "left_leg", "right_leg") var hit_location := "body"
@export var damage_multiplier := 1.0

func receive_shot(base_damage: int, hit_position: Vector3, instigator: Node, weapon_metadata := {}) -> bool:
	var actor := get_parent()
	if actor == null or not actor.has_method("receive_hit"):
		return false
	if not DAMAGE_RULES_3D.can_damage(instigator, actor):
		return false
	actor.receive_hit(roundi(float(base_damage) * damage_multiplier), hit_location, hit_position, instigator, weapon_metadata)
	return true
