## GOAP brain with F.E.A.R.-style goal arbitration and runtime validation.
@icon("res://addons/goap/icons/goap_agent.svg")
class_name GoapAgent
extends Node

const DEBUG_PREFIX := "goap_debug"
const RELEVANCE_EPSILON := 0.001

signal plan_changed(new_plan: Array)
signal goal_changed(new_goal: GoapGoal)
signal action_changed(new_action: GoapAction)

@export var actions_node: Node
@export var goals_node: Node
@export var debug_enabled := true
@export var replan_on_world_state_change := true

var _goals: Array[GoapGoal] = []
var _actions: Array[GoapAction] = []
var _current_goal: GoapGoal
var _planning_goal: GoapGoal
var _current_plan: Array = []
var _current_plan_step := 0
var _actor
var _world_state: GoapWorldState
var _action_planner: GoapActionPlanner
var _last_blackboard: Dictionary = {}
var _replan_requested := false
var _goal_reevaluation_remaining := 0.0
var previous_action: GoapAction
var _debug_id := ""

func _exit_tree() -> void:
	if is_instance_valid(_action_planner):
		_action_planner.free()
		_action_planner = null
	if is_instance_valid(_world_state):
		_world_state.free()
		_world_state = null

func init(actor) -> void:
	_actor = actor
	_world_state = GoapWorldState.new()
	_debug_id = str(get_path())
	for child in goals_node.get_children():
		if child is GoapGoal:
			var goal := child as GoapGoal
			_goals.append(goal)
			goal.agent = self
			goal.init(_actor, _world_state)
	for child in actions_node.get_children():
		if child is GoapAction:
			var action := child as GoapAction
			_actions.append(action)
			action.agent = self
			action.init(_actor, _world_state)
	_action_planner = GoapActionPlanner.new()
	_action_planner.set_actions(_actions)
	_connect_debug_signals()
	_send_debug_register(_actions)

func process(delta) -> void:
	_goal_reevaluation_remaining = maxf(0.0, _goal_reevaluation_remaining - float(delta))
	var force_replan := _replan_requested
	_replan_requested = false
	var must_select := force_replan or _current_goal == null \
		or not _current_goal.enabled or not _current_goal.is_valid() \
		or _goal_reevaluation_remaining <= 0.0
	if must_select:
		if _select_relevant_goal(force_replan):
			return
	if _current_goal != null and not _current_plan.is_empty():
		_follow_plan(float(delta))

func request_replan() -> void:
	_replan_requested = true

func _select_relevant_goal(force_replan: bool) -> bool:
	var candidates: Array[GoapGoal] = []
	for goal in _goals:
		if goal.enabled and goal.is_valid():
			candidates.append(goal)
	candidates.sort_custom(_goal_precedes)

	var current_action := get_current_action()
	var locked := _current_goal != null and (
		not _current_goal.is_plan_interruptible()
		or (current_action != null and not current_action.is_interruptible())
	)
	var selected_goal: GoapGoal
	var selected_plan: Array = []
	for candidate in candidates:
		if locked and candidate != _current_goal \
			and candidate.get_interrupt_priority() <= _current_goal.get_interrupt_priority():
			continue
		if candidate != _current_goal and randf() > candidate.get_activation_chance():
			continue
		candidate.prepare()
		var blackboard := _build_blackboard()
		if _state_satisfies(blackboard, candidate.get_desired_state()):
			if candidate == _current_goal:
				_complete_current_goal()
			continue
		_planning_goal = candidate
		var plan := _action_planner.get_plan(candidate, blackboard)
		_planning_goal = null
		if plan.is_empty():
			_trace("no-plan goal=%s relevance=%.1f world=%s desired=%s" % [candidate.name, candidate.get_relevance(), str(blackboard), str(candidate.get_desired_state())])
			candidate.on_goal_failed()
			continue
		selected_goal = candidate
		selected_plan = plan
		break

	if selected_goal == null:
		if _current_goal != null and (not _current_goal.is_valid() or force_replan):
			_deactivate_current_goal()
		_goal_reevaluation_remaining = 0.1
		return false

	var goal_changed_value := selected_goal != _current_goal
	var plan_changed_value := force_replan or goal_changed_value or _current_plan.is_empty()
	if not plan_changed_value:
		_goal_reevaluation_remaining = selected_goal.get_reevaluation_interval()
		return false

	_interrupt_current_action()
	if goal_changed_value and _current_goal != null:
		_current_goal.exit()
	_current_goal = selected_goal
	if goal_changed_value:
		_current_goal.enter()
		goal_changed.emit(_current_goal)
	_current_plan = selected_plan
	_current_plan_step = 0
	_last_blackboard = _build_blackboard()
	_goal_reevaluation_remaining = _current_goal.get_reevaluation_interval()
	plan_changed.emit(_current_plan)
	_trace("selected goal=%s plan=%s" % [_current_goal.name, str(_current_plan.map(func(item): return item.name))])
	return true

func _goal_precedes(a: GoapGoal, b: GoapGoal) -> bool:
	var relevance_a := a.get_relevance()
	var relevance_b := b.get_relevance()
	if absf(relevance_a - relevance_b) <= RELEVANCE_EPSILON:
		if a == _current_goal:
			return true
		if b == _current_goal:
			return false
		return a.get_interrupt_priority() > b.get_interrupt_priority()
	return relevance_a > relevance_b

func _follow_plan(delta: float) -> void:
	if _current_plan_step >= _current_plan.size() - 1:
		if _state_satisfies(_build_blackboard(), _current_goal.get_desired_state()):
			_complete_current_goal()
		else:
			_fail_current_plan()
		return
	_current_goal.perform(delta)
	var action := _current_plan[_current_plan_step] as GoapAction
	if action == null or not action.is_valid_at_runtime():
		_fail_current_plan()
		return
	if not action.get_meta("_entered", false):
		action.enter()
		action.set_meta("_entered", true)
		action_changed.emit(action)
	if not action.perform(delta):
		return
	previous_action = action
	action.exit()
	action.set_meta("_entered", false)
	action_changed.emit(null)
	action.set_effects(action.get_effects())
	if not _verify_action_effects(action):
		_fail_current_plan()
		return
	_current_plan_step += 1
	if _state_satisfies(_build_blackboard(), _current_goal.get_desired_state()):
		_complete_current_goal()

func _complete_current_goal() -> void:
	if _current_goal == null:
		return
	var completed := _current_goal
	completed.on_goal_achieved()
	completed.exit()
	_current_goal = null
	_current_plan = []
	_current_plan_step = 0
	_goal_reevaluation_remaining = 0.0
	plan_changed.emit([])

func _fail_current_plan() -> void:
	_interrupt_current_action()
	_current_plan = []
	_current_plan_step = 0
	_replan_requested = true
	_goal_reevaluation_remaining = 0.0
	plan_changed.emit([])

func _deactivate_current_goal() -> void:
	_interrupt_current_action()
	if _current_goal != null:
		_current_goal.exit()
	_current_goal = null
	_current_plan = []
	_current_plan_step = 0
	plan_changed.emit([])

func _interrupt_current_action() -> void:
	var action := get_current_action()
	if action != null and action.get_meta("_entered", false):
		action.exit()
		action.set_meta("_entered", false)
		action_changed.emit(null)

func _build_blackboard() -> Dictionary:
	var blackboard := {"global_position": _actor.global_position}
	for key in _world_state._state:
		blackboard[key] = _world_state._state[key]
	return blackboard

func _state_satisfies(state: Dictionary, desired: Dictionary) -> bool:
	if desired.is_empty():
		return false
	for key in desired:
		if not GoapWorldState.is_satisfied(state.get(key), desired[key]):
			return false
	return true

func _verify_action_effects(action: GoapAction) -> bool:
	for key in action.get_effects():
		if not GoapWorldState.is_satisfied(_world_state.get_state(key), action.get_effects()[key]):
			return false
	return true

func _get_best_goal() -> GoapGoal:
	var candidates: Array[GoapGoal] = []
	for goal in _goals:
		if goal.enabled and goal.is_valid():
			candidates.append(goal)
	candidates.sort_custom(_goal_precedes)
	return candidates[0] if not candidates.is_empty() else null

func get_current_goal() -> GoapGoal:
	return _current_goal

func get_context_goal() -> GoapGoal:
	return _planning_goal if _planning_goal != null else _current_goal

func get_current_action() -> GoapAction:
	if _current_plan_step < _current_plan.size() - 1:
		return _current_plan[_current_plan_step] as GoapAction
	return null

func get_world_state() -> GoapWorldState:
	return _world_state

func debug_select() -> void:
	_send_debug("select", [])

func _send_debug(msg_type: String, data: Array) -> void:
	if debug_enabled and EngineDebugger.is_active():
		EngineDebugger.send_message(DEBUG_PREFIX + ":" + msg_type, [_debug_id] + data)

func _connect_debug_signals() -> void:
	goal_changed.connect(_on_debug_goal_changed)
	plan_changed.connect(_on_debug_plan_changed)
	action_changed.connect(_on_debug_action_changed)
	_world_state.state_updated.connect(_on_world_state_updated)

func _send_debug_register(actions: Array) -> void:
	var goal_data := []
	for goal in _goals:
		goal_data.append({
			"name": goal.get_action_name(),
			"priority": goal.get_priority(),
			"desired_state": goal.get_desired_state(),
			"cost": goal.get_cost({}),
		})
	var action_data := []
	for action in actions:
		action_data.append({
			"name": action.get_action_name(),
			"cost": action.cost,
			"preconditions": action.get_preconditions(),
			"effects": action.get_effects(),
		})
	_send_debug("registry", [goal_data, action_data])

func _on_debug_goal_changed(new_goal: GoapGoal) -> void:
	_send_debug("goal", [new_goal.get_action_name(), new_goal.get_relevance(), new_goal.get_desired_state()] if new_goal else ["", 0, {}])

func _on_debug_plan_changed(plan: Array) -> void:
	var data := []
	for item in plan:
		if item is GoapAction:
			data.append({"name": item.get_action_name(), "cost": item.get_cost(_last_blackboard)})
		elif item is GoapGoal:
			data.append({"name": item.get_action_name(), "cost": item.get_cost(_last_blackboard)})
	_send_debug("plan", [data])

func _on_debug_action_changed(new_action: GoapAction) -> void:
	_send_debug("action", [new_action.get_action_name() if new_action else ""])
	_send_debug("step", [_current_plan_step, _current_plan.size()])

func _on_world_state_updated() -> void:
	if replan_on_world_state_change:
		request_replan()
	_send_debug("world_state", [_world_state._state.duplicate()])

func _trace(message: String) -> void:
	if OS.has_environment("GOAP_TRACE"):
		print("[GOAP] actor=%s %s" % [_actor.name if _actor != null else "?", message])
