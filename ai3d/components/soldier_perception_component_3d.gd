extends Node
class_name SoldierPerceptionComponent3D

var actor: Soldier3D

func configure(owner_actor: Soldier3D) -> void:
	actor = owner_actor

func find_best_hostile(require_visible: bool) -> Node3D:
	if actor == null:
		return null
	var best: Node3D
	var best_distance := INF
	for candidate in _get_combatant_candidates():
		if not candidate is Node3D or not actor.is_hostile_target(candidate) or not actor.is_combat_target_alive(candidate):
			continue
		var target := candidate as Node3D
		var distance := actor.global_position.distance_to(target.global_position)
		if distance >= best_distance or not _is_within_effective_sight(target, distance):
			continue
		if require_visible and not can_see(target):
			continue
		best = target
		best_distance = distance
	return best

func find_visible_hostiles() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if actor == null:
		return result
	for candidate in _get_combatant_candidates():
		if not candidate is Node3D or not actor.is_hostile_target(candidate) or not actor.is_combat_target_alive(candidate):
			continue
		var target := candidate as Node3D
		if _is_within_effective_sight(target) and can_see(target):
			result.append(target)
	return result

func can_see(candidate: Node3D) -> bool:
	if actor == null or not is_instance_valid(candidate):
		return false
	var to_target := candidate.global_position - actor.global_position
	to_target.y = 0.0
	if to_target == Vector3.ZERO:
		return true
	if actor.field_of_view_degrees < 359.0:
		var threshold := cos(deg_to_rad(actor.field_of_view_degrees * 0.5))
		if actor.logical_forward.normalized().dot(to_target.normalized()) < threshold:
			return false
	return has_line_of_sight(candidate)

func has_line_of_sight(candidate: Node3D) -> bool:
	if actor == null or not is_instance_valid(candidate):
		return false
	if not _is_within_effective_sight(candidate):
		return false
	var origin := actor.global_position + Vector3.UP * 1.45
	var endpoint: Vector3 = candidate.get_aim_point() if candidate.has_method("get_aim_point") else candidate.global_position + Vector3.UP
	if candidate.has_method("get_visibility_multiplier") \
		and float(candidate.get_visibility_multiplier()) <= 0.22 \
		and actor.global_position.distance_to(candidate.global_position) > 4.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 9, [actor.get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	return collider == candidate or (collider != null and collider.get_parent() == candidate)

func _get_combatant_candidates() -> Array:
	var registry := BattlefieldRegistry3D.find(actor.get_tree())
	return registry.get_combatants() if registry != null else actor.get_tree().get_nodes_in_group("combatant3d")

func _is_within_effective_sight(target: Node3D, distance := -1.0) -> bool:
	var target_distance := distance if distance >= 0.0 else actor.global_position.distance_to(target.global_position)
	var visibility_multiplier := float(target.get_visibility_multiplier()) if target.has_method("get_visibility_multiplier") else 1.0
	return target_distance <= actor.sight_range * clampf(visibility_multiplier, 0.35, 1.25)
