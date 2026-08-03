extends RefCounted
class_name SquadTaskCondition3D

enum Kind {
	AT_TARGET,
	PROTECTED,
	TARGET_NEUTRALIZED,
	DURATION_ELAPSED,
	ZONE_OBSERVED,
	MEMBER_DEAD,
	TIMEOUT,
}

var kind: Kind = Kind.AT_TARGET
var threshold := 0.0
var label := ""

func configure(new_kind: Kind, new_threshold := 0.0, new_label := "") -> SquadTaskCondition3D:
	kind = new_kind
	threshold = new_threshold
	label = new_label if not new_label.is_empty() else Kind.keys()[kind]
	return self

func is_met(
		member: Soldier3D,
		task: SquadTask3D,
		belief: SquadBeliefState3D
) -> bool:
	match kind:
		Kind.AT_TARGET:
			return member != null and member.is_combat_alive() \
				and _flat_distance(member.global_position, task.target_position) <= maxf(0.5, threshold)
		Kind.PROTECTED:
			if member == null or not member.is_combat_alive():
				return false
			if is_instance_valid(member.active_structure):
				return member.active_structure.is_occupied_by(member)
			if is_instance_valid(member.active_cover):
				return member.is_protected_from_position(task.target_position)
			return not task.advance_toward_objective and member.stance == Soldier3D.Stance.PRONE
		Kind.TARGET_NEUTRALIZED:
			if belief == null or task.contact_id == &"":
				return false
			var contact := belief.contacts.get(task.contact_id) as CombatContact3D
			if contact == null:
				return true
			var target := contact.get_target()
			return target == null or (target.has_method("is_combat_alive") and not bool(target.is_combat_alive()))
		Kind.DURATION_ELAPSED:
			var required_seconds := threshold if threshold > 0.0 else maxf(0.1, task.duration)
			return task.activated_msec > 0 \
				and Time.get_ticks_msec() - task.activated_msec >= int(required_seconds * 1000.0)
		Kind.ZONE_OBSERVED:
			return belief != null and task.zone_id != &"" and belief.is_zone_observed(task.zone_id)
		Kind.MEMBER_DEAD:
			return member == null or not member.is_combat_alive()
		Kind.TIMEOUT:
			return task.activated_msec > 0 \
				and Time.get_ticks_msec() - task.activated_msec >= int(maxf(0.1, threshold) * 1000.0)
	return false

func duplicate_condition() -> SquadTaskCondition3D:
	return SquadTaskCondition3D.new().configure(kind, threshold, label)

func get_signature() -> Dictionary:
	return {"kind": int(kind), "threshold": snappedf(threshold, 0.05), "label": label}

func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
