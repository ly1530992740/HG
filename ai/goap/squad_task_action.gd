extends GoapAction
class_name SquadTaskAction

enum Operation {
	MOVE_DIRECT,
	MOVE_SAFE,
	ENTER_COVER,
	COMPLETE_MOVE,
	ACQUIRE_TARGET,
	AIM_TARGET,
	SUPPRESS_TARGET,
	NEUTRALIZE_TARGET,
	GUARD_AREA,
}

@export var operation: Operation = Operation.MOVE_SAFE
var _executing_token: StringName = &""

func is_valid() -> bool:
	if not enabled or _actor == null:
		return false
	var assignment := _get_assignment()
	if assignment == null or assignment.task == null:
		return false
	match operation:
		Operation.MOVE_DIRECT, Operation.MOVE_SAFE:
			return assignment.task.type in [SquadTask.Type.GUARD_AREA, SquadTask.Type.OCCUPY_COVER, SquadTask.Type.MOVE_TO_ZONE, SquadTask.Type.WITHDRAW_TO_ZONE]
		Operation.ENTER_COVER:
			return assignment.task.type == SquadTask.Type.OCCUPY_COVER
		Operation.COMPLETE_MOVE:
			return assignment.task.type in [SquadTask.Type.MOVE_TO_ZONE, SquadTask.Type.WITHDRAW_TO_ZONE]
		Operation.ACQUIRE_TARGET:
			return assignment.task.type in [SquadTask.Type.AIM_TARGET, SquadTask.Type.SUPPRESS_TARGET, SquadTask.Type.NEUTRALIZE_TARGET]
		Operation.AIM_TARGET:
			return assignment.task.type in [SquadTask.Type.AIM_TARGET, SquadTask.Type.NEUTRALIZE_TARGET]
		Operation.SUPPRESS_TARGET:
			return assignment.task.type == SquadTask.Type.SUPPRESS_TARGET
		Operation.NEUTRALIZE_TARGET:
			return assignment.task.type == SquadTask.Type.NEUTRALIZE_TARGET
		Operation.GUARD_AREA:
			return assignment.task.type == SquadTask.Type.GUARD_AREA
	return false

func get_preconditions() -> Dictionary:
	match operation:
		Operation.ENTER_COVER, Operation.COMPLETE_MOVE, Operation.GUARD_AREA:
			preconditions = {&"at_task_destination": true}
		Operation.AIM_TARGET, Operation.SUPPRESS_TARGET:
			preconditions = {&"task_target_acquired": true}
		Operation.NEUTRALIZE_TARGET:
			preconditions = {&"task_target_acquired": true, &"task_aimed": true}
		_:
			preconditions = {}
	return preconditions

func get_effects() -> Dictionary:
	var assignment := _get_assignment()
	if assignment == null:
		return {}
	match operation:
		Operation.MOVE_DIRECT, Operation.MOVE_SAFE:
			effects = {&"at_task_destination": true}
		Operation.ACQUIRE_TARGET:
			effects = {&"task_target_acquired": true}
		Operation.AIM_TARGET:
			if assignment.task.type == SquadTask.Type.AIM_TARGET:
				effects = {&"task_aimed": true, &"completed_task_token": assignment.token()}
			else:
				effects = {&"task_aimed": true}
		Operation.ENTER_COVER, Operation.COMPLETE_MOVE, Operation.SUPPRESS_TARGET, Operation.NEUTRALIZE_TARGET, Operation.GUARD_AREA:
			effects = {&"completed_task_token": assignment.token()}
	return effects

func get_cost(_blackboard) -> int:
	if _actor != null and _actor.has_method("get_task_action_cost"):
		return _actor.get_task_action_cost(operation, cost)
	return cost

func enter() -> void:
	var assignment := _get_assignment()
	_executing_token = assignment.token() if assignment else &""
	if _actor.has_method("begin_task_action"):
		_actor.begin_task_action(operation)

func perform(delta) -> bool:
	var assignment := _get_assignment()
	if assignment == null or assignment.token() != _executing_token:
		return false
	if _actor.has_method("perform_task_action"):
		return _actor.perform_task_action(operation, delta)
	return false

func exit() -> void:
	if _actor.has_method("end_task_action"):
		_actor.end_task_action(operation)

func _get_assignment() -> SquadTaskAssignment:
	var member := _actor.get("squad_member") as SquadMember if _actor else null
	return member.get_current_task() if member else null
