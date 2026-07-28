extends Node

const FLANK_SCENE := preload("res://tests/firearm_test/llm_flank_battle.tscn")

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var battle := FLANK_SCENE.instantiate()
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as SquadCoordinator
	alpha.initial_guard_enabled = false
	alpha.allow_silent_ambush = false
	bravo.process_mode = Node.PROCESS_MODE_DISABLED
	var initial_cover_transforms: Dictionary = {}
	for child in battle.get_children():
		if child is LowWall:
			initial_cover_transforms[child.name] = child.transform
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	for cover_name in initial_cover_transforms:
		var cover := battle.get_node(String(cover_name)) as LowWall
		assert(cover.transform.is_equal_approx(initial_cover_transforms[cover_name]), "Flank setup changed a scene-authored cover transform: %s" % cover_name)
	assert(alpha is SquadGroup, "The Qwen commander is not the squad Group root.")
	assert(alpha.get_member_count() == 8 and bravo.get_member_count() == 8, "The flank scene is not configured as two scene-authored eight-member Groups.")
	assert(alpha.battlefield_analyzer != null and alpha.battlefield_analyzer.get_parent() == alpha, "The battlefield analyzer is not mounted on the squad Group.")
	assert(alpha.route_analyzer != null and alpha.route_analyzer.get_parent() == alpha, "The route analyzer is not mounted on the squad Group.")
	assert(alpha.get_configured_member_actors().size() == 8, "The Alpha Group roster does not expose all eight configured members.")
	assert(bravo.get_configured_member_actors().size() == 8, "The Bravo Group roster does not expose all eight scene members.")
	for actor in alpha.get_configured_member_actors():
		assert(actor.get_parent() == alpha.get_node("Members"), "An Alpha flank soldier is not below its Group member root.")
	for actor in bravo.get_configured_member_actors():
		assert(actor.get_parent() == bravo.get_node("Members"), "A Bravo flank soldier is not below its Group member root.")
	for child in battle.get_children():
		assert(not child is GoblinBase, "The flank battle still contains a hand-placed root soldier: %s" % child.name)
	alpha._begin_direct_contact(bravo.get_member_actor(&"BravoA"))
	var deadline := Time.get_ticks_msec() + 20000
	while alpha.last_llm_plan != &"SUPPRESS_AND_FLANK" and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	assert(alpha.llm_success_count > 0, "Blue Qwen returned no valid flank-scenario decision.")
	assert(alpha.last_llm_plan == &"SUPPRESS_AND_FLANK", "Blue Qwen did not infer suppress-and-flank from the route and firepower state.")
	assert(alpha.last_llm_input.contains("候选包抄路线"), "The Qwen input did not contain analyzer-generated route candidates.")
	var selected_route_id := StringName(alpha._last_decision.get("机动路线ID", ""))
	var selected_route := alpha.get_route_candidate(selected_route_id)
	assert(not selected_route.is_empty() and bool(selected_route.get("available", false)), "Qwen did not select a valid analyzer route ID.")
	var output := alpha.get_node_or_null(alpha.output_label_path) as RichTextLabel
	assert(output != null and output.text.contains("压制包抄"), "The visible Blue Qwen panel did not receive the model decision.")
	var bravo_input := battle.get_node("CanvasLayer/BravoQwenPanel/Margin/VBox/Input") as RichTextLabel
	assert(bravo_input.text.contains("不调用本地Qwen"), "The flank scene did not identify Red as rule-controlled.")
	var plan := alpha.task_scheduler.active_plan
	assert(plan != null and plan.intent == &"SUPPRESS_AND_FLANK", "The Qwen intent was not compiled into an active task graph.")
	var suppress := plan.get_task(&"front_suppress")
	var route_tasks: Array[SquadTask] = []
	for task in plan.tasks:
		if task.type == SquadTask.Type.MOVE_TO_ZONE:
			route_tasks.append(task)
	var flank_aim := plan.get_task(&"flank_aim")
	var flank_attack := plan.get_task(&"flank_attack")
	assert(suppress != null and suppress.persistent, "The frontal group has no persistent suppression task.")
	assert(route_tasks.size() == (selected_route.get("points", []) as Array).size(), "The selected analyzer route was not compiled into all movement stages.")
	assert(not route_tasks.is_empty() and route_tasks[0].recipient_ids.size() >= 3, "Fewer than three soldiers were assigned to the selected flank route.")
	assert(route_tasks[0].depends_on == [&"front_suppress"], "Flank movement did not depend on established frontal suppression.")
	for route_index in range(1, route_tasks.size()):
		assert(route_tasks[route_index].depends_on == [route_tasks[route_index - 1].task_id], "Analyzer route stages were not sequential.")
	assert(flank_aim.depends_on == [route_tasks[-1].task_id] and flank_attack.depends_on == [&"flank_aim"], "Side aiming and attack dependencies are incomplete.")
	var start_positions: Dictionary = {}
	for member_id in route_tasks[0].recipient_ids:
		var member := alpha.task_scheduler.members_by_id.get(member_id) as SquadMember
		start_positions[member_id] = member.actor.global_position
	var movement_deadline := Time.get_ticks_msec() + 18000
	var maximum_progress := 0.0
	while (route_tasks[0].state != SquadTask.State.SUCCEEDED or route_tasks[1].state == SquadTask.State.PENDING) and Time.get_ticks_msec() < movement_deadline:
		await get_tree().create_timer(0.1).timeout
		for member_id in start_positions:
			var member := alpha.task_scheduler.members_by_id.get(member_id) as SquadMember
			if member != null and is_instance_valid(member.actor):
				maximum_progress = maxf(maximum_progress, member.actor.global_position.distance_to(start_positions[member_id]))
	var movement_debug := PackedStringArray()
	for member_id in start_positions:
		var member := alpha.task_scheduler.members_by_id.get(member_id) as SquadMember
		if member == null or not is_instance_valid(member.actor):
			movement_debug.append("%s unavailable" % member_id)
			continue
		var destination := route_tasks[0].get_position_for(member_id)
		var current_action := member.actor.goap_agent.get_current_action() as SquadTaskAction
		movement_debug.append("%s pos=%s dst=%s remaining=%.0f action=%s task=%s" % [
			member_id,
			member.actor.global_position,
			destination,
			member.actor.global_position.distance_to(destination),
			SquadTaskAction.Operation.keys()[current_action.operation] if current_action != null else "NONE",
			member.current_task.task.task_id if member.current_task != null else &"NONE",
		])
	print("Flank movement diagnostic: %s" % " | ".join(movement_debug))
	assert(route_tasks[0].state == SquadTask.State.SUCCEEDED, "The flankers did not complete the first analyzer waypoint; progress=%.0f; %s" % [maximum_progress, " | ".join(movement_debug)])
	assert(route_tasks[1].state in [SquadTask.State.ACTIVE, SquadTask.State.READY, SquadTask.State.SUCCEEDED], "Completing the first waypoint did not unlock the second route stage.")
	for member_id in route_tasks[0].recipient_ids:
		var member := alpha.task_scheduler.members_by_id.get(member_id) as SquadMember
		assert(member != null and member.current_task != null and member.current_task.task.task_id != route_tasks[0].task_id, "A flanker remained stuck on the completed first waypoint: %s" % member_id)
	assert(maximum_progress >= 120.0, "The flank task graph advanced without meaningful soldier movement.")
	print("LLM flank smoke test passed: route=%s, mobile=%d, progress=%.0f, first=%s, second=%s, graph=%s" % [selected_route_id, route_tasks[0].recipient_ids.size(), maximum_progress, route_tasks[0].get_state_name(), route_tasks[1].get_state_name(), alpha.task_scheduler.get_summary()])
	get_tree().quit(0)
