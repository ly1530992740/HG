extends Node
class_name SquadBattlefieldAnalyzer

@export_group("态势分析阈值")
@export_range(0.0, 100.0, 1.0) var strong_firepower_threshold := 10.0
@export_range(0.0, 100.0, 1.0) var overwhelming_firepower_threshold := 18.0
@export var include_unconfirmed_hostiles := false

var squad_group: SquadGroup = null
var last_snapshot: Dictionary = {}

func bind_group(value: SquadGroup) -> void:
	squad_group = value

func analyze(primary_target: Node2D = null) -> Dictionary:
	if squad_group == null:
		squad_group = get_parent() as SquadGroup
	var coordinator := squad_group as SquadCoordinator
	if coordinator == null:
		last_snapshot = {}
		return last_snapshot
	var allies := _living_member_actors(coordinator)
	var hostiles := _known_hostiles(coordinator, primary_target)
	var ally_center := _center_of(allies)
	var hostile_center := _center_of(hostiles)
	var exposed := 0
	var pinned := 0
	var health_total := 0.0
	var health_max_total := 0.0
	var ammo_total := 0
	for actor in allies:
		if actor.has_method("get_active_cover") and actor.get_active_cover() == null:
			exposed += 1
		if actor.has_method("is_pinned_by_fire") and actor.is_pinned_by_fire():
			pinned += 1
		health_total += float(actor.get("health"))
		health_max_total += maxf(1.0, float(actor.get("max_health")))
		var firearm := actor.get("firearm_weapon") as FirearmWeapon
		if firearm != null:
			ammo_total += firearm.get_total_ammo()
	var enemy_firepower := 0.0
	for hostile in hostiles:
		enemy_firepower += _actor_firepower(hostile)
	var firepower_label := "普通"
	if enemy_firepower >= overwhelming_firepower_threshold:
		firepower_label = "极强"
	elif enemy_firepower >= strong_firepower_threshold:
		firepower_label = "强"
	last_snapshot = {
		"ally_count": allies.size(),
		"hostile_count": hostiles.size(),
		"ally_center": ally_center,
		"hostile_center": hostile_center,
		"exposed_count": exposed,
		"pinned_count": pinned,
		"health_ratio": snappedf(health_total / maxf(1.0, health_max_total), 0.01),
		"ammo_total": ammo_total,
		"enemy_firepower_score": snappedf(enemy_firepower, 0.1),
		"enemy_firepower_label": firepower_label,
	}
	coordinator.get_blackboard().set_fact(&"enemy_frontal_firepower", firepower_label)
	return last_snapshot

func _living_member_actors(coordinator: SquadCoordinator) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for member in coordinator.members:
		if is_instance_valid(member) and is_instance_valid(member.actor) and member.actor.is_combat_alive():
			result.append(member.actor)
	return result

func _known_hostiles(coordinator: SquadCoordinator, primary_target: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for target in coordinator._collect_known_hostile_targets():
		if is_instance_valid(target) and not result.has(target):
			result.append(target)
	if is_instance_valid(primary_target) and not result.has(primary_target):
		result.append(primary_target)
	if include_unconfirmed_hostiles:
		for candidate in get_tree().get_nodes_in_group("combatant"):
			if candidate is Node2D and coordinator._is_hostile_target(candidate) and not result.has(candidate):
				result.append(candidate)
	return result

func _center_of(actors: Array[Node2D]) -> Vector2:
	if actors.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for actor in actors:
		total += actor.global_position
	return total / float(actors.size())

func _actor_firepower(actor: Node2D) -> float:
	if actor.has_method("get_combat_role"):
		match actor.get_combat_role() as SquadCombatRole.Type:
			SquadCombatRole.Type.MACHINE_GUNNER:
				return 3.2
			SquadCombatRole.Type.MARKSMAN:
				return 2.6
			SquadCombatRole.Type.RIFLEMAN:
				return 1.8
			SquadCombatRole.Type.SHOTGUNNER:
				return 1.4
			SquadCombatRole.Type.PISTOL_SCOUT:
				return 1.0
			SquadCombatRole.Type.MELEE:
				return 0.7
	return 1.0
