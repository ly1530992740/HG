extends RefCounted
class_name SquadCommandPlan

var situation_version := 0
var plan_version := 0
var intent: StringName = &"GUARD"
var reason := ""
var source := "RULE_FALLBACK"
var tasks: Array[SquadTask] = []
var created_at_msec := 0

func configure(new_situation_version: int, new_plan_version: int, new_intent: StringName, new_reason: String, new_source: String) -> SquadCommandPlan:
	situation_version = new_situation_version
	plan_version = new_plan_version
	intent = new_intent
	reason = new_reason
	source = new_source
	created_at_msec = Time.get_ticks_msec()
	return self

func add_task(task: SquadTask) -> SquadTask:
	if task != null:
		tasks.append(task)
	return task

func get_task(task_id: StringName) -> SquadTask:
	for task in tasks:
		if task.task_id == task_id:
			return task
	return null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var known_ids: Dictionary = {}
	for task in tasks:
		if task.task_id == &"":
			errors.append("task id is empty")
		elif known_ids.has(task.task_id):
			errors.append("duplicate task id: %s" % task.task_id)
		known_ids[task.task_id] = true
		if task.recipient_ids.is_empty():
			errors.append("task %s has no recipients" % task.task_id)
	for task in tasks:
		for dependency_id in task.depends_on:
			if not known_ids.has(dependency_id):
				errors.append("task %s depends on unknown task %s" % [task.task_id, dependency_id])
	return errors

