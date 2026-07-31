extends RefCounted
class_name SquadContactReport3D

enum Stimulus {
	VISUAL,
	GUNSHOT,
	DAMAGE,
	NEAR_MISS,
	ZONE_OBSERVED,
}

var report_id: StringName = &""
var contact_id: StringName = &""
var observer_id: StringName = &""
var observer_ref: WeakRef
var target_ref: WeakRef
var position := Vector3.ZERO
var confidence := 0.0
var stimulus: Stimulus = Stimulus.VISUAL
var timestamp_msec := 0
var estimated_role := -1
var estimated_firepower := 1.0
var enemy_awareness_probability := 0.5
var zone_id: StringName = &""
var zone_visible_contact_ids: Array[StringName] = []
var zone_threat_evidence_count := 0
var observer_suppressed := false

func configure_contact(
		observer: Soldier3D,
		target: Node3D,
		observed_position: Vector3,
		observed_confidence: float,
		observed_stimulus: Stimulus
) -> SquadContactReport3D:
	timestamp_msec = Time.get_ticks_msec()
	observer_id = StringName(observer.name) if is_instance_valid(observer) else &"UNKNOWN"
	observer_ref = weakref(observer) if is_instance_valid(observer) else null
	target_ref = weakref(target) if is_instance_valid(target) else null
	position = observed_position
	confidence = clampf(observed_confidence, 0.0, 1.0)
	stimulus = observed_stimulus
	if is_instance_valid(target):
		contact_id = StringName("contact_%d" % target.get_instance_id())
		if target is Soldier3D and observed_stimulus == Stimulus.VISUAL:
			estimated_role = int((target as Soldier3D).combat_role)
			estimated_firepower = (target as Soldier3D).get_combat_power()
		var target_recently_fired := target is Soldier3D \
			and Time.get_ticks_msec() - (target as Soldier3D).last_weapon_fired_msec <= 1800
		var target_alerted := target is Soldier3D and (target as Soldier3D).aware_of_enemy
		var observer_engaged := is_instance_valid(observer) \
			and Time.get_ticks_msec() - observer.last_weapon_fired_msec <= 1800
		enemy_awareness_probability = 0.9 \
			if target_alerted or target_recently_fired or observer_engaged or observed_stimulus != Stimulus.VISUAL else 0.25
	else:
		var bucket_x := roundi(position.x / 3.0)
		var bucket_z := roundi(position.z / 3.0)
		contact_id = StringName("sound_%d_%d_%d" % [bucket_x, bucket_z, timestamp_msec / 3000])
	report_id = StringName("%s_%s_%d" % [observer_id, contact_id, timestamp_msec])
	return self

func configure_zone_observation(
		observer: Soldier3D,
		observed_zone_id: StringName,
		observed_position: Vector3,
	visible_contacts: Array[StringName],
	suppressed: bool,
	threat_evidence_count := 0
) -> SquadContactReport3D:
	timestamp_msec = Time.get_ticks_msec()
	observer_id = StringName(observer.name) if is_instance_valid(observer) else &"UNKNOWN"
	observer_ref = weakref(observer) if is_instance_valid(observer) else null
	position = observed_position
	confidence = 0.82 if not suppressed else 0.62
	stimulus = Stimulus.ZONE_OBSERVED
	zone_id = observed_zone_id
	zone_visible_contact_ids = visible_contacts.duplicate()
	zone_threat_evidence_count = maxi(0, threat_evidence_count)
	observer_suppressed = suppressed
	report_id = StringName("%s_zone_%s_%d" % [observer_id, zone_id, timestamp_msec])
	return self

func get_observer() -> Soldier3D:
	return observer_ref.get_ref() as Soldier3D if observer_ref != null else null

func get_target() -> Node3D:
	return target_ref.get_ref() as Node3D if target_ref != null else null
