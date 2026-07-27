extends GoapAction
class_name MeleeEngageAction

func is_valid() -> bool:
	if not enabled or _actor == null or not _actor.has_method("is_melee_engagement_needed"):
		return false
	effects = {&"melee_attack_completed": int(_actor.get("melee_goal_version"))}
	return _actor.is_melee_engagement_needed()

func get_effects() -> Dictionary:
	effects = {&"melee_attack_completed": int(_actor.get("melee_goal_version"))}
	return effects

func enter() -> void:
	_actor.begin_melee_engagement()

func perform(delta) -> bool:
	return _actor.perform_melee_engagement(delta)

func exit() -> void:
	_actor.end_melee_engagement()
