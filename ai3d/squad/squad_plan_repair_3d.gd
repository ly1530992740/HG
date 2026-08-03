extends RefCounted
class_name SquadPlanRepair3D

var _route_planner := SquadHeatmapRoutePlanner3D.new()

func repair(
		active_plan: SquadCommandPlan3D,
		failed_task_id: StringName,
		failed_member_id: StringName,
		reason: String,
		snapshot: SquadDecisionSnapshot3D,
		influence: SquadInfluenceMap3D,
		coordinator: SquadCoordinator3D
) -> Dictionary:
	if active_plan == null or snapshot == null:
		return {"repaired": false, "reason": "missing active plan or snapshot"}
	var plan := active_plan.clone_for_patch()
	var changed := false
	var operations := PackedStringArray()
	var replacement_id := _select_replacement(failed_member_id, failed_task_id, snapshot, plan)
	var failed_member_available := _snapshot_has_member(snapshot, failed_member_id)
	if failed_member_id != &"" and replacement_id != &"":
		var member_changed := _replace_member(plan, failed_member_id, replacement_id)
		changed = member_changed or changed
		if member_changed:
			operations.append("member:%s->%s" % [failed_member_id, replacement_id])
	elif failed_member_id != &"" and not failed_member_available:
		var member_removed := _remove_member(plan, failed_member_id)
		changed = member_removed or changed
		if member_removed:
			operations.append("member:%s->removed" % failed_member_id)
	for unavailable_id in _remove_unavailable_members(plan, snapshot):
		changed = true
		operations.append("member:%s->removed" % unavailable_id)

	var staffing_error := _validate_staffing(plan)
	if not staffing_error.is_empty():
		return {
			"repaired": false,
			"requires_full_tactic": true,
			"reason": staffing_error,
		}

	var task := _find_task(plan, failed_task_id)
	if task != null:
		if task.type == SquadTask3D.Type.TAKE_COVER:
			var failed_member := coordinator.get_member_by_id(String(failed_member_id)) if coordinator != null else null
			if failed_member != null and failed_member.active_directive != null:
				var failed_cover := failed_member.active_directive.assigned_cover
				if is_instance_valid(failed_cover) and StringName(failed_cover.name) not in task.excluded_cover_ids:
					task.excluded_cover_ids.append(StringName(failed_cover.name))
			task.assignment_revision += 1
			changed = true
			operations.append("cover")
		if task.type in [
			SquadTask3D.Type.MOVE_TO_OBJECTIVE,
			SquadTask3D.Type.RETURN_TO_ORIGIN,
			SquadTask3D.Type.TAKE_COVER,
			SquadTask3D.Type.RECON_ZONE,
			SquadTask3D.Type.FLANK_ZONE,
		]:
			var route_origin := snapshot.squad_center
			var route_member_id := replacement_id if replacement_id != &"" else failed_member_id
			var route_member := coordinator.get_member_by_id(String(route_member_id)) if coordinator != null else null
			if route_member != null:
				route_origin = route_member.global_position
			var route_plan := _route_planner.build_route(route_origin, task.target_position, influence)
			task.route.assign(route_plan.get("route", []))
			task.route_revision += 1
			task.route_peak_threat = float(route_plan.get("peak_threat", 0.0))
			task.route_exposure_seconds = float(route_plan.get("exposure_seconds", 0.0))
			changed = true
			operations.append("route")

	if not changed:
		return {"repaired": false, "reason": "no local repair available"}
	plan.reason = "PLAN_REPAIR %s: %s" % [", ".join(operations), reason]
	return {"repaired": true, "plan": plan, "operations": operations}

func _select_replacement(
		failed_member_id: StringName,
		failed_task_id: StringName,
		snapshot: SquadDecisionSnapshot3D,
		plan: SquadCommandPlan3D
) -> StringName:
	if failed_member_id == &"":
		return &""
	var used := {}
	var failed_task := _find_task(plan, failed_task_id)
	if failed_task != null:
		for member_id in failed_task.recipient_ids:
			if StringName(member_id) != failed_member_id:
				used[StringName(member_id)] = true
	var candidates := snapshot.members.duplicate()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		return _member_score(a) > _member_score(b)
	)
	for member in candidates:
		var member_id := StringName(member.get("id", ""))
		if member_id != failed_member_id and not used.has(member_id):
			return member_id
	return &""

func _replace_member(plan: SquadCommandPlan3D, previous: StringName, replacement: StringName) -> bool:
	var changed := false
	for task in plan.tasks:
		var index := task.recipient_ids.find(String(previous))
		if index < 0:
			continue
		if String(replacement) in task.recipient_ids:
			task.recipient_ids.remove_at(index)
		else:
			task.recipient_ids[index] = String(replacement)
		if task.member_contact_ids.has(previous):
			if not task.member_contact_ids.has(replacement):
				task.member_contact_ids[replacement] = task.member_contact_ids[previous]
			task.member_contact_ids.erase(previous)
		task.member_states.erase(previous)
		task.assignment_revision += 1
		changed = true
	return changed

func _remove_member(plan: SquadCommandPlan3D, member_id: StringName) -> bool:
	var changed := false
	for task in plan.tasks:
		var index := task.recipient_ids.find(String(member_id))
		if index < 0:
			continue
		task.recipient_ids.remove_at(index)
		task.member_contact_ids.erase(member_id)
		task.member_states.erase(member_id)
		task.assignment_revision += 1
		changed = true
	return changed

func _remove_unavailable_members(
		plan: SquadCommandPlan3D,
		snapshot: SquadDecisionSnapshot3D
) -> PackedStringArray:
	var unavailable := PackedStringArray()
	for task in plan.tasks:
		for recipient_id in task.recipient_ids:
			var member_id := StringName(recipient_id)
			if not _snapshot_has_member(snapshot, member_id) and String(member_id) not in unavailable:
				unavailable.append(String(member_id))
	for member_id in unavailable:
		_remove_member(plan, StringName(member_id))
	return unavailable

func _validate_staffing(plan: SquadCommandPlan3D) -> String:
	for task in plan.tasks:
		if task.recipient_ids.is_empty():
			return "task %s has no living recipient after repair" % task.task_id
		if task.minimum_success_count > 0 and task.recipient_ids.size() < task.minimum_success_count:
			return "task %s requires %d members but only %d remain" % [
				task.task_id, task.minimum_success_count, task.recipient_ids.size(),
			]
	return ""

func _snapshot_has_member(snapshot: SquadDecisionSnapshot3D, member_id: StringName) -> bool:
	if member_id == &"":
		return false
	for member in snapshot.members:
		if StringName(member.get("id", "")) == member_id:
			return true
	return false

func _find_task(plan: SquadCommandPlan3D, task_id: StringName) -> SquadTask3D:
	for task in plan.tasks:
		if task.task_id == task_id:
			return task
	return null

func _member_score(member: Dictionary) -> float:
	return float(member.get("combat_power", 0.0)) * 2.0 \
		+ float(member.get("health", 0.0)) * 40.0 \
		+ float(member.get("mobility", 0.0)) * 25.0 \
		- float(member.get("suppression", 0.0)) * 30.0
