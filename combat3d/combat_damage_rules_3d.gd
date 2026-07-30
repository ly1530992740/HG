extends RefCounted
class_name CombatDamageRules3D

static func can_damage(instigator: Node, target: Node) -> bool:
	if instigator == null or target == null:
		return true
	var source_actor := _find_team_actor(instigator)
	var target_actor := _find_team_actor(target)
	if source_actor == null or target_actor == null:
		return true
	return int(source_actor.get_combat_team()) != int(target_actor.get_combat_team())

static func _find_team_actor(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_method("get_combat_team"):
			return current
		current = current.get_parent()
	return null
