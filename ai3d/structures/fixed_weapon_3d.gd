extends Node3D
class_name FixedWeapon3D

@export_range(1, 100, 1) var damage := 14
@export_range(5.0, 100.0, 1.0) var effective_range := 46.0
@export_range(0.05, 2.0, 0.01) var shot_interval := 0.17
@export_range(1, 1000, 1) var ammunition := 250
@export_range(0.0, 10.0, 0.1) var spread_degrees := 1.8

var last_hit_result: Dictionary = {}
var _last_shot_msec := -100000

func try_fire(operator: Soldier3D, target: Node3D, origin: Vector3) -> bool:
	if operator == null or not is_instance_valid(target) or ammunition <= 0 or operator.get_world_3d() == null:
		return false
	if Time.get_ticks_msec() - _last_shot_msec < int(shot_interval * 1000.0):
		return false
	var target_point: Vector3 = target.get_aim_point() as Vector3 if target.has_method("get_aim_point") else target.global_position + Vector3.UP
	if origin.distance_to(target_point) > effective_range:
		return false
	var direction: Vector3 = (target_point - origin).normalized()
	var spread := deg_to_rad(spread_degrees)
	spread *= operator.get_suppression_accuracy_multiplier()
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(direction).normalized()
	direction = (direction + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()
	var endpoint: Vector3 = origin + direction * effective_range
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 9, [operator.get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := operator.get_world_3d().direct_space_state.intersect_ray(query)
	last_hit_result = hit if not hit.is_empty() else {"position": endpoint}
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		var metadata := {
			"id": "type_92_hmg",
			"family": "lmg",
			"impact_normal": hit.get("normal", -direction),
			"dismember_power": 0.85,
		}
		if collider != null and collider.has_method("receive_shot"):
			collider.receive_shot(damage, hit.get("position", target_point), operator, metadata)
		elif collider == target and target.has_method("receive_hit") and CombatDamageRules3D.can_damage(operator, target):
			target.receive_hit(damage, "body", hit.get("position", target_point), operator, metadata)
	_last_shot_msec = Time.get_ticks_msec()
	ammunition -= 1
	operator.notify_structure_weapon_fired(target, last_hit_result)
	return true
