extends RefCounted
class_name CombatContact

var target: Node2D = null
var observer: Node2D = null
var last_known_position := Vector2.ZERO
var last_seen_time_msec := 0
var confidence := 0.0
var currently_visible := false
var estimated_enemy_awareness := false
var stimulus_type: StringName = &"visual"

func update_visual(new_position: Vector2, new_confidence: float, enemy_aware: bool) -> void:
	last_known_position = new_position
	last_seen_time_msec = Time.get_ticks_msec()
	confidence = clampf(new_confidence, 0.0, 1.0)
	currently_visible = true
	estimated_enemy_awareness = enemy_aware
	stimulus_type = &"visual"

func update_hearing(new_position: Vector2, new_confidence: float) -> void:
	last_known_position = new_position
	last_seen_time_msec = Time.get_ticks_msec()
	confidence = maxf(confidence, clampf(new_confidence, 0.0, 1.0))
	currently_visible = false
	estimated_enemy_awareness = true
	stimulus_type = &"gunshot"

func age_seconds() -> float:
	return float(Time.get_ticks_msec() - last_seen_time_msec) / 1000.0

func is_valid() -> bool:
	return target != null and is_instance_valid(target) and not target.is_queued_for_deletion()
