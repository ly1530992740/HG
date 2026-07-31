extends Node

const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")

var _cases := 0
var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	await _test_idle_security_fallback()
	await _test_friendly_sound_is_ignored()
	await _test_visual_contact_does_not_trigger_prone_or_fire()
	await _test_near_miss_selects_cover_within_fifteen_meters()
	await _test_severe_open_ground_danger_uses_prone()
	await _test_directive_uses_knee_and_wait_for_nonsevere_danger()
	await _test_directive_keeps_goal_while_inserting_cover_action()
	await _test_directive_keeps_goal_while_inserting_prone_action()
	await _test_radio_report_stays_uncertain()
	await _test_idle_weapon_restore()
	await _test_cover_posture_contract()
	await _test_cover_slots_are_reserved_individually()
	_test_astar_prefers_lowest_total_cost()
	await _test_runtime_preconditions_are_revalidated()
	if _failures > 0 or _cases != 14:
		push_error("SOLDIER_AUTONOMY_GOAP_FAIL cases=%d failures=%d" % [_cases, _failures])
		get_tree().quit(1)
		return
	print("SOLDIER_AUTONOMY_GOAP_PASS cases=%d" % _cases)
	get_tree().quit()

func _test_idle_security_fallback() -> void:
	var soldier := await _spawn_soldier("Idle", Soldier3D.Team.BLUE, Vector3.ZERO)
	_plan(soldier)
	var goal := _agent(soldier).get_current_goal() as SoldierAutonomyGoal3D
	_expect(goal != null and goal.kind == SoldierAutonomyGoal3D.Kind.MAINTAIN_SECURITY,
		"A soldier without orders must only maintain local security")
	_expect(_autonomy_operations(soldier) == [SoldierAutonomyAction3D.Operation.GUARD_SECTOR],
		"Idle fallback must not invent movement or combat tasks")
	_pass_case()
	await _remove_nodes([soldier])

func _test_friendly_sound_is_ignored() -> void:
	var soldier := await _spawn_soldier("Listener", Soldier3D.Team.BLUE, Vector3.ZERO)
	var friendly := await _spawn_soldier("Friendly", Soldier3D.Team.BLUE, Vector3(0.0, 0.0, -8.0))
	soldier.hear_combat_sound(friendly.global_position, friendly)
	_expect(float(soldier.get("_threat_memory_timer")) <= 0.0, "Friendly fire must not create hostile memory")
	_pass_case()
	await _remove_nodes([soldier, friendly])

func _test_visual_contact_does_not_trigger_prone_or_fire() -> void:
	var pair := await _spawn_visible_pair("Visual")
	var soldier := pair[0] as Soldier3D
	var hostile := pair[1] as Soldier3D
	soldier.call("_register_autonomy_threat", hostile.global_position, hostile, 1.0, false)
	soldier._sync_dynamic_goap_state()
	_plan(soldier)
	var operations := _autonomy_operations(soldier)
	_expect(soldier.stance == Soldier3D.Stance.STAND and not operations.has(SoldierAutonomyAction3D.Operation.DROP_PRONE),
		"Visual contact alone must not make an unordered soldier drop prone")
	_expect(not operations.has(SoldierAutonomyAction3D.Operation.RETURN_FIRE) \
		and not operations.has(SoldierAutonomyAction3D.Operation.SUPPRESSION_FIRE),
		"An unordered soldier must report and guard, not autonomously attack or chase")
	_expect(not _plan_contains_directive_action(soldier), "Fallback autonomy must never borrow squad movement actions")
	_pass_case()
	await _remove_nodes(pair)

func _test_near_miss_selects_cover_within_fifteen_meters() -> void:
	var soldier := await _spawn_soldier("CoverUser", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0.0, 0.0, -20.0))
	var cover := TacticalCover3D.new()
	cover.position = Vector3(0.0, 0.0, -14.0)
	add_child(cover)
	await get_tree().physics_frame
	soldier.notify_near_miss(hostile.global_position, hostile)
	_plan(soldier)
	_expect(soldier.get("_autonomy_cover_candidate") == cover, "Emergency cover search must include usable cover 12-15 meters away")
	_expect(_autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.SEEK_COVER),
		"A severe near miss must prefer reachable cover over prone in the open")
	_pass_case()
	await _remove_nodes([soldier, hostile, cover])

func _test_severe_open_ground_danger_uses_prone() -> void:
	var soldier := await _spawn_soldier("Exposed", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0.0, 0.0, -10.0))
	soldier.notify_near_miss(hostile.global_position, hostile)
	_plan(soldier)
	_expect(_agent(soldier).get_current_goal() is SoldierAutonomyGoal3D,
		"An unordered exposed soldier needs a local survival fallback")
	_expect(_autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.DROP_PRONE),
		"Prone is reserved for severe danger in open ground without usable cover")
	_agent(soldier).process(0.1)
	_expect(soldier.stance == Soldier3D.Stance.PRONE, "The open-ground prone action must change runtime posture")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_directive_uses_knee_and_wait_for_nonsevere_danger() -> void:
	var soldier := await _spawn_soldier("OrderedKnee", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0.0, 0.0, -10.0))
	soldier.receive_directive(SquadDirective3D.new().configure(SquadDirective3D.Type.MOVE, 1, null, Vector3(8.0, 0.0, 0.0)))
	soldier.call("_register_autonomy_threat", hostile.global_position, hostile, 0.7, true)
	_plan(soldier)
	var operations := _autonomy_operations(soldier)
	_expect(_agent(soldier).get_current_goal() is SoldierDirectiveGoal3D,
		"A local danger reaction must not replace the squad Directive Goal")
	_expect(operations.has(SoldierAutonomyAction3D.Operation.TAKE_KNEE) \
		and operations.has(SoldierAutonomyAction3D.Operation.WAIT_FOR_OPENING) \
		and operations.has(SoldierAutonomyAction3D.Operation.RECOVER_MOVEMENT_POSTURE),
		"Nonsevere danger must insert knee, wait, and posture recovery before movement")
	_expect(not operations.has(SoldierAutonomyAction3D.Operation.DROP_PRONE),
		"Nonsevere danger must not cause routine crawling")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_directive_keeps_goal_while_inserting_cover_action() -> void:
	var soldier := await _spawn_soldier("OrderedCover", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0.0, 0.0, -12.0))
	var cover := TacticalCover3D.new()
	cover.position = Vector3(0.0, 0.0, -5.0)
	add_child(cover)
	await get_tree().physics_frame
	soldier.receive_directive(SquadDirective3D.new().configure(SquadDirective3D.Type.MOVE, 1, null, Vector3(8.0, 0.0, 0.0)))
	soldier.receive_hit(1, "body", soldier.global_position, hostile)
	_plan(soldier)
	_expect(_agent(soldier).get_current_goal() is SoldierDirectiveGoal3D,
		"A hit must replan Actions inside the existing Directive Goal")
	_expect(_autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.SEEK_COVER),
		"A hit during an order must insert emergency cover before continuing")
	_expect(_directive_operations(soldier).has(SoldierDirectiveAction3D.Operation.MOVE),
		"The original ordered movement must remain in the repaired plan")
	_pass_case()
	await _remove_nodes([soldier, hostile, cover])

func _test_directive_keeps_goal_while_inserting_prone_action() -> void:
	var soldier := await _spawn_soldier("OrderedProne", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Hostile", Soldier3D.Team.RED, Vector3(0.0, 0.0, -10.0))
	soldier.receive_directive(SquadDirective3D.new().configure(SquadDirective3D.Type.MOVE, 1, null, Vector3(8.0, 0.0, 0.0)))
	soldier.notify_near_miss(hostile.global_position, hostile)
	_plan(soldier)
	_expect(_agent(soldier).get_current_goal() is SoldierDirectiveGoal3D,
		"Severe danger must not erase the assigned Directive Goal")
	_expect(_autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.DROP_PRONE) \
		and _autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.WAIT_FOR_OPENING) \
		and _autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.RECOVER_MOVEMENT_POSTURE),
		"Open-ground severe danger must recover posture before resuming the order")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_radio_report_stays_uncertain() -> void:
	var soldier := await _spawn_soldier("Radio", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier("Reported", Soldier3D.Team.RED, Vector3(0.0, 0.0, 12.0))
	soldier.receive_squad_contact(hostile.global_position, hostile, 1.0)
	var fact := soldier.working_memory.get_best_threat()
	_plan(soldier)
	_expect(not bool(fact.get("direct", true)) and float(fact.get("confidence", 1.0)) <= 0.65,
		"A radio report must remain uncertain personal knowledge")
	_expect(not soldier.is_autonomy_goal_valid(SoldierAutonomyGoal3D.Kind.INVESTIGATE_DISTURBANCE) \
		and not _autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.RETURN_FIRE),
		"Without an order, a radio contact must not start a search or targeted fire")
	_pass_case()
	await _remove_nodes([soldier, hostile])

func _test_idle_weapon_restore() -> void:
	var soldier := await _spawn_soldier("Reload", Soldier3D.Team.BLUE, Vector3.ZERO)
	soldier.magazine_ammo = 0
	soldier.reserve_ammo = 20
	soldier._sync_dynamic_goap_state()
	_agent(soldier).request_replan()
	_plan(soldier)
	var goal := _agent(soldier).get_current_goal() as SoldierAutonomyGoal3D
	_expect(goal != null and goal.kind == SoldierAutonomyGoal3D.Kind.RESTORE_WEAPON,
		"An idle soldier may restore an empty weapon as a local maintenance goal")
	_expect(_autonomy_operations(soldier).has(SoldierAutonomyAction3D.Operation.RELOAD_SAFE),
		"Idle weapon restoration must use the safe reload Action")
	_pass_case()
	await _remove_nodes([soldier])

func _test_cover_posture_contract() -> void:
	var pair := await _spawn_visible_pair("CoverPosture")
	var soldier := pair[0] as Soldier3D
	var hostile := pair[1] as Soldier3D
	var standing_collision_center := soldier.collision.position.y
	var cover := TacticalCover3D.new()
	add_child(cover)
	await get_tree().physics_frame
	var slot := cover.reserve_slot(soldier, hostile.global_position)
	soldier.global_position = slot.global_position
	soldier.active_cover = cover
	soldier.active_cover_slot = slot
	soldier.set_cover_exposed(false)
	soldier.set_stance(Soldier3D.Stance.CROUCH)
	soldier.set_stance(Soldier3D.Stance.PRONE)
	_expect(soldier.stance == Soldier3D.Stance.STAND, "Cover hiding must not reuse ordinary crouch or prone stance")
	_expect(soldier.collision.position.y < standing_collision_center,
		"The hidden cover pose must lower collision geometry without changing ordinary stance")
	_expect(not soldier.is_autonomy_action_valid(SoldierAutonomyAction3D.Operation.DROP_PRONE),
		"GOAP must not plan a prone Action while the soldier occupies cover")
	soldier.current_target = hostile
	soldier.set("_operation_elapsed", 10.0)
	_expect(not soldier._try_attack_target(hostile), "A soldier hidden behind cover must not fire")
	_expect(soldier._perform_aim() and soldier.is_cover_exposed() and soldier.stance == Soldier3D.Stance.STAND,
		"A covered soldier must expose its standing cover pose before aiming")
	_expect(is_equal_approx(soldier.collision.position.y, standing_collision_center),
		"The exposed cover pose must restore standing collision geometry")
	soldier.fire_cycle_component.can_fire(hostile)
	soldier.fire_cycle_component.process(1.0)
	soldier.set("_cover_exposure_shots_remaining", 1)
	var ammo_before := soldier.magazine_ammo
	soldier._perform_engage()
	_expect(soldier.magazine_ammo < ammo_before, "An exposed standing soldier must be able to fire from cover")
	_expect(not soldier.is_cover_exposed() and not soldier.is_aimed,
		"A covered soldier must hide and clear aim immediately after its firing window")
	_expect(soldier.collision.position.y < standing_collision_center,
		"The covered soldier must lower its collision geometry after firing")
	var automatic_definition := {
		"id": "cover_budget_test",
		"family": "smg",
		"aim_settle_time": 0.2,
		"reload_duration": 1.0,
		"fire_interval": 0.08,
	}
	var low_pressure_total := 0
	var low_pressure_budgets := {}
	var saw_magazine_dump := false
	soldier.fire_cycle_component.configure(automatic_definition, Soldier3D.CombatRole.SMG, 4242)
	for _sample in 128:
		var budget := soldier.fire_cycle_component.roll_cover_exposure_shot_budget(24, 0.0)
		low_pressure_total += budget
		low_pressure_budgets[budget] = true
		saw_magazine_dump = saw_magazine_dump or budget == 24
	var high_pressure_total := 0
	soldier.fire_cycle_component.configure(automatic_definition, Soldier3D.CombatRole.SMG, 4242)
	for _sample in 128:
		high_pressure_total += soldier.fire_cycle_component.roll_cover_exposure_shot_budget(24, 0.85)
	_expect(low_pressure_budgets.size() > 2, "Unpinned cover fire must vary between short and longer exposure windows")
	_expect(saw_magazine_dump, "Low-pressure automatic fire must retain a small deterministic chance to empty the magazine")
	_expect(high_pressure_total < low_pressure_total,
		"Heavy suppression must shorten cover exposure windows without forcing every normal shot to retract")
	_expect(not soldier.is_autonomy_action_valid(SoldierAutonomyAction3D.Operation.BLIND_FIRE_FROM_COVER),
		"Blind fire code may remain, but GOAP must not select it yet")
	soldier.end_goap_operation(SoldierDirectiveAction3D.Operation.ENGAGE)
	_expect(not soldier.is_cover_exposed() and soldier.stance == Soldier3D.Stance.STAND,
		"A covered shooter must return to the hidden cover pose after its engage Action")
	_pass_case()
	await _remove_nodes(pair + [cover])

func _test_cover_slots_are_reserved_individually() -> void:
	var first := await _spawn_soldier("CoverA", Soldier3D.Team.BLUE, Vector3(-1.0, 0.0, 0.0))
	var second := await _spawn_soldier("CoverB", Soldier3D.Team.BLUE, Vector3(1.0, 0.0, 0.0))
	var cover := TacticalCover3D.new()
	cover.cover_length = 5.0
	add_child(cover)
	await get_tree().process_frame
	var first_slot := cover.reserve_slot(first, Vector3(0.0, 0.0, 10.0))
	var second_slot := cover.reserve_slot(second, Vector3(0.0, 0.0, 10.0))
	_expect(first_slot != null and second_slot != null and first_slot != second_slot,
		"Two soldiers must never reserve the same tactical cover slot")
	_pass_case()
	await _remove_nodes([first, second, cover])

func _test_astar_prefers_lowest_total_cost() -> void:
	var planner := GoapActionPlanner.new()
	var prepare := GoapAction.new()
	prepare.cost = 1
	prepare.effects = {&"prepared": true}
	var finish := GoapAction.new()
	finish.cost = 1
	finish.preconditions = {&"prepared": true}
	finish.effects = {&"done": true}
	var shortcut := GoapAction.new()
	shortcut.cost = 5
	shortcut.effects = {&"done": true}
	var goal := GoapGoal.new()
	goal.desired_state = {&"done": true}
	planner.set_actions([prepare, finish, shortcut])
	var plan := planner.get_plan(goal, {&"prepared": false, &"done": false})
	_expect(plan.size() == 3 and plan[0] == prepare and plan[1] == finish,
		"Forward A* must choose the lowest total-cost Action chain")
	planner.free()
	prepare.free()
	finish.free()
	shortcut.free()
	goal.free()
	_pass_case()

func _test_runtime_preconditions_are_revalidated() -> void:
	var soldier := await _spawn_soldier("Runtime", Soldier3D.Team.BLUE, Vector3.ZERO)
	var action := GoapAction.new()
	action.preconditions = {&"weapon_loaded": true}
	action.init(soldier, _agent(soldier).get_world_state())
	_agent(soldier).get_world_state().set_state(&"weapon_loaded", false)
	_expect(not action.is_valid_at_runtime(), "A live state change must invalidate a stale planned Action")
	action.free()
	_pass_case()
	await _remove_nodes([soldier])

func _spawn_visible_pair(prefix: String) -> Array:
	var soldier := await _spawn_soldier(prefix + "Soldier", Soldier3D.Team.BLUE, Vector3.ZERO)
	var hostile := await _spawn_soldier(prefix + "Hostile", Soldier3D.Team.RED, Vector3(0.0, 0.0, -8.0))
	await get_tree().physics_frame
	_expect(soldier.perception_component.can_see(hostile), "Test setup must provide a visible hostile")
	return [soldier, hostile]

func _spawn_soldier(node_name: String, team: Soldier3D.Team, position_value: Vector3) -> Soldier3D:
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	soldier.name = node_name
	soldier.combat_team = team
	soldier.awards_player_score = false
	soldier.drops_ammo_on_death = false
	soldier.position = position_value
	soldier.set_physics_process(false)
	add_child(soldier)
	await get_tree().process_frame
	return soldier

func _plan(soldier: Soldier3D) -> void:
	_agent(soldier).process(0.0)

func _agent(soldier: Soldier3D) -> GoapAgent:
	return soldier.get("_goap_agent") as GoapAgent

func _autonomy_operations(soldier: Soldier3D) -> Array[int]:
	var result: Array[int] = []
	for item in _agent(soldier).get("_current_plan") as Array:
		if item is SoldierAutonomyAction3D:
			result.append((item as SoldierAutonomyAction3D).operation)
	return result

func _directive_operations(soldier: Soldier3D) -> Array[int]:
	var result: Array[int] = []
	for item in _agent(soldier).get("_current_plan") as Array:
		if item is SoldierDirectiveAction3D:
			result.append((item as SoldierDirectiveAction3D).operation)
	return result

func _plan_contains_directive_action(soldier: Soldier3D) -> bool:
	return not _directive_operations(soldier).is_empty()

func _pass_case() -> void:
	_cases += 1

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("GOAP CASE FAILURE: %s" % message)

func _remove_nodes(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
