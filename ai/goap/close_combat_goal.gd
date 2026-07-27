extends GoapGoal
class_name CloseCombatGoal

func is_valid() -> bool:
	return enabled and _actor != null and _actor.has_method("is_melee_engagement_needed") and _actor.is_melee_engagement_needed()

func get_priority() -> int:
	if _actor.has_method("get_melee_goal_priority"):
		return _actor.get_melee_goal_priority()
	return 125

func prepare() -> void:
	var version: int = _actor.prepare_melee_goal()
	desired_state = {&"melee_attack_completed": version}

func enter() -> void:
	super.enter()
	var member := _actor.get("squad_member") as SquadMember
	if member:
		member.set_ai_status("敌人进入近战距离", "切换近战武器", "收起枪械 -> 接近 -> 近战攻击")
