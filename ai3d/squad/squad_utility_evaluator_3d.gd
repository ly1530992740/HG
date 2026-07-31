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
		var mission_kind := HOLD_OBJECTIVE if snapshot.mission_state in [SquadMissionController3D.State.HOLDING, SquadMissionController3D.State.COMPLETE] else "MISSION_MOVE"
		result.append(_candidate(mission_kind, mission_kind, 100.0, "No confirmed contact; continue mission"))
		return result
	if not contact_cover_complete:
		result.append(_candidate("CONTACT_COVER", "CONTACT_COVER", 240.0, "Immediate squad contact drill"))
		return result

	var fire_state := int(snapshot.fire_assessment.get("state", FireSuperiorityAssessment3D.State.CONTESTED))
	var pressure_ratio := float(snapshot.fire_assessment.get("pressure_ratio", 1.0))
	var suppression_ratio := float(snapshot.fire_assessment.get("suppression_ratio", 0.0))
	var visible_count := snapshot.visible_contact_count()
	var defense_locked := snapshot.mission_state in [SquadMissionController3D.State.HOLDING, SquadMissionController3D.State.COMPLETE]
	var machine_guns := snapshot.count_role(Soldier3D.CombatRole.MACHINE_GUNNER)
	var observed_zones := zones.filter(func(zone: TacticalZone3D): return zone.recon_enabled and belief.is_zone_observed(zone.zone_id))
	var unobserved_zones := zones.filter(func(zone: TacticalZone3D): return zone.recon_enabled and not belief.is_zone_observed(zone.zone_id))
	var contact_sector_count := _contact_sector_count(snapshot)

	if defense_locked:
		result.append(_candidate(DEFEND_CONTACT, DEFEND_CONTACT, 115.0 + minf(35.0, float(visible_count) * 7.0), "Defend the configured mission area"))
		if contact_sector_count >= 2:
			result.append(_candidate(COUNTER_FLANK, COUNTER_FLANK, 170.0 + float(contact_sector_count) * 10.0, "Hostiles reported from multiple sectors"))
		if fire_state in [FireSuperiorityAssessment3D.State.LOSING, FireSuperiorityAssessment3D.State.PINNED]:
			result.append(_candidate(FALLBACK_DEFENSE, FALLBACK_DEFENSE, 150.0 + suppression_ratio * 55.0, "Compress into an inner defensive perimeter"))
		if suppression_ratio >= 0.24:
			result.append(_candidate(RECOVER_IN_COVER, RECOVER_IN_COVER, 138.0 + suppression_ratio * 70.0, "Recover protected shooters before resuming fire"))
		return _sort(result)

	result.append(_candidate(DEFEND_CONTACT, DEFEND_CONTACT, 48.0 + maxf(0.0, 1.0 - pressure_ratio) * 20.0, "Hold current cover and maintain contact"))
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
		var candidate := _candidate(RECON_SPLIT, RECON_SPLIT, 82.0 + suppression_ratio * 28.0 + float(unobserved_zones.size()) * 5.0, "Probe unknown routes while a base of fire remains")
		candidate["zones"] = unobserved_zones
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
			var flank := _candidate("FLANK_%s" % String(zone.zone_id).to_upper(), SUPPRESS_AND_FLANK, utility, "Use the safest observed route for a synchronized flank")
			flank["zone"] = zone
			flank["route_score"] = route_score
			result.append(flank)
	if snapshot.members.size() >= 4 and pressure_ratio >= 0.72 and suppression_ratio < 0.48 \
			and (recon_complete or unobserved_zones.is_empty()):
		result.append(_candidate(BOUNDING_ADVANCE, BOUNDING_ADVANCE, 58.0 + pressure_ratio * 24.0, "Advance by alternating fire and movement teams"))
	var all_routes_observed := recon_complete or zones.filter(func(zone: TacticalZone3D): return zone.recon_enabled).is_empty()
	var safe_flank_exists := result.any(func(item: Dictionary): return String(item.get("kind", "")) == SUPPRESS_AND_FLANK and float(item.get("route_score", -INF)) > -35.0)
	if all_routes_observed and not safe_flank_exists:
		result.append(_candidate(DIRECT_ASSAULT, DIRECT_ASSAULT, 76.0 + maxf(0.0, pressure_ratio - 0.7) * 30.0, "No usable flank remains; attack through the least dangerous approach"))
	var average_awareness := _average_enemy_awareness(snapshot)
	if visible_count > 0 and average_awareness < 0.45 and suppression_ratio < 0.1:
		result.append(_candidate(AMBUSH, AMBUSH, 118.0 + (0.45 - average_awareness) * 60.0, "Targets are unaware; prepare a synchronized opening volley"))
	if fire_state == FireSuperiorityAssessment3D.State.PINNED or suppression_ratio >= 0.55:
		result.append(_candidate(RECOVER_IN_COVER, RECOVER_IN_COVER, 150.0 + suppression_ratio * 70.0, "Squad is pinned; recover before further movement"))
	if fire_state == FireSuperiorityAssessment3D.State.LOSING and snapshot.average_health() < 0.55:
		result.append(_candidate(BREAK_CONTACT, BREAK_CONTACT, 120.0 + (1.0 - snapshot.average_health()) * 45.0, "Combat power is collapsing; disengage by bounds"))
	if visible_count == 0 and not snapshot.contacts.is_empty():
		result.append(_candidate(SEARCH_LAST_CONTACT, SEARCH_LAST_CONTACT, 67.0, "Search the last reliable contact sector"))
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
