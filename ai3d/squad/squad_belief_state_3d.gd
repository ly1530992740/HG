extends RefCounted
class_name SquadBeliefState3D

signal belief_changed(version: int, reason: StringName)

var contact_memory_seconds := 24.0
var contacts: Dictionary = {}
var zone_observations: Dictionary = {}
var threat_events: Array[Dictionary] = []
var version := 1

func merge_report(report: SquadContactReport3D) -> void:
	if report == null:
		return
	if report.stimulus == SquadContactReport3D.Stimulus.ZONE_OBSERVED:
		zone_observations[report.zone_id] = {
			"reported_at": report.timestamp_msec,
			"reported_by": report.observer_id,
			"position": report.position,
			"confidence": report.confidence,
			"visible_contact_ids": report.zone_visible_contact_ids.duplicate(),
			"threat_evidence_count": report.zone_threat_evidence_count,
			"observer_suppressed": report.observer_suppressed,
		}
		_touch(&"zone_observed")
		return
	if report.get_target() == null:
		threat_events.append({
			"position": report.position,
			"reported_at": report.timestamp_msec,
			"confidence": report.confidence,
			"stimulus": report.stimulus,
			"observer_id": report.observer_id,
		})
		_prune_threat_events()
		_touch(&"anonymous_threat")
		return
	var contact := contacts.get(report.contact_id) as CombatContact3D
	if contact == null:
		contact = CombatContact3D.new()
		contacts[report.contact_id] = contact
	contact.merge_report(report)
	_touch(&"contact")

func update(delta: float) -> void:
	var removed := false
	for contact_id in contacts.keys():
		var contact := contacts[contact_id] as CombatContact3D
		if contact == null or contact.get_decayed_confidence(contact_memory_seconds) <= 0.02:
			contacts.erase(contact_id)
			removed = true
			continue
		contact.currently_visible = contact.currently_visible and contact.age_seconds() <= 0.8
	_prune_threat_events()
	if removed:
		_touch(&"contact_expired")

func get_known_contacts(minimum_confidence := 0.12) -> Array[CombatContact3D]:
	var result: Array[CombatContact3D] = []
	for value in contacts.values():
		var contact := value as CombatContact3D
		if contact != null and contact.get_decayed_confidence(contact_memory_seconds) >= minimum_confidence:
			result.append(contact)
	return result

func get_living_contacts(minimum_confidence := 0.12) -> Array[CombatContact3D]:
	var result: Array[CombatContact3D] = []
	for contact in get_known_contacts(minimum_confidence):
		var target := contact.get_target()
		if contact.target_ref == null \
				or (target != null and (not target.has_method("is_combat_alive") or bool(target.is_combat_alive()))):
			result.append(contact)
	return result

func get_best_contact() -> CombatContact3D:
	var best: CombatContact3D
	var best_score := -INF
	for contact in get_living_contacts():
		var score := contact.get_decayed_confidence(contact_memory_seconds) * 10.0
		if contact.currently_visible:
			score += 5.0
		score += contact.estimated_firepower
		if score > best_score:
			best = contact
			best_score = score
	return best

func get_estimated_enemy_count() -> int:
	return get_living_contacts(0.2).size()

func get_estimated_enemy_power() -> float:
	var result := 0.0
	for contact in get_living_contacts(0.2):
		result += contact.estimated_firepower * contact.get_decayed_confidence(contact_memory_seconds)
	return result

func has_known_hostile_in_radius(center: Vector3, radius: float) -> bool:
	for contact in get_living_contacts(0.2):
		var delta := contact.last_known_position - center
		delta.y = 0.0
		if delta.length() <= radius:
			return true
	return false

func has_recent_threat_in_radius(center: Vector3, radius: float, max_age_seconds := 8.0) -> bool:
	var cutoff := Time.get_ticks_msec() - int(maxf(0.0, max_age_seconds) * 1000.0)
	for event in threat_events:
		if int(event.get("reported_at", 0)) < cutoff:
			continue
		var delta := (event.get("position", Vector3.ZERO) as Vector3) - center
		delta.y = 0.0
		if delta.length() <= radius:
			return true
	return false

func get_contacts_in_zone(zone: TacticalZone3D) -> Array[CombatContact3D]:
	var result: Array[CombatContact3D] = []
	if zone == null:
		return result
	for contact in get_living_contacts():
		if zone.contains_world_position(contact.last_known_position):
			result.append(contact)
	return result

func get_threat_events_in_zone(zone: TacticalZone3D) -> Array[Dictionary]:
	if zone == null:
		return []
	return threat_events.filter(func(event: Dictionary):
		return zone.contains_world_position(event.get("position", Vector3.ZERO) as Vector3)
	)

func is_zone_observed(zone_id: StringName) -> bool:
	return zone_observations.has(zone_id)

func get_zone_observation(zone_id: StringName) -> Dictionary:
	return (zone_observations.get(zone_id, {}) as Dictionary).duplicate(true)

func make_tactical_snapshot(zones: Array[TacticalZone3D]) -> Dictionary:
	var contact_facts: Array[Dictionary] = []
	for contact in get_living_contacts():
		contact_facts.append({
			"id": String(contact.contact_id),
			"last_known_position": _vector_fact(contact.last_known_position),
			"age_seconds": snappedf(contact.age_seconds(), 0.1),
			"confidence": snappedf(contact.get_decayed_confidence(contact_memory_seconds), 0.01),
			"currently_visible": contact.currently_visible,
			"estimated_role": contact.estimated_role,
			"estimated_firepower": snappedf(contact.estimated_firepower, 0.1),
			"enemy_awareness_probability": snappedf(contact.enemy_awareness_probability, 0.05),
			"stimulus": String(contact.stimulus),
		})
	var zone_facts: Array[Dictionary] = []
	for zone in zones:
		var observation := get_zone_observation(zone.zone_id)
		zone_facts.append({
			"id": String(zone.zone_id),
			"known_terrain": true,
			"observed": not observation.is_empty(),
			"observation_confidence": float(observation.get("confidence", 0.0)),
			"known_contacts": get_contacts_in_zone(zone).size(),
			"threat_evidence_count": int(observation.get("threat_evidence_count", 0)),
			"concealment": zone.concealment,
			"cover_value": zone.cover_value,
			"route_exposure": zone.route_exposure,
		})
	return {
		"belief_version": version,
		"estimated_enemy_count": get_estimated_enemy_count(),
		"estimated_enemy_power": snappedf(get_estimated_enemy_power(), 0.1),
		"contacts": contact_facts,
		"zones": zone_facts,
	}

func _prune_threat_events() -> void:
	var cutoff := Time.get_ticks_msec() - int(contact_memory_seconds * 1000.0)
	threat_events = threat_events.filter(func(event: Dictionary): return int(event.get("reported_at", 0)) >= cutoff)

func _touch(reason: StringName) -> void:
	version += 1
	belief_changed.emit(version, reason)

func _vector_fact(value: Vector3) -> Dictionary:
	return {"x": snappedf(value.x, 0.1), "y": snappedf(value.y, 0.1), "z": snappedf(value.z, 0.1)}
