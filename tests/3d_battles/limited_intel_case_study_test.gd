extends Node

const DEFAULT_CASE_SCENE := preload("res://tests/3d_battles/limited_intel_case_study_3d.tscn")
const DEFAULT_RUN_COUNT := 10
const MAX_FRAMES_PER_RUN := 5400
const SETTLE_FRAMES := 120

var failures: Array[String] = []

@export var case_scene: PackedScene = DEFAULT_CASE_SCENE
@export var expected_defended_zone_id: StringName = &"left_route"
@export var expected_flank_zone_id: StringName = &"right_grass"

func _ready() -> void:
	var run_count := maxi(1, int(OS.get_environment("HG_TEST_RUN_COUNT"))) \
		if OS.has_environment("HG_TEST_RUN_COUNT") else DEFAULT_RUN_COUNT
	for run_index in run_count:
		await _run_case(run_index)
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("LIMITED_INTEL_CASE_STUDY_PASS runs=%d" % run_count)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("LIMITED_INTEL_CASE_STUDY_FAIL runs=%d failures=%d" % [run_count, failures.size()])
		get_tree().quit(1)

func _run_case(run_index: int) -> void:
	var seed_offset := int(OS.get_environment("HG_TEST_SEED_OFFSET")) \
		if OS.has_environment("HG_TEST_SEED_OFFSET") else 0
	seed(4100 + seed_offset + run_index)
	var battle := case_scene.instantiate() as LimitedIntelCaseStudy3D
	battle.show_debug_hud = false
	_stabilize_combat_outcomes(battle)
	add_child(battle)
	var settle_remaining := -1
	for _frame in MAX_FRAMES_PER_RUN:
		await get_tree().process_frame
		var snapshot := battle.get_case_metrics()
		if bool(snapshot.get("blue_synchronized_attack_started", false)) \
				and int(snapshot.get("blue_synchronized_attack_shots", 0)) > 0:
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
		"defended_observed": bool(metrics.get("blue_defended_route_observed", false)),
		"flank_observed": bool(metrics.get("blue_flank_route_observed", false)),
		"defended_contacts": int(metrics.get("blue_defended_route_contacts", -1)),
		"flank_contacts": int(metrics.get("blue_flank_route_contacts", -1)),
		"flank_zone": String(metrics.get("blue_flank_zone", "")),
		"flank_arrived": bool(metrics.get("blue_flank_task_succeeded", false)),
		"synchronized_attack": bool(metrics.get("blue_synchronized_attack_started", false)),
		"flank_shots": int(metrics.get("blue_synchronized_attack_shots", 0)),
		"red_max_distance": snappedf(float(metrics.get("red_max_mission_distance", 0.0)), 0.01),
		"shots_blue": int(metrics.get("shots_blue", 0)),
		"shots_red": int(metrics.get("shots_red", 0)),
		"red_tasks": metrics.get("red_task_debug", []),
		"red_members": metrics.get("red_member_debug", []),
		"blue_tasks": metrics.get("blue_task_debug", []),
		"blue_members": metrics.get("blue_member_debug", []),
	}))
	for reason in run_failures:
		failures.append("run %d: %s" % [run_index + 1, reason])
	battle.queue_free()
	await get_tree().process_frame

func _stabilize_combat_outcomes(battle: LimitedIntelCaseStudy3D) -> void:
	for squad_path in [NodePath("BlueSquad/Members"), NodePath("RedSquad/Members")]:
		var members := battle.get_node(squad_path)
		for child in members.get_children():
			if child is Soldier3D:
				(child as Soldier3D).max_health = 100000
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
	if not bool(metrics.get("blue_defended_route_observed", false)):
		result.append("defended route %s was not observed" % expected_defended_zone_id)
	if not bool(metrics.get("blue_flank_route_observed", false)):
		result.append("flank route %s was not observed" % expected_flank_zone_id)
	if int(metrics.get("blue_defended_route_contacts", 0)) <= 0:
		result.append("defended route %s did not contain a reported defender" % expected_defended_zone_id)
	if int(metrics.get("blue_flank_route_contacts", -1)) != 0:
		result.append("flank route %s was expected to contain no enemies" % expected_flank_zone_id)
	if not bool(metrics.get("blue_flank_started", false)) or StringName(metrics.get("blue_flank_zone", "")) != expected_flank_zone_id:
		result.append("blue squad did not choose expected flank %s" % expected_flank_zone_id)
	if not bool(metrics.get("blue_flank_task_succeeded", false)):
		result.append("blue flank element never reached its attack position")
	if not bool(metrics.get("blue_synchronized_attack_started", false)):
		result.append("blue synchronized attack never activated")
	if int(metrics.get("blue_synchronized_attack_shots", 0)) <= 0:
		result.append("blue flank element never fired from the attack position")
	if not bool(metrics.get("red_defend_started", false)):
		result.append("red squad did not enter contact defense")
	if int(metrics.get("shots_blue", 0)) <= 0:
		result.append("blue base of fire never fired")
	if int(metrics.get("shots_red", 0)) < 4:
		result.append("red persistent defense did not sustain return fire")
	return result
