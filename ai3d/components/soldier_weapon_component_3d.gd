extends Node
class_name SoldierWeaponComponent3D

const DAMAGE_RULES_3D := preload("res://combat3d/combat_damage_rules_3d.gd")

# Role values mirror Soldier3D.CombatRole without depending on the actor class.
const ROLE_SMG := 1
const ROLE_MACHINE_GUNNER := 2
const ROLE_MARKSMAN := 3
const ROLE_SHOTGUNNER := 4
const ROLE_MELEE := 5

var role := 0
var damage := 25
var effective_range := 28.0
var melee_range := 1.5
var magazine_size := 24
var magazine_ammo := 24
var reserve_ammo := 72
var weapon_id := "type_38"
var definition: Dictionary = {}
var last_hit_result: Dictionary = {}
var ai_spread_degrees := 1.1

func configure(new_role: int, combat_team := 1) -> void:
	role = new_role
	var player_aligned := combat_team == 0
	match role:
		ROLE_SMG:
			weapon_id = "ppsh41" if player_aligned else "type_100"
		ROLE_MACHINE_GUNNER:
			weapon_id = "dp28" if player_aligned else "type_99_lmg"
		ROLE_MARKSMAN:
			weapon_id = "zhongzheng" if player_aligned else "type_38"
		ROLE_SHOTGUNNER:
			weapon_id = "trench_gun"
		ROLE_MELEE:
			weapon_id = "knife"
		_:
			weapon_id = "zhongzheng" if player_aligned else "type_38"
	definition = WeaponCatalog3D.get_definition(weapon_id)
	if role != ROLE_MARKSMAN and weapon_id == "type_38":
		definition["dismember_power"] = 0.75
	damage = int(definition.get("damage", 25))
	var family := String(definition.get("family", "rifle"))
	var ai_range_factor := float({"bolt_rifle": 0.55, "pistol": 0.72, "smg": 0.72, "lmg": 0.74, "shotgun": 1.0, "melee": 1.0}.get(family, 0.7))
	effective_range = float(definition.get("maximum_range", 28.0)) * ai_range_factor
	magazine_size = int(definition.get("magazine_size", 24))
	melee_range = effective_range if role == ROLE_MELEE else melee_range
	ai_spread_degrees = float({ROLE_SMG: 2.1, ROLE_MACHINE_GUNNER: 2.45, ROLE_MARKSMAN: 0.48, ROLE_SHOTGUNNER: 4.4, ROLE_MELEE: 0.0}.get(role, 1.05))
	magazine_ammo = magazine_size
	reserve_ammo = int(definition.get("starting_reserve", magazine_size * 3))

func uses_ammunition() -> bool:
	return role != ROLE_MELEE

func can_reload() -> bool:
	return uses_ammunition() and magazine_ammo <= 0 and reserve_ammo > 0

func reload() -> bool:
	if reserve_ammo <= 0 or magazine_ammo >= magazine_size:
		return false
	var amount := mini(magazine_size - magazine_ammo, reserve_ammo)
	magazine_ammo += amount
	reserve_ammo -= amount
	return amount > 0

func is_target_in_range(actor: Node3D, target: Node3D) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return false
	if role == ROLE_MELEE:
		var flat_delta := target.global_position - actor.global_position
		flat_delta.y = 0.0
		return flat_delta.length() <= melee_range
	return actor.global_position.distance_to(get_target_point(target)) <= effective_range

func try_attack(
		actor: Node3D,
		target: Node3D,
		origin: Vector3,
		collision_mask: int = 9,
		ray_exclusions: Array[RID] = []
) -> bool:
	last_hit_result = {}
	if not is_instance_valid(actor) or not is_instance_valid(target) or not is_target_in_range(actor, target):
		return false
	var target_point := get_target_point(target)
	if role == ROLE_MELEE:
		if target.has_method("receive_hit") and DAMAGE_RULES_3D.can_damage(actor, target):
			target.receive_hit(damage, "body", target_point, actor, definition)
			last_hit_result = {"position": target_point, "collider": target}
		return true
	if magazine_ammo <= 0 or actor.get_world_3d() == null:
		return false
	var direction := (target_point - origin).normalized()
	var spread := deg_to_rad(ai_spread_degrees)
	if actor.has_method("get_suppression_accuracy_multiplier"):
		spread *= float(actor.get_suppression_accuracy_multiplier())
	if bool(actor.get("is_aimed")):
		spread *= 0.48
	if actor is CharacterBody3D and Vector2((actor as CharacterBody3D).velocity.x, (actor as CharacterBody3D).velocity.z).length() > 0.35:
		spread *= 1.55
	var right := direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var up := right.cross(direction).normalized()
	direction = (direction + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()
	var ballistic_range := float(definition.get("maximum_range", effective_range))
	var endpoint := origin + direction * ballistic_range
	var exclusions: Array[RID] = ray_exclusions.duplicate()
	if actor.get_rid() not in exclusions:
		exclusions.append(actor.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, collision_mask, exclusions)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		last_hit_result = {"position": endpoint}
	else:
		last_hit_result = hit
		var collider := hit.get("collider") as Node
		if collider != null and collider.has_method("receive_shot"):
			var metadata := definition.duplicate(true)
			metadata["impact_normal"] = hit.get("normal", -direction)
			collider.receive_shot(damage, hit.get("position", target_point), actor, metadata)
		elif collider == target and target.has_method("receive_hit") and DAMAGE_RULES_3D.can_damage(actor, target):
			target.receive_hit(damage, "body", hit.get("position", target_point), actor, definition)
	var impact_position: Vector3 = hit.get("position", endpoint) if not hit.is_empty() else endpoint
	var impact_collider := hit.get("collider") as Node if not hit.is_empty() else null
	if impact_collider != null and impact_collider.has_method("report_projectile_impact"):
		impact_collider.report_projectile_impact(actor.global_position, _get_suppression_power())
	_notify_near_misses(actor, origin, impact_position, hit.get("collider") as Node if not hit.is_empty() else null)
	magazine_ammo -= 1
	return true

func _notify_near_misses(actor: Node3D, origin: Vector3, endpoint: Vector3, direct_collider: Node) -> void:
	var registry := BattlefieldRegistry3D.find(actor.get_tree())
	if registry == null:
		return
	var segment := endpoint - origin
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.001:
		return
	var suppression_power := _get_suppression_power()
	var suppression_radius := float({ROLE_MACHINE_GUNNER: 2.6, ROLE_SMG: 1.8, ROLE_MARKSMAN: 1.1, ROLE_SHOTGUNNER: 1.65}.get(role, 1.45))
	for candidate in registry.get_soldiers():
		if candidate == actor or not candidate.is_combat_alive() or not actor.has_method("is_hostile_target") or not bool(actor.is_hostile_target(candidate)):
			continue
		var direct_actor := direct_collider.get_parent() if direct_collider != null and direct_collider.get_parent() is Soldier3D else direct_collider
		if direct_actor == candidate:
			continue
		var point := candidate.global_position + Vector3.UP
		var t := clampf((point - origin).dot(segment) / segment_length_squared, 0.0, 1.0)
		var nearest := origin + segment * t
		var distance_to_fire := point.distance_to(nearest)
		if distance_to_fire <= suppression_radius:
			var falloff := lerpf(1.0, 0.28, distance_to_fire / suppression_radius)
			var cover_factor := 0.35 if candidate.has_method("is_protected_from_position") \
				and bool(candidate.is_protected_from_position(actor.global_position)) else 1.0
			candidate.notify_near_miss(actor.global_position, actor, suppression_power * falloff * cover_factor)

func _get_suppression_power() -> float:
	return float({ROLE_MACHINE_GUNNER: 1.55, ROLE_SMG: 1.2, ROLE_MARKSMAN: 0.8, ROLE_SHOTGUNNER: 1.1}.get(role, 1.0))

func get_target_point(target: Node3D) -> Vector3:
	return target.get_aim_point() if target.has_method("get_aim_point") else target.global_position + Vector3.UP
