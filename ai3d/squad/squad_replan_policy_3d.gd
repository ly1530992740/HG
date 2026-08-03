extends RefCounted
class_name SquadReplanPolicy3D

enum Level { NONE, LOCAL_ACTION, PLAN_REPAIR, FULL_TACTIC }

var minimum_commitment_seconds := 7.0
var utility_switch_margin := 20.0
var challenger_stability_seconds := 1.2

var _committed_at_msec := 0
var _pending_candidate_id := ""
var _pending_since_msec := 0

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
		return false
	var selected_id := String(selected.get("id", ""))
	if not active_plan or current_candidate_id.is_empty():
		return true
	if selected_id == current_candidate_id:
		return level >= Level.PLAN_REPAIR
	# Local danger interrupts a soldier's State Chart, not the squad's tactical option.
	# A failed reconnaissance/flank or genuinely new tactical situation arrives as FULL_TACTIC.
	if (current_candidate_id == SquadUtilityEvaluator3D.RECON_SPLIT \
			or current_candidate_id.begins_with("FLANK_")) and level < Level.FULL_TACTIC:
		return false
	var current_utility := _candidate_utility(candidates, current_candidate_id)
	var selected_utility := float(selected.get("utility", -INF))
	var committed_seconds := float(now_msec - _committed_at_msec) / 1000.0
	if level == Level.FULL_TACTIC:
		return true
	if committed_seconds < minimum_commitment_seconds:
		return false
	if selected_utility < current_utility + utility_switch_margin and current_utility > -INF:
		return false
	if _pending_candidate_id != selected_id:
		_pending_candidate_id = selected_id
		_pending_since_msec = now_msec
		return false
	return float(now_msec - _pending_since_msec) / 1000.0 >= challenger_stability_seconds

func note_applied(now_msec := Time.get_ticks_msec()) -> void:
	reset_commitment(now_msec)

func _candidate_utility(candidates: Array[Dictionary], candidate_id: String) -> float:
	for candidate in candidates:
		if String(candidate.get("id", "")) == candidate_id:
			return float(candidate.get("utility", -INF))
	return -INF
