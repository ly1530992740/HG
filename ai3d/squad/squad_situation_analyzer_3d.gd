extends Node
class_name SquadSituationAnalyzer3D

func living_members(members: Array[Soldier3D]) -> Array[Soldier3D]:
	var result: Array[Soldier3D] = []
	for member in members:
		if is_instance_valid(member) and member.is_combat_alive():
			result.append(member)
	return result

func squad_center(members: Array[Soldier3D], fallback: Vector3) -> Vector3:
	if members.is_empty():
		return fallback
	var result := Vector3.ZERO
	for member in members:
		result += member.global_position
	return result / float(members.size())

func average_health_ratio(members: Array[Soldier3D]) -> float:
	if members.is_empty():
		return 0.0
	var total := 0.0
	for member in members:
		total += float(member.health) / float(maxi(1, member.max_health))
	return total / float(members.size())

func formation_power(members: Array[Soldier3D]) -> float:
	var result := 0.0
	for member in members:
		result += member.get_combat_power()
	return result

func enemy_members(tree: SceneTree, target: Node3D) -> Array[Soldier3D]:
	var result: Array[Soldier3D] = []
	if not is_instance_valid(target) or not target.has_method("get_combat_team"):
		return result
	var team := int(target.get_combat_team())
	var registry := BattlefieldRegistry3D.find(tree)
	var candidates: Array = registry.get_soldiers() if registry != null else tree.get_nodes_in_group("soldier3d")
	for candidate in candidates:
		if candidate is Soldier3D and candidate.is_combat_alive() and int(candidate.combat_team) == team:
			result.append(candidate)
	return result

func enemy_power(tree: SceneTree, target: Node3D) -> float:
	var enemies := enemy_members(tree, target)
	if enemies.is_empty():
		return 1.5 if is_instance_valid(target) else 0.0
	return formation_power(enemies)

func enemy_is_aware(tree: SceneTree, target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	if target is Soldier3D and target.aware_of_enemy:
		return true
	for enemy in enemy_members(tree, target):
		if enemy.aware_of_enemy:
			return true
	return false

func is_alive(actor: Node) -> bool:
	return actor != null and (not actor.has_method("is_combat_alive") or bool(actor.is_combat_alive()))
