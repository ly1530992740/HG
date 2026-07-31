extends GoapGoal
class_name SoldierAutonomyGoal3D

enum Kind {
	SURVIVE_THREAT,
	REACT_TO_THREAT,
	SUPPRESS_THREAT,
	RESPOND_TO_CONTACT,
	INVESTIGATE_DISTURBANCE,
	RESTORE_WEAPON,
	MAINTAIN_SECURITY,
}

@export var kind: Kind = Kind.MAINTAIN_SECURITY

func is_valid() -> bool:
	return enabled \
		and _actor != null \
		and _actor.has_method("is_autonomy_goal_valid") \
		and _actor.is_autonomy_goal_valid(kind)

func get_priority() -> int:
	if _actor != null and _actor.has_method("get_autonomy_goal_priority"):
		return _actor.get_autonomy_goal_priority(kind)
	return priority

func get_interrupt_priority() -> int:
	match kind:
		Kind.SURVIVE_THREAT:
			return 100
		Kind.REACT_TO_THREAT:
			return 80
		Kind.RESTORE_WEAPON:
			return 25
	return 10

func get_reevaluation_interval() -> float:
	return 0.1 if kind in [Kind.SURVIVE_THREAT, Kind.REACT_TO_THREAT] else 0.35

func get_activation_chance() -> float:
	return 1.0

func get_desired_state() -> Dictionary:
	match kind:
		Kind.SURVIVE_THREAT:
			return {&"protected_from_threat": true}
		Kind.REACT_TO_THREAT:
			return {&"reacted_to_threat": true}
		Kind.SUPPRESS_THREAT:
			return {&"threat_suppressed": true, &"contact_reported": true}
		Kind.RESPOND_TO_CONTACT:
			return {&"contact_response_complete": true, &"contact_reported": true}
		Kind.INVESTIGATE_DISTURBANCE:
			return {&"disturbance_investigated": true, &"contact_reported": true}
		Kind.RESTORE_WEAPON:
			return {&"weapon_loaded": true}
		Kind.MAINTAIN_SECURITY:
			return {&"security_cycle_complete": true}
	return {}

func prepare() -> void:
	if _actor != null and _actor.has_method("prepare_autonomy_goal"):
		_actor.prepare_autonomy_goal(kind)

func on_goal_achieved() -> void:
	if _actor != null and _actor.has_method("on_autonomy_goal_achieved"):
		_actor.on_autonomy_goal_achieved(kind)
