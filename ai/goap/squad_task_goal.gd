extends GoapGoal
class_name SquadTaskGoal

func is_valid() -> bool:
	if not enabled or _actor == null:
		return false
	var member := _actor.get("squad_member") as SquadMember
	return member != null and member.get_current_task() != null

func get_priority() -> int:
	var member := _actor.get("squad_member") as SquadMember
	var assignment := member.get_current_task() if member else null
	return assignment.task.priority if assignment and assignment.task else priority

func prepare() -> void:
	var member := _actor.get("squad_member") as SquadMember
	var assignment := member.get_current_task() if member else null
	desired_state = {&"completed_task_token": assignment.token()} if assignment else {}

func enter() -> void:
	super.enter()
	var member := _actor.get("squad_member") as SquadMember
	var assignment := member.get_current_task() if member else null
	if member and assignment:
		member.set_ai_status("服从任务图", "GOAP 正在拆解动作", "%s：%s" % [assignment.task.task_id, assignment.task.get_type_name()])

func on_goal_achieved() -> void:
	var member := _actor.get("squad_member") as SquadMember
	if member:
		member.report_task_succeeded()

func on_goal_failed() -> void:
	var member := _actor.get("squad_member") as SquadMember
	if member:
		member.report_task_failed("GOAP 无可用动作链")

