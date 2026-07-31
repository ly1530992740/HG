extends Node
class_name SquadAdvancedTactics3D

const CONTACT_EPISODE_RESET_MSEC := 30000

signal belief_report_accepted(report: SquadContactReport3D)
signal tactical_candidates_evaluated(candidates: Array[Dictionary], selected_id: String)
signal mission_state_changed(state_name: String)

var coordinator: SquadCoordinator3D
var belief := SquadBeliefState3D.new()
var mission := SquadMissionController3D.new()
var utility := SquadUtilityEvaluator3D.new()
var htn := SquadHtnPlanner3D.new()
var influence := SquadInfluenceMap3D.new()
var replan_policy := SquadReplanPolicy3D.new()
var fire_superiority := FireSuperiorityAssessment3D.new()
var scheduler: SquadTaskScheduler3D
var dispatcher: SquadDirectiveDispatcher3D
var zones: Array[TacticalZone3D] = []

var _pending_reports: Array[Dictionary] = []
var _pending_zone_observations: Dictionary = {}
var _persistent_redispatches: Dictionary = {}
var _last_queued_report: Dictionary = {}
var _directive_bindings: Dictionary = {}
var _evaluation_timer := 0.0
var _force_evaluation := true
var _plan_sequence := 0
var _active_intent: StringName = &""
var _active_candidate_id := ""
var _contact_started_msec := 0
var _last_contact_report_msec := 0
var _contact_cover_complete := false
var _recon_complete := false
var _qwen_context_version := 1
var _qwen_context_signature := ""
var _rng := RandomNumberGenerator.new()
var _last_fire_assessment: Dictionary = {}
var _last_candidates: Array[Dictionary] = []
var _last_selected_candidate_id := ""
var _influence_timer := 0.0
var _pending_replan_level: SquadReplanPolicy3D.Level = SquadReplanPolicy3D.Level.FULL_TACTIC
var _last_decision_snapshot: SquadDecisionSnapshot3D

func configure(owner_coordinator: SquadCoordinator3D) -> void:
	coordinator = owner_coordinator
	_rng.seed = hash(String(coordinator.squad_id))
	scheduler = SquadTaskScheduler3D.new()
	scheduler.name = "TaskScheduler3D"
	add_child(scheduler)
	dispatcher = SquadDirectiveDispatcher3D.new()
	dispatcher.name = "DirectiveDispatcher3D"
	add_child(dispatcher)
	dispatcher.configure(coordinator, belief)
	scheduler.task_activated.connect(dispatcher.dispatch)
	dispatcher.directive_bound.connect(_on_directive_bound)
	dispatcher.task_member_ready.connect(scheduler.mark_member_ready)
	dispatcher.task_member_succeeded.connect(scheduler.mark_member_succeeded)
	dispatcher.task_member_failed.connect(_on_task_member_failed)
	scheduler.plan_completed.connect(_on_plan_completed)
	scheduler.task_state_changed.connect(_on_task_state_changed)
	mission.state_changed.connect(_on_mission_state_changed)
	influence.configure(3.0, 42.0)
	for member in coordinator.get_configured_member_actors():
		member.set_squad_influence_map(influence)
	call_deferred("_finish_configuration")

func _finish_configuration() -> void:
	refresh_tactical_environment()
	refresh_mission_configuration()
	_force_evaluation = true

func refresh_tactical_environment() -> void:
	zones.clear()
	for node in get_tree().get_nodes_in_group("tactical_zone3d"):
		if node is TacticalZone3D:
			zones.append(node as TacticalZone3D)
	for member in coordinator.get_configured_member_actors():
		member.set_squad_influence_map(influence)

func refresh_mission_configuration() -> void:
	if coordinator == null:
		return
	mission.configure(
		coordinator.mission_type,
		coordinator.get_mission_target_position(),
		coordinator.mission_radius,
		coordinator.get_squad_center(),
		coordinator.mission_clear_confirmation_seconds,
		coordinator.mission_return_radius
	)
	_force_evaluation = true

func process(delta: float) -> void:
	_process_reports()
	_monitor_persistent_redispatches()
	_monitor_recon_tasks()
	_monitor_cover_tasks()
	belief.update(delta)
	var recent_identified_contact := _last_contact_report_msec > 0 \
			and Time.get_ticks_msec() - _last_contact_report_msec < int(belief.contact_memory_seconds * 1000.0)
	var unresolved_contact: bool = _contact_started_msec > 0 and (
		not _recon_complete or not belief.get_living_contacts(0.05).is_empty() \
				or recent_identified_contact \
				or belief.has_recent_threat_in_radius(mission.target_position, mission.target_radius)
	)
	mission.update(
		delta,
		coordinator.get_squad_center(),
		belief.has_known_hostile_in_radius(mission.target_position, mission.target_radius) or unresolved_contact
	)
	_influence_timer -= delta
	if _influence_timer <= 0.0:
		_influence_timer = 0.25
		_rebuild_influence()
	_evaluation_timer -= delta
	if _force_evaluation or _evaluation_timer <= 0.0:
		_force_evaluation = false
		_evaluation_timer = coordinator.evaluation_interval
		_evaluate()

func queue_perception_report(observer: Soldier3D, hostile: Node3D, position: Vector3, confidence: float, stimulus_name: StringName) -> void:
	if observer == null or not coordinator.is_member(observer):
		return
	if hostile != null and not observer.is_hostile_target(hostile):
		return
	var stimulus := _stimulus_from_name(stimulus_name)
	var contact_key := "anonymous_%s" % stimulus_name
	if hostile != null:
		contact_key = "contact_%d" % hostile.get_instance_id()
	var throttle_key := "%s:%s:%s" % [observer.name, contact_key, stimulus_name]
	var now := Time.get_ticks_msec()
	if now - int(_last_queued_report.get(throttle_key, -100000)) < (700 if stimulus == SquadContactReport3D.Stimulus.VISUAL else 350):
		return
	_last_queued_report[throttle_key] = now
	var report := SquadContactReport3D.new().configure_contact(observer, hostile, position, confidence, stimulus)
	var delay := _rng.randf_range(coordinator.contact_report_delay_min, coordinator.contact_report_delay_max)
	_pending_reports.append({"report": report, "deliver_at": now + int(delay * 1000.0)})

func get_debug_snapshot() -> Dictionary:
	return {
		"physics_frame": Engine.get_physics_frames(),
		"captured_msec": Time.get_ticks_msec(),
		"mission_state": mission.get_state_name(),
		"active_intent": String(_active_intent),
		"candidate_id": _active_candidate_id,
		"belief": belief.make_tactical_snapshot(zones),
		"tasks": scheduler.get_summary(),
		"fire_superiority": _last_fire_assessment.duplicate(true),
		"influence_version": influence.version,
		"htn_method": htn.last_selected_method,
		"htn_methods": htn.last_method_scores.duplicate(true),
		"candidates": _make_candidate_debug(_last_candidates),
		"selected_candidate": _last_selected_candidate_id,
		"active_tasks": _make_task_debug(),
		"replan_level": SquadReplanPolicy3D.Level.keys()[_pending_replan_level],
	}

func build_debug_analysis_preview() -> Dictionary:
	if coordinator == null:
		return {}
	refresh_tactical_environment()
	_rebuild_influence()
	var assessment := fire_superiority.assess(coordinator.get_living_members(), belief.get_estimated_enemy_count())
	var snapshot := SquadDecisionSnapshot3D.capture(belief, mission, coordinator.get_living_members(), assessment)
	var contact_elapsed := 0.0 if _contact_started_msec <= 0 else float(Time.get_ticks_msec() - _contact_started_msec) / 1000.0
	var candidates := utility.build_candidates(
		snapshot,
		belief,
		zones,
		influence,
		_contact_cover_complete,
		_recon_complete,
		contact_elapsed
	)
	var selected: Dictionary = candidates[0] if not candidates.is_empty() else {}
	var preview_plan: SquadCommandPlan3D
	if not selected.is_empty():
		preview_plan = htn.compile(selected, snapshot, belief, zones, influence, mission, _plan_sequence + 1)
	return {
		"physics_frame": Engine.get_physics_frames(),
		"captured_msec": Time.get_ticks_msec(),
		"mission_state": mission.get_state_name(),
		"belief": belief.make_tactical_snapshot(zones),
		"fire_superiority": assessment.duplicate(true),
		"candidates": _make_candidate_debug(candidates),
		"selected_candidate": String(selected.get("id", "")),
		"htn_method": htn.last_selected_method,
		"htn_methods": htn.last_method_scores.duplicate(true),
		"preview_tasks": _make_plan_task_debug(preview_plan),
		"active_tasks": _make_task_debug(),
		"influence_version": influence.version,
	}

func _make_candidate_debug(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate in candidates:
		var zone := candidate.get("zone") as TacticalZone3D
		result.append({
			"id": String(candidate.get("id", "")),
			"kind": String(candidate.get("kind", "")),
			"utility": float(candidate.get("utility", 0.0)),
			"reason": String(candidate.get("reason", "")),
			"zone": String(zone.zone_id) if zone != null else "",
		})
	return result

func _make_task_debug() -> Array[Dictionary]:
	return _make_plan_task_debug(scheduler.active_plan if scheduler != null else null)

func _make_plan_task_debug(plan: SquadCommandPlan3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if plan == null:
		return result
	for task_value in plan.tasks:
		var task := task_value as SquadTask3D
		if task == null:
			continue
		result.append({
			"id": String(task.task_id),
			"type": task.get_type_name(),
			"state": task.get_state_name(),
			"members": Array(task.recipient_ids),
			"zone": String(task.zone_id),
			"depends_on": task.depends_on.map(func(value: StringName): return String(value)),
			"reason": task.reason,
		})
	return result

func get_qwen_context_version() -> int:
	return _qwen_context_version

func get_qwen_snapshot() -> Dictionary:
	var member_facts: Array[Dictionary] = []
	for member in coordinator.get_living_members():
		member_facts.append({
			"id": String(member.name),
			"role": Soldier3D.CombatRole.keys()[member.combat_role],
			"health_ratio": snappedf(float(member.health) / maxf(1.0, float(member.max_health)), 0.05),
			"suppression_ratio": snappedf(member.get_suppression_ratio(), 0.05),
		})
	return {
		"context_version": _qwen_context_version,
		"mission": {"type": mission.get_mission_type_name(), "state": mission.get_state_name()},
		"squad": {"id": String(coordinator.squad_id), "members": member_facts},
		"belief": belief.make_tactical_snapshot(zones),
	}

func get_zone_by_id(zone_id: StringName) -> TacticalZone3D:
	for zone in zones:
		if zone.zone_id == zone_id:
			return zone
	return null

func _process_reports() -> void:
	var now := Time.get_ticks_msec()
	for pending in _pending_reports.duplicate():
		if now < int(pending.get("deliver_at", 0)):
			continue
		_pending_reports.erase(pending)
		var report := pending.get("report") as SquadContactReport3D
		if report == null or not is_instance_valid(report.get_observer()) or report.get_observer().dead:
			continue
		var previous_contact_count := belief.get_estimated_enemy_count()
		var previous_sector_count := _known_contact_sector_count()
		belief.merge_report(report)
		belief_report_accepted.emit(report)
		coordinator.share_contact_report(report.get_observer(), report.get_target(), report.position, report.confidence)
		if report.stimulus != SquadContactReport3D.Stimulus.ZONE_OBSERVED:
			var best := belief.get_best_contact()
			coordinator.known_target = best.get_target() if best != null else null
			var next_contact_count := belief.get_estimated_enemy_count()
			var replan_level := replan_policy.classify_report(report, previous_contact_count, next_contact_count)
			if mission.is_defense_locked() and previous_contact_count > 0 \
				and _known_contact_sector_count() > previous_sector_count:
				replan_level = SquadReplanPolicy3D.Level.FULL_TACTIC
			_request_replan(replan_level)
			var starts_new_contact_episode := _contact_started_msec <= 0 \
					or _last_contact_report_msec <= 0 \
					or now - _last_contact_report_msec >= CONTACT_EPISODE_RESET_MSEC
			if previous_contact_count == 0 and next_contact_count > 0 and starts_new_contact_episode:
				_contact_started_msec = now
				_contact_cover_complete = false
				_recon_complete = false
			if report.get_target() != null and next_contact_count > 0:
				_last_contact_report_msec = now
			_try_complete_recon_from_contact(report)
		if report.stimulus == SquadContactReport3D.Stimulus.ZONE_OBSERVED:
			_pending_zone_observations.erase(report.zone_id)
			_recon_complete = _all_recon_zones_observed()
			# Route utility must use the observation that triggered this tactical replan.
			_rebuild_influence()
			_influence_timer = 0.25
			if _recon_complete:
				_request_replan(SquadReplanPolicy3D.Level.FULL_TACTIC)
				# Let delayed reports and the influence map settle before committing the route choice.
				_force_evaluation = false
				_evaluation_timer = 0.8
			else:
				_request_replan(SquadReplanPolicy3D.Level.PLAN_REPAIR)

func _evaluate() -> void:
	if coordinator.get_configured_member_actors().is_empty():
		return
	if not _pending_zone_observations.is_empty():
		return
	var contact_elapsed := 0.0 if _contact_started_msec <= 0 else float(Time.get_ticks_msec() - _contact_started_msec) / 1000.0
	_last_fire_assessment = fire_superiority.assess(coordinator.get_living_members(), belief.get_estimated_enemy_count())
	_last_decision_snapshot = SquadDecisionSnapshot3D.capture(belief, mission, coordinator.get_living_members(), _last_fire_assessment)
	var candidates := utility.build_candidates(
		_last_decision_snapshot,
		belief,
		zones,
		influence,
		_contact_cover_complete,
		_recon_complete,
		contact_elapsed
	)
	_last_candidates = candidates.duplicate(true)
	if candidates.is_empty():
		_last_selected_candidate_id = ""
		return
	_update_qwen_context(candidates)
	var selected: Dictionary = candidates[0]
	_last_selected_candidate_id = String(selected.get("id", ""))
	tactical_candidates_evaluated.emit(candidates, String(selected.get("id", "")))
	var level := _pending_replan_level
	_pending_replan_level = SquadReplanPolicy3D.Level.NONE
	var active_plan := scheduler.active_plan != null
	if active_plan and _active_plan_has_failed_task():
		level = SquadReplanPolicy3D.Level.FULL_TACTIC
	var immediate_contact_drill := String(selected.get("kind", "")) == "CONTACT_COVER"
	var should_apply := false
	if immediate_contact_drill:
		should_apply = not active_plan or _active_candidate_id != "CONTACT_COVER" or _active_plan_has_failed_task()
	else:
		should_apply = replan_policy.should_apply(
			selected, candidates, _active_candidate_id, level, active_plan, Time.get_ticks_msec()
		)
	if should_apply:
		_apply_candidate(selected, "UTILITY", "", active_plan and String(selected.get("id", "")) == _active_candidate_id)
	coordinator.request_advanced_candidate(
		get_qwen_snapshot(), candidates, String(selected.get("id", "")), _qwen_context_version
	)

func apply_qwen_candidate(candidate_id: String, reason: String) -> bool:
	_last_fire_assessment = fire_superiority.assess(coordinator.get_living_members(), belief.get_estimated_enemy_count())
	var snapshot := SquadDecisionSnapshot3D.capture(belief, mission, coordinator.get_living_members(), _last_fire_assessment)
	var candidates := utility.build_candidates(
		snapshot, belief, zones, influence,
		_contact_cover_complete, _recon_complete,
		0.0 if _contact_started_msec <= 0 else float(Time.get_ticks_msec() - _contact_started_msec) / 1000.0
	)
	for candidate in candidates:
		if String(candidate.get("id", "")) == candidate_id:
			_apply_candidate(candidate, "LOCAL_QWEN", reason)
			return true
	return false

func _apply_candidate(candidate: Dictionary, source: String, reason_override := "", patch_existing := false) -> void:
	var candidate_id := String(candidate.get("id", ""))
	var kind := StringName(candidate.get("kind", ""))
	if candidate_id == _active_candidate_id and scheduler.active_plan != null and not patch_existing:
		return
	_plan_sequence += 1
	var snapshot := _last_decision_snapshot
	if snapshot == null:
		snapshot = SquadDecisionSnapshot3D.capture(belief, mission, coordinator.get_living_members(), _last_fire_assessment)
	var plan := htn.compile(candidate, snapshot, belief, zones, influence, mission, _plan_sequence)
	if plan == null:
		return
	if not reason_override.is_empty():
		plan.reason = reason_override
	plan.source = source
	var accepted := scheduler.patch_plan(plan) if patch_existing else scheduler.start_plan(plan)
	if not accepted:
		return
	_active_candidate_id = candidate_id
	_active_intent = kind
	coordinator.current_plan = String(kind)
	coordinator.current_stage = 1
	coordinator.last_command_source = source
	coordinator.last_command_summary = "%s | %s" % [candidate_id, plan.reason]
	coordinator.command_changed.emit(coordinator.current_plan, coordinator.last_command_summary, source)
	replan_policy.note_applied()
	print("[TACTICAL3D_PLAN] squad=%s mission=%s belief=%d candidate=%s source=%s" % [
		coordinator.squad_display_name, mission.get_state_name(), belief.version, candidate_id, source
	])

func _on_directive_bound(task_id: StringName, member_id: StringName, directive_version: int) -> void:
	_directive_bindings["%s:%d" % [member_id, directive_version]] = {"task_id": task_id, "member_id": member_id}

func on_member_directive_completed(member: Soldier3D, directive: SquadDirective3D) -> void:
	var key := "%s:%d" % [member.name, directive.version]
	var binding: Dictionary = _directive_bindings.get(key, {})
	if binding.is_empty():
		return
	_directive_bindings.erase(key)
	var task_id := StringName(binding.get("task_id", ""))
	var task := scheduler.tasks_by_id.get(task_id) as SquadTask3D
	if task != null and task.type == SquadTask3D.Type.RECON_ZONE:
		_queue_zone_observation(member, task.zone_id)
	if task != null and task.persistent:
		scheduler.mark_member_ready(task_id, StringName(member.name))
		_queue_persistent_redispatch(task, member)
		return
	scheduler.mark_member_succeeded(task_id, StringName(member.name))

func _queue_persistent_redispatch(task: SquadTask3D, member: Soldier3D) -> void:
	if task == null or member == null or task.type == SquadTask3D.Type.HOLD_OBJECTIVE:
		return
	var key := "%s:%s" % [task.task_id, member.name]
	_persistent_redispatches[key] = {
		"task": task,
		"member_id": StringName(member.name),
		"due_at": Time.get_ticks_msec() + _rng.randi_range(250, 600),
	}

func _monitor_persistent_redispatches() -> void:
	if scheduler == null:
		_persistent_redispatches.clear()
		return
	var now := Time.get_ticks_msec()
	for key in _persistent_redispatches.keys():
		var pending: Dictionary = _persistent_redispatches.get(key, {})
		if now < int(pending.get("due_at", 0)):
			continue
		_persistent_redispatches.erase(key)
		var task := pending.get("task") as SquadTask3D
		var member_id := StringName(pending.get("member_id", ""))
		if task == null or scheduler.tasks_by_id.get(task.task_id) != task \
				or task.state not in [SquadTask3D.State.ACTIVE, SquadTask3D.State.READY]:
			continue
		var member := coordinator.get_member_by_id(String(member_id))
		if member == null or member.dead or (member.active_directive != null \
				and member.active_directive.version > member.last_completed_directive_version):
			continue
		dispatcher.redispatch_persistent_member(task, member)

func on_member_died(member: Soldier3D) -> void:
	var active_task_failed := false
	for task in scheduler.tasks_by_id.values():
		if String(member.name) in (task as SquadTask3D).recipient_ids:
			scheduler.mark_member_failed((task as SquadTask3D).task_id, StringName(member.name))
			active_task_failed = active_task_failed or (task as SquadTask3D).state == SquadTask3D.State.FAILED
	_request_replan(
		SquadReplanPolicy3D.Level.FULL_TACTIC if active_task_failed \
		else SquadReplanPolicy3D.Level.PLAN_REPAIR
	)

func _queue_zone_observation(observer: Soldier3D, zone_id: StringName) -> void:
	var zone := get_zone_by_id(zone_id)
	if zone == null:
		return
	var visible_ids: Array[StringName] = []
	for known_contact in belief.get_contacts_in_zone(zone):
		if known_contact.reported_by.has(String(observer.name)):
			visible_ids.append(known_contact.contact_id)
	for candidate in observer.perception_component.find_visible_hostiles():
		if not zone.contains_world_position(candidate.global_position):
			continue
		var contact_report := SquadContactReport3D.new().configure_contact(
			observer, candidate, candidate.global_position, 1.0, SquadContactReport3D.Stimulus.VISUAL
		)
		belief.merge_report(contact_report)
		if contact_report.contact_id not in visible_ids:
			visible_ids.append(contact_report.contact_id)
	var threat_evidence_count := belief.get_threat_events_in_zone(zone).size()
	var zone_report := SquadContactReport3D.new().configure_zone_observation(
		observer, zone_id, observer.global_position, visible_ids, observer.is_suppressed(), threat_evidence_count
	)
	_pending_zone_observations[zone_id] = true
	_pending_reports.append({"report": zone_report, "deliver_at": Time.get_ticks_msec() + int(coordinator.contact_report_delay_min * 1000.0)})

func _try_complete_recon_from_contact(report: SquadContactReport3D) -> void:
	if report.stimulus not in [
		SquadContactReport3D.Stimulus.VISUAL,
		SquadContactReport3D.Stimulus.GUNSHOT,
		SquadContactReport3D.Stimulus.DAMAGE,
		SquadContactReport3D.Stimulus.NEAR_MISS,
	]:
		return
	var observer := report.get_observer()
	var task := _get_active_recon_task_for(observer)
	if task == null:
		return
	var zone := get_zone_by_id(task.zone_id)
	if zone == null or not zone.contains_world_position(report.position):
		return
	if report.stimulus == SquadContactReport3D.Stimulus.VISUAL and report.get_target() != null:
		_complete_recon_information_goal(task, observer, "contact observed in assigned zone")
	elif zone.contains_world_position(observer.global_position):
		_complete_recon_information_goal(task, observer, "hostile fire heard in assigned zone")

func _monitor_recon_tasks() -> void:
	if scheduler == null or scheduler.active_plan == null:
		return
	for value in scheduler.active_plan.tasks:
		var task := value as SquadTask3D
		if task == null or task.type != SquadTask3D.Type.RECON_ZONE or task.state != SquadTask3D.State.ACTIVE:
			continue
		var zone := get_zone_by_id(task.zone_id)
		if zone == null:
			continue
		for member_id in task.recipient_ids:
			var member := coordinator.get_member_by_id(String(member_id))
			if member != null and member.is_pinned() and zone.contains_world_position(member.global_position):
				_complete_recon_information_goal(task, member, "pinned after entering assigned zone")

func _monitor_cover_tasks() -> void:
	if scheduler == null or scheduler.active_plan == null:
		return
	for value in scheduler.active_plan.tasks:
		var task := value as SquadTask3D
		if task == null or task.type != SquadTask3D.Type.TAKE_COVER or task.state != SquadTask3D.State.ACTIVE:
			continue
		for member_id in task.recipient_ids:
			if task.member_states.get(StringName(member_id)) != SquadTask3D.State.ACTIVE:
				continue
			var member := coordinator.get_member_by_id(String(member_id))
			if member == null:
				continue
			var already_protected := is_instance_valid(member.active_cover) \
				and member.is_protected_from_position(task.target_position)
			var pinned_low := member.is_pinned() \
				and (is_instance_valid(member.active_cover) or member.stance == Soldier3D.Stance.PRONE)
			var timed_out := task.activated_msec > 0 and Time.get_ticks_msec() - task.activated_msec >= 4500
			if not already_protected and not pinned_low and not timed_out:
				continue
			if member.active_directive != null:
				_directive_bindings.erase("%s:%d" % [member.name, member.active_directive.version])
			if timed_out and not is_instance_valid(member.active_cover):
				member.set_stance(Soldier3D.Stance.PRONE)
			scheduler.mark_member_succeeded(task.task_id, StringName(member.name))
			var ready_reason := "already_protected" if already_protected else ("timeout_low" if timed_out else "pinned_low")
			print("[TACTICAL3D_COVER_READY] squad=%s member=%s reason=%s" % [
				coordinator.squad_display_name, member.name, ready_reason
			])

func _get_active_recon_task_for(member: Soldier3D) -> SquadTask3D:
	if member == null or scheduler == null or scheduler.active_plan == null:
		return null
	for value in scheduler.active_plan.tasks:
		var task := value as SquadTask3D
		if task != null and task.type == SquadTask3D.Type.RECON_ZONE \
				and task.state == SquadTask3D.State.ACTIVE and String(member.name) in task.recipient_ids:
			return task
	return null

func _complete_recon_information_goal(task: SquadTask3D, member: Soldier3D, reason: String) -> void:
	if task == null or member == null or task.member_states.get(StringName(member.name)) != SquadTask3D.State.ACTIVE:
		return
	if member.active_directive != null:
		_directive_bindings.erase("%s:%d" % [member.name, member.active_directive.version])
	_queue_zone_observation(member, task.zone_id)
	scheduler.mark_member_succeeded(task.task_id, StringName(member.name))
	coordinator.issue_tactical_directive(
		member,
		SquadDirective3D.Type.HOLD_SECTOR,
		null,
		member.global_position,
		[],
		null,
		0.0,
		"Recon information goal complete: %s" % reason,
		task.zone_id,
		SquadDirective3D.RulesOfEngagement.RETURN_FIRE
	)
	print("[TACTICAL3D_RECON_COMPLETE] squad=%s member=%s zone=%s reason=%s" % [
		coordinator.squad_display_name, member.name, task.zone_id, reason
	])

func _on_plan_completed(plan: SquadCommandPlan3D) -> void:
	match plan.intent:
		&"CONTACT_COVER":
			_contact_cover_complete = true
		&"RECON_SPLIT":
			_recon_complete = _all_recon_zones_observed()
	_active_candidate_id = ""
	_request_replan(SquadReplanPolicy3D.Level.FULL_TACTIC)

func _on_task_state_changed(task: SquadTask3D, _previous: SquadTask3D.State, current: SquadTask3D.State) -> void:
	if current == SquadTask3D.State.FAILED:
		print("[TACTICAL3D_TASK_FAIL] squad=%s task=%s" % [coordinator.squad_display_name, task.task_id])
		_request_replan(SquadReplanPolicy3D.Level.PLAN_REPAIR)
	if scheduler.active_plan != null and scheduler.active_plan.intent == &"RECON_SPLIT":
		_resolve_partial_recon_plan()

func _on_task_member_failed(task_id: StringName, member_id: StringName, reason: String) -> void:
	print("[TACTICAL3D_MEMBER_FAIL] squad=%s task=%s member=%s reason=%s" % [coordinator.squad_display_name, task_id, member_id, reason])
	scheduler.mark_member_failed(task_id, member_id)

func _on_mission_state_changed(previous: SquadMissionController3D.State, current: SquadMissionController3D.State) -> void:
	mission_state_changed.emit(SquadMissionController3D.State.keys()[current])
	coordinator.refresh_member_mission_constraints()
	var strategic_states := [
		SquadMissionController3D.State.HOLDING,
		SquadMissionController3D.State.RETURNING,
		SquadMissionController3D.State.COMPLETE,
	]
	if current in strategic_states or previous in strategic_states:
		_active_candidate_id = ""
		_request_replan(SquadReplanPolicy3D.Level.FULL_TACTIC)

func _stimulus_from_name(value: StringName) -> SquadContactReport3D.Stimulus:
	match value:
		&"gunshot": return SquadContactReport3D.Stimulus.GUNSHOT
		&"damage": return SquadContactReport3D.Stimulus.DAMAGE
		&"near_miss": return SquadContactReport3D.Stimulus.NEAR_MISS
	return SquadContactReport3D.Stimulus.VISUAL

func _all_recon_zones_observed() -> bool:
	var found := false
	for zone in zones:
		if not zone.recon_enabled:
			continue
		found = true
		if not belief.is_zone_observed(zone.zone_id):
			return false
	return found

func _known_contact_sector_count() -> int:
	var sectors := {}
	var center := coordinator.get_squad_center() if coordinator != null else Vector3.ZERO
	for contact in belief.get_living_contacts():
		var direction := contact.last_known_position - center
		direction.y = 0.0
		if direction.length_squared() > 0.01:
			sectors[roundi(atan2(direction.z, direction.x) / (PI * 0.5))] = true
	return sectors.size()

func _active_plan_has_failed_task() -> bool:
	if scheduler == null or scheduler.active_plan == null:
		return false
	return scheduler.active_plan.tasks.any(func(task: SquadTask3D): return task.state == SquadTask3D.State.FAILED)

func _update_qwen_context(candidates: Array[Dictionary]) -> void:
	var candidate_ids := PackedStringArray()
	for candidate in candidates:
		candidate_ids.append(String(candidate.get("id", "")))
	candidate_ids.sort()
	var member_ids := PackedStringArray()
	for member in coordinator.get_living_members():
		member_ids.append(String(member.name))
	member_ids.sort()
	var observed_zone_ids := PackedStringArray()
	for zone in zones:
		if belief.is_zone_observed(zone.zone_id):
			observed_zone_ids.append(String(zone.zone_id))
	observed_zone_ids.sort()
	var signature := JSON.stringify({
		"mission": mission.get_state_name(),
		"candidates": candidate_ids,
		"members": member_ids,
		"enemy_count": belief.get_estimated_enemy_count(),
		"observed_zones": observed_zone_ids,
	})
	if signature != _qwen_context_signature:
		_qwen_context_signature = signature
		_qwen_context_version += 1

func _resolve_partial_recon_plan() -> void:
	var recon_tasks: Array[SquadTask3D] = []
	var has_failure := false
	for value in scheduler.active_plan.tasks:
		var task := value as SquadTask3D
		if task.type != SquadTask3D.Type.RECON_ZONE:
			continue
		recon_tasks.append(task)
		has_failure = has_failure or task.state == SquadTask3D.State.FAILED
	if not has_failure or recon_tasks.is_empty():
		return
	if recon_tasks.any(func(task: SquadTask3D): return task.state in [SquadTask3D.State.PENDING, SquadTask3D.State.ACTIVE]):
		return
	scheduler.cancel_active_plan("partial recon complete")
	_recon_complete = _all_recon_zones_observed()
	_active_candidate_id = ""
	_request_replan(SquadReplanPolicy3D.Level.PLAN_REPAIR)

func _request_replan(level: SquadReplanPolicy3D.Level) -> void:
	_pending_replan_level = maxi(int(_pending_replan_level), int(level))
	if level >= SquadReplanPolicy3D.Level.PLAN_REPAIR:
		_force_evaluation = true

func _rebuild_influence() -> void:
	if coordinator == null:
		return
	var assessment := fire_superiority.assess(coordinator.get_living_members(), belief.get_estimated_enemy_count())
	var snapshot := SquadDecisionSnapshot3D.capture(belief, mission, coordinator.get_living_members(), assessment)
	influence.rebuild(
		belief,
		zones,
		snapshot.members,
		coordinator.get_registered_covers(),
		snapshot.squad_center,
		mission.target_position
	)
