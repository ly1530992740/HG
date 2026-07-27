extends GoapGoal
class_name PreserveLifeGoal

func is_valid() -> bool:
	if not enabled or _actor == null:
		return false
	var will := _actor.get("will_component") as WillComponent
	if will == null or not will.should_seek_safety():
		return false
	return not bool(_world_state.get_state(&"is_safe", false))

func get_priority() -> int:
	var will := _actor.get("will_component") as WillComponent
	return will.get_survival_goal_priority() if will else priority

func prepare() -> void:
	desired_state = {&"is_safe": true}

func enter() -> void:
	super.enter()
	var member := _actor.get("squad_member") as SquadMember
	if member:
		member.set_ai_status("优先保全生命", "寻找掩体", "到达掩体 -> 保持隐蔽")
