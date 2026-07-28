extends Node
class_name SquadTaskScheduler

signal plan_started(plan: SquadCommandPlan)
signal plan_cancelled(plan_version: int, reason: String)
signal task_state_changed(task: SquadTask, previous: SquadTask.State, current: SquadTask.State)

var active_plan: SquadCommandPlan = null
var members_by_id: Dictionary = {}
var tasks_by_id: Dictionary = {}
var _task_versions: Dictionary = {}

func bind_members(members: Array[SquadMember]) -> void:
	members_by_id.clear()
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var member_id := String(member.actor.name)
		members_by_id[member_id] = member
		if not member.task_state_reported.is_connected(_on_member_task_state):
			member.task_state_reported.connect(_on_member_task_state)

func remove_member(member: SquadMember) -> void:
	if member == null or not is_instance_valid(member.actor):
		return
	var member_id := String(member.actor.name)
	members_by_id.erase(member_id)
	if active_plan == null:
		return
	var active_tasks_to_evaluate: Array[SquadTask] = []
	for task in active_plan.tasks:
		var recipient_index := task.recipient_ids.find(member_id)
		if recipient_index >= 0:
			task.recipient_ids.remove_at(recipient_index)
		task.member_positions.erase(member_id)
		task.member_covers.erase(member_id)
		task.member_targets.erase(member_id)
		if task.member_states.erase(member_id) and task.state in [SquadTask.State.ACTIVE, SquadTask.State.READY]:
			active_tasks_to_evaluate.append(task)
	for task in active_tasks_to_evaluate:
		if task.recipient_ids.is_empty():
			_set_task_state(task, SquadTask.State.FAILED)
		else:
			_evaluate_task(task)

func start_plan(plan: SquadCommandPlan, members: Array[SquadMember]) -> bool:
	if plan == null or not plan.validate().is_empty():
		return false
	cancel_active_plan("replaced")
	active_plan = plan
	bind_members(members)
	tasks_by_id.clear()
	for task in plan.tasks:
		task.state = SquadTask.State.PENDING
		task.member_states.clear()
		tasks_by_id[task.task_id] = task
	plan_started.emit(plan)
	_schedule_ready_tasks()
	return true

func cancel_active_plan(reason: String) -> void:
	if active_plan == null:
		return
	var previous_version := active_plan.plan_version
	for task in active_plan.tasks:
		if task.state in [SquadTask.State.PENDING, SquadTask.State.ACTIVE, SquadTask.State.READY]:
			_set_task_state(task, SquadTask.State.CANCELLED)
	for member in members_by_id.values():
		(member as SquadMember).cancel_task(active_plan.situation_version, active_plan.plan_version, reason)
	active_plan = null
	tasks_by_id.clear()
	plan_cancelled.emit(previous_version, reason)

func get_summary() -> String:
	if active_plan == null:
		return "无活动任务图"
	var parts := PackedStringArray()
	for task in active_plan.tasks:
		parts.append("%s:%s" % [task.get_type_name(), task.get_state_name()])
	return " -> ".join(parts)

func _schedule_ready_tasks() -> void:
	if active_plan == null:
		return
	for task in active_plan.tasks:
		if task.state != SquadTask.State.PENDING or not task.dependencies_satisfied(tasks_by_id):
			continue
		_dispatch_task(task)

func _dispatch_task(task: SquadTask) -> void:
	_set_task_state(task, SquadTask.State.ACTIVE)
	for member_id in task.recipient_ids:
		var member := members_by_id.get(member_id) as SquadMember
		if member == null:
			task.member_states[member_id] = SquadTask.State.FAILED
			continue
		var next_version := int(_task_versions.get(member_id, 0)) + 1
		_task_versions[member_id] = next_version
		var assignment := SquadTaskAssignment.new().configure(
			task.clone_for_member(member_id),
			member_id,
			active_plan.situation_version,
			active_plan.plan_version,
			next_version
		)
		task.member_states[member_id] = SquadTask.State.ACTIVE
		member.receive_task(assignment)
	_evaluate_task(task)

func _on_member_task_state(member: SquadMember, assignment: SquadTaskAssignment, state: SquadTask.State, _detail: String) -> void:
	if active_plan == null or assignment == null:
		return
	if assignment.situation_version != active_plan.situation_version or assignment.plan_version != active_plan.plan_version:
		return
	var task := tasks_by_id.get(assignment.task.task_id) as SquadTask
	if task == null or not is_instance_valid(member.actor):
		return
	task.member_states[String(member.actor.name)] = state
	_evaluate_task(task)

func _evaluate_task(task: SquadTask) -> void:
	if task.recipient_ids.is_empty():
		_set_task_state(task, SquadTask.State.FAILED)
		return
	var states: Array = task.member_states.values()
	if states.any(func(value): return value == SquadTask.State.FAILED):
		_set_task_state(task, SquadTask.State.FAILED)
		return
	var satisfied := false
	match task.completion_policy:
		SquadTask.CompletionPolicy.ALL_READY:
			satisfied = not states.is_empty() and states.all(func(value): return value in [SquadTask.State.READY, SquadTask.State.SUCCEEDED])
		SquadTask.CompletionPolicy.ANY_SUCCEEDED:
			satisfied = states.any(func(value): return value == SquadTask.State.SUCCEEDED)
		_:
			satisfied = not states.is_empty() and states.all(func(value): return value == SquadTask.State.SUCCEEDED)
	if satisfied:
		_set_task_state(task, SquadTask.State.READY if task.persistent else SquadTask.State.SUCCEEDED)
		_schedule_ready_tasks()

func _set_task_state(task: SquadTask, state: SquadTask.State) -> void:
	if task.state == state:
		return
	var previous := task.state
	task.state = state
	task_state_changed.emit(task, previous, state)
