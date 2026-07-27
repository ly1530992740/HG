extends GoapGoal
class_name SquadOrderGoal

func is_valid() -> bool:
	if not enabled or _actor == null:
		return false
	var member := _actor.get("squad_member") as SquadMember
	return member != null and member.get_current_order() != null

func get_priority() -> int:
	var will := _actor.get("will_component") as WillComponent
	return will.get_order_goal_priority() if will else priority

func prepare() -> void:
	var member := _actor.get("squad_member") as SquadMember
	var order := member.get_current_order() if member else null
	if order != null:
		desired_state = {&"completed_order_version": order.version}

func enter() -> void:
	super.enter()
	var member := _actor.get("squad_member") as SquadMember
	var order := member.get_current_order() if member else null
	if member and order:
		member.set_ai_status("服从队长命令", "正在制定行动", "目标: %s" % order.get_type_name())

func on_goal_achieved() -> void:
	if _actor.has_method("on_squad_goal_completed"):
		_actor.on_squad_goal_completed()
