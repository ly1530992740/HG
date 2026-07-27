extends Node

const AMBUSH_SCENE := preload("res://tests/firearm_test/llm_ambush_battle.tscn")

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var battle := AMBUSH_SCENE.instantiate()
	var setup := battle.get_node("LlmAmbushSetup")
	setup.set("auto_pause_after_opening_volley", false)
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	assert(alpha != null and bravo != null, "The ambush scene must use Qwen for both squad leaders.")

	var decision_deadline := Time.get_ticks_msec() + 20000
	while alpha.llm_success_count == 0 and Time.get_ticks_msec() < decision_deadline:
		await get_tree().create_timer(0.1).timeout
	assert(alpha.llm_success_count > 0, "Blue did not receive a valid Qwen decision.")
	assert(alpha.last_llm_plan == &"AMBUSH", "Blue Qwen did not infer the ambush plan from the sample and state.")
	assert(alpha.last_llm_input.contains("样本二"), "The complete few-shot prompt was not exposed in the Chinese debug input.")
	assert(alpha.last_llm_input.contains("\"敌军是否警觉\":false"), "The model input did not describe an unaware enemy.")
	assert(alpha.last_llm_input.contains("\"可用隐蔽掩体组\":2"), "The model input did not describe both ambush cover groups.")
	assert(alpha.last_llm_input.contains("\"兵力人数差（我方减敌方）\""), "The model input did not expose an unambiguous force difference.")
	assert(not alpha.last_llm_input.contains("程序建议姿态"), "The model input still leaked a program-selected posture.")
	assert(alpha.last_llm_output.contains("伏击包围"), "The raw Chinese model output did not select the ambush plan.")
	assert(int(alpha.get_blackboard().get_fact(&"ambush_cover_count", 0)) >= 2, "The plan did not assign both ambush cover groups.")
	assert(int(alpha.get_blackboard().get_fact(&"ambush_assigned_target_count", 0)) == 8, "The ambush did not assign all identified enemy targets.")
	for member in alpha.members:
		assert(member.current_order != null and member.current_order.type == SquadOrder.Type.AMBUSH_POSITION, "A blue soldier did not receive AMBUSH_POSITION from the inferred plan.")

	var fire_deadline := Time.get_ticks_msec() + 20000
	while not bool(battle.get("alpha_first_fire_observed")) and Time.get_ticks_msec() < fire_deadline:
		await get_tree().create_timer(0.1).timeout
	assert(bool(battle.get("alpha_first_fire_observed")), "The inferred ambush never opened fire.")
	await get_tree().create_timer(0.25).timeout
	assert(bool(battle.get("alpha_ambush_opened_all_in_cover")), "Blue fired before every soldier reached assigned cover.")
	assert(StringName(battle.get("alpha_ambush_open_reason")) == &"aimed_ready", "Blue fired before every soldier completed aiming.")
	assert(bool(battle.get("bravo_unaware_at_alpha_first_fire")), "Red detected Blue before the synchronized volley.")
	assert(not bool(battle.get("bravo_combat_order_before_alpha_fire")), "Red issued a combat order before Blue opened fire.")
	var volley_times := battle.get("alpha_opening_volley_fire_msec") as Dictionary
	assert(volley_times.size() == 8, "The synchronized opening volley did not include all eight blue soldiers.")
	var earliest := 9223372036854775807
	var latest := 0
	for timestamp in volley_times.values():
		earliest = mini(earliest, int(timestamp))
		latest = maxi(latest, int(timestamp))
	assert(latest - earliest <= 50, "The eight opening shots were not synchronized.")
	print("LLM ambush smoke test passed: Qwen inferred 伏击包围 in %dms; 8 soldiers used 2 covers and fired within %dms." % [
		alpha.last_llm_latency_ms,
		latest - earliest,
	])
	get_tree().quit(0)
