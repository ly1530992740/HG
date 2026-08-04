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
var topology: SquadTacticalTopology3D

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
		result.append(_candidate_with_components(ESTABLISH_BASE_OF_FIRE, ESTABLISH_BASE_OF_FIRE, "Use support weapons to establish fire superiority", [
			_component("base", "Base of fire priority", 72.0, 1.0, "constant", 72.0),
			_component("machine_guns", "Available machine guns", machine_guns, clampf(float(machine_guns) / 2.0, 0.0, 1.0), "linear", float(machine_guns) * 14.0),
			_component("suppression", "Friendly suppression pressure", suppression_ratio, suppression_ratio, "linear", suppression_ratio * 20.0),
		]))
	if visible_count > 0:
		result.append(_candidate_with_components(FIX_AND_SUPPRESS, FIX_AND_SUPPRESS, "Fix known contacts while the squad prepares its next move", [
			_component("base", "Fixing fire priority", 62.0, 1.0, "constant", 62.0),
			_component("visible_contacts", "Visible contacts", visible_count, clampf(float(visible_count) / 4.0, 0.0, 1.0), "linear", float(visible_count) * 5.0),
			_component("suppression", "Friendly suppression pressure", suppression_ratio, suppression_ratio, "linear", suppression_ratio * 18.0),
		]))
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
		var candidate := _candidate_with_components(RECON_SPLIT, RECON_SPLIT, "Probe the safest unknown route while a base of fire remains", [
			_component("base", "Recon probe priority", 82.0, 1.0, "constant", 82.0),
			_component("suppression", "Covering fire opportunity", suppression_ratio, suppression_ratio, "linear", suppression_ratio * 28.0),
			_component("unknown_routes", "Unobserved routes", unobserved_zones.size(), clampf(float(unobserved_zones.size()) / 4.0, 0.0, 1.0), "linear", float(unobserved_zones.size()) * 5.0),
			_component("route_access", "Safest route access", safest_route_score, clampf((safest_route_score + 100.0) / 200.0, 0.0, 1.0), "clamped_linear", clampf(safest_route_score, -100.0, 100.0) * 0.12),
		])
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
		result.append(_candidate_with_components(BOUNDING_ADVANCE, BOUNDING_ADVANCE, "Advance by alternating fire and movement teams", [
			_component("base", "Bounding advance priority", 58.0, 1.0, "constant", 58.0),
			_component("fire_pressure", "Friendly fire pressure", pressure_ratio, clampf(pressure_ratio, 0.0, 1.0), "linear", pressure_ratio * 24.0),
		]))
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
		result.append(_candidate_with_components(AMBUSH, AMBUSH, "Targets are unaware; prepare a synchronized opening volley", [
			_component("base", "Ambush priority", 118.0, 1.0, "constant", 118.0),
			_component("surprise", "Enemy unawareness", average_awareness, clampf(1.0 - average_awareness / 0.45, 0.0, 1.0), "inverse_linear", (0.45 - average_awareness) * 60.0),
		]))
	if fire_state == FireSuperiorityAssessment3D.State.PINNED or suppression_ratio >= 0.55:
		result.append(_candidate_with_components(RECOVER_IN_COVER, RECOVER_IN_COVER, "Squad is pinned; recover before further movement", [
			_component("base", "Pinned recovery priority", 150.0, 1.0, "constant", 150.0),
			_component("suppression", "Squad suppression", suppression_ratio, suppression_ratio, "linear", suppression_ratio * 70.0),
		]))
	if fire_state == FireSuperiorityAssessment3D.State.LOSING and snapshot.average_health() < 0.55:
		result.append(_candidate_with_components(BREAK_CONTACT, BREAK_CONTACT, "Combat power is collapsing; disengage by bounds", [
			_component("base", "Disengagement priority", 120.0, 1.0, "constant", 120.0),
			_component("casualty_pressure", "Missing health", snapshot.average_health(), clampf(1.0 - snapshot.average_health(), 0.0, 1.0), "inverse_linear", (1.0 - snapshot.average_health()) * 45.0),
		]))
	if visible_count == 0 and not snapshot.contacts.is_empty():
		result.append(_candidate(SEARCH_LAST_CONTACT, SEARCH_LAST_CONTACT, 94.0, "Leave static cover and search the last reliable contact sector"))
	if _average_ammo(snapshot) < 0.2 and suppression_ratio < 0.25:
		result.append(_candidate(CONSOLIDATE, CONSOLIDATE, 88.0, "Consolidate in cover and restore weapons"))
	return _sort(result)

func _candidate(id: String, kind: String, utility: float, reason: String) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"utility": utility,
		"reason": reason,
		"considerations": [_component("authored_base", "Authored base priority", utility, 1.0, "constant", utility)],
		"gates": [],
	}

func _candidate_with_components(id: String, kind: String, reason: String, components: Array[Dictionary]) -> Dictionary:
	var utility := 0.0
	for component in components:
		utility += float(component.get("contribution", 0.0))
	return {
		"id": id,
		"kind": kind,
		"utility": utility,
		"reason": reason,
		"considerations": components.duplicate(true),
		"gates": [],
	}

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
	var controls := _topology_controls(snapshot.squad_center, snapshot.mission_target)
	var route_plan := _route_planner.build_route(snapshot.squad_center, snapshot.mission_target, influence, controls)
	var metrics := _option_metrics(snapshot, route_plan)
	var utility := base_utility \
		- float(metrics.get("route_peak_threat", 0.0)) * 0.12 \
		- float(metrics.get("exposure_seconds", 0.0)) * 1.2 \
		- (18.0 if bool(metrics.get("destination_dead_end", false)) else 0.0)
	metrics["considerations"] = [
		_component("situation_base", "Defensive situation", base_utility, 1.0, "authored", base_utility),
		_component("route_threat", "Route peak threat", metrics.get("route_peak_threat", 0.0), clampf(float(metrics.get("route_peak_threat", 0.0)) / 100.0, 0.0, 1.0), "linear", -float(metrics.get("route_peak_threat", 0.0)) * 0.12),
		_component("exposure", "Exposure time", metrics.get("exposure_seconds", 0.0), clampf(float(metrics.get("exposure_seconds", 0.0)) / 10.0, 0.0, 1.0), "linear", -float(metrics.get("exposure_seconds", 0.0)) * 1.2),
		_component("dead_end", "Destination is a dead end", metrics.get("destination_dead_end", false), 1.0 if bool(metrics.get("destination_dead_end", false)) else 0.0, "binary", -18.0 if bool(metrics.get("destination_dead_end", false)) else 0.0),
	]
	return SquadTacticalOption3D.new().configure(
		option_kind, option_kind, utility, reason, metrics,
		[{"role": SquadRoleAllocator3D.SECURITY, "count": snapshot.members.size()}]
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
	var support_count := snapshot.members.filter(func(member: Dictionary): return _can_option_support(member)).size()
	var maneuver_count := snapshot.members.filter(func(member: Dictionary): return _can_option_maneuver(member)).size()
	if support_count < 1 or maneuver_count < 2:
		return {}
	var controls := _topology_controls(snapshot.squad_center, zone.get_observation_point(snapshot.squad_center))
	controls.append_array(zone.get_recon_route(snapshot.squad_center))
	var destination := zone.get_observation_point(snapshot.squad_center)
	var route_plan := _route_planner.build_route(snapshot.squad_center, destination, influence, controls)
	var metrics := _option_metrics(snapshot, route_plan)
	metrics["zone"] = zone
	var utility := base_utility \
		+ clampf((snapshot.get_power_ratio() - 1.0) * 20.0, -35.0, 30.0) \
		- float(metrics.get("route_peak_threat", 0.0)) * 0.42 \
		- float(metrics.get("exposure_seconds", 0.0)) * 3.5 \
		- (35.0 if bool(metrics.get("destination_dead_end", false)) else 0.0)
	metrics["eligible_support"] = support_count
	metrics["eligible_maneuver"] = maneuver_count
	metrics["considerations"] = [
		_component("tactical_base", "Observed flank opportunity", base_utility, 1.0, "authored", base_utility),
		_component("power_ratio", "Friendly power ratio", snapshot.get_power_ratio(), clampf(snapshot.get_power_ratio() / 2.0, 0.0, 1.0), "clamped_linear", clampf((snapshot.get_power_ratio() - 1.0) * 20.0, -35.0, 30.0)),
		_component("route_threat", "Route peak threat", metrics.get("route_peak_threat", 0.0), clampf(float(metrics.get("route_peak_threat", 0.0)) / 100.0, 0.0, 1.0), "linear", -float(metrics.get("route_peak_threat", 0.0)) * 0.42),
		_component("exposure", "Exposure time", metrics.get("exposure_seconds", 0.0), clampf(float(metrics.get("exposure_seconds", 0.0)) / 10.0, 0.0, 1.0), "linear", -float(metrics.get("exposure_seconds", 0.0)) * 3.5),
		_component("dead_end", "Flank destination is a dead end", metrics.get("destination_dead_end", false), 1.0 if bool(metrics.get("destination_dead_end", false)) else 0.0, "binary", -35.0 if bool(metrics.get("destination_dead_end", false)) else 0.0),
	]
	metrics["gates"] = [
		_gate("support_available", support_count >= 1, support_count, 1),
		_gate("maneuver_team_available", maneuver_count >= 2, maneuver_count, 2),
	]
	var option_id := "FLANK_%s" % String(zone.zone_id).to_upper()
	return SquadTacticalOption3D.new().configure(
		option_id, SUPPRESS_AND_FLANK, utility, reason, metrics,
		[
			{"role": SquadRoleAllocator3D.BASE_OF_FIRE, "minimum": 1},
			{"role": SquadRoleAllocator3D.MANEUVER_LEAD, "minimum": 1},
			{"role": SquadRoleAllocator3D.MANEUVER_WING, "minimum": 1},
		]
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
	var controls := _topology_controls(snapshot.squad_center, contact.last_known_position)
	var route_plan := _route_planner.build_route(snapshot.squad_center, contact.last_known_position, influence, controls)
	var metrics := _option_metrics(snapshot, route_plan)
	var utility := base_utility \
		+ clampf((snapshot.get_power_ratio() - 1.0) * 42.0, -70.0, 55.0) \
		- float(metrics.get("route_peak_threat", 0.0)) * 0.62 \
		- float(metrics.get("exposure_seconds", 0.0)) * 4.8 \
		- (45.0 if bool(metrics.get("destination_dead_end", false)) else 0.0)
	metrics["considerations"] = [
		_component("assault_base", "Direct assault necessity", base_utility, 1.0, "authored", base_utility),
		_component("power_ratio", "Friendly power ratio", snapshot.get_power_ratio(), clampf(snapshot.get_power_ratio() / 2.0, 0.0, 1.0), "clamped_linear", clampf((snapshot.get_power_ratio() - 1.0) * 42.0, -70.0, 55.0)),
		_component("route_threat", "Route peak threat", metrics.get("route_peak_threat", 0.0), clampf(float(metrics.get("route_peak_threat", 0.0)) / 100.0, 0.0, 1.0), "linear", -float(metrics.get("route_peak_threat", 0.0)) * 0.62),
		_component("exposure", "Exposure time", metrics.get("exposure_seconds", 0.0), clampf(float(metrics.get("exposure_seconds", 0.0)) / 10.0, 0.0, 1.0), "linear", -float(metrics.get("exposure_seconds", 0.0)) * 4.8),
		_component("dead_end", "Assault destination is a dead end", metrics.get("destination_dead_end", false), 1.0 if bool(metrics.get("destination_dead_end", false)) else 0.0, "binary", -45.0 if bool(metrics.get("destination_dead_end", false)) else 0.0),
	]
	return SquadTacticalOption3D.new().configure(
		DIRECT_ASSAULT, DIRECT_ASSAULT, utility, reason, metrics,
		[{"role": SquadRoleAllocator3D.MANEUVER_LEAD, "minimum": 1}]
	).to_candidate()

func _option_metrics(snapshot: SquadDecisionSnapshot3D, route_plan: Dictionary) -> Dictionary:
	var result := {
		"friendly_power": snapshot.friendly_power,
		"enemy_power": snapshot.enemy_power,
		"power_ratio": snapshot.get_power_ratio(),
		"route_peak_threat": float(route_plan.get("peak_threat", 0.0)),
		"exposure_seconds": float(route_plan.get("exposure_seconds", 0.0)),
		"route_total_cost": float(route_plan.get("total_cost", 0.0)),
		"route": route_plan.get("route", []),
	}
	if topology != null and topology.version > 0:
		var topology_score := topology.score_connection(snapshot.squad_center, (route_plan.get("route", []) as Array).back() if not (route_plan.get("route", []) as Array).is_empty() else snapshot.mission_target)
		for key in topology_score:
			if key != "waypoints":
				result[key] = topology_score[key]
	return result

func _topology_controls(from_position: Vector3, to_position: Vector3) -> Array[Vector3]:
	return topology.get_route_waypoints(from_position, to_position) if topology != null and topology.version > 0 else []

func _component(id: String, label: String, raw: Variant, normalized: float, curve: String, contribution: float) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"raw": raw,
		"normalized": clampf(normalized, 0.0, 1.0),
		"curve": curve,
		"contribution": contribution,
	}

func _gate(id: String, passed: bool, raw: Variant, required: Variant) -> Dictionary:
	return {"id": id, "passed": passed, "raw": raw, "required": required}

func _can_option_support(member: Dictionary) -> bool:
	return not bool(member.get("pinned", false)) and bool(member.get("loaded", true)) \
		and float(member.get("ammo", 0.0)) > 0.08 and float(member.get("health", 0.0)) > 0.2

func _can_option_maneuver(member: Dictionary) -> bool:
	return not bool(member.get("pinned", false)) and float(member.get("health", 0.0)) >= 0.5 \
		and float(member.get("mobility", 0.0)) >= 0.4
