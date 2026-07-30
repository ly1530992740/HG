extends Node
class_name SquadBattlefieldSnapshot3D

const MAX_COVER_FACTS := 8

func build(
	coordinator: SquadCoordinator3D,
	members: Array[Soldier3D],
	leader: Soldier3D,
	target: Node3D,
	routes: Array[Dictionary],
	situation_version: int
) -> Dictionary:
	var visible_by: Array[String] = []
	var member_facts: Array[Dictionary] = []
	for member in members:
		var sees_target := is_instance_valid(target) and member.perception_component.can_see(target)
		if sees_target:
			visible_by.append(String(member.name))
		member_facts.append(_member_fact(member, leader, sees_target))

	var target_id := _target_id(target)
	var center := coordinator.get_squad_center()
	return {
		"situation_version": situation_version,
		"mission": {
			"objective": "ELIMINATE_TARGET",
			"target_id": target_id,
			"retreat_allowed": false,
		},
		"squad": {
			"id": String(coordinator.squad_id),
			"name": coordinator.squad_display_name,
			"leader_id": String(leader.name) if is_instance_valid(leader) else "NONE",
			"living_count": members.size(),
			"members": member_facts,
		},
		"enemy": _enemy_fact(target, center, visible_by),
		"routes": _route_facts(routes),
		"covers": _cover_facts(coordinator, target, center),
		"current_execution": {
			"plan": coordinator.current_plan,
			"stage": coordinator.current_stage,
			"summary": coordinator.last_command_summary,
		},
		"legal_goals": QwenSquadBrain3D.get_legal_goals(members.size(), is_instance_valid(target)),
	}

func _member_fact(member: Soldier3D, leader: Soldier3D, sees_target: bool) -> Dictionary:
	var directive := member.active_directive
	return {
		"id": String(member.name),
		"leader": member == leader,
		"role": member.get_combat_role_name(),
		"health": member.health,
		"health_max": member.max_health,
		"magazine": member.magazine_ammo,
		"reserve_ammo": member.reserve_ammo,
		"weapon_range": snappedf(member.weapon_component.effective_range, 0.1),
		"position": _vector_fact(member.global_position),
		"sees_target": sees_target,
		"in_cover": is_instance_valid(member.active_cover),
		"aimed": member.is_aimed,
		"stance": member.get_stance_label(),
		"movement": member.get_movement_mode_label(),
		"current_goal": directive.get_label() if directive != null and member.has_active_directive() else "IDLE",
	}

func _enemy_fact(target: Node3D, center: Vector3, visible_by: Array[String]) -> Dictionary:
	if not is_instance_valid(target):
		return {
			"known": false,
			"id": "UNKNOWN",
			"visible_by": visible_by,
		}
	var fact := {
		"known": true,
		"id": _target_id(target),
		"position": _vector_fact(target.global_position),
		"distance_from_squad": snappedf(center.distance_to(target.global_position), 0.1),
		"visible_by": visible_by,
		"currently_visible": not visible_by.is_empty(),
	}
	if target is Soldier3D:
		var soldier := target as Soldier3D
		fact["role"] = soldier.get_combat_role_name()
		fact["health"] = soldier.health
		fact["aware_of_squad"] = soldier.aware_of_enemy
		fact["recently_fired"] = Time.get_ticks_msec() - soldier.last_weapon_fired_msec <= 1500
	elif target.has_method("is_aiming"):
		fact["aware_of_squad"] = bool(target.is_aiming())
	return fact

func _route_facts(routes: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route in routes:
		result.append({
			"id": String(route.get("id", "")),
			"side": String(route.get("side", "")),
			"direction": String(route.get("direction", "")),
			"reachable": bool(route.get("available", false)),
			"distance": float(route.get("distance", 0.0)),
			"exposure": float(route.get("exposure", 1.0)),
			"capacity": int(route.get("capacity", 0)),
		})
	return result

func _cover_facts(coordinator: SquadCoordinator3D, target: Node3D, center: Vector3) -> Array[Dictionary]:
	var covers: Array = coordinator.get_registered_covers()
	covers.sort_custom(func(a: Node3D, b: Node3D): return center.distance_to(a.global_position) < center.distance_to(b.global_position))
	var result: Array[Dictionary] = []
	for node in covers.slice(0, mini(MAX_COVER_FACTS, covers.size())):
		if not node is TacticalCover3D:
			continue
		var cover := node as TacticalCover3D
		result.append({
			"id": String(cover.name),
			"distance": snappedf(center.distance_to(cover.global_position), 0.1),
			"length": snappedf(cover.cover_length, 0.1),
			"height": snappedf(cover.cover_height, 0.1),
			"free_slots": cover.get_available_slot_count_against(target.global_position) if is_instance_valid(target) else cover.get_cover_capacity_per_side(),
		})
	return result

func _target_id(target: Node3D) -> String:
	if not is_instance_valid(target):
		return "UNKNOWN"
	return "PLAYER" if target.is_in_group("player3d") else String(target.name)

func _vector_fact(value: Vector3) -> Dictionary:
	return {
		"x": snappedf(value.x, 0.1),
		"y": snappedf(value.y, 0.1),
		"z": snappedf(value.z, 0.1),
	}
