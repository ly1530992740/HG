extends GoapAction
class_name SoldierAutonomyAction3D

enum Operation {
	SEEK_COVER,
	DROP_PRONE,
	TAKE_KNEE,
	RECOVER_MOVEMENT_POSTURE,
	FLINCH_AND_ASSESS,
	ORIENT_TO_THREAT,
	COMMUNICATE_CONTACT,
	ACQUIRE_VISIBLE_TARGET,
	AIM,
	RELOAD_COVERED,
	RELOAD_SAFE,
	RETURN_FIRE,
	BLIND_FIRE_FROM_COVER,
	SUPPRESSION_FIRE,
	WAIT_FOR_OPENING,
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
		Operation.SEEK_COVER, Operation.DROP_PRONE, Operation.TAKE_KNEE:
			return {&"immediate_threat": true}
		Operation.RECOVER_MOVEMENT_POSTURE:
			return {&"movement_safe": true, &"safe_posture": true, &"movement_posture_ready": false}
		Operation.FLINCH_AND_ASSESS:
			return {&"protected_from_threat": true}
		Operation.ORIENT_TO_THREAT:
			return {}
		Operation.COMMUNICATE_CONTACT:
			return {&"oriented_to_threat": true}
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
		Operation.BLIND_FIRE_FROM_COVER:
			return {&"protected_from_threat": true, &"weapon_loaded": true, &"contact_reported": true}
		Operation.SUPPRESSION_FIRE:
			return {&"protected_from_threat": true, &"target_acquired": true, &"weapon_loaded": true}
		Operation.WAIT_FOR_OPENING:
			return {&"safe_posture": true} if _is_directive_context() else {&"protected_from_threat": true}
		Operation.SCAN_THREAT_SECTOR:
			return {&"oriented_to_threat": true}
	return {}

func get_effects() -> Dictionary:
	match operation:
		Operation.SEEK_COVER:
			return {&"protected_from_threat": true, &"safe_posture": true, &"movement_safe": true, &"movement_posture_ready": true}
		Operation.DROP_PRONE:
			return {&"protected_from_threat": true, &"safe_posture": true, &"movement_safe": false, &"movement_posture_ready": false}
		Operation.TAKE_KNEE:
			return {&"safe_posture": true, &"movement_safe": false, &"movement_posture_ready": false}
		Operation.RECOVER_MOVEMENT_POSTURE:
			return {&"movement_posture_ready": true}
		Operation.FLINCH_AND_ASSESS:
			return {&"reacted_to_threat": true}
		Operation.ORIENT_TO_THREAT:
			return {&"oriented_to_threat": true}
		Operation.COMMUNICATE_CONTACT:
			return {&"contact_reported": true}
		Operation.ACQUIRE_VISIBLE_TARGET:
			return {&"target_acquired": true}
		Operation.AIM:
			return {&"aimed": true}
		Operation.RELOAD_COVERED, Operation.RELOAD_SAFE:
			return {&"weapon_loaded": true}
		Operation.RETURN_FIRE:
			return {&"contact_response_complete": true}
		Operation.BLIND_FIRE_FROM_COVER:
			return {&"contact_response_complete": true}
		Operation.WAIT_FOR_OPENING:
			return {&"movement_safe": true} if _is_directive_context() else {&"contact_response_complete": true}
		Operation.SUPPRESSION_FIRE:
			return {&"threat_suppressed": true}
		Operation.SCAN_THREAT_SECTOR:
			return {&"contact_response_complete": true, &"disturbance_investigated": true}
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

func _is_directive_context() -> bool:
	return agent != null and agent.get_context_goal() is SoldierDirectiveGoal3D
