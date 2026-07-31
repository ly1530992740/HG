extends RefCounted
class_name CombatContact3D

var contact_id: StringName = &""
var target_ref: WeakRef
var last_known_position := Vector3.ZERO
var last_report_msec := 0
var confidence := 0.0
var currently_visible := false
var estimated_role := -1
var estimated_firepower := 1.0
var enemy_awareness_probability := 0.5
var stimulus: StringName = &"unknown"
var reported_by: Dictionary = {}

func merge_report(report: SquadContactReport3D) -> void:
	contact_id = report.contact_id
	if report.target_ref != null and report.get_target() != null:
		target_ref = report.target_ref
	last_known_position = report.position
	last_report_msec = report.timestamp_msec
	confidence = maxf(confidence * 0.72, report.confidence)
	currently_visible = report.stimulus == SquadContactReport3D.Stimulus.VISUAL
	if report.estimated_role >= 0:
		estimated_role = report.estimated_role
	estimated_firepower = maxf(0.25, report.estimated_firepower)
	enemy_awareness_probability = maxf(
		enemy_awareness_probability * 0.95,
		clampf(report.enemy_awareness_probability, 0.0, 1.0)
	)
	stimulus = SquadContactReport3D.Stimulus.keys()[report.stimulus].to_lower()
	reported_by[String(report.observer_id)] = report.timestamp_msec

func get_target() -> Node3D:
	if target_ref == null:
		return null
	return target_ref.get_ref() as Node3D

func age_seconds(now_msec := Time.get_ticks_msec()) -> float:
	return maxf(0.0, float(now_msec - last_report_msec) / 1000.0)

func get_decayed_confidence(memory_seconds: float, now_msec := Time.get_ticks_msec()) -> float:
	if memory_seconds <= 0.0:
		return 0.0
	return confidence * clampf(1.0 - age_seconds(now_msec) / memory_seconds, 0.0, 1.0)
