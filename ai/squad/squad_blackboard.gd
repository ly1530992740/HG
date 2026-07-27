extends RefCounted
class_name SquadBlackboard

signal members_changed(members: Array)
signal leader_changed(leader: Node)
signal order_changed(order: SquadOrder)
signal shared_target_changed(target: Node2D)
signal fact_changed(key: StringName, value: Variant)

var members: Array[Node] = []
var leader: Node = null
var current_order: SquadOrder = null
var broadcast_order: SquadOrder = null
var member_orders: Dictionary = {}
var shared_target: Node2D = null
var order_version := 0
var facts: Dictionary = {}

func set_members(new_members: Array) -> void:
	var normalized_members: Array[Node] = []
	for member in new_members:
		if member is Node and is_instance_valid(member):
			normalized_members.append(member)
	if members == normalized_members:
		return
	members = normalized_members
	members_changed.emit(members.duplicate())

func set_leader(new_leader: Node) -> void:
	if leader == new_leader:
		return
	leader = new_leader
	leader_changed.emit(leader)

func publish_order(order: SquadOrder) -> void:
	order_version += 1
	order.version = order_version
	current_order = order
	if order.recipients.is_empty():
		broadcast_order = order
	else:
		for recipient in order.recipients:
			member_orders[recipient] = order
	order_changed.emit(current_order)

func clear_order() -> void:
	if current_order == null:
		return
	current_order = null
	broadcast_order = null
	member_orders.clear()
	order_changed.emit(null)

func get_order_for(member: Node) -> SquadOrder:
	var targeted_order := member_orders.get(member) as SquadOrder
	if targeted_order != null:
		if not targeted_order.is_expired():
			return targeted_order
		member_orders.erase(member)
	if broadcast_order != null and not broadcast_order.is_expired():
		return broadcast_order
	return null

func clear_member(member: Node) -> void:
	member_orders.erase(member)

func set_shared_target(new_target: Node2D) -> void:
	if shared_target == new_target:
		return
	shared_target = new_target
	shared_target_changed.emit(shared_target)

func set_fact(key: StringName, value: Variant) -> void:
	if facts.has(key) and facts[key] == value:
		return
	facts[key] = value
	fact_changed.emit(key, value)

func get_fact(key: StringName, default_value: Variant = null) -> Variant:
	return facts.get(key, default_value)
