extends RefCounted
class_name SquadPlanCompiler

static func compile(
		coordinator: SquadCoordinator,
		intent: StringName,
		decision: Dictionary,
		target: Node2D,
		situation_version: int,
		plan_version: int,
		source: String
) -> SquadCommandPlan:
	var reason := String(decision.get("理由", "依据当前态势执行任务图。"))
	var plan := SquadCommandPlan.new().configure(situation_version, plan_version, intent, reason, source)
	var valid_members := _valid_members(coordinator)
	if valid_members.is_empty():
		return plan
	match intent:
		&"AMBUSH":
			_build_ambush(plan, coordinator, valid_members, target)
		&"SUPPRESS_AND_FLANK":
			_build_suppress_and_flank(plan, coordinator, valid_members, target, decision)
		&"ASSAULT":
			_build_assault(plan, coordinator, valid_members, target)
		&"RETREAT":
			_build_retreat(plan, coordinator, valid_members, target)
		&"GUARD":
			_build_guard(plan, coordinator, valid_members)
		_:
			_build_defend(plan, coordinator, valid_members, target)
	return plan

static func _build_ambush(plan: SquadCommandPlan, coordinator: SquadCoordinator, members: Array[SquadMember], target: Node2D) -> void:
	coordinator._ensure_ambush_cover_assignments(target)
	coordinator._refresh_ambush_target_assignments(target)
	var ids := _member_ids(members)
	var occupy := SquadTask.new().configure(&"ambush_cover", SquadTask.Type.OCCUPY_COVER, ids)
	occupy.zone_id = &"AMBUSH_COVERS"
	occupy.target = target
	occupy.timeout_seconds = 18.0
	var aim := SquadTask.new().configure(&"ambush_aim", SquadTask.Type.AIM_TARGET, ids)
	aim.depends_on = [&"ambush_cover"]
	var fire := SquadTask.new().configure(&"ambush_fire", SquadTask.Type.NEUTRALIZE_TARGET, ids)
	fire.depends_on = [&"ambush_aim"]
	for member in members:
		var member_id := String(member.actor.name)
		var cover := coordinator.get_ambush_cover_for(member)
		var assigned_target := coordinator.get_ambush_target_for(member)
		occupy.member_covers[member_id] = cover
		occupy.member_positions[member_id] = _reserve_cover_destination(cover, member.actor, target)
		aim.member_targets[member_id] = assigned_target if is_instance_valid(assigned_target) else target
		fire.member_targets[member_id] = assigned_target if is_instance_valid(assigned_target) else target
	plan.add_task(occupy)
	plan.add_task(aim)
	plan.add_task(fire)

static func _build_suppress_and_flank(plan: SquadCommandPlan, coordinator: SquadCoordinator, members: Array[SquadMember], target: Node2D, decision: Dictionary) -> void:
	if members.size() < 4:
		_build_defend(plan, coordinator, members, target)
		return
	var requested_mobile := clampi(int(decision.get("机动组人数", 3)), 3, maxi(3, members.size() - 2))
	var sorted := members.duplicate()
	sorted.sort_custom(func(a: SquadMember, b: SquadMember): return _mobility_score(a) > _mobility_score(b))
	var flankers: Array[SquadMember] = []
	for member in sorted:
		if flankers.size() >= requested_mobile:
			break
		if member.actor.get_combat_role() != SquadCombatRole.Type.MACHINE_GUNNER:
			flankers.append(member)
	var front: Array[SquadMember] = []
	for member in members:
		if not flankers.has(member):
			front.append(member)
	if front.is_empty():
		front.append(flankers.pop_back())

	var suppress := SquadTask.new().configure(&"front_suppress", SquadTask.Type.SUPPRESS_TARGET, _member_ids(front))
	suppress.target = target
	for member in front:
		suppress.member_targets[String(member.actor.name)] = target
	plan.add_task(suppress)

	var route_id := StringName(decision.get("机动路线ID", ""))
	var route := coordinator.get_route_candidate(route_id)
	if route.is_empty():
		route = coordinator.get_best_route_candidate()
	var route_points: Array = route.get("points", [])
	if route_points.is_empty():
		route_points = coordinator.get_blackboard().get_fact(&"right_flank_route", [])
	if route_points.is_empty():
		var center := coordinator._get_squad_center()
		var direction := (target.global_position - center).normalized() if is_instance_valid(target) else Vector2.RIGHT
		var right := Vector2(-direction.y, direction.x)
		route_points = [center + right * 380.0 + direction * 260.0, target.global_position + right * 420.0 - direction * 260.0]
	var route_side := StringName(route.get("side", &"RIGHT"))
	var route_prefix := "left" if route_side == &"LEFT" else "right"
	var dependency: StringName = &"front_suppress"
	for route_index in route_points.size():
		var task_id := StringName("%s_route_%d" % [route_prefix, route_index + 1])
		var move := SquadTask.new().configure(task_id, SquadTask.Type.MOVE_TO_ZONE, _member_ids(flankers))
		move.zone_id = StringName("%s_ROUTE_%d" % [route_prefix.to_upper(), route_index + 1])
		move.depends_on = [dependency]
		var previous_point: Vector2 = coordinator._get_squad_center() if route_index == 0 else route_points[route_index - 1] as Vector2
		var next_point: Vector2 = route_points[mini(route_index + 1, route_points.size() - 1)] as Vector2
		var route_direction := (next_point - previous_point).normalized()
		var lane_axis := Vector2(-route_direction.y, route_direction.x) if route_direction != Vector2.ZERO else Vector2.DOWN
		for lane_index in flankers.size():
			var member := flankers[lane_index]
			var lane_offset := lane_axis * (float(lane_index) - float(flankers.size() - 1) * 0.5) * 46.0
			move.member_positions[String(member.actor.name)] = (route_points[route_index] as Vector2) + lane_offset
		plan.add_task(move)
		dependency = task_id
	var aim := SquadTask.new().configure(&"flank_aim", SquadTask.Type.AIM_TARGET, _member_ids(flankers))
	aim.depends_on = [dependency]
	var attack := SquadTask.new().configure(&"flank_attack", SquadTask.Type.NEUTRALIZE_TARGET, _member_ids(flankers))
	attack.depends_on = [&"flank_aim"]
	_assign_targets(coordinator, flankers, target, aim)
	_assign_targets(coordinator, flankers, target, attack)
	plan.add_task(aim)
	plan.add_task(attack)

static func _build_defend(plan: SquadCommandPlan, coordinator: SquadCoordinator, members: Array[SquadMember], target: Node2D) -> void:
	coordinator._ensure_ambush_cover_assignments(target)
	var occupy := SquadTask.new().configure(&"defend_cover", SquadTask.Type.OCCUPY_COVER, _member_ids(members))
	occupy.target = target
	var attack := SquadTask.new().configure(&"defend_fire", SquadTask.Type.NEUTRALIZE_TARGET, _member_ids(members))
	attack.depends_on = [&"defend_cover"]
	for member in members:
		var member_id := String(member.actor.name)
		var cover := coordinator.get_ambush_cover_for(member)
		occupy.member_covers[member_id] = cover
		occupy.member_positions[member_id] = _reserve_cover_destination(cover, member.actor, target)
	_assign_targets(coordinator, members, target, attack)
	plan.add_task(occupy)
	plan.add_task(attack)

static func _build_assault(plan: SquadCommandPlan, coordinator: SquadCoordinator, members: Array[SquadMember], target: Node2D) -> void:
	var move := SquadTask.new().configure(&"assault_move", SquadTask.Type.MOVE_TO_ZONE, _member_ids(members))
	var attack := SquadTask.new().configure(&"assault_fire", SquadTask.Type.NEUTRALIZE_TARGET, _member_ids(members))
	attack.depends_on = [&"assault_move"]
	var center := coordinator._get_squad_center()
	var direction := (target.global_position - center).normalized() if is_instance_valid(target) else Vector2.RIGHT
	for index in members.size():
		move.member_positions[String(members[index].actor.name)] = target.global_position - direction * 260.0 + Vector2(0.0, (index - members.size() / 2.0) * 55.0)
	_assign_targets(coordinator, members, target, attack)
	plan.add_task(move)
	plan.add_task(attack)

static func _build_retreat(plan: SquadCommandPlan, coordinator: SquadCoordinator, members: Array[SquadMember], target: Node2D) -> void:
	var retreat := SquadTask.new().configure(&"withdraw", SquadTask.Type.WITHDRAW_TO_ZONE, _member_ids(members))
	var center := coordinator._get_squad_center()
	var away := (center - target.global_position).normalized() if is_instance_valid(target) else Vector2.LEFT
	for index in members.size():
		retreat.member_positions[String(members[index].actor.name)] = members[index].actor.global_position + away * 520.0 + Vector2(0.0, (index - members.size() / 2.0) * 48.0)
	plan.add_task(retreat)

static func _build_guard(plan: SquadCommandPlan, coordinator: SquadCoordinator, members: Array[SquadMember]) -> void:
	var guard := SquadTask.new().configure(&"perimeter_guard", SquadTask.Type.GUARD_AREA, _member_ids(members))
	guard.zone_id = &"PERIMETER"
	var center := coordinator._get_squad_center()
	var radius := 230.0
	for index in members.size():
		var angle := TAU * float(index) / float(maxi(1, members.size()))
		var member_id := String(members[index].actor.name)
		guard.member_positions[member_id] = center + Vector2.from_angle(angle) * radius
	plan.add_task(guard)

static func _assign_targets(coordinator: SquadCoordinator, members: Array[SquadMember], fallback: Node2D, task: SquadTask) -> void:
	var targets := coordinator._collect_known_hostile_targets()
	if targets.is_empty() and is_instance_valid(fallback):
		targets.append(fallback)
	for index in members.size():
		if not targets.is_empty():
			task.member_targets[String(members[index].actor.name)] = targets[index % targets.size()]

static func _valid_members(coordinator: SquadCoordinator) -> Array[SquadMember]:
	var result: Array[SquadMember] = []
	for member in coordinator.members:
		if is_instance_valid(member) and is_instance_valid(member.actor) and member.actor.is_combat_alive():
			result.append(member)
	return result

static func _member_ids(members: Array[SquadMember]) -> PackedStringArray:
	var result := PackedStringArray()
	for member in members:
		result.append(String(member.actor.name))
	return result

static func _mobility_score(member: SquadMember) -> int:
	match member.actor.get_combat_role() as SquadCombatRole.Type:
		SquadCombatRole.Type.PISTOL_SCOUT:
			return 100
		SquadCombatRole.Type.SHOTGUNNER:
			return 90
		SquadCombatRole.Type.MELEE:
			return 85
		SquadCombatRole.Type.RIFLEMAN:
			return 70
		SquadCombatRole.Type.MARKSMAN:
			return 30
	return 10

static func _reserve_cover_destination(cover: Node, actor: Node2D, threat: Node2D) -> Vector2:
	if not is_instance_valid(cover) or not cover is Node2D:
		return actor.global_position
	if cover.has_method("reserve_cover_against") and is_instance_valid(threat):
		var slot := cover.reserve_cover_against(actor, threat.global_position) as Marker2D
		if is_instance_valid(slot):
			return slot.global_position
	return (cover as Node2D).global_position
