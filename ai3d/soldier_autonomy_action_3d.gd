extends GoapAction
class_name SoldierAutonomyAction3D

enum Operation {
	SEEK_COVER,
	DROP_PRONE,
	ORIENT_TO_THREAT,
	ACQUIRE_VISIBLE_TARGET,
	AIM,
	RELOAD_COVERED,
	RELOAD_SAFE,
	RETURN_FIRE,
	SCAN_THREAT_SECTOR,
	GUARD_SECTOR,
}

@export var operation: Operation = Operation.GUARD_SECTOR

func is_valid() -> bool:
	return enabled \
		and _actor != null \
		and _actor.has_method("is_autonomy_action_valid") \
		and _actor.is_autonomy_action_valid(operation)

func get_cost(_blackboard) -> int:
	if _actor != null and _actor.has_method("get_autonomy_action_cost"):
		return _actor.get_autonomy_action_cost(operation)
	return cost

func get_preconditions() -> Dictionary:
	match operation:
		Operation.SEEK_COVER, Operation.DROP_PRONE:
			return {&"immediate_threat": true}
		Operation.ORIENT_TO_THREAT:
			return {}
		Operation.ACQUIRE_VISIBLE_TARGET:
			return {&"protected_from_threat": true, &"oriented_to_threat": true}
		Operation.AIM:
			return {&"protected_from_threat": true, &"target_acquired": true}
		Operation.RELOAD_COVERED:
			return {&"protected_from_threat": true}
		Operation.RETURN_FIRE:
			return {
				&"protected_from_threat": true,
				&"target_acquired": true,
				&"aimed": true,
				&"weapon_loaded": true,
			}
		Operation.SCAN_THREAT_SECTOR:
			return {&"oriented_to_threat": true}
	return {}

func get_effects() -> Dictionary:
	match operation:
		Operation.SEEK_COVER, Operation.DROP_PRONE:
			return {&"protected_from_threat": true, &"safe_posture": true}
		Operation.ORIENT_TO_THREAT:
			return {&"oriented_to_threat": true}
		Operation.ACQUIRE_VISIBLE_TARGET:
			return {&"target_acquired": true}
		Operation.AIM:
			return {&"aimed": true}
		Operation.RELOAD_COVERED, Operation.RELOAD_SAFE:
			return {&"weapon_loaded": true}
		Operation.RETURN_FIRE, Operation.SCAN_THREAT_SECTOR:
			return {&"contact_response_complete": true}
		Operation.GUARD_SECTOR:
			return {&"security_cycle_complete": true}
	return {}

func enter() -> void:
	if _actor != null and _actor.has_method("begin_autonomy_operation"):
		_actor.begin_autonomy_operation(operation)

func perform(delta) -> bool:
	if _actor == null or not _actor.has_method("perform_autonomy_operation"):
		return false
	return _actor.perform_autonomy_operation(operation, float(delta))

func exit() -> void:
	if _actor != null and _actor.has_method("end_autonomy_operation"):
		_actor.end_autonomy_operation(operation)
