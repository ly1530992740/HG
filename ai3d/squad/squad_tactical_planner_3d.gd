extends RefCounted
class_name SquadTacticalPlanner3D

func build_candidates(
		belief: SquadBeliefState3D,
		zones: Array[TacticalZone3D],
		members: Array[Soldier3D],
		mission: SquadMissionController3D,
		contact_cover_complete: bool,
		recon_complete: bool,
		current_intent: StringName,
		contact_elapsed: float
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var contact := belief.get_best_contact()
	if contact == null:
		var mission_kind := "HOLD_OBJECTIVE" if mission.is_defense_locked() else "MISSION_MOVE"
		candidates.append({"id": mission_kind, "kind": mission_kind, "utility": 100.0})
		return candidates
	if not contact_cover_complete:
		candidates.append({"id": "CONTACT_COVER", "kind": "CONTACT_COVER", "utility": 200.0})
		return candidates
	if mission.is_defense_locked():
		candidates.append({"id": "DEFEND_CONTACT", "kind": "DEFEND_CONTACT", "utility": 120.0})
		return candidates

	var suppression_ratio := _suppression_ratio(members)
	var heavy_contact := belief.get_living_contacts().any(func(item: CombatContact3D): return item.estimated_role == Soldier3D.CombatRole.MACHINE_GUNNER)
	var recon_zones := zones.filter(func(zone: TacticalZone3D): return zone.recon_enabled)
	var unobserved := recon_zones.filter(func(zone: TacticalZone3D): return not belief.is_zone_observed(zone.zone_id))
	var observed := recon_zones.filter(func(zone: TacticalZone3D): return belief.is_zone_observed(zone.zone_id))
	candidates.append({"id": "DEFEND_CONTACT", "kind": "DEFEND_CONTACT", "utility": 35.0 - suppression_ratio * 12.0})
	if not recon_complete and not unobserved.is_empty() and members.size() >= 3 \
		and (suppression_ratio >= 0.08 or heavy_contact or contact_elapsed >= 2.0):
		candidates.append({
			"id": "RECON_SPLIT",
			"kind": "RECON_SPLIT",
			"utility": 72.0 + suppression_ratio * 25.0 + float(unobserved.size()) * 4.0,
			"zones": unobserved,
		})
	if recon_complete and not observed.is_empty() and members.size() >= 3:
		for zone_value in observed:
			var zone := zone_value as TacticalZone3D
			var utility: float = zone.get_utility(belief.get_contacts_in_zone(zone).size(), belief.get_zone_observation(zone.zone_id))
			candidates.append({
				"id": "FLANK_%s" % String(zone.zone_id).to_upper(),
				"kind": "SUPPRESS_AND_FLANK",
				"zone": zone,
				"utility": 65.0 + utility * 6.0,
			})
	if current_intent == &"SUPPRESS_AND_FLANK":
		for candidate in candidates:
			if String(candidate.get("kind", "")) == "SUPPRESS_AND_FLANK":
				candidate["utility"] = float(candidate.get("utility", 0.0)) + 8.0
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("utility", 0.0)) > float(b.get("utility", 0.0)))
	return candidates

func compile_candidate(
		candidate: Dictionary,
		belief: SquadBeliefState3D,
		members: Array[Soldier3D],
		mission: SquadMissionController3D,
		plan_sequence: int
) -> SquadCommandPlan3D:
	var member_ids := _member_ids(members)
	var plan_id := StringName("plan_%d_%s" % [plan_sequence, String(candidate.get("id", "unknown"))])
	var kind := String(candidate.get("kind", ""))
	var contact := belief.get_best_contact()
	match kind:
		"MISSION_MOVE":
			return SquadPlanCompiler3D.mission_move(plan_id, member_ids, mission.get_destination(), belief.version, mission.state == SquadMissionController3D.State.RETURNING)
		"HOLD_OBJECTIVE":
			return SquadPlanCompiler3D.hold_objective(plan_id, member_ids, mission.get_destination(), belief.version)
		"CONTACT_COVER":
			return SquadPlanCompiler3D.contact_cover(plan_id, member_ids, contact, belief.version)
		"DEFEND_CONTACT":
			return SquadPlanCompiler3D.defensive_fire(plan_id, member_ids, belief.get_living_contacts(), belief.version)
		"RECON_SPLIT":
			var groups := _split_recon_groups(members, candidate.get("zones", []) as Array, contact.last_known_position)
			return SquadPlanCompiler3D.recon_split(plan_id, groups.suppressors, groups.recon, contact, belief.version)
		"SUPPRESS_AND_FLANK":
			var groups := _split_flank_groups(members)
			return SquadPlanCompiler3D.suppress_and_flank(plan_id, groups.suppressors, groups.flankers, candidate.get("zone") as TacticalZone3D, contact, belief.version)
	return null

func _split_recon_groups(members: Array[Soldier3D], zones: Array, threat_position: Vector3) -> Dictionary:
	var sorted_zones: Array[TacticalZone3D] = []
	for zone_value in zones:
		if zone_value is TacticalZone3D:
			sorted_zones.append(zone_value as TacticalZone3D)
	sorted_zones.sort_custom(func(a: TacticalZone3D, b: TacticalZone3D):
		return _recon_mobility_value(a) > _recon_mobility_value(b)
	)
	var recon: Array[Dictionary] = []
	var used: Dictionary = {}
	var count := mini(sorted_zones.size(), maxi(1, members.size() - 2))
	for index in count:
		var zone := sorted_zones[index]
		var member := _best_recon_member(members, used, zone)
		if member == null:
			continue
		used[member] = true
		recon.append({
			"member_id": String(member.name),
			"zone_id": zone.zone_id,
			"position": zone.get_observation_point(member.global_position),
			"route": zone.get_recon_route(member.global_position),
		})
	var suppressors := PackedStringArray()
	for member in members:
		if not used.has(member):
			suppressors.append(String(member.name))
	return {"suppressors": suppressors, "recon": recon, "threat": threat_position}

func _recon_mobility_value(zone: TacticalZone3D) -> float:
	return zone.concealment * 4.0 + zone.information_value - zone.route_exposure * 2.0

func _best_recon_member(members: Array[Soldier3D], used: Dictionary, zone: TacticalZone3D) -> Soldier3D:
	var best: Soldier3D
	var best_score := -INF
	for member in members:
		if used.has(member):
			continue
		var route := zone.get_recon_route(member.global_position)
		var entry := route[0] if not route.is_empty() else zone.get_observation_point(member.global_position)
		var mobility := _mobility_score(member)
		var score := mobility - member.global_position.distance_to(entry) * 3.0 + zone.concealment * mobility * 0.15
		if score > best_score:
			best = member
			best_score = score
	return best

func _split_flank_groups(members: Array[Soldier3D]) -> Dictionary:
	var sorted: Array[Soldier3D] = members.duplicate()
	sorted.sort_custom(func(a: Soldier3D, b: Soldier3D): return _mobility_score(a) > _mobility_score(b))
	var flank_count := clampi(members.size() / 2, 1, maxi(1, members.size() - 1))
	var flankers := PackedStringArray()
	var suppressors := PackedStringArray()
	for index in sorted.size():
		if index < flank_count:
			flankers.append(String(sorted[index].name))
		else:
			suppressors.append(String(sorted[index].name))
	return {"suppressors": suppressors, "flankers": flankers}

func _member_ids(members: Array[Soldier3D]) -> PackedStringArray:
	var result := PackedStringArray()
	for member in members:
		result.append(String(member.name))
	return result

func _mobility_score(member: Soldier3D) -> float:
	match member.combat_role:
		Soldier3D.CombatRole.SMG:
			return 100.0
		Soldier3D.CombatRole.SHOTGUNNER:
			return 92.0
		Soldier3D.CombatRole.RIFLEMAN:
			return 75.0
		Soldier3D.CombatRole.MARKSMAN:
			return 38.0
		Soldier3D.CombatRole.MACHINE_GUNNER:
			return 20.0
	return 50.0

func _suppression_ratio(members: Array[Soldier3D]) -> float:
	if members.is_empty():
		return 0.0
	var total := 0.0
	for member in members:
		total += member.get_suppression_ratio()
	return total / float(members.size())
