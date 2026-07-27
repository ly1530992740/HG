extends GoapAction
class_name SquadCommandAction

@export var supported_order_type: SquadOrder.Type = SquadOrder.Type.HOLD

var _executing_version := 0

func is_valid() -> bool:
	if not enabled or _actor == null:
		return false
	var member := _actor.get("squad_member") as SquadMember
	var order := member.get_current_order() if member else null
	if order == null:
		return false
	if order.type != supported_order_type:
		return false
	effects = {&"completed_order_version": order.version}
	return true

func get_effects() -> Dictionary:
	var member := _actor.get("squad_member") as SquadMember
	var order := member.get_current_order() if member else null
	if order != null and order.type == supported_order_type:
		effects = {&"completed_order_version": order.version}
	return effects

func get_cost(_blackboard) -> int:
	if _actor.has_method("get_squad_action_cost"):
		return _actor.get_squad_action_cost(supported_order_type, cost)
	return cost

func enter() -> void:
	var member := _actor.get("squad_member") as SquadMember
	var order := member.get_current_order() if member else null
	_executing_version = order.version if order else 0
	if _actor.has_method("begin_squad_action"):
		_actor.begin_squad_action(supported_order_type)

func perform(delta) -> bool:
	var member := _actor.get("squad_member") as SquadMember
	var order := member.get_current_order() if member else null
	if order == null or order.version != _executing_version:
		return false
	if _actor.has_method("perform_squad_action"):
		return _actor.perform_squad_action(supported_order_type, delta)
	return true

func exit() -> void:
	if _actor.has_method("end_squad_action"):
		_actor.end_squad_action(supported_order_type)
