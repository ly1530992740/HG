extends Node

class TestCombatTarget:
	extends Node3D
	var alive := true
	func is_combat_alive() -> bool:
		return alive

var _cases := 0
var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	await _test_route_choices()
	await _test_htn_role_allocation()
	await _test_ambush_and_defense_methods()
	_test_scheduler_patch_preserves_tasks()
	_test_replan_thresholds()
	await _test_belief_scoped_influence()
	await _test_belief_forgets_freed_targets()
	await _test_utility_catalogue()
	if _failures > 0:
		push_error("SQUAD_TACTICAL_PIPELINE_FAIL cases=%d failures=%d" % [_cases, _failures])
		get_tree().quit(1)
		return
	print("SQUAD_TACTICAL_PIPELINE_PASS cases=%d" % _cases)
	get_tree().quit()

func _test_route_choices() -> void:
	await _assert_route_case(75.0, -100.0, "FLANK_LEFT", "left open, right blocked")
	await _assert_route_case(-100.0, 75.0, "FLANK_RIGHT", "right open, left blocked")
	await _assert_route_case(35.0, 80.0, "FLANK_RIGHT", "both open, right safer")
	await _assert_route_case(-100.0, -100.0, SquadUtilityEvaluator3D.DIRECT_ASSAULT, "both routes blocked")
	await _assert_confirmed_clear_route_survives_adjacent_heat()

func _assert_confirmed_clear_route_survives_adjacent_heat() -> void:
	var route := _make_zone(&"clear_route", Vector3(10.0, 0.0, 0.0))
	var belief := _belief_with_contacts([Vector3(0.0, 0.0, -20.0)], [0.9])
	belief.zone_observations[route.zone_id] = {
		"confidence": 1.0,
		"visible_contact_ids": [],
		"threat_evidence_count": 0,
	}
	var influence := SquadInfluenceMap3D.new()
	influence.configure(1.0, 42.0)
	influence.origin = Vector3.ZERO
	_set_zone_score(influence, route, -100.0)
	var snapshot := _snapshot(_standard_members(), _snapshot_contacts(belief), {
		"state": FireSuperiorityAssessment3D.State.CONTESTED,
		"pressure_ratio": 0.65,
		"suppression_ratio": 0.18,
	})
	var candidates := SquadUtilityEvaluator3D.new().build_candidates(
		snapshot, belief, [route], influence, true, true, 5.0
	)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.SUPPRESS_AND_FLANK),
		"A confirmed empty route must remain a flank option despite heat from adjacent combat")
	_pass_case()
	await _free_nodes([route])

func _assert_route_case(left_value: float, right_value: float, expected_id: String, label: String) -> void:
	var left := _make_zone(&"left", Vector3(-10.0, 0.0, 0.0))
	var right := _make_zone(&"right", Vector3(10.0, 0.0, 0.0))
	var belief := _belief_with_contacts([Vector3(0.0, 0.0, -20.0)], [0.9])
	belief.zone_observations[left.zone_id] = {"confidence": 1.0}
	belief.zone_observations[right.zone_id] = {"confidence": 1.0}
	var influence := SquadInfluenceMap3D.new()
	influence.configure(1.0, 42.0)
	influence.origin = Vector3.ZERO
	_set_zone_score(influence, left, left_value)
	_set_zone_score(influence, right, right_value)
	var snapshot := _snapshot(_standard_members(), _snapshot_contacts(belief), {
		"state": FireSuperiorityAssessment3D.State.CONTESTED,
		"pressure_ratio": 0.65,
		"suppression_ratio": 0.18,
	})
	var candidates := SquadUtilityEvaluator3D.new().build_candidates(snapshot, belief, [left, right], influence, true, true, 5.0)
	_expect(not candidates.is_empty() and String(candidates[0].get("id", "")) == expected_id,
		"Route case '%s' expected %s, got %s" % [label, expected_id, String(candidates[0].get("id", "NONE")) if not candidates.is_empty() else "NONE"])
	_pass_case()
	await _free_nodes([left, right])

func _test_htn_role_allocation() -> void:
	var zone := _make_zone(&"flank", Vector3(9.0, 0.0, 0.0))
	var belief := _belief_with_contacts([Vector3(0.0, 0.0, -18.0)], [0.9])
	var influence := SquadInfluenceMap3D.new()
	var mission := _mission()
	var members := [
		_member("MG", Soldier3D.CombatRole.MACHINE_GUNNER, 1.0, 0.8),
		_member("Wounded", Soldier3D.CombatRole.RIFLEMAN, 0.35, 0.35),
		_member("SMG", Soldier3D.CombatRole.SMG, 1.0, 0.9),
		_member("Rifle", Soldier3D.CombatRole.RIFLEMAN, 0.95, 0.8),
	]
	var snapshot := _snapshot(members, _snapshot_contacts(belief))
	var planner := SquadHtnPlanner3D.new()
	var candidate := {"id": "FLANK_FLANK", "kind": SquadUtilityEvaluator3D.SUPPRESS_AND_FLANK, "zone": zone}
	var methods := planner.build_methods(candidate, snapshot, [zone], influence)
	_expect(String(methods[0].get("id", "")) == "MG_BASE_OF_FIRE", "A healthy machine gun must anchor the base of fire")
	var plan := planner.compile(candidate, snapshot, belief, [zone], influence, mission, 1)
	var support := _task(plan, &"base_of_fire")
	var flank := _task(plan, &"flank_move")
	var synchronized_attack := _task(plan, &"synchronized_attack")
	_expect("MG" in support.recipient_ids and "Wounded" in support.recipient_ids,
		"Machine gun and wounded member must remain in the support element")
	_expect("SMG" in flank.recipient_ids and "Rifle" in flank.recipient_ids and "Wounded" not in flank.recipient_ids,
		"Only healthy mobile members should execute the flank")
	_expect(support.minimum_success_count == 1 and flank.minimum_success_count == 1 \
			and synchronized_attack.minimum_success_count == 1 and synchronized_attack.persistent \
			and synchronized_attack.successful_members_from == &"flank_move",
		"Flank HTN tasks must continue while at least one assigned member remains effective")
	_pass_case()

	var no_mg_members := [
		_member("R1", Soldier3D.CombatRole.RIFLEMAN),
		_member("R2", Soldier3D.CombatRole.RIFLEMAN),
		_member("SMG", Soldier3D.CombatRole.SMG),
		_member("Shotgun", Soldier3D.CombatRole.SHOTGUNNER),
	]
	var no_mg_snapshot := _snapshot(no_mg_members, _snapshot_contacts(belief))
	methods = planner.build_methods(candidate, no_mg_snapshot, [zone], influence)
	_expect(String(methods[0].get("id", "")) == "DISTRIBUTED_RIFLE_FIRE",
		"Two available rifles must replace an absent machine-gun base of fire")
	_pass_case()

	var positioned_members := [
		_member("FarSMG", Soldier3D.CombatRole.SMG),
		_member("NearRifle", Soldier3D.CombatRole.RIFLEMAN),
		_member("NearShotgun", Soldier3D.CombatRole.SHOTGUNNER),
		_member("SupportRifle", Soldier3D.CombatRole.RIFLEMAN),
	]
	positioned_members[0]["position"] = Vector3(-12.0, 0.0, -2.0)
	positioned_members[1]["position"] = Vector3(8.0, 0.0, 2.0)
	positioned_members[2]["position"] = Vector3(7.0, 0.0, 1.0)
	positioned_members[3]["position"] = Vector3(0.0, 0.0, 0.0)
	var positioned_plan := planner.compile(
		candidate, _snapshot(positioned_members, _snapshot_contacts(belief)),
		belief, [zone], influence, mission, 2
	)
	var positioned_flank := _task(positioned_plan, &"flank_move")
	_expect("NearRifle" in positioned_flank.recipient_ids and "NearShotgun" in positioned_flank.recipient_ids \
			and "FarSMG" not in positioned_flank.recipient_ids,
		"HTN must prefer healthy members already near the flank entry over a distant specialist")
	_pass_case()

	var replanned_members := members.duplicate(true)
	replanned_members[2]["health"] = 0.25
	replanned_members[2]["mobility"] = 0.2
	var repaired := planner.compile(candidate, _snapshot(replanned_members, _snapshot_contacts(belief)), belief, [zone], influence, mission, 2)
	var repaired_flank := _task(repaired, &"flank_move")
	_expect("SMG" not in repaired_flank.recipient_ids and "Rifle" in repaired_flank.recipient_ids,
		"An injured flanker must be removed from maneuver duty during HTN repair")
	_pass_case()

	var suppress_plan := planner.compile(
		{"id": "FIX", "kind": SquadUtilityEvaluator3D.FIX_AND_SUPPRESS},
		snapshot, belief, [zone], influence, mission, 3
	)
	_expect(not _task(suppress_plan, &"base_of_fire").persistent,
		"A standalone fix-and-suppress phase must end so reconnaissance can take over")
	_pass_case()
	await _free_nodes([zone])

func _test_ambush_and_defense_methods() -> void:
	var belief := _belief_with_contacts([Vector3(-4.0, 0.0, -18.0), Vector3(5.0, 0.0, -18.0)], [0.2, 0.25])
	var snapshot := _snapshot(_standard_members(), _snapshot_contacts(belief))
	var planner := SquadHtnPlanner3D.new()
	var influence := SquadInfluenceMap3D.new()
	var mission := _mission()
	var ambush := {"id": "AMBUSH", "kind": SquadUtilityEvaluator3D.AMBUSH}
	var methods := planner.build_methods(ambush, snapshot, [], influence)
	_expect(String(methods[0].get("id", "")) == "SYNCHRONIZED_VOLLEY", "Unaware contacts must produce a synchronized-volley method")
	var plan := planner.compile(ambush, snapshot, belief, [], influence, mission, 1)
	var aim := _task(plan, &"ambush_aim")
	var volley := _task(plan, &"ambush_volley")
	_expect(aim != null and volley != null and &"ambush_aim" in volley.depends_on,
		"Ambush fire must wait for every assigned member to finish aiming")
	_expect(aim.member_contact_ids.size() == snapshot.members.size(), "Ambush HTN must assign every shooter a target")
	_pass_case()

	snapshot.contacts[0]["awareness"] = 0.9
	methods = planner.build_methods(ambush, snapshot, [], influence)
	_expect(String(methods[0].get("id", "")) == "COMPROMISED_CONTACT_DRILL",
		"A compromised ambush must immediately become a contact drill")
	plan = planner.compile(ambush, snapshot, belief, [], influence, mission, 2)
	_expect(plan.intent == &"CONTACT_COVER", "Compromised ambush members must seek cover before fighting")
	_pass_case()

	var single_belief := _belief_with_contacts([Vector3(0.0, 0.0, -18.0)], [0.9])
	var single_snapshot := _snapshot(_standard_members(), _snapshot_contacts(single_belief))
	var defense := {"id": "DEFEND", "kind": SquadUtilityEvaluator3D.DEFEND_CONTACT}
	methods = planner.build_methods(defense, single_snapshot, [], influence)
	_expect(String(methods[0].get("id", "")) == "SINGLE_AXIS_DEFENSE", "One contact sector must use single-axis defense")
	_pass_case()

	var multi_belief := _belief_with_contacts([Vector3(0.0, 0.0, -18.0), Vector3(18.0, 0.0, 0.0)], [0.9, 0.9])
	var multi_snapshot := _snapshot(_standard_members(), _snapshot_contacts(multi_belief))
	methods = planner.build_methods(defense, multi_snapshot, [], influence)
	plan = planner.compile(defense, multi_snapshot, multi_belief, [], influence, mission, 3)
	var defend_task := _task(plan, &"defensive_fire")
	_expect(String(methods[0].get("id", "")) == "MULTI_AXIS_DEFENSE" and _unique_values(defend_task.member_contact_ids).size() == 2,
		"Multiple contact sectors must split defenders across both axes")
	_pass_case()

	var fallback := {"id": "FALLBACK", "kind": SquadUtilityEvaluator3D.FALLBACK_DEFENSE}
	plan = planner.compile(fallback, single_snapshot, single_belief, [], influence, mission, 4)
	var fallback_cover := _task(plan, &"fallback_cover")
	var fallback_defense := _task(plan, &"fallback_defense")
	_expect(fallback_cover != null and fallback_defense != null and fallback_defense.persistent \
		and &"fallback_cover" in fallback_defense.depends_on,
		"Fallback defense must enter cover once and then hold without reissuing every frame")
	_pass_case()

	var search := {"id": "SEARCH", "kind": SquadUtilityEvaluator3D.SEARCH_LAST_CONTACT}
	plan = planner.compile(search, single_snapshot, single_belief, [], influence, mission, 5)
	var search_move := _task(plan, &"search_move")
	var search_observe := _task(plan, &"search_observe")
	_expect(search_move != null and search_observe != null and search_observe.persistent \
			and &"search_move" in search_observe.depends_on,
		"Search must settle into persistent sector observation instead of completing and reissuing every frame")
	_pass_case()

func _test_scheduler_patch_preserves_tasks() -> void:
	var scheduler := SquadTaskScheduler3D.new()
	add_child(scheduler)
	var first := SquadCommandPlan3D.new().configure(&"first", &"TEST", "TEST", "", 1)
	var original := SquadTask3D.new().configure(&"hold", SquadTask3D.Type.HOLD_OBJECTIVE, PackedStringArray(["A", "B"]))
	first.add_task(original)
	_expect(scheduler.start_plan(first), "Scheduler must accept the baseline plan")
	var patch := SquadCommandPlan3D.new().configure(&"patch", &"TEST", "TEST", "", 2)
	patch.add_task(SquadTask3D.new().configure(&"hold", SquadTask3D.Type.HOLD_OBJECTIVE, PackedStringArray(["A", "B"])))
	_expect(scheduler.patch_plan(patch) and scheduler.tasks_by_id[&"hold"] == original,
		"An unchanged task must retain its object and member directive state during plan repair")
	_pass_case()

	var changed := SquadCommandPlan3D.new().configure(&"changed", &"TEST", "TEST", "", 3)
	changed.add_task(SquadTask3D.new().configure(&"hold", SquadTask3D.Type.HOLD_OBJECTIVE, PackedStringArray(["A"])))
	_expect(scheduler.patch_plan(changed) and scheduler.tasks_by_id[&"hold"] != original,
		"A changed assignment must replace only its affected task")
	_pass_case()

	var staged := SquadCommandPlan3D.new().configure(&"staged", &"TEST", "TEST", "", 4)
	var gate := SquadTask3D.new().configure(&"gate", SquadTask3D.Type.TAKE_COVER, PackedStringArray(["A"]))
	var persistent := SquadTask3D.new().configure(&"persistent", SquadTask3D.Type.SUPPRESS_CONTACT, PackedStringArray(["A"]))
	persistent.depends_on = [&"gate"]
	staged.add_task(gate)
	staged.add_task(persistent)
	_expect(scheduler.start_plan(staged), "Scheduler must accept a staged persistent plan")
	scheduler.mark_member_succeeded(&"gate", &"A")
	scheduler.mark_member_ready(&"persistent", &"A")
	_expect(scheduler.active_plan == staged and persistent.state == SquadTask3D.State.READY,
		"A persistent READY task must keep its plan active while exposing dependency readiness")
	_pass_case()

	var resilient := SquadCommandPlan3D.new().configure(&"resilient", &"TEST", "TEST", "", 5)
	var resilient_fire := SquadTask3D.new().configure(
		&"resilient_fire", SquadTask3D.Type.SUPPRESS_CONTACT, PackedStringArray(["A", "B"])
	)
	resilient_fire.minimum_success_count = 1
	resilient.add_task(resilient_fire)
	_expect(scheduler.start_plan(resilient), "Scheduler must accept a casualty-tolerant support task")
	scheduler.mark_member_ready(&"resilient_fire", &"A")
	scheduler.mark_member_ready(&"resilient_fire", &"B")
	scheduler.mark_member_failed(&"resilient_fire", &"A")
	_expect(resilient_fire.state == SquadTask3D.State.READY,
		"A support casualty must not fail the task while its minimum effective strength remains")
	_pass_case()

	var inherited := SquadCommandPlan3D.new().configure(&"inherited", &"TEST", "TEST", "", 6)
	var maneuver := SquadTask3D.new().configure(
		&"maneuver", SquadTask3D.Type.FLANK_ZONE, PackedStringArray(["A", "B"])
	)
	maneuver.minimum_success_count = 1
	var assault := SquadTask3D.new().configure(
		&"assault", SquadTask3D.Type.ATTACK_CONTACT, PackedStringArray(["A", "B"])
	)
	assault.depends_on = [&"maneuver"]
	assault.successful_members_from = &"maneuver"
	inherited.add_task(maneuver)
	inherited.add_task(assault)
	_expect(scheduler.start_plan(inherited), "Scheduler must accept successful-member inheritance")
	scheduler.mark_member_succeeded(&"maneuver", &"A")
	_expect(assault.state == SquadTask3D.State.ACTIVE and assault.recipient_ids == PackedStringArray(["A"]),
		"A dependent assault must include only maneuver members that actually reached the objective")
	_pass_case()
	scheduler.queue_free()

func _test_replan_thresholds() -> void:
	var policy := SquadReplanPolicy3D.new()
	policy.reset_commitment(1000)
	var current := {"id": "HOLD", "utility": 80.0}
	var challenger := {"id": "FLANK", "utility": 110.0}
	var candidates: Array[Dictionary] = [challenger, current]
	_expect(not policy.should_apply(current, candidates, "HOLD", SquadReplanPolicy3D.Level.NONE, true, 3000),
		"Minor battlefield updates must not restart Utility")
	_expect(not policy.should_apply(current, candidates, "HOLD", SquadReplanPolicy3D.Level.PLAN_REPAIR, true, 3000),
		"Plan repair must preserve a still-valid HTN plan with the same tactic")
	_expect(not policy.should_apply(challenger, candidates, "HOLD", SquadReplanPolicy3D.Level.PLAN_REPAIR, true, 3000),
		"A noncritical challenger must respect the tactic commitment window")
	_expect(policy.should_apply({"id": "WITHDRAW", "utility": 81.0}, [{"id": "WITHDRAW", "utility": 81.0}, current], "HOLD", SquadReplanPolicy3D.Level.FULL_TACTIC, true, 3000),
		"Major casualties or objective changes must bypass commitment and score margin")
	_pass_case()

	policy.reset_commitment(1000)
	_expect(not policy.should_apply(challenger, candidates, "HOLD", SquadReplanPolicy3D.Level.PLAN_REPAIR, true, 9000),
		"A better tactic must remain stable before replacing a committed plan")
	_expect(policy.should_apply(challenger, candidates, "HOLD", SquadReplanPolicy3D.Level.PLAN_REPAIR, true, 10300),
		"A materially better stable tactic may replace a plan after its commitment window")
	_pass_case()

	policy.reset_commitment(1000)
	var recover := {"id": SquadUtilityEvaluator3D.RECOVER_IN_COVER, "utility": 180.0}
	var flank := {"id": "FLANK_RIGHT", "utility": 110.0}
	_expect(not policy.should_apply(recover, [recover, flank], "FLANK_RIGHT", SquadReplanPolicy3D.Level.PLAN_REPAIR, true, 20000),
		"Local suppression must not cancel a committed squad flank")
	_expect(policy.should_apply(recover, [recover, flank], "FLANK_RIGHT", SquadReplanPolicy3D.Level.FULL_TACTIC, true, 20000),
		"A failed flank or major tactical change must still permit replacement")
	_pass_case()

	policy.reset_commitment(1000)
	var recon := {"id": SquadUtilityEvaluator3D.RECON_SPLIT, "utility": 90.0}
	_expect(not policy.should_apply(recover, [recover, recon], SquadUtilityEvaluator3D.RECON_SPLIT,
		SquadReplanPolicy3D.Level.PLAN_REPAIR, true, 20000),
		"Local pressure must not cancel an assigned reconnaissance task")
	_pass_case()

	var damage := SquadContactReport3D.new()
	damage.stimulus = SquadContactReport3D.Stimulus.DAMAGE
	_expect(policy.classify_report(damage, 2, 2) == SquadReplanPolicy3D.Level.LOCAL_ACTION,
		"A nonfatal wound must trigger local GOAP response without rebuilding the HTN assignment")
	_pass_case()

	var near_miss := SquadContactReport3D.new()
	near_miss.stimulus = SquadContactReport3D.Stimulus.NEAR_MISS
	_expect(policy.classify_report(near_miss, 2, 2) == SquadReplanPolicy3D.Level.LOCAL_ACTION,
		"Near misses must only replan individual safety Actions")
	_pass_case()

func _test_belief_scoped_influence() -> void:
	var left_belief := _belief_with_contacts([Vector3(-6.0, 0.0, 0.0)], [0.9])
	var right_belief := _belief_with_contacts([Vector3(6.0, 0.0, 0.0)], [0.9])
	var left_map := SquadInfluenceMap3D.new()
	var right_map := SquadInfluenceMap3D.new()
	left_map.configure(3.0, 15.0)
	right_map.configure(3.0, 15.0)
	left_map.rebuild(left_belief, [], [], [], Vector3.ZERO, Vector3.ZERO)
	right_map.rebuild(right_belief, [], [], [], Vector3.ZERO, Vector3.ZERO)
	_expect(float(left_map.sample(Vector3(-6.0, 0.0, 0.0)).get(SquadInfluenceMap3D.LAYER_ENEMY_THREAT, 0.0)) \
		> float(right_map.sample(Vector3(-6.0, 0.0, 0.0)).get(SquadInfluenceMap3D.LAYER_ENEMY_THREAT, 0.0)),
		"Each squad influence map must contain only contacts in that squad's belief")
	_pass_case()

	var threat_report := SquadContactReport3D.new().configure_contact(
		null, null, Vector3(2.0, 0.0, 1.0), 0.8, SquadContactReport3D.Stimulus.GUNSHOT
	)
	left_belief.merge_report(threat_report)
	_expect(left_belief.has_recent_threat_in_radius(Vector3.ZERO, 4.0) \
			and not left_belief.has_recent_threat_in_radius(Vector3(20.0, 0.0, 0.0), 4.0),
		"Recent anonymous fire must block a false objective-clear state only in its reported area")
	_pass_case()

func _test_belief_forgets_freed_targets() -> void:
	var target := TestCombatTarget.new()
	add_child(target)
	var belief := SquadBeliefState3D.new()
	var contact := CombatContact3D.new()
	contact.contact_id = &"freed_target"
	contact.target_ref = weakref(target)
	contact.last_report_msec = Time.get_ticks_msec()
	contact.confidence = 1.0
	belief.contacts[contact.contact_id] = contact
	_expect(belief.get_living_contacts().size() == 1, "A live referenced target must remain in squad belief")
	target.queue_free()
	await get_tree().process_frame
	_expect(belief.get_living_contacts().is_empty(),
		"A freed target must not become an imaginary living contact for the rest of memory time")
	_pass_case()

func _test_utility_catalogue() -> void:
	var utility := SquadUtilityEvaluator3D.new()
	var influence := SquadInfluenceMap3D.new()
	var no_enemy := SquadBeliefState3D.new()
	var snapshot := _snapshot(_standard_members(), [])
	snapshot.enemy_count = 0
	var candidates := utility.build_candidates(snapshot, no_enemy, [], influence, true, true, 0.0)
	_expect(String(candidates[0].get("kind", "")) == "MISSION_MOVE", "No contact must continue the configured mission")
	_pass_case()

	var belief := _belief_with_contacts([Vector3(0.0, 0.0, -15.0)], [0.2])
	snapshot = _snapshot(_standard_members(), _snapshot_contacts(belief), {
		"state": FireSuperiorityAssessment3D.State.CONTESTED, "pressure_ratio": 1.0, "suppression_ratio": 0.0})
	candidates = utility.build_candidates(snapshot, belief, [], influence, false, false, 0.0)
	_expect(String(candidates[0].get("kind", "")) == "CONTACT_COVER", "First confirmed contact must force the contact-cover drill")
	_pass_case()

	candidates = utility.build_candidates(snapshot, belief, [], influence, true, true, 4.0)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.AMBUSH), "Unaware enemies must expose an ambush option")
	_pass_case()

	var unknown_route := _make_zone(&"unknown_route", Vector3(8.0, 0.0, 0.0))
	candidates = utility.build_candidates(snapshot, belief, [unknown_route], influence, true, false, 4.0)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.RECON_SPLIT) \
		and not _has_kind(candidates, SquadUtilityEvaluator3D.BOUNDING_ADVANCE),
		"An unknown flank must be reconnoitered before a bounding advance")
	_pass_case()
	await _free_nodes([unknown_route])

	var observed_route := _make_zone(&"observed_route", Vector3(-8.0, 0.0, 0.0))
	var pending_route := _make_zone(&"pending_route", Vector3(8.0, 0.0, 0.0))
	belief.zone_observations[observed_route.zone_id] = {
		"visible_contact_ids": [], "threat_evidence_count": 0, "confidence": 1.0,
	}
	candidates = utility.build_candidates(snapshot, belief, [observed_route, pending_route], influence, true, false, 4.0)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.RECON_SPLIT) \
		and not _has_kind(candidates, SquadUtilityEvaluator3D.SUPPRESS_AND_FLANK),
		"A partially observed route set must finish reconnaissance before committing a flank")
	_pass_case()
	await _free_nodes([observed_route, pending_route])

	snapshot.contacts[0]["visible"] = false
	candidates = utility.build_candidates(snapshot, belief, [], influence, true, true, 4.0)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.SEARCH_LAST_CONTACT), "Lost visual contact must expose a bounded search option")
	_pass_case()

	for member in snapshot.members:
		member["ammo"] = 0.1
	candidates = utility.build_candidates(snapshot, belief, [], influence, true, true, 4.0)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.CONSOLIDATE), "Low ammunition must expose consolidation")
	_pass_case()

	snapshot.fire_assessment = {"state": FireSuperiorityAssessment3D.State.LOSING, "pressure_ratio": 0.35, "suppression_ratio": 0.62}
	for member in snapshot.members:
		member["health"] = 0.4
	candidates = utility.build_candidates(snapshot, belief, [], influence, true, true, 4.0)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.RECOVER_IN_COVER) and _has_kind(candidates, SquadUtilityEvaluator3D.BREAK_CONTACT),
		"Pinned, depleted squads must expose recovery and break-contact options")
	_pass_case()

	snapshot.mission_state = SquadMissionController3D.State.HOLDING
	snapshot.contacts.append({"position": Vector3(15.0, 0.0, 0.0), "visible": true, "awareness": 0.9})
	snapshot.enemy_count = 2
	candidates = utility.build_candidates(snapshot, belief, [], influence, true, true, 4.0)
	_expect(_has_kind(candidates, SquadUtilityEvaluator3D.COUNTER_FLANK), "Defenders under multi-axis contact must expose counter-flank defense")
	_pass_case()

func _snapshot(members: Array, contacts: Array, assessment := {}) -> SquadDecisionSnapshot3D:
	return SquadDecisionSnapshot3D.from_facts({
		"mission_type": SquadMissionController3D.MissionType.CAPTURE_AND_HOLD,
		"mission_state": SquadMissionController3D.State.CLEARING,
		"mission_target": Vector3(0.0, 0.0, -20.0),
		"mission_radius": 12.0,
		"squad_center": Vector3.ZERO,
		"enemy_count": contacts.size(),
		"enemy_power": float(contacts.size()),
		"members": members,
		"contacts": contacts,
		"fire_assessment": assessment if not assessment.is_empty() else {
			"state": FireSuperiorityAssessment3D.State.CONTESTED,
			"pressure_ratio": 1.0,
			"suppression_ratio": 0.0,
		},
	})

func _standard_members() -> Array:
	return [
		_member("R1", Soldier3D.CombatRole.RIFLEMAN),
		_member("R2", Soldier3D.CombatRole.RIFLEMAN),
		_member("SMG", Soldier3D.CombatRole.SMG),
		_member("Shotgun", Soldier3D.CombatRole.SHOTGUNNER),
	]

func _member(id: String, role: int, health := 1.0, mobility := 0.8) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "role": role, "health": health, "mobility": mobility,
		"suppression": 0.0, "pinned": false, "ammo": 0.8, "loaded": true, "covered": true,
		"combat_power": 1.0, "leader": id == "R1"}

func _belief_with_contacts(positions: Array, awareness: Array) -> SquadBeliefState3D:
	var belief := SquadBeliefState3D.new()
	for index in positions.size():
		var contact := CombatContact3D.new()
		contact.contact_id = StringName("enemy_%d" % index)
		contact.last_known_position = positions[index] as Vector3
		contact.last_report_msec = Time.get_ticks_msec()
		contact.confidence = 1.0
		contact.currently_visible = true
		contact.estimated_role = Soldier3D.CombatRole.RIFLEMAN
		contact.estimated_firepower = 1.0
		contact.enemy_awareness_probability = float(awareness[index])
		belief.contacts[contact.contact_id] = contact
	return belief

func _snapshot_contacts(belief: SquadBeliefState3D) -> Array:
	var result := []
	for contact in belief.get_living_contacts():
		result.append({"id": String(contact.contact_id), "position": contact.last_known_position,
			"confidence": 1.0, "visible": contact.currently_visible, "firepower": contact.estimated_firepower,
			"role": contact.estimated_role, "awareness": contact.enemy_awareness_probability, "age": 0.0})
	return result

func _mission() -> SquadMissionController3D:
	var result := SquadMissionController3D.new()
	result.configure(SquadMissionController3D.MissionType.CAPTURE_AND_HOLD, Vector3(0.0, 0.0, -20.0), 12.0, Vector3.ZERO, 1.0, 2.0)
	result.state = SquadMissionController3D.State.CLEARING
	return result

func _make_zone(id: StringName, position_value: Vector3) -> TacticalZone3D:
	var zone := TacticalZone3D.new()
	zone.zone_id = id
	zone.position = position_value
	zone.show_zone = false
	add_child(zone)
	return zone

func _set_zone_score(influence: SquadInfluenceMap3D, zone: TacticalZone3D, value: float) -> void:
	var threat := maxf(0.0, -value)
	var cover := maxf(0.0, value)
	for position in [
		zone.global_position,
		zone.get_observation_point(Vector3.ZERO),
		zone.to_global(Vector3(zone.size.x * 0.3, 0.0, 0.0)),
		zone.to_global(Vector3(-zone.size.x * 0.3, 0.0, 0.0)),
		zone.to_global(Vector3(0.0, 0.0, zone.size.y * 0.3)),
		zone.to_global(Vector3(0.0, 0.0, -zone.size.y * 0.3)),
	]:
		var key := Vector2i(roundi(position.x / influence.cell_size), roundi(position.z / influence.cell_size))
		influence.cells[key] = {
			SquadInfluenceMap3D.LAYER_ENEMY_THREAT: threat,
			SquadInfluenceMap3D.LAYER_COVER: cover,
		}

func _task(plan: SquadCommandPlan3D, id: StringName) -> SquadTask3D:
	if plan == null:
		return null
	for task in plan.tasks:
		if task.task_id == id:
			return task
	return null

func _has_kind(candidates: Array[Dictionary], kind: String) -> bool:
	return candidates.any(func(candidate: Dictionary): return String(candidate.get("kind", "")) == kind)

func _unique_values(values: Dictionary) -> Dictionary:
	var result := {}
	for value in values.values():
		result[value] = true
	return result

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TACTICAL PIPELINE CASE FAILURE: %s" % message)

func _pass_case() -> void:
	_cases += 1

func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
