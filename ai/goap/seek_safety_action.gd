extends GoapAction
class_name SeekSafetyAction

func _ready() -> void:
	effects = {&"is_safe": true}

func is_valid() -> bool:
	return enabled and _actor != null and _actor.has_method("perform_safety_action")

func get_cost(_blackboard) -> int:
	var will := _actor.get("will_component") as WillComponent
	if will == null:
		return cost
	return maxi(1, int(round(float(cost) / maxf(0.5, float(will.get_survival_goal_priority()) / 70.0))))

func enter() -> void:
	if _actor.has_method("begin_safety_action"):
		_actor.begin_safety_action()

func perform(delta) -> bool:
	return _actor.perform_safety_action(delta)

func exit() -> void:
	if _actor.has_method("end_safety_action"):
		_actor.end_safety_action()
