extends RefCounted
class_name SquadPlanCompiler3D

static func mission_move(plan_id: StringName, member_ids: PackedStringArray, destination: Vector3, belief_version: int, returning := false) -> SquadCommandPlan3D:
	var intent := &"RETURN_TO_ORIGIN" if returning else &"MOVE_TO_OBJECTIVE"
	var plan := SquadCommandPlan3D.new().configure(plan_id, intent, "MISSION", "Move to configured mission area", belief_version)
	var task_type := SquadTask3D.Type.RETURN_TO_ORIGIN if returning else SquadTask3D.Type.MOVE_TO_OBJECTIVE
	var task := SquadTask3D.new().configure(&"mission_move", task_type, member_ids)
	task.target_position = destination
	task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	return plan.add_task(task)

static func hold_objective(plan_id: StringName, member_ids: PackedStringArray, destination: Vector3, belief_version: int) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"HOLD_OBJECTIVE", "MISSION", "Hold the configured mission area", belief_version)
	var task := SquadTask3D.new().configure(&"hold_objective", SquadTask3D.Type.HOLD_OBJECTIVE, member_ids)
	task.target_position = destination
	task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_FREE
	return plan.add_task(task)

static func contact_cover(plan_id: StringName, member_ids: PackedStringArray, contact: CombatContact3D, belief_version: int) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"CONTACT_COVER", "FAST_RULE", "Immediate cover after confirmed contact", belief_version)
	var task := SquadTask3D.new().configure(&"contact_cover", SquadTask3D.Type.TAKE_COVER, member_ids)
	task.contact_id = contact.contact_id
	task.target_position = contact.last_known_position
	task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	return plan.add_task(task)

static func defensive_fire(plan_id: StringName, member_ids: PackedStringArray, contacts: Array[CombatContact3D], belief_version: int) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"DEFEND_CONTACT", "UTILITY", "Defend the mission area from cover", belief_version)
	var task := SquadTask3D.new().configure(&"defensive_fire", SquadTask3D.Type.ATTACK_CONTACT, member_ids)
	task.persistent = true
	if contacts.is_empty():
		return plan
	task.contact_id = contacts[0].contact_id
	task.target_position = contacts[0].last_known_position
	for index in member_ids.size():
		task.member_contact_ids[StringName(member_ids[index])] = contacts[index % contacts.size()].contact_id
	return plan.add_task(task)

static func recon_split(
		plan_id: StringName,
		suppressor_ids: PackedStringArray,
		recon_assignments: Array[Dictionary],
		contact: CombatContact3D,
		belief_version: int
) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"RECON_SPLIT", "UTILITY", "Probe unknown routes while a base of fire remains", belief_version)
	if not suppressor_ids.is_empty():
		var suppress := SquadTask3D.new().configure(&"recon_base_fire", SquadTask3D.Type.SUPPRESS_CONTACT, suppressor_ids)
		suppress.contact_id = contact.contact_id
		suppress.target_position = contact.last_known_position
		suppress.duration = 30.0
		plan.add_task(suppress)
	for index in recon_assignments.size():
		var assignment: Dictionary = recon_assignments[index]
		var task := SquadTask3D.new().configure(
			StringName("recon_%d" % index),
			SquadTask3D.Type.RECON_ZONE,
			PackedStringArray([String(assignment.get("member_id", ""))])
		)
		task.zone_id = StringName(assignment.get("zone_id", ""))
		task.target_position = assignment.get("position", Vector3.ZERO) as Vector3
		task.route.assign(assignment.get("route", []))
		task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
		plan.add_task(task)
	return plan

static func suppress_and_flank(
		plan_id: StringName,
		suppressor_ids: PackedStringArray,
		flanker_ids: PackedStringArray,
		zone: TacticalZone3D,
		contact: CombatContact3D,
		belief_version: int
) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"SUPPRESS_AND_FLANK", "UTILITY", "Use the best observed route for a synchronized flank", belief_version)
	var suppress := SquadTask3D.new().configure(&"base_of_fire", SquadTask3D.Type.SUPPRESS_CONTACT, suppressor_ids)
	suppress.contact_id = contact.contact_id
	suppress.target_position = contact.last_known_position
	suppress.duration = 30.0
	var flank := SquadTask3D.new().configure(&"flank_move", SquadTask3D.Type.FLANK_ZONE, flanker_ids)
	flank.zone_id = zone.zone_id
	flank.target_position = zone.get_observation_point(contact.last_known_position)
	flank.route = zone.get_recon_route(contact.last_known_position)
	flank.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
	var attack := SquadTask3D.new().configure(&"synchronized_attack", SquadTask3D.Type.ATTACK_CONTACT, flanker_ids)
	attack.depends_on = [&"base_of_fire", &"flank_move"]
	attack.contact_id = contact.contact_id
	attack.target_position = contact.last_known_position
	plan.add_task(suppress)
	plan.add_task(flank)
	plan.add_task(attack)
	return plan
