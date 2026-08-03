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

static func mission_cover_advance(plan_id: StringName, member_ids: PackedStringArray, destination: Vector3, belief_version: int) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(
		plan_id, &"MISSION_COVER_ADVANCE", "MISSION", "Approach the objective through protected observation positions", belief_version
	)
	var task := SquadTask3D.new().configure(&"mission_cover_advance", SquadTask3D.Type.TAKE_COVER, member_ids)
	task.target_position = destination
	task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	task.advance_toward_objective = true
	return plan.add_task(task)

static func hold_objective(plan_id: StringName, member_ids: PackedStringArray, destination: Vector3, belief_version: int) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"HOLD_OBJECTIVE", "MISSION", "Hold the configured mission area", belief_version)
	var task := SquadTask3D.new().configure(&"hold_objective", SquadTask3D.Type.HOLD_OBJECTIVE, member_ids)
	task.target_position = destination
	task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_FREE
	task.prefer_defensive_structures = true
	return plan.add_task(task)

static func contact_cover(plan_id: StringName, member_ids: PackedStringArray, contact: CombatContact3D, belief_version: int, prefer_structures := false) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"CONTACT_COVER", "FAST_RULE", "Immediate cover after confirmed contact", belief_version)
	var task := SquadTask3D.new().configure(&"contact_cover", SquadTask3D.Type.TAKE_COVER, member_ids)
	task.contact_id = contact.contact_id
	task.target_position = contact.last_known_position
	task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	task.prefer_defensive_structures = prefer_structures
	return plan.add_task(task)

static func recover_in_cover(plan_id: StringName, member_ids: PackedStringArray, contact: CombatContact3D, belief_version: int, prefer_structures := false) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"RECOVER_IN_COVER", "FAST_RULE", "Break exposure and recover from incoming fire", belief_version)
	var cover := SquadTask3D.new().configure(&"recover_cover", SquadTask3D.Type.TAKE_COVER, member_ids)
	cover.contact_id = contact.contact_id
	cover.target_position = contact.last_known_position
	cover.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
	cover.prefer_defensive_structures = prefer_structures
	var recover := SquadTask3D.new().configure(&"recover_pause", SquadTask3D.Type.RECOVER_IN_COVER, member_ids)
	recover.depends_on = [&"recover_cover"]
	recover.duration = 2.4
	recover.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
	recover.prefer_defensive_structures = prefer_structures
	plan.add_task(cover)
	return plan.add_task(recover)

static func defense_option(
		plan_id: StringName,
		member_ids: PackedStringArray,
		contacts: Array[CombatContact3D],
		belief_version: int,
		prefer_structures := true
) -> SquadCommandPlan3D:
	if contacts.is_empty():
		return null
	var plan := SquadCommandPlan3D.new().configure(
		plan_id, &"DEFEND_CONTACT", "TACTICAL_OPTION", "Occupy protected positions and defend assigned sectors", belief_version
	)
	var cover := SquadTask3D.new().configure(&"defense_positions", SquadTask3D.Type.TAKE_COVER, member_ids)
	cover.minimum_success_count = 1
	cover.contact_id = contacts[0].contact_id
	cover.target_position = contacts[0].last_known_position
	cover.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	cover.prefer_defensive_structures = prefer_structures
	var fire := SquadTask3D.new().configure(&"defensive_fire", SquadTask3D.Type.ATTACK_CONTACT, member_ids)
	fire.depends_on = [&"defense_positions"]
	fire.successful_members_from = &"defense_positions"
	fire.persistent = true
	fire.minimum_success_count = 1
	fire.contact_id = contacts[0].contact_id
	fire.target_position = contacts[0].last_known_position
	fire.prefer_defensive_structures = prefer_structures
	for index in member_ids.size():
		fire.member_contact_ids[StringName(member_ids[index])] = contacts[index % contacts.size()].contact_id
	plan.add_task(cover)
	return plan.add_task(fire)

static func direct_assault_option(
		plan_id: StringName,
		member_ids: PackedStringArray,
		contact: CombatContact3D,
		belief_version: int
) -> SquadCommandPlan3D:
	if contact == null:
		return null
	var plan := SquadCommandPlan3D.new().configure(
		plan_id, &"DIRECT_ASSAULT", "TACTICAL_OPTION", "Advance through the least exposed approach and assault", belief_version
	)
	var approach := SquadTask3D.new().configure(&"assault_approach", SquadTask3D.Type.TAKE_COVER, member_ids)
	approach.minimum_success_count = 1
	approach.contact_id = contact.contact_id
	approach.target_position = contact.last_known_position
	approach.advance_toward_objective = true
	approach.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	var attack := SquadTask3D.new().configure(&"direct_assault", SquadTask3D.Type.ATTACK_CONTACT, member_ids)
	attack.depends_on = [&"assault_approach"]
	attack.successful_members_from = &"assault_approach"
	attack.minimum_success_count = 1
	attack.contact_id = contact.contact_id
	attack.target_position = contact.last_known_position
	plan.add_task(approach)
	return plan.add_task(attack)

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
		suppress.duration = 6.0
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
	suppress.minimum_success_count = 1
	suppress.contact_id = contact.contact_id
	suppress.target_position = contact.last_known_position
	suppress.duration = 8.0
	var flank := SquadTask3D.new().configure(&"flank_move", SquadTask3D.Type.FLANK_ZONE, flanker_ids)
	flank.minimum_success_count = 1
	flank.zone_id = zone.zone_id
	flank.target_position = zone.get_observation_point(contact.last_known_position)
	flank.route = zone.get_recon_route(contact.last_known_position)
	flank.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
	var attack := SquadTask3D.new().configure(&"synchronized_attack", SquadTask3D.Type.ATTACK_CONTACT, flanker_ids)
	attack.persistent = true
	attack.minimum_success_count = 1
	attack.depends_on = [&"base_of_fire", &"flank_move"]
	attack.successful_members_from = &"flank_move"
	attack.contact_id = contact.contact_id
	attack.target_position = contact.last_known_position
	plan.add_task(suppress)
	plan.add_task(flank)
	plan.add_task(attack)
	return plan
