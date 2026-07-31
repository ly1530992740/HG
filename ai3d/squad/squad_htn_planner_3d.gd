extends RefCounted
class_name SquadHtnPlanner3D

var last_selected_method := ""
var last_method_scores: Array[Dictionary] = []

func compile(
		candidate: Dictionary,
		snapshot: SquadDecisionSnapshot3D,
		belief: SquadBeliefState3D,
		zones: Array[TacticalZone3D],
		influence: SquadInfluenceMap3D,
		mission: SquadMissionController3D,
		plan_sequence: int
) -> SquadCommandPlan3D:
	var plan_id := StringName("plan_%d_%s" % [plan_sequence, String(candidate.get("id", "unknown"))])
	var kind := String(candidate.get("kind", ""))
	var contact := belief.get_best_contact()
	last_method_scores = build_methods(candidate, snapshot, zones, influence)
	last_selected_method = String(last_method_scores[0].get("id", "")) if not last_method_scores.is_empty() else ""
	var plan: SquadCommandPlan3D
	match kind:
		"MISSION_MOVE":
			plan = SquadPlanCompiler3D.mission_move(plan_id, snapshot.get_member_ids(), mission.get_destination(), belief.version, mission.state == SquadMissionController3D.State.RETURNING)
		"HOLD_OBJECTIVE":
			plan = SquadPlanCompiler3D.hold_objective(plan_id, snapshot.get_member_ids(), mission.get_destination(), belief.version)
		"CONTACT_COVER":
			plan = SquadPlanCompiler3D.contact_cover(plan_id, snapshot.get_member_ids(), contact, belief.version)
		SquadUtilityEvaluator3D.RECOVER_IN_COVER, SquadUtilityEvaluator3D.CONSOLIDATE:
			plan = SquadPlanCompiler3D.recover_in_cover(plan_id, snapshot.get_member_ids(), contact, belief.version)
		SquadUtilityEvaluator3D.DEFEND_CONTACT, SquadUtilityEvaluator3D.COUNTER_FLANK:
			plan = _compile_defense(plan_id, snapshot, belief, mission, kind)
		SquadUtilityEvaluator3D.RECON_SPLIT:
			plan = _compile_recon(plan_id, snapshot, candidate.get("zones", []) as Array, contact, belief.version)
		SquadUtilityEvaluator3D.SUPPRESS_AND_FLANK:
			plan = _compile_flank(
				plan_id, snapshot, candidate.get("zone") as TacticalZone3D, contact,
				belief.version, last_selected_method, influence
			)
		SquadUtilityEvaluator3D.ESTABLISH_BASE_OF_FIRE, SquadUtilityEvaluator3D.FIX_AND_SUPPRESS:
			plan = _compile_base_of_fire(plan_id, snapshot, contact, belief.version, kind)
		SquadUtilityEvaluator3D.BOUNDING_ADVANCE:
			plan = _compile_bounding_advance(plan_id, snapshot, contact, mission.get_destination(), belief.version)
		SquadUtilityEvaluator3D.DIRECT_ASSAULT:
			plan = _compile_direct_assault(plan_id, snapshot, contact, belief.version)
		SquadUtilityEvaluator3D.AMBUSH:
			plan = _compile_ambush(plan_id, snapshot, belief.get_living_contacts(), belief.version, last_selected_method)
		SquadUtilityEvaluator3D.BREAK_CONTACT:
			plan = _compile_break_contact(plan_id, snapshot, contact, mission.origin_position, belief.version)
		SquadUtilityEvaluator3D.FALLBACK_DEFENSE, SquadUtilityEvaluator3D.REPOSITION:
			plan = _compile_fallback_defense(plan_id, snapshot, contact, mission, belief.version)
		SquadUtilityEvaluator3D.SEARCH_LAST_CONTACT:
			plan = _compile_search(plan_id, snapshot, candidate, zones, contact, belief.version)
	if plan != null:
		plan.source = "HTN:%s" % last_selected_method
		if plan.reason.is_empty():
			plan.reason = String(candidate.get("reason", kind))
	return plan

func build_methods(
		candidate: Dictionary,
		snapshot: SquadDecisionSnapshot3D,
		zones: Array[TacticalZone3D],
		influence: SquadInfluenceMap3D
) -> Array[Dictionary]:
	var methods: Array[Dictionary] = []
	var kind := String(candidate.get("kind", ""))
	match kind:
		SquadUtilityEvaluator3D.SUPPRESS_AND_FLANK:
			var healthy_mg := _members_for_role(snapshot.members, Soldier3D.CombatRole.MACHINE_GUNNER).any(func(member: Dictionary): return _can_support(member))
			if healthy_mg:
				methods.append(_method("MG_BASE_OF_FIRE", 120.0, "Machine gun anchors the base of fire"))
			var rifle_support_count := 0
			for member in snapshot.members:
				rifle_support_count += 1 if _can_support(member) and int(member.get("role", -1)) != Soldier3D.CombatRole.MELEE else 0
			if rifle_support_count >= 2:
				methods.append(_method("DISTRIBUTED_RIFLE_FIRE", 92.0 if not healthy_mg else 74.0, "Two shooters alternate suppression"))
			if snapshot.members.size() == 3:
				methods.append(_method("MINIMAL_TEAM_FLANK", 82.0, "One shooter fixes while two maneuver"))
			if _maneuver_members(snapshot.members).is_empty():
				methods.append(_method("DIRECT_ASSAULT_FALLBACK", 30.0, "No healthy maneuver element remains"))
		SquadUtilityEvaluator3D.AMBUSH:
			var compromised := snapshot.contacts.any(func(contact: Dictionary): return float(contact.get("awareness", 0.5)) >= 0.55) \
				or snapshot.members.any(func(member: Dictionary): return float(member.get("suppression", 0.0)) > 0.15)
			methods.append(_method("COMPROMISED_CONTACT_DRILL" if compromised else "SYNCHRONIZED_VOLLEY", 140.0, "Ambush state determines opening method"))
		SquadUtilityEvaluator3D.DEFEND_CONTACT, SquadUtilityEvaluator3D.COUNTER_FLANK:
			methods.append(_method("MULTI_AXIS_DEFENSE" if _contact_sector_count(snapshot) >= 2 else "SINGLE_AXIS_DEFENSE", 100.0, "Allocate defenders by known contact sector"))
		SquadUtilityEvaluator3D.BOUNDING_ADVANCE, SquadUtilityEvaluator3D.DIRECT_ASSAULT:
			methods.append(_method("TWO_ELEMENT_BOUNDS" if snapshot.members.size() >= 4 else "HASTY_ASSAULT", 100.0, "Team size determines movement method"))
		_:
			methods.append(_method("STANDARD", 100.0, "Standard decomposition"))
	methods.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	return methods

func _compile_defense(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, belief: SquadBeliefState3D, mission: SquadMissionController3D, intent: String) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, StringName(intent), "HTN", "Defend known contact sectors without leaving the mission boundary", belief.version)
	var contacts := belief.get_living_contacts()
	if contacts.is_empty():
		return SquadPlanCompiler3D.hold_objective(plan_id, snapshot.get_member_ids(), mission.get_destination(), belief.version)
	var assignments: Dictionary = {}
	for index in snapshot.members.size():
		var member: Dictionary = snapshot.members[index]
		assignments[StringName(member.get("id", ""))] = contacts[index % contacts.size()].contact_id
	var defend := SquadTask3D.new().configure(&"defensive_fire", SquadTask3D.Type.ATTACK_CONTACT, snapshot.get_member_ids())
	defend.persistent = true
	defend.minimum_success_count = 1
	defend.contact_id = contacts[0].contact_id
	defend.target_position = contacts[0].last_known_position
	defend.member_contact_ids = assignments
	defend.reason = "Cover all reported attack axes"
	return plan.add_task(defend)

func _compile_recon(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, zone_values: Array, contact: CombatContact3D, belief_version: int) -> SquadCommandPlan3D:
	var zones: Array[TacticalZone3D] = []
	for value in zone_values:
		if value is TacticalZone3D:
			zones.append(value)
	var scouts := _maneuver_members(snapshot.members)
	var assignments: Array[Dictionary] = []
	var used: Dictionary = {}
	for zone in zones:
		var scout := _best_member_for_zone(scouts, used, zone)
		if scout.is_empty():
			continue
		used[String(scout.get("id", ""))] = true
		assignments.append({
			"member_id": String(scout.get("id", "")),
			"zone_id": zone.zone_id,
			"position": zone.get_observation_point(scout.get("position", snapshot.squad_center) as Vector3),
			"route": zone.get_recon_route(scout.get("position", snapshot.squad_center) as Vector3),
		})
	var suppressors := PackedStringArray()
	for member in snapshot.members:
		if not used.has(String(member.get("id", ""))):
			suppressors.append(String(member.get("id", "")))
	return SquadPlanCompiler3D.recon_split(plan_id, suppressors, assignments, contact, belief_version)

func _compile_flank(
		plan_id: StringName,
		snapshot: SquadDecisionSnapshot3D,
		zone: TacticalZone3D,
		contact: CombatContact3D,
		belief_version: int,
		method: String,
		influence: SquadInfluenceMap3D
) -> SquadCommandPlan3D:
	if zone == null or contact == null:
		return null
	var support_count := 1
	if method == "MG_BASE_OF_FIRE":
		support_count = 1
	elif method == "DISTRIBUTED_RIFLE_FIRE":
		support_count = mini(2, maxi(1, snapshot.members.size() - 1))
	var maneuver := _maneuver_members(snapshot.members)
	maneuver.sort_custom(func(a: Dictionary, b: Dictionary):
		return _flank_member_score(a, zone, influence) > _flank_member_score(b, zone, influence)
	)
	var support_ids := PackedStringArray()
	var maneuver_ids := PackedStringArray()
	var reserved_support: Dictionary = {}
	if method == "MG_BASE_OF_FIRE":
		for member in _support_members(snapshot.members):
			if int(member.get("role", -1)) == Soldier3D.CombatRole.MACHINE_GUNNER and _can_support(member):
				reserved_support[String(member.get("id", ""))] = true
				break
	var desired_maneuver_count := maxi(1, snapshot.members.size() - support_count)
	for member in maneuver:
		var id := String(member.get("id", ""))
		if not reserved_support.has(id) and maneuver_ids.size() < desired_maneuver_count:
			maneuver_ids.append(id)
	for member in snapshot.members:
		var id := String(member.get("id", ""))
		if id not in maneuver_ids:
			support_ids.append(id)
	if maneuver_ids.is_empty():
		return _compile_direct_assault(plan_id, snapshot, contact, belief_version)
	if support_ids.is_empty():
		support_ids.append(maneuver_ids[0])
		maneuver_ids.remove_at(0)
	if maneuver_ids.is_empty():
		return _compile_direct_assault(plan_id, snapshot, contact, belief_version)
	return SquadPlanCompiler3D.suppress_and_flank(plan_id, support_ids, maneuver_ids, zone, contact, belief_version)

func _compile_base_of_fire(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, contact: CombatContact3D, belief_version: int, intent: String) -> SquadCommandPlan3D:
	if contact == null:
		return null
	var support := _support_members(snapshot.members)
	var count := mini(maxi(1, snapshot.members.size() / 2), support.size())
	var ids := PackedStringArray()
	for index in count:
		ids.append(String(support[index].get("id", "")))
	var plan := SquadCommandPlan3D.new().configure(plan_id, StringName(intent), "HTN", "Establish a protected base of fire", belief_version)
	var task := SquadTask3D.new().configure(&"base_of_fire", SquadTask3D.Type.SUPPRESS_CONTACT, ids)
	task.persistent = false
	task.contact_id = contact.contact_id
	task.target_position = contact.last_known_position
	task.duration = 6.0
	return plan.add_task(task)

func _compile_bounding_advance(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, contact: CombatContact3D, destination: Vector3, belief_version: int) -> SquadCommandPlan3D:
	if contact == null:
		return null
	var support := _support_members(snapshot.members)
	var maneuver := _maneuver_members(snapshot.members)
	var support_count := maxi(1, snapshot.members.size() / 2)
	var support_ids := PackedStringArray()
	var move_ids := PackedStringArray()
	var maneuver_eligible := {}
	for member in maneuver:
		maneuver_eligible[String(member.get("id", ""))] = true
	for member in support:
		var id := String(member.get("id", ""))
		if not maneuver_eligible.has(id) or support_ids.size() < support_count:
			support_ids.append(id)
		else:
			move_ids.append(id)
	if move_ids.is_empty() and maneuver.size() > 1:
		var released_id := String(maneuver[0].get("id", ""))
		support_ids.remove_at(support_ids.find(released_id))
		move_ids.append(released_id)
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"BOUNDING_ADVANCE", "HTN", "Alternate a base of fire with a maneuver element", belief_version)
	var fire := SquadTask3D.new().configure(&"bound_support", SquadTask3D.Type.SUPPRESS_CONTACT, support_ids)
	fire.contact_id = contact.contact_id
	fire.target_position = contact.last_known_position
	fire.duration = 5.0
	var move := SquadTask3D.new().configure(&"bound_move", SquadTask3D.Type.MOVE_TO_OBJECTIVE, move_ids)
	move.depends_on = [&"bound_support"]
	var advance := destination - snapshot.squad_center
	advance.y = 0.0
	move.target_position = destination if advance.length() <= 5.0 \
		else snapshot.squad_center + advance.normalized() * 5.0
	move.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	plan.add_task(fire)
	return plan.add_task(move)

func _compile_direct_assault(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, contact: CombatContact3D, belief_version: int) -> SquadCommandPlan3D:
	if contact == null:
		return null
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"DIRECT_ASSAULT", "HTN", "No flank is usable; assault the known contact directly", belief_version)
	var attack := SquadTask3D.new().configure(&"direct_assault", SquadTask3D.Type.ATTACK_CONTACT, snapshot.get_member_ids())
	attack.contact_id = contact.contact_id
	attack.target_position = contact.last_known_position
	return plan.add_task(attack)

func _compile_ambush(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, contacts: Array[CombatContact3D], belief_version: int, method: String) -> SquadCommandPlan3D:
	if contacts.is_empty():
		return null
	if method == "COMPROMISED_CONTACT_DRILL":
		return SquadPlanCompiler3D.contact_cover(plan_id, snapshot.get_member_ids(), contacts[0], belief_version)
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"AMBUSH", "HTN", "Assign targets, settle aim, then open fire together", belief_version)
	var aim := SquadTask3D.new().configure(&"ambush_aim", SquadTask3D.Type.AIM_CONTACT, snapshot.get_member_ids())
	aim.contact_id = contacts[0].contact_id
	aim.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
	var attack := SquadTask3D.new().configure(&"ambush_volley", SquadTask3D.Type.ATTACK_CONTACT, snapshot.get_member_ids())
	attack.depends_on = [&"ambush_aim"]
	attack.contact_id = contacts[0].contact_id
	for index in snapshot.members.size():
		var member_id := StringName(snapshot.members[index].get("id", ""))
		var assigned := contacts[index % contacts.size()]
		aim.member_contact_ids[member_id] = assigned.contact_id
		attack.member_contact_ids[member_id] = assigned.contact_id
	plan.add_task(aim)
	return plan.add_task(attack)

func _compile_break_contact(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, contact: CombatContact3D, fallback: Vector3, belief_version: int) -> SquadCommandPlan3D:
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"BREAK_CONTACT", "HTN", "Withdraw by bounds toward the mission fallback", belief_version)
	var ids := snapshot.get_member_ids()
	var task := SquadTask3D.new().configure(&"break_contact", SquadTask3D.Type.RETURN_TO_ORIGIN, ids)
	task.target_position = fallback
	task.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	if contact != null:
		task.contact_id = contact.contact_id
	return plan.add_task(task)

func _compile_fallback_defense(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, contact: CombatContact3D, mission: SquadMissionController3D, belief_version: int) -> SquadCommandPlan3D:
	if contact == null:
		return SquadPlanCompiler3D.hold_objective(plan_id, snapshot.get_member_ids(), mission.target_position, belief_version)
	var ids := snapshot.get_member_ids()
	var plan := SquadCommandPlan3D.new().configure(
		plan_id, &"FALLBACK_DEFENSE", "HTN", "Compress into protected positions inside the mission boundary", belief_version
	)
	var cover := SquadTask3D.new().configure(&"fallback_cover", SquadTask3D.Type.TAKE_COVER, ids)
	cover.contact_id = contact.contact_id
	cover.target_position = contact.last_known_position
	cover.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
	var defend := SquadTask3D.new().configure(&"fallback_defense", SquadTask3D.Type.ATTACK_CONTACT, ids)
	defend.depends_on = [&"fallback_cover"]
	defend.persistent = true
	defend.minimum_success_count = 1
	defend.contact_id = contact.contact_id
	defend.target_position = contact.last_known_position
	defend.rules_of_engagement = SquadDirective3D.RulesOfEngagement.WEAPONS_FREE
	plan.add_task(cover)
	return plan.add_task(defend)

func _compile_search(plan_id: StringName, snapshot: SquadDecisionSnapshot3D, candidate: Dictionary, zones: Array[TacticalZone3D], contact: CombatContact3D, belief_version: int) -> SquadCommandPlan3D:
	var destination := contact.last_known_position if contact != null else snapshot.mission_target
	var plan := SquadCommandPlan3D.new().configure(plan_id, &"SEARCH_LAST_CONTACT", "HTN", "Search the last reliable contact sector", belief_version)
	var move := SquadTask3D.new().configure(&"search_move", SquadTask3D.Type.MOVE_TO_OBJECTIVE, snapshot.get_member_ids())
	move.target_position = destination
	move.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	var observe := SquadTask3D.new().configure(&"search_observe", SquadTask3D.Type.HOLD_OBJECTIVE, snapshot.get_member_ids())
	observe.depends_on = [&"search_move"]
	observe.target_position = destination
	observe.rules_of_engagement = SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	observe.minimum_success_count = 1
	plan.add_task(move)
	return plan.add_task(observe)

func _support_members(members: Array[Dictionary]) -> Array[Dictionary]:
	var result := members.duplicate()
	result.sort_custom(func(a: Dictionary, b: Dictionary): return _support_score(a) > _support_score(b))
	return result

func _maneuver_members(members: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member in members:
		if not bool(member.get("pinned", false)) and float(member.get("health", 0.0)) >= 0.52 and float(member.get("mobility", 0.0)) >= 0.42:
			result.append(member)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return _maneuver_score(a) > _maneuver_score(b))
	return result

func _support_score(member: Dictionary) -> float:
	var role := int(member.get("role", -1))
	var role_score := 0.0
	match role:
		Soldier3D.CombatRole.MACHINE_GUNNER: role_score = 120.0
		Soldier3D.CombatRole.MARKSMAN: role_score = 95.0
		Soldier3D.CombatRole.RIFLEMAN: role_score = 70.0
		Soldier3D.CombatRole.SMG: role_score = 48.0
		Soldier3D.CombatRole.SHOTGUNNER: role_score = 38.0
		_: role_score = 15.0
	return role_score + float(member.get("health", 0.0)) * 20.0 + float(member.get("ammo", 0.0)) * 20.0 \
		- float(member.get("suppression", 0.0)) * 55.0 - (80.0 if bool(member.get("pinned", false)) else 0.0)

func _maneuver_score(member: Dictionary) -> float:
	var role := int(member.get("role", -1))
	var role_score := 0.0
	match role:
		Soldier3D.CombatRole.SMG: role_score = 110.0
		Soldier3D.CombatRole.SHOTGUNNER: role_score = 100.0
		Soldier3D.CombatRole.RIFLEMAN: role_score = 78.0
		Soldier3D.CombatRole.MARKSMAN: role_score = 42.0
		Soldier3D.CombatRole.MACHINE_GUNNER: role_score = 25.0
		_: role_score = 55.0
	return role_score + float(member.get("health", 0.0)) * 45.0 + float(member.get("mobility", 0.0)) * 38.0 \
		- float(member.get("suppression", 0.0)) * 65.0

func _flank_member_score(member: Dictionary, zone: TacticalZone3D, influence: SquadInfluenceMap3D) -> float:
	var position := member.get("position", Vector3.ZERO) as Vector3
	var route := zone.get_recon_route(position)
	var entry := route[0] if not route.is_empty() else zone.get_observation_point(position)
	var access_route: Array[Vector3] = [position, entry]
	var access_score := influence.score_route(access_route) if influence != null else 0.0
	return _maneuver_score(member) - position.distance_to(entry) * 6.0 \
		+ clampf(access_score, -100.0, 100.0) * 0.15

func _can_support(member: Dictionary) -> bool:
	return not bool(member.get("pinned", false)) and bool(member.get("loaded", true)) \
		and float(member.get("ammo", 0.0)) > 0.08 and float(member.get("health", 0.0)) > 0.2

func _members_for_role(members: Array[Dictionary], role: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member in members:
		if int(member.get("role", -1)) == role:
			result.append(member)
	return result

func _best_member_for_zone(members: Array[Dictionary], used: Dictionary, zone: TacticalZone3D) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for member in members:
		var id := String(member.get("id", ""))
		if used.has(id):
			continue
		var position := member.get("position", Vector3.ZERO) as Vector3
		var score := _maneuver_score(member) - position.distance_to(zone.get_observation_point(position)) * 2.5
		if score > best_score:
			best = member
			best_score = score
	return best

func _contact_sector_count(snapshot: SquadDecisionSnapshot3D) -> int:
	var sectors: Dictionary = {}
	for contact in snapshot.contacts:
		var direction := (contact.get("position", snapshot.squad_center) as Vector3) - snapshot.squad_center
		if direction.length_squared() > 0.01:
			sectors[roundi(atan2(direction.z, direction.x) / (PI * 0.5))] = true
	return sectors.size()

func _method(id: String, score: float, reason: String) -> Dictionary:
	return {"id": id, "score": score, "reason": reason}
