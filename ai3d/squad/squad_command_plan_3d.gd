extends RefCounted
class_name SquadCommandPlan3D

var plan_id: StringName = &""
var intent: StringName = &""
var source := "RULES"
var reason := ""
var belief_version := 0
var created_msec := 0
var tasks: Array[SquadTask3D] = []
var role_assignments: Array[Dictionary] = []
var role_assignment_score := 0.0

func configure(
		new_plan_id: StringName,
		new_intent: StringName,
		new_source: String,
		new_reason: String,
		new_belief_version: int
) -> SquadCommandPlan3D:
	plan_id = new_plan_id
	intent = new_intent
	source = new_source
	reason = new_reason
	belief_version = new_belief_version
	created_msec = Time.get_ticks_msec()
	return self

func add_task(task: SquadTask3D) -> SquadCommandPlan3D:
	if task != null:
		tasks.append(task)
	return self

func set_role_allocation(allocation: Dictionary) -> SquadCommandPlan3D:
	role_assignments.clear()
	role_assignments.assign(allocation.get("assignments", []))
	role_assignment_score = float(allocation.get("score", 0.0))
	return self

func clone_for_patch() -> SquadCommandPlan3D:
	var result := SquadCommandPlan3D.new().configure(plan_id, intent, source, reason, belief_version)
	result.created_msec = created_msec
	result.role_assignments = role_assignments.duplicate(true)
	result.role_assignment_score = role_assignment_score
	for task in tasks:
		result.add_task(task.clone_for_patch())
	return result

func validate() -> String:
	if plan_id == &"":
		return "plan_id is empty"
	if tasks.is_empty():
		return "plan has no tasks"
	var ids: Dictionary = {}
	for task in tasks:
		if task.task_id == &"" or ids.has(task.task_id):
			return "task id is empty or duplicated"
		ids[task.task_id] = true
		if task.recipient_ids.is_empty():
			return "task %s has no recipients" % task.task_id
	for task in tasks:
		for dependency_id in task.depends_on:
			if not ids.has(dependency_id):
				return "task %s has unknown dependency %s" % [task.task_id, dependency_id]
	return ""
