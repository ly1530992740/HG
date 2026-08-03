extends RefCounted
class_name SquadUtilityEvaluator3D

const HOLD_OBJECTIVE := "HOLD_OBJECTIVE"
const DEFEND_CONTACT := "DEFEND_CONTACT"
const RECON_SPLIT := "RECON_SPLIT"
const SUPPRESS_AND_FLANK := "SUPPRESS_AND_FLANK"
const ESTABLISH_BASE_OF_FIRE := "ESTABLISH_BASE_OF_FIRE"
const FIX_AND_SUPPRESS := "FIX_AND_SUPPRESS"
const BOUNDING_ADVANCE := "BOUNDING_ADVANCE"
const DIRECT_ASSAULT := "DIRECT_ASSAULT"
const AMBUSH := "AMBUSH"
const COUNTER_FLANK := "COUNTER_FLANK"
const REPOSITION := "REPOSITION"
const RECOVER_IN_COVER := "RECOVER_IN_COVER"
const BREAK_CONTACT := "BREAK_CONTACT"
const FALLBACK_DEFENSE := "FALLBACK_DEFENSE"
const SEARCH_LAST_CONTACT := "SEARCH_LAST_CONTACT"
const CONSOLIDATE := "CONSOLIDATE"
const MISSION_COVER_ADVANCE := "MISSION_COVER_ADVANCE"

var _route_planner := SquadHeatmapRoutePlanner3D.new()

func build_candidates(
		snapshot: SquadDecisionSnapshot3D,
		belief: SquadBeliefState3D,
		zones: Array[TacticalZone3D],
		influence: SquadInfluenceMap3D,
		contact_cover_complete: bool,
		recon_complete: bool,
		contact_elapsed: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if snapshot.enemy_count <= 0:
		var mission_kind := HOLD_OBJECTIVE if snapshot.defense_locked else "MISSION_MOVE"
		if snapshot.mission_type == SquadMissionController3D.MissionType.CAPTURE_AND_HOLD \
				and not snapshot.objective_clear_confirmed and not snapshot.defense_locked:
			mission_kind = MISSION_COVER_ADVANCE
		result.append(_candidate(mission_kind, mission_kind, 100.0,
			"Advance through cover until the objective is observed clear" if mission_kind == MISSION_COVER_ADVANCE \
			else "No confirmed contact; continue mission"))
		return result
	if not contact_cover_complete:
		result.append(_candidate("CONTACT_COVER", "CONTACT_COVER", 240.0, "Immediate squad contact drill"))
		return result

	var fire_state := int(snapshot.fire_assessment.get("state", FireSuperiorityAssessment3D.State.CONTESTED))
	var pressure_ratio := float(snapshot.fire_assessment.get("pressure_ratio", 1.0))
	var suppression_ratio := float(snapshot.fire_assessment.get("suppression_ratio", 0.0))
	var visible_count := snapshot.visible_contact_count()
	var defense_locked := snapshot.defense_locked
	var power_ratio := snapshot.get_power_ratio()
	var machine_guns := snapshot.count_role(Soldier3D.CombatRole.MACHINE_GUNNER)
	var observed_zones := zones.filter(func(zone: TacticalZone3D): return zone.recon_enabled and belief.is_zone_observed(zone.zone_id))
	var unobserved_zones := zones.filter(func(zone: TacticalZone3D): return zone.recon_enabled and not belief.is_zone_observed(zone.zone_id))
	var contact_sector_count := _contact_sector_count(snapshot)

	if defense_locked:
		result.append(_defense_option(
			snapshot, belief, influence,
			115.0 + minf(35.0, float(visible_count) * 7.0) + maxf(0.0, 1.0 - power_ratio) * 45.0,
			"Defend the configured mission area"
		))
		if contact_sector_count >= 2:
			result.append(_defense_option(
				snapshot, belief, influence, 170.0 + float(contact_sector_count) * 10.0,
				"Hostiles reported from multiple sectors", COUNTER_FLANK
			))
		if fire_state in [FireSuperiorityAssessment3D.State.LOSING, FireSuperiorityAssessment3D.State.PINNED]:
			result.append(_candidate(FALLBACK_DEFENSE, FALLBACK_DEFENSE, 150.0 + suppression_ratio * 55.0, "Compress into an inner defensive perimeter"))
		if suppression_ratio >= 0.24:
			result.append(_candidate(RECOVER_IN_COVER, RECOVER_IN_COVER, 138.0 + suppression_ratio * 70.0, "Recover protected shooters before resuming fire"))
		return _sort(result)

	if visible_count > 0 or suppression_ratio >= 0.12 \
			or fire_state in [FireSuperiorityAssessment3D.State.LOSING, FireSuperiorityAssessment3D.State.PINNED]:
		result.append(_defense_option(
			snapshot, belief, influence,
			48.0 + maxf(0.0, 1.0 - pressure_ratio) * 20.0 + suppression_ratio * 35.0 \
				+ maxf(0.0, 1.0 - power_ratio) * 28.0,
			"Hold current cover only while contact or incoming fire remains"
		))
	if machine_guns > 0 and visible_count > 0:
		result.append(_candidate(ESTABLISH_BASE_OF_FIRE, ESTABLISH_BASE_OF_FIRE, 72.0 + float(machine_guns) * 14.0 + suppression_ratio * 20.0, "Use support weapons to establish fire superiority"))
	if visible_count > 0:
		result.append(_candidate(FIX_AND_SUPPRESS, FIX_AND_SUPPRESS, 62.0 + float(visible_count) * 5.0 + suppression_ratio * 18.0, "Fix known contacts while the squad prepares its next move"))
	var maneuver_available := snapshot.members.any(func(member: Dictionary):
		return not bool(member.get("pinned", false)) and float(member.get("health", 0.0)) >= 0.52 \
			and float(member.get("mobility", 0.0)) >= 0.42
	)
	if not recon_complete and not unobserved_zones.is_empty() and snapshot.members.size() >= 3 and maneuver_available \
			and (suppression_ratio >= 0.08 or machine_guns > 0 or contact_elapsed >= 2.0):
		var probe_zones := unobserved_zones.duplicate()
		probe_zones.sort_custom(func(a: TacticalZone3D, b: TacticalZone3D):
			return _zone_access_score(influence, a, snapshot.squad_center) \
				> _zone_access_score(influence, b, snapshot.squad_center)
		)
		var safest_probe := probe_zones[0] as TacticalZone3D
		var safest_route_score := _zone_access_score(influence, safest_probe, snapshot.squad_center)
		var probe_utility := 82.0 + suppression_ratio * 28.0 + float(unobserved_zones.size()) * 5.0 \
			+ clampf(safest_route_score, -100.0, 100.0) * 0.12
		var candidate := _candidate(RECON_SPLIT, RECON_SPLIT, probe_utility, "Probe the safest unknown route while a base of fire remains")
		# Probe one route at a time. Once it is observed, Utility can commit to it or test the next route.
		candidate["zones"] = [safest_probe]
		candidate["route_score"] = safest_route_score
		result.append(candidate)
	if not observed_zones.is_empty() and snapshot.members.size() >= 3 \
			and (recon_complete or unobserved_zones.is_empty()):
		for zone in observed_zones:
			var route: Array[Vector3] = zone.get_recon_route(snapshot.squad_center)
			var route_score := influence.score_route(route)
			var observation := belief.get_zone_observation(zone.zone_id)
			var observed_contacts := (observation.get("visible_contact_ids", []) as Array).size()
			var observed_threats := int(observation.get("threat_evidence_count", 0))
			var confirmed_clear := observation.has("visible_contact_ids") \
					and observed_contacts == 0 and observed_threats == 0
			if confirmed_clear:
				# A completed patrol report outranks heat leaking in from an adjacent firefight.
				route_score = maxf(-30.0, route_score + 30.0)
			if route_score <= -35.0:
				continue
			var known_enemies := maxi(observed_contacts, belief.get_contacts_in_zone(zone).size())
			var tactical_score := influence.score_zone(zone)
			var utility := 112.0 + route_score * 0.08 + tactical_score * 0.05 - float(known_enemies) * 18.0
			var flank := _flank_option(
				snapshot, belief, influence, zone, utility,
				"Use the safest observed route for a synchronized flank"
			)
			if not flank.is_empty():
				flank["route_score"] = route_score
				result.append(flank)
	if snapshot.members.size() >= 4 and pressure_ratio >= 0.72 and suppression_ratio < 0.48 \
			and (recon_complete or unobserved_zones.is_empty()):
		result.append(_candidate(BOUNDING_ADVANCE, BOUNDING_ADVANCE, 58.0 + pressure_ratio * 24.0, "Advance by alternating fire and movement teams"))
	var all_routes_observed := recon_complete or zones.filter(func(zone: TacticalZone3D): return zone.recon_enabled).is_empty()
	var safe_flank_exists := result.any(func(item: Dictionary): return String(item.get("kind", "")) == SUPPRESS_AND_FLANK and float(item.get("route_score", -INF)) > -35.0)
	if all_routes_observed and not safe_flank_exists:
		var direct := _direct_assault_option(
			snapshot, belief, influence,
			76.0 + maxf(0.0, pressure_ratio - 0.7) * 30.0,
			"No usable flank remains; attack through the least dangerous approach"
		)
		if not direct.is_empty():
			result.append(direct)
	var average_awareness := _average_enemy_awareness(snapshot)
	if visible_count > 0 and average_awareness < 0.45 and suppression_ratio < 0.1:
		result.append(_candidate(AMBUSH, AMBUSH, 118.0 + (0.45 - average_awareness) * 60.0, "Targets are unaware; prepare a synchronized opening volley"))
	if fire_state == FireSuperiorityAssessment3D.State.PINNED or suppression_ratio >= 0.55:
		result.append(_candidate(RECOVER_IN_COVER, RECOVER_IN_COVER, 150.0 + suppression_ratio * 70.0, "Squad is pinned; recover before further movement"))
	if fire_state == FireSuperiorityAssessment3D.State.LOSING and snapshot.average_health() < 0.55:
		result.append(_candidate(BREAK_CONTACT, BREAK_CONTACT, 120.0 + (1.0 - snapshot.average_health()) * 45.0, "Combat power is collapsing; disengage by bounds"))
	if visible_count == 0 and not snapshot.contacts.is_empty():
		result.append(_candidate(SEARCH_LAST_CONTACT, SEARCH_LAST_CONTACT, 94.0, "Leave static cover and search the last reliable contact sector"))
	if _average_ammo(snapshot) < 0.2 and suppression_ratio < 0.25:
		result.append(_candidate(CONSOLIDATE, CONSOLIDATE, 88.0, "Consolidate in cover and restore weapons"))
	return _sort(result)

func _candidate(id: String, kind: String, utility: float, reason: String) -> Dictionary:
	return {"id": id, "kind": kind, "utility": utility, "reason": reason}

func _sort(candidates: Array[Dictionary]) -> Array[Dictionary]:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("utility", 0.0)) > float(b.get("utility", 0.0)))
	return candidates

func _contact_sector_count(snapshot: SquadDecisionSnapshot3D) -> int:
	var sectors: Dictionary = {}
	for contact in snapshot.contacts:
		var direction := (contact.get("position", snapshot.squad_center) as Vector3) - snapshot.squad_center
		if direction.length_squared() <= 0.01:
			continue
		var angle := atan2(direction.z, direction.x)
		sectors[roundi(angle / (PI * 0.5))] = true
	return sectors.size()

func _average_enemy_awareness(snapshot: SquadDecisionSnapshot3D) -> float:
	if snapshot.contacts.is_empty():
		return 1.0
	var total := 0.0
	for contact in snapshot.contacts:
		total += float(contact.get("awareness", 0.5))
	return total / float(snapshot.contacts.size())

func _average_ammo(snapshot: SquadDecisionSnapshot3D) -> float:
	if snapshot.members.is_empty():
		return 0.0
	var total := 0.0
	for member in snapshot.members:
		total += float(member.get("ammo", 0.0))
	return total / float(snapshot.members.size())

func _zone_access_score(influence: SquadInfluenceMap3D, zone: TacticalZone3D, origin: Vector3) -> float:
	var route: Array[Vector3] = [origin]
	route.append_array(zone.get_recon_route(origin))
	return influence.score_route(route)

func _defense_option(
		snapshot: SquadDecisionSnapshot3D,
		belief: SquadBeliefState3D,
		influence: SquadInfluenceMap3D,
		base_utility: float,
		reason: String,
		option_kind := DEFEND_CONTACT
) -> Dictionary:
	var contacts := belief.get_living_contacts()
	if contacts.is_empty():
		return _candidate(option_kind, option_kind, base_utility, reason)
	var route_plan := _route_planner.build_route(snapshot.squad_center, snapshot.mission_target, influence)
	var metrics := _option_metrics(snapshot, route_plan)
	var utility := base_utility \
		- float(metrics.get("route_peak_threat", 0.0)) * 0.12 \
		- float(metrics.get("exposure_seconds", 0.0)) * 1.2
	var template := SquadPlanCompiler3D.defense_option(
		&"option_defense", snapshot.get_member_ids(), contacts, snapshot.belief_version, snapshot.defense_locked
	)
	_set_task_route_metrics(template, &"defense_positions", route_plan)
	return SquadTacticalOption3D.new().configure(
		option_kind, option_kind, utility, reason, "LAYERED_DEFENSE", metrics, template
	).to_candidate()

func _flank_option(
		snapshot: SquadDecisionSnapshot3D,
		belief: SquadBeliefState3D,
		influence: SquadInfluenceMap3D,
		zone: TacticalZone3D,
		base_utility: float,
		reason: String
) -> Dictionary:
	var contact := belief.get_best_contact()
	if contact == null or zone == null or snapshot.members.size() < 3:
		return {}
	var ranked := snapshot.members.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return _support_option_score(a) > _support_option_score(b))
	var support_ids := PackedStringArray([String(ranked[0].get("id", ""))])
	var maneuver_ids := PackedStringArray()
	for member in snapshot.members:
		var member_id := String(member.get("id", ""))
		if member_id not in support_ids and _can_option_maneuver(member):
			maneuver_ids.append(member_id)
	if maneuver_ids.is_empty():
		return {}
	var controls: Array[Vector3] = zone.get_recon_route(snapshot.squad_center)
	var destination := zone.get_observation_point(snapshot.squad_center)
	var route_plan := _route_planner.build_route(snapshot.squad_center, destination, influence, controls)
	var metrics := _option_metrics(snapshot, route_plan)
	metrics["zone"] = zone
	var utility := base_utility \
		+ clampf((snapshot.get_power_ratio() - 1.0) * 20.0, -35.0, 30.0) \
		- float(metrics.get("route_peak_threat", 0.0)) * 0.42 \
		- float(metrics.get("exposure_seconds", 0.0)) * 3.5
	var method := "MG_BASE_OF_FIRE" if int(ranked[0].get("role", -1)) == Soldier3D.CombatRole.MACHINE_GUNNER \
		else "RIFLE_BASE_OF_FIRE"
	var template := SquadPlanCompiler3D.suppress_and_flank(
		&"option_flank", support_ids, maneuver_ids, zone, contact, snapshot.belief_version
	)
	_set_task_route_metrics(template, &"flank_move", route_plan)
	var option_id := "FLANK_%s" % String(zone.zone_id).to_upper()
	return SquadTacticalOption3D.new().configure(
		option_id, SUPPRESS_AND_FLANK, utility, reason, method, metrics, template
	).to_candidate()

func _direct_assault_option(
		snapshot: SquadDecisionSnapshot3D,
		belief: SquadBeliefState3D,
		influence: SquadInfluenceMap3D,
		base_utility: float,
		reason: String
) -> Dictionary:
	var contact := belief.get_best_contact()
	if contact == null:
		return {}
	var route_plan := _route_planner.build_route(snapshot.squad_center, contact.last_known_position, influence)
	var metrics := _option_metrics(snapshot, route_plan)
	var utility := base_utility \
		+ clampf((snapshot.get_power_ratio() - 1.0) * 42.0, -70.0, 55.0) \
		- float(metrics.get("route_peak_threat", 0.0)) * 0.62 \
		- float(metrics.get("exposure_seconds", 0.0)) * 4.8
	var template := SquadPlanCompiler3D.direct_assault_option(
		&"option_direct", snapshot.get_member_ids(), contact, snapshot.belief_version
	)
	_set_task_route_metrics(template, &"assault_approach", route_plan)
	return SquadTacticalOption3D.new().configure(
		DIRECT_ASSAULT, DIRECT_ASSAULT, utility, reason, "COVERED_DIRECT_ASSAULT", metrics, template
	).to_candidate()

func _option_metrics(snapshot: SquadDecisionSnapshot3D, route_plan: Dictionary) -> Dictionary:
	return {
		"friendly_power": snapshot.friendly_power,
		"enemy_power": snapshot.enemy_power,
		"power_ratio": snapshot.get_power_ratio(),
		"route_peak_threat": float(route_plan.get("peak_threat", 0.0)),
		"exposure_seconds": float(route_plan.get("exposure_seconds", 0.0)),
		"route_total_cost": float(route_plan.get("total_cost", 0.0)),
	}

func _set_task_route_metrics(plan: SquadCommandPlan3D, task_id: StringName, route_plan: Dictionary) -> void:
	if plan == null:
		return
	for task in plan.tasks:
		if task.task_id != task_id:
			continue
		task.route.assign(route_plan.get("route", []))
		task.set_route_metrics(route_plan)
		return

func _support_option_score(member: Dictionary) -> float:
	var role_bonus := 45.0 if int(member.get("role", -1)) == Soldier3D.CombatRole.MACHINE_GUNNER else 0.0
	return role_bonus + float(member.get("combat_power", 0.0)) * 2.0 \
		+ float(member.get("ammo", 0.0)) * 25.0 - float(member.get("suppression", 0.0)) * 35.0

func _can_option_maneuver(member: Dictionary) -> bool:
	return not bool(member.get("pinned", false)) and float(member.get("health", 0.0)) >= 0.5 \
		and float(member.get("mobility", 0.0)) >= 0.4
