extends Node

const AMBUSH_SCENE := preload("res://tests/firearm_test/llm_ambush_battle.tscn")

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var battle := AMBUSH_SCENE.instantiate()
	var initial_cover_transforms: Dictionary = {}
	for child in battle.get_children():
		if child is LowWall:
			initial_cover_transforms[child.name] = child.transform
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	for cover_name in initial_cover_transforms:
		var cover := battle.get_node(String(cover_name)) as LowWall
		assert(cover.transform.is_equal_approx(initial_cover_transforms[cover_name]), "Ambush setup changed a scene-authored cover transform: %s" % cover_name)
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	var setup := battle.get_node("LlmAmbushSetup")
	assert(alpha.get_member_count() == 8 and bravo.get_member_count() == 8, "The ambush scene is not configured as two scene-authored eight-member Groups.")
	for actor in alpha.get_configured_member_actors():
		assert(actor.get_parent() == alpha.get_node("Members"), "An Alpha ambush soldier is not below its Group member root.")
	for actor in bravo.get_configured_member_actors():
		assert(actor.get_parent() == bravo.get_node("Members"), "A Bravo ambush soldier is not below its Group member root.")
	for child in battle.get_children():
		assert(not child is GoblinBase, "The ambush battle still contains a hand-placed root soldier: %s" % child.name)
	var deadline := Time.get_ticks_msec() + 20000
	while (alpha.llm_success_count == 0 or alpha.last_llm_plan != &"AMBUSH") and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	assert(alpha.llm_success_count > 0 and alpha.last_llm_plan == &"AMBUSH", "Blue Qwen did not infer the ambush task graph.")
	assert(alpha.last_llm_input.contains("敌军未警觉"), "The Qwen prompt no longer explains the general unaware-enemy condition.")
	assert(alpha.last_llm_input.contains("\"敌军是否警觉\":false"), "The state did not report that Red was unaware.")
	var output := alpha.get_node_or_null(alpha.output_label_path) as RichTextLabel
	assert(output != null and output.text.contains("伏击包围"), "The visible Blue Qwen panel did not receive the ambush decision.")
	var plan := alpha.task_scheduler.active_plan
	assert(plan != null and plan.intent == &"AMBUSH", "The ambush intent was not compiled.")
	var occupy := plan.get_task(&"ambush_cover")
	var aim := plan.get_task(&"ambush_aim")
	var fire := plan.get_task(&"ambush_fire")
	assert(occupy != null and occupy.recipient_ids.size() == 8, "All eight blue soldiers were not assigned covers.")
	assert(aim.depends_on == [&"ambush_cover"], "Aiming did not wait for all cover arrivals.")
	assert(fire.depends_on == [&"ambush_aim"], "Fire did not wait for all soldiers to aim.")

	var red_count := 0
	for actor in bravo.get_configured_member_actors():
		var soldier := actor as GoblinBase
		red_count += 1
		assert(soldier.get_facing_direction().dot(Vector2.RIGHT) > 0.8, "An initial Red soldier was not facing away from Blue.")
		assert(soldier.global_position.x - 640.0 < 360.0, "The initial Red line was not close to the covers behind it.")
	assert(red_count == 8, "Scenario 1 must start with eight Red soldiers.")

	deadline = Time.get_ticks_msec() + 25000
	while fire.state != SquadTask.State.ACTIVE and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	if fire.state != SquadTask.State.ACTIVE:
		for member in alpha.members:
			var actor := member.actor
			var agent := actor.get("goap_agent") as GoapAgent
			print("[TASK DIAGNOSTIC] actor=%s pos=%s task_state=%s goal=%s action=%s world=%s" % [
				actor.name,
				actor.global_position,
				SquadTask.State.keys()[member.current_task_state],
				agent.get_current_goal().name if agent and agent.get_current_goal() else "NONE",
				agent.get_current_action().name if agent and agent.get_current_action() else "NONE",
				agent.get_world_state()._state if agent else {},
			])
	assert(occupy.state == SquadTask.State.SUCCEEDED, "The atomic GOAP chain did not bring every blue soldier into assigned cover.")
	assert(aim.state == SquadTask.State.SUCCEEDED, "The task scheduler released fire before every blue soldier aimed.")
	assert(fire.state == SquadTask.State.ACTIVE, "The synchronized neutralization task never activated.")
	deadline = Time.get_ticks_msec() + 5000
	while not bool(battle.get("alpha_first_fire_observed")) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	if not bool(battle.get("alpha_first_fire_observed")):
		for member in alpha.members:
			var agent := member.actor.get("goap_agent") as GoapAgent
			print("[FIRE DIAGNOSTIC] actor=%s task_state=%s goal=%s action=%s roe=%s target=%s" % [
				member.actor.name,
				SquadTask.State.keys()[member.current_task_state],
				agent.get_current_goal().name if agent and agent.get_current_goal() else "NONE",
				agent.get_current_action().name if agent and agent.get_current_action() else "NONE",
				member.actor._get_rules_of_engagement(),
				member.current_task.task.target.name if member.current_task and is_instance_valid(member.current_task.task.target) else "NONE",
			])
	assert(bool(battle.get("alpha_first_fire_observed")), "The atomic neutralization actions never fired.")
	await get_tree().create_timer(0.3).timeout

	# End any survivors deterministically so this smoke test can continue to guard and replanning.
	for actor in bravo.get_configured_member_actors():
		var soldier := actor as GoblinBase
		if soldier.is_combat_alive():
			soldier.take_damage(10000, Vector2.ZERO)
	var first_plan_version := alpha.plan_version
	deadline = Time.get_ticks_msec() + 20000
	while (alpha.task_scheduler.active_plan == null or alpha.task_scheduler.active_plan.intent != &"GUARD") and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	assert(alpha.task_scheduler.active_plan != null and alpha.task_scheduler.active_plan.intent == &"GUARD", "Blue did not issue perimeter guard after wave one.")
	var guard := alpha.task_scheduler.active_plan.get_task(&"perimeter_guard")
	var unique_guard_positions: Dictionary = {}
	if guard != null:
		for position in guard.member_positions.values():
			unique_guard_positions[position] = true
	assert(guard != null and unique_guard_positions.size() >= 6, "Guard positions were not distributed around the perimeter.")
	var guard_plan_version := alpha.plan_version
	assert(guard_plan_version > first_plan_version, "Guard did not create a new plan version.")

	deadline = Time.get_ticks_msec() + 20000
	while not bool(setup.get("_reinforcements_spawned")) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	if not bool(setup.get("_reinforcements_spawned")):
		var active_guard := alpha.task_scheduler.active_plan.get_task(&"perimeter_guard") if alpha.task_scheduler.active_plan else null
		for member in alpha.members:
			var destination := active_guard.get_position_for(String(member.actor.name)) if active_guard else Vector2.ZERO
			print("[GUARD DIAGNOSTIC] actor=%s distance=%.1f task_state=%s" % [
				member.actor.name,
				member.actor.global_position.distance_to(destination),
				SquadTask.State.keys()[member.current_task_state],
			])
	assert(bool(setup.get("_reinforcements_spawned")), "The second Red wave did not enter after guard was established.")
	var reinforcements := setup.get("reinforcement_members") as Array[Node2D]
	assert(reinforcements.size() == 6, "The east reinforcement wave must contain six soldiers.")
	for soldier in reinforcements:
		assert(soldier.global_position.x >= 1300.0, "A reinforcement did not enter from the fixed east side.")

	deadline = Time.get_ticks_msec() + 20000
	while alpha.plan_version <= guard_plan_version and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	assert(alpha.plan_version > guard_plan_version, "New east-side contact did not trigger a new plan version.")
	assert(alpha.task_scheduler.active_plan != null and alpha.task_scheduler.active_plan.intent != &"GUARD", "Blue kept the stale guard plan after detecting reinforcements.")
	print("LLM scenario 1 smoke test passed: ambush v%d -> guard v%d -> east-contact v%d, input/output are Chinese." % [first_plan_version, guard_plan_version, alpha.plan_version])
	get_tree().quit(0)
