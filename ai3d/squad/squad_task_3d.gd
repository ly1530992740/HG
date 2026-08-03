extends RefCounted
class_name SquadTask3D

enum Type {
	MOVE_TO_OBJECTIVE,
	TAKE_COVER,
	RECON_ZONE,
	SUPPRESS_CONTACT,
	FLANK_ZONE,
	ATTACK_CONTACT,
	HOLD_OBJECTIVE,
	RETURN_TO_ORIGIN,
	RECOVER_IN_COVER,
	AIM_CONTACT,
}

enum State { PENDING, ACTIVE, READY, SUCCEEDED, FAILED, CANCELLED }

var task_id: StringName = &""
var type: Type = Type.HOLD_OBJECTIVE
var recipient_ids: PackedStringArray = []
var depends_on: Array[StringName] = []
var successful_members_from: StringName = &""
var contact_id: StringName = &""
var member_contact_ids: Dictionary = {}
var zone_id: StringName = &""
var target_position := Vector3.ZERO
var route: Array[Vector3] = []
var duration := 0.0
var persistent := false
var minimum_success_count := 0
var reason := ""
var rules_of_engagement := SquadDirective3D.RulesOfEngagement.WEAPONS_FREE
var prefer_defensive_structures := false
var advance_toward_objective := false
var success_conditions: Array[SquadTaskCondition3D] = []
var failure_conditions: Array[SquadTaskCondition3D] = []
var excluded_cover_ids: Array[StringName] = []
var assignment_revision := 0
var route_revision := 0
var route_peak_threat := 0.0
var route_exposure_seconds := 0.0
var state: State = State.PENDING
var member_states: Dictionary = {}
var activated_msec := 0

func configure(new_id: StringName, new_type: Type, recipients: PackedStringArray) -> SquadTask3D:
	task_id = new_id
	type = new_type
	recipient_ids = recipients
	persistent = type in [Type.SUPPRESS_CONTACT, Type.HOLD_OBJECTIVE]
	_configure_default_conditions()
	return self

func clone_for_patch() -> SquadTask3D:
	var result := SquadTask3D.new().configure(task_id, type, recipient_ids.duplicate())
	result.depends_on = depends_on.duplicate()
	result.successful_members_from = successful_members_from
	result.contact_id = contact_id
	result.member_contact_ids = member_contact_ids.duplicate(true)
	result.zone_id = zone_id
	result.target_position = target_position
	result.route = route.duplicate()
	result.duration = duration
	result.persistent = persistent
	result.minimum_success_count = minimum_success_count
	result.reason = reason
	result.rules_of_engagement = rules_of_engagement
	result.prefer_defensive_structures = prefer_defensive_structures
	result.advance_toward_objective = advance_toward_objective
	result.success_conditions.clear()
	for condition in success_conditions:
		result.success_conditions.append(condition.duplicate_condition())
	result.failure_conditions.clear()
	for condition in failure_conditions:
		result.failure_conditions.append(condition.duplicate_condition())
	result.excluded_cover_ids = excluded_cover_ids.duplicate()
	result.assignment_revision = assignment_revision
	result.route_revision = route_revision
	result.route_peak_threat = route_peak_threat
	result.route_exposure_seconds = route_exposure_seconds
	result.state = state
	result.member_states = member_states.duplicate(true)
	result.activated_msec = activated_msec
	return result

func set_route_metrics(metrics: Dictionary) -> void:
	route_peak_threat = float(metrics.get("peak_threat", 0.0))
	route_exposure_seconds = float(metrics.get("exposure_seconds", 0.0))

func dependencies_satisfied(tasks_by_id: Dictionary) -> bool:
	for dependency_id in depends_on:
		var dependency := tasks_by_id.get(dependency_id) as SquadTask3D
		if dependency == null or dependency.state not in [State.READY, State.SUCCEEDED]:
			return false
	return true

func get_required_success_count() -> int:
	if recipient_ids.is_empty():
		return 0
	return clampi(minimum_success_count, 1, recipient_ids.size()) if minimum_success_count > 0 else recipient_ids.size()

func get_type_name() -> String:
	return Type.keys()[type]

func get_state_name() -> String:
	return State.keys()[state]

func get_signature() -> String:
	return JSON.stringify({
		"type": type,
		"recipients": Array(recipient_ids),
		"depends_on": depends_on.map(func(value): return String(value)),
		"successful_members_from": String(successful_members_from),
		"contact": String(contact_id),
		"member_contacts": member_contact_ids,
		"zone": String(zone_id),
		"position": [snappedf(target_position.x, 0.05), snappedf(target_position.y, 0.05), snappedf(target_position.z, 0.05)],
		"route": route.map(func(value: Vector3): return [snappedf(value.x, 0.05), snappedf(value.y, 0.05), snappedf(value.z, 0.05)]),
		"duration": snappedf(duration, 0.05),
		"persistent": persistent,
		"minimum_success_count": minimum_success_count,
		"roe": rules_of_engagement,
		"prefer_defensive_structures": prefer_defensive_structures,
		"advance_toward_objective": advance_toward_objective,
		"success_conditions": success_conditions.map(func(condition: SquadTaskCondition3D): return condition.get_signature()),
		"failure_conditions": failure_conditions.map(func(condition: SquadTaskCondition3D): return condition.get_signature()),
		"excluded_covers": excluded_cover_ids.map(func(value): return String(value)),
		"assignment_revision": assignment_revision,
		"route_revision": route_revision,
		"route_peak_threat": snappedf(route_peak_threat, 0.1),
		"route_exposure_seconds": snappedf(route_exposure_seconds, 0.1),
	})

func _configure_default_conditions() -> void:
	success_conditions.clear()
	failure_conditions = [SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.MEMBER_DEAD)]
	match type:
		Type.MOVE_TO_OBJECTIVE, Type.RETURN_TO_ORIGIN, Type.FLANK_ZONE:
			success_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.AT_TARGET, 1.0))
			failure_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.TIMEOUT, 30.0))
		Type.RECON_ZONE:
			success_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.ZONE_OBSERVED))
			failure_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.TIMEOUT, 35.0))
		Type.TAKE_COVER:
			success_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.PROTECTED))
			failure_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.TIMEOUT, 18.0))
		Type.ATTACK_CONTACT:
			success_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.TARGET_NEUTRALIZED))
		Type.SUPPRESS_CONTACT, Type.RECOVER_IN_COVER:
			success_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.DURATION_ELAPSED))
		Type.HOLD_OBJECTIVE:
			success_conditions.append(SquadTaskCondition3D.new().configure(SquadTaskCondition3D.Kind.AT_TARGET, 2.0))
