extends Node

const CASE_SCENE := preload("res://tests/3d_battles/limited_intel_case_study_3d.tscn")
const RUN_COUNT := 10
const MAX_FRAMES_PER_RUN := 1800
const SETTLE_FRAMES := 120

var failures: Array[String] = []

func _ready() -> void:
	for run_index in RUN_COUNT:
		await _run_case(run_index)
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("LIMITED_INTEL_CASE_STUDY_PASS runs=%d" % RUN_COUNT)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("LIMITED_INTEL_CASE_STUDY_FAIL runs=%d failures=%d" % [RUN_COUNT, failures.size()])
		get_tree().quit(1)

func _run_case(run_index: int) -> void:
	seed(4100 + run_index)
	var battle := CASE_SCENE.instantiate() as LimitedIntelCaseStudy3D
	battle.show_debug_hud = false
	add_child(battle)
	var settle_remaining := -1
	for _frame in MAX_FRAMES_PER_RUN:
		await get_tree().process_frame
		var snapshot := battle.get_case_metrics()
		if bool(snapshot.get("blue_flank_started", false)):
			if settle_remaining < 0:
				settle_remaining = SETTLE_FRAMES
			else:
				settle_remaining -= 1
				if settle_remaining <= 0:
					break
	var metrics := battle.get_case_metrics()
	var run_failures := _validate_metrics(metrics)
	print("LIMITED_INTEL_CASE_RUN %s" % JSON.stringify({
		"run": run_index + 1,
		"passed": run_failures.is_empty(),
		"failures": run_failures,
		"elapsed": snappedf(float(metrics.get("elapsed", 0.0)), 0.1),
		"known_before_left": int(metrics.get("blue_max_known_before_left", -1)),
		"left_observed": bool(metrics.get("blue_left_observed", false)),
		"right_observed": bool(metrics.get("blue_right_observed", false)),
		"flank_zone": String(metrics.get("blue_flank_zone", "")),
		"red_max_distance": snappedf(float(metrics.get("red_max_mission_distance", 0.0)), 0.01),
		"shots_blue": int(metrics.get("shots_blue", 0)),
		"shots_red": int(metrics.get("shots_red", 0)),
	}))
	for reason in run_failures:
		failures.append("run %d: %s" % [run_index + 1, reason])
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _validate_metrics(metrics: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if not bool(metrics.get("red_hold_reached", false)):
		result.append("red squad never reached HOLDING")
	if float(metrics.get("red_max_mission_distance", INF)) > 14.6:
		result.append("red squad left configured mission radius")
	if int(metrics.get("blue_max_known_before_left", 99)) > 4:
		result.append("blue squad knew hidden defenders before left reconnaissance")
	if not bool(metrics.get("blue_recon_started", false)):
		result.append("blue squad never selected split reconnaissance")
	if not bool(metrics.get("blue_left_observed", false)):
		result.append("left defended route was not observed")
	if not bool(metrics.get("blue_right_observed", false)):
		result.append("right grass route was not observed")
	if not bool(metrics.get("blue_flank_started", false)) or String(metrics.get("blue_flank_zone", "")) != "right_grass":
		result.append("blue squad did not choose the right grass flank")
	if not bool(metrics.get("red_defend_started", false)):
		result.append("red squad did not enter contact defense")
	if int(metrics.get("shots_blue", 0)) <= 0:
		result.append("blue base of fire never fired")
	return result
