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
	var registry := BattlefieldRegistry3D.find(actor.get_tree())
	var candidates: Array = registry.get_combatants() if registry != null else actor.get_tree().get_nodes_in_group("combatant3d")
	for candidate in candidates:
		if not candidate is Node3D or not actor.is_hostile_target(candidate) or not actor.is_combat_target_alive(candidate):
			continue
		var target := candidate as Node3D
		var distance := actor.global_position.distance_to(target.global_position)
		var visibility_multiplier := float(target.get_visibility_multiplier()) if target.has_method("get_visibility_multiplier") else 1.0
		var effective_sight_range := actor.sight_range * clampf(visibility_multiplier, 0.35, 1.25)
		if distance >= best_distance or distance > effective_sight_range:
			continue
		if require_visible and not can_see(target):
			continue
		best = target
		best_distance = distance
	return best

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
	var origin := actor.global_position + Vector3.UP * 1.45
	var endpoint: Vector3 = candidate.get_aim_point() if candidate.has_method("get_aim_point") else candidate.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 9, [actor.get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	return collider == candidate or (collider != null and collider.get_parent() == candidate)
