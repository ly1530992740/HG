extends GoapGoal
class_name DefendPositionGoal

func is_valid() -> bool:
	return enabled \
		and _actor != null \
		and _actor.has_method("needs_to_reach_defense_anchor") \
		and _actor.needs_to_reach_defense_anchor()

func get_priority() -> int:
	return 145

func prepare() -> void:
	desired_state = {&"defense_anchor_reached": int(_actor.get("defense_goal_version"))}

func enter() -> void:
	super.enter()
	var member := _actor.get("squad_member") as SquadMember
	if member:
		member.set_ai_status("执行玩家集结", "前往指定阵地", "安全移动 -> 到达目标 -> 原地防守")
