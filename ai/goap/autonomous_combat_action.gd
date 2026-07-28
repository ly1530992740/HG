extends GoapAction
class_name AutonomousCombatAction

func is_valid() -> bool:
	if not enabled or _actor == null or not _actor.has_method("has_autonomous_combat_target"):
		return false
	effects = {&"autonomous_target_neutralized": int(_actor.get("autonomous_target_version"))}
	return _actor.has_autonomous_combat_target()

func get_effects() -> Dictionary:
	effects = {&"autonomous_target_neutralized": int(_actor.get("autonomous_target_version"))}
	return effects

func enter() -> void:
	_actor.begin_autonomous_combat()

func perform(delta) -> bool:
	return _actor.perform_autonomous_combat(delta)

func exit() -> void:
	_actor.end_autonomous_combat()
