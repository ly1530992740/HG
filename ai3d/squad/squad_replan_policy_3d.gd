extends RefCounted
class_name SquadReplanPolicy3D

enum Level { NONE, LOCAL_ACTION, PLAN_REPAIR, FULL_TACTIC }

var minimum_commitment_seconds := 7.0
var utility_switch_margin := 20.0
var challenger_stability_seconds := 1.2

var _committed_at_msec := 0
var _pending_candidate_id := ""
var _pending_since_msec := 0
var last_decision: Dictionary = {}

func reset_commitment(now_msec := Time.get_ticks_msec()) -> void:
	_committed_at_msec = now_msec
	_pending_candidate_id = ""
	_pending_since_msec = 0

func classify_report(report: SquadContactReport3D, previous_contact_count: int, next_contact_count: int) -> Level:
	if report == null:
		return Level.NONE
	if report.stimulus == SquadContactReport3D.Stimulus.ZONE_OBSERVED:
		return Level.PLAN_REPAIR
	if report.stimulus == SquadContactReport3D.Stimulus.DAMAGE:
		return Level.LOCAL_ACTION
	if next_contact_count > previous_contact_count:
		return Level.FULL_TACTIC if previous_contact_count == 0 else Level.PLAN_REPAIR
	if report.stimulus in [SquadContactReport3D.Stimulus.NEAR_MISS, SquadContactReport3D.Stimulus.GUNSHOT]:
		return Level.LOCAL_ACTION
	return Level.NONE

func should_apply(
		selected: Dictionary,
		candidates: Array[Dictionary],
		current_candidate_id: String,
		level: Level,
		active_plan: bool,
		now_msec := Time.get_ticks_msec()
) -> bool:
	if selected.is_empty():
		return _finish(false, "no_selected_candidate", "", current_candidate_id, -INF, -INF, 0.0, level, now_msec)
	var selected_id := String(selected.get("id", ""))
	var selected_utility := float(selected.get("utility", -INF))
	var current_utility := _candidate_utility(candidates, current_candidate_id)
	var committed_seconds := float(now_msec - _committed_at_msec) / 1000.0
	if not active_plan or current_candidate_id.is_empty():
		return _finish(true, "no_active_plan", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)
	if selected_id == current_candidate_id:
		return _finish(level >= Level.PLAN_REPAIR, "repair_active_plan" if level >= Level.PLAN_REPAIR else "same_candidate_no_repair", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)
	# Local danger interrupts a soldier's State Chart, not the squad's tactical option.
	# A failed reconnaissance/flank or genuinely new tactical situation arrives as FULL_TACTIC.
	if (current_candidate_id == SquadUtilityEvaluator3D.RECON_SPLIT \
			or current_candidate_id.begins_with("FLANK_")) and level < Level.FULL_TACTIC:
		return _finish(false, "protected_multi_stage_tactic", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)
	if level == Level.FULL_TACTIC:
		return _finish(true, "full_tactic_interrupt", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)
	if committed_seconds < minimum_commitment_seconds:
		return _finish(false, "minimum_commitment", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)
	if selected_utility < current_utility + utility_switch_margin and current_utility > -INF:
		return _finish(false, "switch_margin", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)
	if _pending_candidate_id != selected_id:
		_pending_candidate_id = selected_id
		_pending_since_msec = now_msec
		return _finish(false, "challenger_started", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)
	var stable_seconds := float(now_msec - _pending_since_msec) / 1000.0
	return _finish(stable_seconds >= challenger_stability_seconds, "challenger_stable" if stable_seconds >= challenger_stability_seconds else "challenger_stabilizing", selected_id, current_candidate_id, selected_utility, current_utility, committed_seconds, level, now_msec)

func note_applied(now_msec := Time.get_ticks_msec()) -> void:
	reset_commitment(now_msec)

func _candidate_utility(candidates: Array[Dictionary], candidate_id: String) -> float:
	for candidate in candidates:
		if String(candidate.get("id", "")) == candidate_id:
			return float(candidate.get("utility", -INF))
	return -INF

func get_debug_state() -> Dictionary:
	return last_decision.duplicate(true)

func _finish(
		applied: bool,
		reason: String,
		selected_id: String,
		current_id: String,
		selected_utility: float,
		current_utility: float,
		committed_seconds: float,
		level: Level,
		now_msec: int
) -> bool:
	last_decision = {
		"applied": applied,
		"reason": reason,
		"selected_id": selected_id,
		"current_id": current_id,
		"selected_utility": selected_utility,
		"current_utility": current_utility,
		"switch_margin": utility_switch_margin,
		"committed_seconds": committed_seconds,
		"minimum_commitment_seconds": minimum_commitment_seconds,
		"pending_candidate_id": _pending_candidate_id,
		"challenger_stable_seconds": 0.0 if _pending_since_msec <= 0 else float(now_msec - _pending_since_msec) / 1000.0,
		"challenger_required_seconds": challenger_stability_seconds,
		"replan_level": Level.keys()[level],
	}
	return applied
