extends GoapGoal
class_name SoldierDirectiveGoal3D

func _ready() -> void:
	priority = 100

func is_valid() -> bool:
	return enabled and _actor != null and _actor.has_method("has_active_directive") and _actor.has_active_directive()

func get_relevance() -> float:
	if _actor != null and _actor.has_method("get_directive_goal_relevance"):
		return _actor.get_directive_goal_relevance()
	return float(get_priority())

func get_interrupt_priority() -> int:
	return 20

func get_reevaluation_interval() -> float:
	return 0.4

func get_desired_state() -> Dictionary:
	if _actor == null or not _actor.has_method("get_directive_version"):
		return {}
	return {&"directive_complete": _actor.get_directive_version()}

func prepare() -> void:
	if _actor != null and _actor.has_method("prepare_directive_goal"):
		_actor.prepare_directive_goal()

func on_goal_achieved() -> void:
	if _actor != null and _actor.has_method("on_directive_plan_completed"):
		_actor.on_directive_plan_completed()
