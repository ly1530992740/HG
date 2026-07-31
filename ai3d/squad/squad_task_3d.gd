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
var state: State = State.PENDING
var member_states: Dictionary = {}
var activated_msec := 0

func configure(new_id: StringName, new_type: Type, recipients: PackedStringArray) -> SquadTask3D:
	task_id = new_id
	type = new_type
	recipient_ids = recipients
	persistent = type in [Type.SUPPRESS_CONTACT, Type.HOLD_OBJECTIVE]
	return self

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
	})
