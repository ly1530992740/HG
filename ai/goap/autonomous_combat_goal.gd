extends GoapGoal
class_name AutonomousCombatGoal

func is_valid() -> bool:
	return enabled \
		and _actor != null \
		and _actor.has_method("has_autonomous_combat_target") \
		and _actor.has_autonomous_combat_target()

func get_priority() -> int:
	return 95

func prepare() -> void:
	var version: int = _actor.prepare_autonomous_combat_goal()
	desired_state = {&"autonomous_target_neutralized": version}

func enter() -> void:
	super.enter()
	var member := _actor.get("squad_member") as SquadMember
	if member:
		member.set_ai_status("自主消灭敌人", "GOAP选择交战方式", "守住阵地 -> 利用掩体 -> 消灭范围内目标")
