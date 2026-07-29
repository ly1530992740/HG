extends Node
class_name SoldierWeaponComponent3D

# Role values mirror Soldier3D.CombatRole without depending on the actor class.
const ROLE_SMG := 1
const ROLE_MACHINE_GUNNER := 2
const ROLE_MARKSMAN := 3
const ROLE_SHOTGUNNER := 4
const ROLE_MELEE := 5

var role := 0
var damage := 25
var effective_range := 28.0
var shot_cooldown := 0.32
var melee_range := 1.5
var magazine_size := 24
var magazine_ammo := 24
var reserve_ammo := 72

func configure(new_role: int) -> void:
	role = new_role
	match role:
		ROLE_SMG:
			damage = 18; effective_range = 19.0; shot_cooldown = 0.14; magazine_size = 32
		ROLE_MACHINE_GUNNER:
			damage = 16; effective_range = 30.0; shot_cooldown = 0.11; magazine_size = 60
		ROLE_MARKSMAN:
			damage = 64; effective_range = 48.0; shot_cooldown = 1.2; magazine_size = 6
		ROLE_SHOTGUNNER:
			damage = 46; effective_range = 13.0; shot_cooldown = 0.82; magazine_size = 8
		ROLE_MELEE:
			damage = 38; effective_range = melee_range; shot_cooldown = 0.72; magazine_size = 1
		_:
			damage = 25; effective_range = 28.0; shot_cooldown = 0.32; magazine_size = 24
	magazine_ammo = magazine_size
	reserve_ammo = magazine_size * 3

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

func try_attack(actor: Node3D, target: Node3D, origin: Vector3, collision_mask: int = 9) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(target) or not is_target_in_range(actor, target):
		return false
	var target_point := get_target_point(target)
	if role == ROLE_MELEE:
		if target.has_method("receive_hit"):
			target.receive_hit(damage, "body", target_point, actor)
		return true
	if magazine_ammo <= 0 or actor.get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target_point, collision_mask, [actor.get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	if collider != null and collider.has_method("receive_shot"):
		collider.receive_shot(damage, hit.get("position", target_point), actor)
	elif collider == target and target.has_method("receive_hit"):
		target.receive_hit(damage, "body", hit.get("position", target_point), actor)
	magazine_ammo -= 1
	return true

func get_target_point(target: Node3D) -> Vector3:
	return target.get_aim_point() if target.has_method("get_aim_point") else target.global_position + Vector3.UP
