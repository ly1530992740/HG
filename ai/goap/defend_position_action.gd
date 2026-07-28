extends GoapAction
class_name DefendPositionAction

func is_valid() -> bool:
	if not enabled or _actor == null or not _actor.has_method("needs_to_reach_defense_anchor"):
		return false
	effects = {&"defense_anchor_reached": int(_actor.get("defense_goal_version"))}
	return _actor.needs_to_reach_defense_anchor()

func get_effects() -> Dictionary:
	effects = {&"defense_anchor_reached": int(_actor.get("defense_goal_version"))}
	return effects

func enter() -> void:
	_actor.begin_defense_move()

func perform(delta) -> bool:
	return _actor.perform_defense_move(delta)

func exit() -> void:
	_actor.end_defense_move()
