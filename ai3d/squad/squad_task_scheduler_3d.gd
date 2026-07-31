extends Node
class_name SquadTaskScheduler3D

signal plan_started(plan: SquadCommandPlan3D)
signal plan_completed(plan: SquadCommandPlan3D)
signal plan_cancelled(plan: SquadCommandPlan3D, reason: String)
signal plan_patched(previous: SquadCommandPlan3D, current: SquadCommandPlan3D)
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

func patch_plan(plan: SquadCommandPlan3D) -> bool:
	if active_plan == null:
		return start_plan(plan)
	var error := plan.validate()
	if not error.is_empty():
		push_error("[SQUAD_TASK_3D] rejected patch: %s" % error)
		return false
	var previous := active_plan
	var previous_tasks := tasks_by_id.duplicate()
	var next_tasks: Dictionary = {}
	for task in plan.tasks:
		var existing := previous_tasks.get(task.task_id) as SquadTask3D
		if existing != null and existing.get_signature() == task.get_signature() \
				and existing.state not in [SquadTask3D.State.FAILED, SquadTask3D.State.CANCELLED]:
			next_tasks[task.task_id] = existing
			var index := plan.tasks.find(task)
			plan.tasks[index] = existing
		else:
			if existing != null and existing.state in [SquadTask3D.State.PENDING, SquadTask3D.State.ACTIVE, SquadTask3D.State.READY]:
				_set_task_state(existing, SquadTask3D.State.CANCELLED)
			task.state = SquadTask3D.State.PENDING
			task.member_states.clear()
			next_tasks[task.task_id] = task
	for old_value in previous.tasks:
		var old_task := old_value as SquadTask3D
		if not next_tasks.has(old_task.task_id) and old_task.state in [SquadTask3D.State.PENDING, SquadTask3D.State.ACTIVE, SquadTask3D.State.READY]:
			_set_task_state(old_task, SquadTask3D.State.CANCELLED)
	active_plan = plan
	tasks_by_id = next_tasks
	plan_patched.emit(previous, plan)
	_schedule_ready_tasks()
	return true

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
			if not _inherit_successful_members(task):
				_set_task_state(task, SquadTask3D.State.FAILED)
				continue
			_set_task_state(task, SquadTask3D.State.ACTIVE)
			for member_id in task.recipient_ids:
				task.member_states[StringName(member_id)] = SquadTask3D.State.ACTIVE
			task_activated.emit(task)

func _inherit_successful_members(task: SquadTask3D) -> bool:
	if task.successful_members_from == &"":
		return true
	var source := tasks_by_id.get(task.successful_members_from) as SquadTask3D
	if source == null:
		return false
	var eligible := PackedStringArray()
	for member_id in task.recipient_ids:
		if source.member_states.get(StringName(member_id)) == SquadTask3D.State.SUCCEEDED:
			eligible.append(member_id)
	task.recipient_ids = eligible
	return not task.recipient_ids.is_empty()

func _mark_member_state(task_id: StringName, member_id: StringName, state: SquadTask3D.State) -> void:
	var task := tasks_by_id.get(task_id) as SquadTask3D
	if task == null or task.state not in [SquadTask3D.State.ACTIVE, SquadTask3D.State.READY]:
		return
	task.member_states[member_id] = state
	_evaluate_task(task)

func _evaluate_task(task: SquadTask3D) -> void:
	var states: Array = task.member_states.values()
	var required := task.get_required_success_count()
	var failed_count := states.count(SquadTask3D.State.FAILED)
	if states.size() - failed_count < required:
		_set_task_state(task, SquadTask3D.State.FAILED)
		return
	if states.is_empty():
		return
	if task.persistent:
		var ready_count := states.count(SquadTask3D.State.READY) + states.count(SquadTask3D.State.SUCCEEDED)
		if ready_count >= required:
			_set_task_state(task, SquadTask3D.State.READY)
			_schedule_ready_tasks()
		return
	if states.count(SquadTask3D.State.SUCCEEDED) >= required:
		_set_task_state(task, SquadTask3D.State.SUCCEEDED)
		_schedule_ready_tasks()
		_check_plan_completed()

func _check_plan_completed() -> void:
	if active_plan == null:
		return
	for task in active_plan.tasks:
		if task.persistent and task.state == SquadTask3D.State.READY:
			return
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
	if state == SquadTask3D.State.ACTIVE:
		task.activated_msec = Time.get_ticks_msec()
	task_state_changed.emit(task, previous, state)
