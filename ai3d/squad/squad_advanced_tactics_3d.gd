extends Node
class_name SquadAdvancedTactics3D

signal belief_report_accepted(report: SquadContactReport3D)
signal tactical_candidates_evaluated(candidates: Array[Dictionary], selected_id: String)
signal mission_state_changed(state_name: String)

var coordinator: SquadCoordinator3D
var belief := SquadBeliefState3D.new()
var mission := SquadMissionController3D.new()
var planner := SquadTacticalPlanner3D.new()
var scheduler: SquadTaskScheduler3D
var dispatcher: SquadDirectiveDispatcher3D
var zones: Array[TacticalZone3D] = []

var _pending_reports: Array[Dictionary] = []
var _pending_zone_observations: Dictionary = {}
var _last_queued_report: Dictionary = {}
var _directive_bindings: Dictionary = {}
var _evaluation_timer := 0.0
var _force_evaluation := true
var _plan_sequence := 0
var _active_intent: StringName = &""
var _active_candidate_id := ""
var _contact_started_msec := 0
var _contact_cover_complete := false
var _recon_complete := false
var _qwen_context_version := 1
var _qwen_context_signature := ""
var _rng := RandomNumberGenerator.new()

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
	dispatcher.task_member_failed.connect(_on_task_member_failed)
	scheduler.plan_completed.connect(_on_plan_completed)
	scheduler.task_state_changed.connect(_on_task_state_changed)
	mission.state_changed.connect(_on_mission_state_changed)
	call_deferred("_finish_configuration")

func _finish_configuration() -> void:
	zones.clear()
	for node in get_tree().get_nodes_in_group("tactical_zone3d"):
		if node is TacticalZone3D:
			zones.append(node as TacticalZone3D)
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
	_monitor_recon_tasks()
	belief.update(delta)
	mission.update(
		delta,
		coordinator.get_squad_center(),
		belief.has_known_hostile_in_radius(mission.target_position, mission.target_radius)
	)
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
		"mission_state": mission.get_state_name(),
		"active_intent": String(_active_intent),
		"candidate_id": _active_candidate_id,
		"belief": belief.make_tactical_snapshot(zones),
		"tasks": scheduler.get_summary(),
	}

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
		belief.merge_report(report)
		belief_report_accepted.emit(report)
		if report.stimulus != SquadContactReport3D.Stimulus.ZONE_OBSERVED:
			var best := belief.get_best_contact()
			coordinator.known_target = best.get_target() if best != null else null
			var next_contact_count := belief.get_estimated_enemy_count()
			if previous_contact_count == 0 and next_contact_count > 0:
				_contact_started_msec = now
				_contact_cover_complete = false
				_recon_complete = false
			if next_contact_count != previous_contact_count or report.stimulus == SquadContactReport3D.Stimulus.DAMAGE:
				if next_contact_count != previous_contact_count and _active_intent == &"DEFEND_CONTACT":
					_active_candidate_id = ""
				_force_evaluation = true
			_try_complete_recon_from_contact(report)
		if report.stimulus == SquadContactReport3D.Stimulus.ZONE_OBSERVED:
			_pending_zone_observations.erase(report.zone_id)
			_recon_complete = _all_recon_zones_observed()
			_force_evaluation = true

func _evaluate() -> void:
	if coordinator.get_configured_member_actors().is_empty():
		return
	if not _pending_zone_observations.is_empty():
		return
	var contact_elapsed := 0.0 if _contact_started_msec <= 0 else float(Time.get_ticks_msec() - _contact_started_msec) / 1000.0
	var candidates := planner.build_candidates(
		belief,
		zones,
		coordinator.get_living_members(),
		mission,
		_contact_cover_complete,
		_recon_complete,
		_active_intent,
		contact_elapsed
	)
	if candidates.is_empty():
		return
	_update_qwen_context(candidates)
	var selected: Dictionary = candidates[0]
	tactical_candidates_evaluated.emit(candidates, String(selected.get("id", "")))
	_apply_candidate(selected, "UTILITY")
	coordinator.request_advanced_candidate(
		get_qwen_snapshot(), candidates, String(selected.get("id", "")), _qwen_context_version
	)

func apply_qwen_candidate(candidate_id: String, reason: String) -> bool:
	var candidates := planner.build_candidates(
		belief, zones, coordinator.get_living_members(), mission,
		_contact_cover_complete, _recon_complete, _active_intent,
		0.0 if _contact_started_msec <= 0 else float(Time.get_ticks_msec() - _contact_started_msec) / 1000.0
	)
	for candidate in candidates:
		if String(candidate.get("id", "")) == candidate_id:
			_apply_candidate(candidate, "LOCAL_QWEN", reason)
			return true
	return false

func _apply_candidate(candidate: Dictionary, source: String, reason_override := "") -> void:
	var candidate_id := String(candidate.get("id", ""))
	var kind := StringName(candidate.get("kind", ""))
	if candidate_id == _active_candidate_id and scheduler.active_plan != null:
		return
	_plan_sequence += 1
	var plan := planner.compile_candidate(candidate, belief, coordinator.get_living_members(), mission, _plan_sequence)
	if plan == null:
		return
	if not reason_override.is_empty():
		plan.reason = reason_override
	plan.source = source
	if not scheduler.start_plan(plan):
		return
	_active_candidate_id = candidate_id
	_active_intent = kind
	coordinator.current_plan = String(kind)
	coordinator.current_stage = 1
	coordinator.last_command_source = source
	coordinator.last_command_summary = "%s | %s" % [candidate_id, plan.reason]
	coordinator.command_changed.emit(coordinator.current_plan, coordinator.last_command_summary, source)
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
	if task != null and task.type in [SquadTask3D.Type.RECON_ZONE, SquadTask3D.Type.FLANK_ZONE]:
		_queue_zone_observation(member, task.zone_id)
	scheduler.mark_member_succeeded(task_id, StringName(member.name))

func on_member_died(member: Soldier3D) -> void:
	for task in scheduler.tasks_by_id.values():
		if String(member.name) in (task as SquadTask3D).recipient_ids:
			scheduler.mark_member_failed((task as SquadTask3D).task_id, StringName(member.name))
	_force_evaluation = true

func _queue_zone_observation(observer: Soldier3D, zone_id: StringName) -> void:
	var zone := get_zone_by_id(zone_id)
	if zone == null:
		return
	var visible_ids: Array[StringName] = []
	for known_contact in belief.get_contacts_in_zone(zone):
		if known_contact.reported_by.has(String(observer.name)):
			visible_ids.append(known_contact.contact_id)
	for candidate in observer.perception_component.find_visible_hostiles():
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
	_force_evaluation = true

func _on_task_state_changed(task: SquadTask3D, _previous: SquadTask3D.State, current: SquadTask3D.State) -> void:
	if current == SquadTask3D.State.FAILED:
		print("[TACTICAL3D_TASK_FAIL] squad=%s task=%s" % [coordinator.squad_display_name, task.task_id])
	if scheduler.active_plan != null and scheduler.active_plan.intent == &"RECON_SPLIT":
		_resolve_partial_recon_plan()

func _on_task_member_failed(task_id: StringName, member_id: StringName, reason: String) -> void:
	print("[TACTICAL3D_MEMBER_FAIL] squad=%s task=%s member=%s reason=%s" % [coordinator.squad_display_name, task_id, member_id, reason])
	scheduler.mark_member_failed(task_id, member_id)

func _on_mission_state_changed(_previous: SquadMissionController3D.State, current: SquadMissionController3D.State) -> void:
	mission_state_changed.emit(SquadMissionController3D.State.keys()[current])
	_active_candidate_id = ""
	_force_evaluation = true
	coordinator.refresh_member_mission_constraints()

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
	_force_evaluation = true
