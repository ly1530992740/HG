## Forward A* planner for symbolic GOAP world states.
@icon("res://addons/goap/icons/goap_action_planner.svg")
class_name GoapActionPlanner
extends Node

const MAX_EXPANDED_NODES := 4096

var _actions: Array = []

func set_actions(actions: Array) -> void:
	_actions = actions

func get_plan(goal: GoapGoal, blackboard := {}) -> Array:
	if goal == null:
		return []
	var desired := goal.get_desired_state()
	if desired.is_empty() or _state_satisfies(blackboard, desired):
		return []
	return _search(goal, blackboard.duplicate(true), desired)

func _search(goal: GoapGoal, start: Dictionary, desired: Dictionary) -> Array:
	var open: Array[Dictionary] = [{
		"state": start,
		"actions": [],
		"cost": 0,
		"score": _heuristic(start, desired),
	}]
	var best_cost: Dictionary = {_state_key(start): 0}
	var expanded := 0
	while not open.is_empty() and expanded < MAX_EXPANDED_NODES:
		var best_index := _lowest_score_index(open)
		var current: Dictionary = open.pop_at(best_index)
		var state: Dictionary = current["state"]
		if _state_satisfies(state, desired):
			var result: Array = current["actions"].duplicate()
			result.append(goal)
			return result
		expanded += 1
		for action_value in _actions:
			var action := action_value as GoapAction
			if action == null or not action.is_valid_for_planning(state):
				continue
			if not _state_satisfies(state, action.get_preconditions()):
				continue
			var next_state := _apply_effects(state, action.get_effects())
			if next_state == state:
				continue
			var next_cost := int(current["cost"]) + maxi(0, action.get_cost(state))
			var key := _state_key(next_state)
			if best_cost.has(key) and int(best_cost[key]) <= next_cost:
				continue
			best_cost[key] = next_cost
			var next_actions: Array = current["actions"].duplicate()
			next_actions.append(action)
			open.append({
				"state": next_state,
				"actions": next_actions,
				"cost": next_cost,
				"score": next_cost + _heuristic(next_state, desired),
			})
	return []

func _lowest_score_index(nodes: Array[Dictionary]) -> int:
	var best_index := 0
	var best_score := int(nodes[0]["score"])
	var best_cost_value := int(nodes[0]["cost"])
	for index in range(1, nodes.size()):
		var score := int(nodes[index]["score"])
		var cost_value := int(nodes[index]["cost"])
		if score < best_score or (score == best_score and cost_value < best_cost_value):
			best_index = index
			best_score = score
			best_cost_value = cost_value
	return best_index

func _state_satisfies(state: Dictionary, conditions: Dictionary) -> bool:
	for key in conditions:
		if not GoapWorldState.is_satisfied(state.get(key), conditions[key]):
			return false
	return true

func _apply_effects(state: Dictionary, effects: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	for key in effects:
		result[key] = effects[key]
	return result

func _heuristic(state: Dictionary, desired: Dictionary) -> int:
	var missing := 0
	for key in desired:
		if not GoapWorldState.is_satisfied(state.get(key), desired[key]):
			missing += 1
	return missing

func _state_key(state: Dictionary) -> String:
	var keys := state.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%s" % [str(key), var_to_str(state[key])])
	return "|".join(parts)
