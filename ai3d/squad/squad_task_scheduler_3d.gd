extends Node
class_name SquadTaskScheduler3D

signal plan_started(plan: SquadCommandPlan3D)
signal plan_completed(plan: SquadCommandPlan3D)
signal plan_cancelled(plan: SquadCommandPlan3D, reason: String)
signal task_activated(task: SquadTask3D)
signal task_state_changed(task: SquadTask3D, previous: SquadTask3D.State, current: SquadTask3D.State)

var active_plan: SquadCommandPlan3D
var tasks_by_id: Dictionary = {}

func start_plan(plan: SquadCommandPlan3D) -> bool:
	if plan == null:
		return false
	var error := plan.validate()
	if not error.is_empty():
		push_error("[SQUAD_TASK_3D] rejected plan: %s" % error)
		return false
	cancel_active_plan("replaced")
	active_plan = plan
	tasks_by_id.clear()
	for task in plan.tasks:
		task.state = SquadTask3D.State.PENDING
		task.member_states.clear()
		tasks_by_id[task.task_id] = task
	plan_started.emit(plan)
	_schedule_ready_tasks()
	return true

func cancel_active_plan(reason: String) -> void:
	if active_plan == null:
		return
	var previous := active_plan
	for task in previous.tasks:
		if task.state in [SquadTask3D.State.PENDING, SquadTask3D.State.ACTIVE, SquadTask3D.State.READY]:
			_set_task_state(task, SquadTask3D.State.CANCELLED)
	active_plan = null
	tasks_by_id.clear()
	plan_cancelled.emit(previous, reason)

func mark_member_ready(task_id: StringName, member_id: StringName) -> void:
	_mark_member_state(task_id, member_id, SquadTask3D.State.READY)

func mark_member_succeeded(task_id: StringName, member_id: StringName) -> void:
	_mark_member_state(task_id, member_id, SquadTask3D.State.SUCCEEDED)

func mark_member_failed(task_id: StringName, member_id: StringName) -> void:
	_mark_member_state(task_id, member_id, SquadTask3D.State.FAILED)

func get_summary() -> String:
	if active_plan == null:
		return "NO_ACTIVE_PLAN"
	var parts := PackedStringArray()
	for task in active_plan.tasks:
		parts.append("%s:%s" % [task.get_type_name(), task.get_state_name()])
	return " | ".join(parts)

func _schedule_ready_tasks() -> void:
	if active_plan == null:
		return
	for task in active_plan.tasks:
		if task.state == SquadTask3D.State.PENDING and task.dependencies_satisfied(tasks_by_id):
			_set_task_state(task, SquadTask3D.State.ACTIVE)
			for member_id in task.recipient_ids:
				task.member_states[StringName(member_id)] = SquadTask3D.State.ACTIVE
			task_activated.emit(task)

func _mark_member_state(task_id: StringName, member_id: StringName, state: SquadTask3D.State) -> void:
	var task := tasks_by_id.get(task_id) as SquadTask3D
	if task == null or task.state not in [SquadTask3D.State.ACTIVE, SquadTask3D.State.READY]:
		return
	task.member_states[member_id] = state
	_evaluate_task(task)

func _evaluate_task(task: SquadTask3D) -> void:
	var states: Array = task.member_states.values()
	if states.any(func(value): return value == SquadTask3D.State.FAILED):
		_set_task_state(task, SquadTask3D.State.FAILED)
		return
	if states.is_empty():
		return
	if task.persistent:
		if states.all(func(value): return value in [SquadTask3D.State.READY, SquadTask3D.State.SUCCEEDED]):
			_set_task_state(task, SquadTask3D.State.READY)
			_schedule_ready_tasks()
		return
	if states.all(func(value): return value == SquadTask3D.State.SUCCEEDED):
		_set_task_state(task, SquadTask3D.State.SUCCEEDED)
		_schedule_ready_tasks()
		_check_plan_completed()

func _check_plan_completed() -> void:
	if active_plan == null:
		return
	for task in active_plan.tasks:
		if task.state not in [SquadTask3D.State.READY, SquadTask3D.State.SUCCEEDED]:
			return
	var completed := active_plan
	active_plan = null
	tasks_by_id.clear()
	plan_completed.emit(completed)

func _set_task_state(task: SquadTask3D, state: SquadTask3D.State) -> void:
	if task.state == state:
		return
	var previous := task.state
	task.state = state
	task_state_changed.emit(task, previous, state)

