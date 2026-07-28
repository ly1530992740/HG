extends RefCounted
class_name SquadTaskAssignment

var situation_version := 0
var plan_version := 0
var task_version := 0
var member_id := ""
var task: SquadTask = null
var assigned_at_msec := 0

func configure(
		new_task: SquadTask,
		new_member_id: String,
		new_situation_version: int,
		new_plan_version: int,
		new_task_version: int
) -> SquadTaskAssignment:
	task = new_task
	member_id = new_member_id
	situation_version = new_situation_version
	plan_version = new_plan_version
	task_version = new_task_version
	assigned_at_msec = Time.get_ticks_msec()
	return self

func is_newer_than(other: SquadTaskAssignment) -> bool:
	if other == null:
		return true
	if situation_version != other.situation_version:
		return situation_version > other.situation_version
	if plan_version != other.plan_version:
		return plan_version > other.plan_version
	return task_version > other.task_version

func token() -> StringName:
	return StringName("%d:%d:%d" % [situation_version, plan_version, task_version])
