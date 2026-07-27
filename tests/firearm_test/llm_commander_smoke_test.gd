extends Node

const BATTLE_SCENE := preload("res://tests/firearm_test/llm_commander_battle.tscn")

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var battle := BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	assert(alpha != null, "Alpha does not use LlmSquadCoordinator.")
	assert(bravo != null, "Bravo does not use LlmSquadCoordinator.")

	var deadline := Time.get_ticks_msec() + 20000
	while (alpha.llm_success_count == 0 or bravo.llm_success_count == 0) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout

	_assert_commander_decision(alpha)
	_assert_commander_decision(bravo)
	print("Dual LLM commander smoke test passed:")
	print("  Alpha plan=%s latency=%dms %s" % [String(alpha.last_llm_plan), alpha.last_llm_latency_ms, alpha.last_order_summary])
	print("  Bravo plan=%s latency=%dms %s" % [String(bravo.last_llm_plan), bravo.last_llm_latency_ms, bravo.last_order_summary])
	get_tree().quit(0)

func _assert_commander_decision(commander: LlmSquadCoordinator) -> void:
	assert(commander.llm_request_count > 0, "%s never requested a local-model decision." % commander.commander_display_name)
	assert(commander.llm_success_count > 0, "%s received no valid local-model decision." % commander.commander_display_name)
	assert(String(commander.last_llm_plan) in LlmSquadCoordinator.ALLOWED_PLANS, "%s produced an illegal model plan." % commander.commander_display_name)
	assert(commander.last_llm_input.contains("【当前态势】"), "%s did not retain its complete model input." % commander.commander_display_name)
	assert(not commander.last_llm_input.contains("程序建议姿态"), "%s leaked a deterministic posture hint into the model input." % commander.commander_display_name)
	assert(commander.last_llm_output.begins_with("{"), "%s did not retain its raw model output." % commander.commander_display_name)
	assert(commander.last_order_summary != "Orders: none", "%s produced no GOAP squad orders." % commander.commander_display_name)
