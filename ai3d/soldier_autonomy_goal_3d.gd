extends GoapGoal
class_name SoldierAutonomyGoal3D

enum Kind {
	SURVIVE_THREAT,
	RESPOND_TO_CONTACT,
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

func get_desired_state() -> Dictionary:
	match kind:
		Kind.SURVIVE_THREAT:
			return {&"protected_from_threat": true}
		Kind.RESPOND_TO_CONTACT:
			return {&"contact_response_complete": true}
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
