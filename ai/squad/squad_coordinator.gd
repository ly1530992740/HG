extends Node
class_name SquadCoordinator

signal member_registered(member: SquadMember)
signal member_unregistered(member: SquadMember)
signal leader_changed(leader: SquadMember)
signal order_issued(order: SquadOrder)
signal posture_changed(posture: SquadTacticalEvaluator.Posture)
signal contact_report_queued(observer: SquadMember, contact: CombatContact)
signal contact_report_accepted(observer: SquadMember, contact: CombatContact)
signal ambush_opened(target: Node2D, reason: StringName)

enum ContactPhase { SEARCH, AMBUSH, COMBAT }

@export var squad_id: StringName = &"default"
@export var combat_team: StringName = &"hostile"
@export var squad_display_name := ""
@export var can_target_players := true
@export var auto_discover_members := true
@export var context_refresh_interval := 0.5
@export var order_interval := 4.0
@export var initial_cover_duration := 8.0
@export_range(0.0, 1.0) var assault_charge_chance := 0.22
@export var contact_report_delay_min := 0.3
@export var contact_report_delay_max := 1.0
@export var ambush_timeout := 6.0
@export_range(0.1, 1.0) var ambush_ready_ratio_required := 0.7
@export var ambush_danger_close_distance := 190.0
@export var search_order_interval := 5.0
@export var search_step_distance := 340.0
@export var search_movement_enabled := true
@export var search_direction_override := Vector2.ZERO
@export var use_shared_ambush_cover := true
@export var ambush_opening_volley_duration := 2.5
@export_range(0.5, 1.0) var ambush_aim_quality_required := 0.9
@export var ambush_aim_timeout := 2.5
@export var ambush_max_cover_groups := 3
@export var ambush_cover_score_tolerance := 700.0
@export var ambush_load_balance_weight := 0.0
@export_range(0.0, 1.0) var ambush_min_approach_progress := 0.55

var blackboard := SquadBlackboard.new()
var members: Array[SquadMember] = []
var leader: SquadMember = null
var tactical_evaluator := SquadTacticalEvaluator.new()
var tactical_posture: SquadTacticalEvaluator.Posture = SquadTacticalEvaluator.Posture.BALANCED

var _rng := RandomNumberGenerator.new()
var _refresh_timer := 0.0
var _election_pending := false
var _casualties := 0
var _initial_strength := 0
var _order_timer := 0.0
var _command_phase := 0
var _engagement_time := 0.0
var _engagement_active := false
var _active_suppressor: SquadMember = null
var _pending_contact_reports: Array[Dictionary] = []
var _contact_phase: ContactPhase = ContactPhase.SEARCH
var _ambush_elapsed := 0.0
var _search_sweep_index := 0
var _last_contact_position := Vector2.ZERO
var _active_ambush_cover: Node = null
var _active_ambush_covers: Array[Node] = []
var _ambush_cover_assignments: Dictionary = {}
var _ambush_target_assignments: Dictionary = {}
var _ambush_assignment_target_count := 0
var _ambush_aim_started_msec := 0
var _opening_volley_until_msec := 0

func _ready() -> void:
	add_to_group("squad_coordinator")
	_rng.randomize()
	blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)
	blackboard.set_fact(&"contact_phase", ContactPhase.SEARCH)
	blackboard.set_fact(&"ambush_ready_ratio", 0.0)
	if auto_discover_members:
		call_deferred("_discover_members")

func _process(delta: float) -> void:
	_order_timer = maxf(0.0, _order_timer - delta)
	_process_contact_reports()
	_update_engagement(delta)
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = context_refresh_interval
	_cleanup_members()
	_refresh_context()
	_refresh_tactical_posture()

func register_member(member: SquadMember) -> void:
	if member == null or member.squad_id != squad_id or members.has(member):
		return
	members.append(member)
	_initial_strength = max(_initial_strength, members.size() + _casualties)
	member.assign_coordinator(self, blackboard)
	if not member.member_died.is_connected(_on_member_died):
		member.member_died.connect(_on_member_died)
	blackboard.set_members(members)
	var existing_order := blackboard.get_order_for(member)
	if existing_order != null:
		member.receive_order(existing_order)
	member_registered.emit(member)
	_schedule_leader_election()

func unregister_member(member: SquadMember) -> void:
	if member == null or not members.has(member):
		return
	var assigned_cover: Node = get_ambush_cover_for(member)
	if is_instance_valid(assigned_cover) and is_instance_valid(member.actor) and assigned_cover.has_method("release_cover"):
		assigned_cover.release_cover(member.actor)
	members.erase(member)
	_ambush_cover_assignments.erase(member)
	_ambush_target_assignments.erase(member)
	blackboard.clear_member(member)
	if member.member_died.is_connected(_on_member_died):
		member.member_died.disconnect(_on_member_died)
	member.clear_coordinator(self)
	if leader == member:
		leader = null
		blackboard.set_leader(null)
	blackboard.set_members(members)
	member_unregistered.emit(member)
	_schedule_leader_election()

func issue_order(
		order_type: SquadOrder.Type,
		target: Node2D = null,
		target_position := Vector2.ZERO,
		assigned_cover: Node = null,
		priority := 0,
		duration_seconds := -1.0,
		recipients: Array = []
) -> SquadOrder:
	var issuer: Node = self
	if leader != null and is_instance_valid(leader) and leader.actor != null and is_instance_valid(leader.actor):
		issuer = leader.actor
	var order := SquadOrder.new().configure(
		order_type,
		issuer,
		target,
		target_position,
		assigned_cover,
		priority,
		duration_seconds,
		recipients
	)
	blackboard.publish_order(order)
	if target != null:
		blackboard.set_shared_target(target)
	for member in members:
		if is_instance_valid(member) and order.applies_to(member):
			member.receive_order(order)
	order_issued.emit(order)
	return order

func get_blackboard() -> SquadBlackboard:
	return blackboard

func get_posture_name() -> String:
	return tactical_evaluator.get_posture_name()

func is_engagement_active() -> bool:
	return _engagement_active

func get_engagement_time() -> float:
	return _engagement_time

func get_active_suppressor() -> SquadMember:
	return _active_suppressor if is_instance_valid(_active_suppressor) else null

func get_contact_phase() -> ContactPhase:
	return _contact_phase

func get_pending_contact_report_count() -> int:
	return _pending_contact_reports.size()

func report_contact(observer: SquadMember, contact: CombatContact, delay_override := -1.0) -> void:
	if observer == null or contact == null or not contact.is_valid() or not members.has(observer):
		return
	for pending in _pending_contact_reports:
		if pending.get("observer") == observer and pending.get("target") == contact.target:
			return
	var delay := delay_override if delay_override >= 0.0 else _rng.randf_range(contact_report_delay_min, contact_report_delay_max)
	_pending_contact_reports.append({
		"observer": observer,
		"contact": contact,
		"target": contact.target,
		"deliver_at": Time.get_ticks_msec() + int(delay * 1000.0),
	})
	contact_report_queued.emit(observer, contact)

func _discover_members() -> void:
	for node in get_tree().get_nodes_in_group("squad_member"):
		if node is SquadMember:
			register_member(node)

func _schedule_leader_election() -> void:
	if _election_pending:
		return
	_election_pending = true
	call_deferred("_elect_leader")

func _elect_leader() -> void:
	_election_pending = false
	_cleanup_members()
	if leader != null and members.has(leader):
		return
	if members.is_empty():
		leader = null
		blackboard.set_leader(null)
		return
	leader = members[_rng.randi_range(0, members.size() - 1)]
	for member in members:
		member.set_is_leader(member == leader)
	blackboard.set_leader(leader)
	leader_changed.emit(leader)
	if blackboard.current_order == null:
		_issue_search_sweep()

func _cleanup_members() -> void:
	for member in members.duplicate():
		if not is_instance_valid(member) or member.actor == null or not is_instance_valid(member.actor):
			members.erase(member)
	if leader != null and not members.has(leader):
		leader = null
		blackboard.set_leader(null)
		_schedule_leader_election()
	blackboard.set_members(members)

func _refresh_context() -> void:
	var hostile_count := _collect_known_hostile_targets().size()
	var ally_count := members.size()
	var force_ratio := float(ally_count) / float(max(1, hostile_count))
	blackboard.set_fact(&"ally_alive_count", ally_count)
	blackboard.set_fact(&"hostile_alive_count", hostile_count)
	blackboard.set_fact(&"player_alive_count", hostile_count)
	blackboard.set_fact(&"force_ratio", force_ratio)
	blackboard.set_fact(&"squad_casualties", _casualties)
	blackboard.set_fact(&"initial_squad_strength", _initial_strength)
	blackboard.set_fact(&"leader_alive", leader != null)
	blackboard.set_fact(&"engagement_active", _engagement_active)
	blackboard.set_fact(&"engagement_time", _engagement_time)

func _refresh_tactical_posture() -> void:
	if leader == null or members.is_empty():
		return
	var previous_posture := tactical_posture
	tactical_posture = tactical_evaluator.evaluate(blackboard)
	blackboard.set_fact(&"tactical_posture", tactical_posture)
	if tactical_posture != previous_posture:
		posture_changed.emit(tactical_posture)
		_order_timer = 0.0
	if not _engagement_active:
		if _contact_phase == ContactPhase.SEARCH and _order_timer <= 0.0:
			_issue_search_sweep()
			_order_timer = search_order_interval
		return
	if _contact_phase == ContactPhase.AMBUSH:
		return
	if Time.get_ticks_msec() < _opening_volley_until_msec:
		return
	if _order_timer <= 0.0:
		_issue_tactical_order()
		_order_timer = order_interval

func _issue_tactical_order() -> void:
	var primary_target := _find_primary_target()
	if primary_target == null:
		_issue_search_sweep()
		return
	var exposed_members := _get_members_out_of_cover()
	_active_suppressor = null
	if _engagement_time < initial_cover_duration:
		if exposed_members.is_empty():
			_issue_contact_fire_plan(primary_target)
		else:
			blackboard.set_fact(&"tactical_plan", "CONTACT_TO_COVER")
			_coordinate_cover_move(primary_target, exposed_members, 110)
		return
	match tactical_posture:
		SquadTacticalEvaluator.Posture.ASSAULT:
			_issue_combined_arms_plan(primary_target, true)
		SquadTacticalEvaluator.Posture.DEFENSIVE:
			_issue_defensive_plan(primary_target)
		SquadTacticalEvaluator.Posture.ROUT:
			_issue_covering_retreat(primary_target)
		_:
			_issue_combined_arms_plan(primary_target, false)
	_command_phase += 1

func _issue_contact_fire_plan(target: Node2D) -> void:
	blackboard.set_fact(&"tactical_plan", "CONTACT_BASE_OF_FIRE")
	var machine_gunners := _get_members_with_role(SquadCombatRole.Type.MACHINE_GUNNER)
	var marksmen := _get_members_with_role(SquadCombatRole.Type.MARKSMAN)
	var specialists: Dictionary = {}
	for member in machine_gunners:
		specialists[member] = true
		_active_suppressor = member
		issue_order(SquadOrder.Type.SUPPRESS, target, Vector2.ZERO, null, 108, order_interval, [member])
	for member in marksmen:
		specialists[member] = true
		issue_order(SquadOrder.Type.OVERWATCH, target, Vector2.ZERO, null, 106, order_interval, [member])
	for member in members:
		if not specialists.has(member):
			issue_order(SquadOrder.Type.STAY_HIDDEN, target, Vector2.ZERO, null, 100, order_interval, [member])

func _issue_combined_arms_plan(target: Node2D, aggressive: bool) -> void:
	blackboard.set_fact(&"tactical_plan", "AGGRESSIVE_ENVELOPMENT" if aggressive else "SUPPRESS_AND_FLANK")
	var assigned: Dictionary = {}
	var machine_gunners := _get_members_with_role(SquadCombatRole.Type.MACHINE_GUNNER)
	var marksmen := _get_members_with_role(SquadCombatRole.Type.MARKSMAN)
	var riflemen := _get_members_with_role(SquadCombatRole.Type.RIFLEMAN)
	var flankers := _get_members_with_role(SquadCombatRole.Type.SHOTGUNNER)
	flankers.append_array(_get_members_with_role(SquadCombatRole.Type.PISTOL_SCOUT))
	if aggressive and riflemen.size() > 1:
		flankers.append(riflemen.pop_back())

	for member in machine_gunners:
		assigned[member] = true
		if _active_suppressor == null:
			_active_suppressor = member
		issue_order(SquadOrder.Type.SUPPRESS, target, Vector2.ZERO, null, 100, order_interval, [member])
	if machine_gunners.is_empty() and not riflemen.is_empty():
		var improvised_suppressor := riflemen.pop_front() as SquadMember
		assigned[improvised_suppressor] = true
		_active_suppressor = improvised_suppressor
		issue_order(SquadOrder.Type.SUPPRESS, target, Vector2.ZERO, null, 98, order_interval, [improvised_suppressor])
	for member in marksmen:
		assigned[member] = true
		issue_order(SquadOrder.Type.OVERWATCH, target, Vector2.ZERO, null, 96, order_interval, [member])
	for index in flankers.size():
		var flanker := flankers[index]
		assigned[flanker] = true
		var side := -1 if index % 2 == 0 else 1
		var order_type := SquadOrder.Type.FLANK_LEFT if side < 0 else SquadOrder.Type.FLANK_RIGHT
		var destination := _calculate_flank_position(target, flanker, side, index / 2, aggressive)
		issue_order(order_type, target, destination, null, 94, order_interval + 1.0, [flanker])
	for member in riflemen:
		if assigned.has(member):
			continue
		assigned[member] = true
		issue_order(SquadOrder.Type.FOCUS_FIRE, target, Vector2.ZERO, null, 88, order_interval, [member])
	for member in members:
		if not assigned.has(member):
			issue_order(SquadOrder.Type.FOCUS_FIRE, target, Vector2.ZERO, null, 82, order_interval, [member])

func _issue_defensive_plan(target: Node2D) -> void:
	blackboard.set_fact(&"tactical_plan", "HOLD_DEFENSIVE_LINE")
	var exposed_members := _get_members_out_of_cover()
	if not exposed_members.is_empty():
		_coordinate_cover_move(target, exposed_members, 105)
	var assigned: Dictionary = {}
	for member in _get_members_with_role(SquadCombatRole.Type.MACHINE_GUNNER):
		if exposed_members.has(member):
			continue
		assigned[member] = true
		_active_suppressor = member
		issue_order(SquadOrder.Type.SUPPRESS, target, Vector2.ZERO, null, 102, order_interval, [member])
	for member in _get_members_with_role(SquadCombatRole.Type.MARKSMAN):
		if exposed_members.has(member):
			continue
		assigned[member] = true
		issue_order(SquadOrder.Type.OVERWATCH, target, Vector2.ZERO, null, 100, order_interval, [member])
	for member in members:
		if exposed_members.has(member) or assigned.has(member):
			continue
		issue_order(SquadOrder.Type.FOCUS_FIRE, target, Vector2.ZERO, null, 92, order_interval, [member])

func _issue_covering_retreat(target: Node2D) -> void:
	blackboard.set_fact(&"tactical_plan", "COVERING_RETREAT")
	var rear_guard := _select_rear_guard()
	if rear_guard != null and members.size() > 1:
		_active_suppressor = rear_guard
		issue_order(SquadOrder.Type.SUPPRESS, target, Vector2.ZERO, null, 112, order_interval, [rear_guard])
	var retreat_index := 0
	for member in members:
		if member == rear_guard:
			continue
		var destination := _calculate_retreat_position(target, retreat_index)
		issue_order(SquadOrder.Type.RETREAT, target, destination, null, 110, order_interval, [member])
		retreat_index += 1
	if members.size() == 1 and rear_guard != null:
		issue_order(SquadOrder.Type.RETREAT, target, _calculate_retreat_position(target, 0), null, 115, order_interval, [rear_guard])

func _get_members_with_role(role: SquadCombatRole.Type) -> Array[SquadMember]:
	var result: Array[SquadMember] = []
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		if member.actor.has_method("get_combat_role") and member.actor.get_combat_role() == role:
			result.append(member)
	return result

func _calculate_flank_position(target: Node2D, member: SquadMember, side: int, lane_index: int, aggressive: bool) -> Vector2:
	var center := _get_squad_center()
	var approach := (target.global_position - center).normalized()
	if approach == Vector2.ZERO:
		approach = Vector2.RIGHT
	var lateral := Vector2(-approach.y, approach.x)
	var role := member.actor.get_combat_role() as SquadCombatRole.Type
	var standoff := 215.0 if role == SquadCombatRole.Type.SHOTGUNNER else 320.0
	if aggressive:
		standoff *= 0.8
	var lateral_distance := 380.0 + float(lane_index) * 95.0
	return target.global_position - approach * standoff + lateral * float(side) * lateral_distance

func _calculate_retreat_position(target: Node2D, member_index: int) -> Vector2:
	var center := _get_squad_center()
	var away := (center - target.global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.LEFT
	var lateral := Vector2(-away.y, away.x)
	var lane := float(member_index / 2 + 1) * 70.0 * (-1.0 if member_index % 2 == 0 else 1.0)
	return center + away * 620.0 + lateral * lane

func _get_squad_center() -> Vector2:
	var center := Vector2.ZERO
	var count := 0
	for member in members:
		if is_instance_valid(member) and is_instance_valid(member.actor):
			center += member.actor.global_position
			count += 1
	return center / float(maxi(1, count))

func _select_rear_guard() -> SquadMember:
	var candidates := _get_members_with_role(SquadCombatRole.Type.MACHINE_GUNNER)
	if candidates.is_empty():
		candidates = _get_members_with_role(SquadCombatRole.Type.RIFLEMAN)
	return candidates[0] if not candidates.is_empty() else (members[0] if not members.is_empty() else null)

func _coordinate_cover_move(target: Node2D, exposed_members: Array[SquadMember], priority: int) -> void:
	var suppressor := _find_available_suppressor(exposed_members)
	if suppressor != null:
		_active_suppressor = suppressor
		issue_order(SquadOrder.Type.SUPPRESS, target, Vector2.ZERO, null, priority + 1, order_interval, [suppressor])
	issue_order(SquadOrder.Type.TAKE_COVER, target, Vector2.ZERO, null, priority, order_interval, exposed_members)

func _find_available_suppressor(excluded_members: Array[SquadMember]) -> SquadMember:
	var best: SquadMember = null
	var best_suppression := INF
	for member in members:
		if excluded_members.has(member) or not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		if member.actor.get_active_cover() == null:
			continue
		var will := member.actor.get("will_component") as WillComponent
		if will and will.mental_state in [WillComponent.MentalState.AFRAID, WillComponent.MentalState.RECOVERING, WillComponent.MentalState.BROKEN]:
			continue
		var member_suppression := float(member.actor.get_suppression()) if member.actor.has_method("get_suppression") else 0.0
		if member.actor.has_method("get_combat_role") and member.actor.get_combat_role() == SquadCombatRole.Type.MACHINE_GUNNER:
			member_suppression -= 50.0
		if member_suppression < best_suppression:
			best = member
			best_suppression = member_suppression
	return best

func _issue_search_sweep() -> void:
	if members.is_empty():
		return
	var center := _get_squad_center()
	if not search_movement_enabled:
		blackboard.set_fact(&"tactical_plan", "SEARCH_HALT")
		blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)
		_set_squad_searching(center)
		issue_order(SquadOrder.Type.HOLD, null, Vector2.ZERO, null, 70, search_order_interval)
		_order_timer = search_order_interval
		return
	var forward := Vector2.RIGHT
	if _last_contact_position != Vector2.ZERO and center.distance_to(_last_contact_position) > 120.0:
		forward = (_last_contact_position - center).normalized()
	elif search_direction_override != Vector2.ZERO:
		forward = search_direction_override.normalized()
	elif leader != null and is_instance_valid(leader) and leader.actor != null and is_instance_valid(leader.actor):
		if leader.actor.has_method("get_facing_direction"):
			forward = leader.actor.get_facing_direction()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	if _last_contact_position != Vector2.ZERO and center.distance_to(_last_contact_position) <= 120.0:
		var sweep_angle := deg_to_rad(-42.0 + float(_search_sweep_index % 4) * 28.0)
		forward = forward.rotated(sweep_angle).normalized()
	var step_distance := search_step_distance
	if _last_contact_position != Vector2.ZERO:
		step_distance = minf(step_distance, maxf(140.0, center.distance_to(_last_contact_position)))
	var formation_center := center + forward * step_distance
	var lateral := Vector2(-forward.y, forward.x)
	blackboard.set_fact(&"tactical_plan", "SEARCH_SWEEP")
	blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)
	blackboard.set_fact(&"search_destination", formation_center)
	_set_squad_searching(formation_center)
	for index in members.size():
		var member := members[index]
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var role: SquadCombatRole.Type = SquadCombatRole.Type.RIFLEMAN
		if member.actor.has_method("get_combat_role"):
			role = member.actor.get_combat_role()
		var role_depth := 0.0
		match role:
			SquadCombatRole.Type.MARKSMAN:
				role_depth = -190.0
			SquadCombatRole.Type.MACHINE_GUNNER:
				role_depth = -110.0
			SquadCombatRole.Type.SHOTGUNNER:
				role_depth = 115.0
			SquadCombatRole.Type.PISTOL_SCOUT:
				role_depth = 175.0
		var lane := (float(index) - float(members.size() - 1) * 0.5) * 76.0
		var destination := formation_center + forward * role_depth + lateral * lane
		issue_order(SquadOrder.Type.SEARCH_AREA, null, destination, null, 70, search_order_interval + 1.0, [member])
	_search_sweep_index += 1
	_order_timer = search_order_interval

func _set_squad_searching(position: Vector2) -> void:
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var member_alert := member.actor.get("alert_component") as AlertComponent
		if member_alert:
			member_alert.set_state(AlertComponent.State.SEARCHING, position)

func _process_contact_reports() -> void:
	var now := Time.get_ticks_msec()
	for report in _pending_contact_reports.duplicate():
		if int(report.get("deliver_at", 0)) > now:
			continue
		_pending_contact_reports.erase(report)
		var observer_value = report.get("observer")
		if not is_instance_valid(observer_value):
			continue
		var observer := observer_value as SquadMember
		var contact := report.get("contact") as CombatContact
		if not _is_observer_able_to_report(observer) or contact == null or not contact.is_valid():
			continue
		_accept_contact_report(observer, contact)

func _is_observer_able_to_report(observer: SquadMember) -> bool:
	if observer == null or not is_instance_valid(observer) or not members.has(observer):
		return false
	if observer.actor == null or not is_instance_valid(observer.actor) or observer.actor.is_queued_for_deletion():
		return false
	return not observer.actor.has_method("is_combat_alive") or observer.actor.is_combat_alive()

func _accept_contact_report(observer: SquadMember, contact: CombatContact) -> void:
	_last_contact_position = contact.last_known_position
	blackboard.set_shared_target(contact.target)
	blackboard.set_fact(&"contact_confidence", contact.confidence)
	blackboard.set_fact(&"contact_last_position", contact.last_known_position)
	blackboard.set_fact(&"estimated_enemy_awareness", contact.estimated_enemy_awareness)
	contact_report_accepted.emit(observer, contact)
	if _contact_phase == ContactPhase.SEARCH:
		if contact.stimulus_type == &"gunshot" or _is_target_combat_aware(contact.target) or contact.estimated_enemy_awareness:
			_begin_direct_contact(contact.target)
		else:
			_begin_ambush(contact.target)
	elif _contact_phase == ContactPhase.AMBUSH and (_is_target_combat_aware(contact.target) or contact.estimated_enemy_awareness):
		_open_ambush(&"compromised")

func _begin_direct_contact(target: Node2D) -> void:
	_contact_phase = ContactPhase.COMBAT
	_engagement_active = true
	_engagement_time = 0.0
	_command_phase = 0
	_order_timer = order_interval
	_active_suppressor = null
	blackboard.set_fact(&"contact_phase", _contact_phase)
	blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_FREE)
	blackboard.set_fact(&"ambush_ready_ratio", 0.0)
	blackboard.set_fact(&"tactical_plan", "CONTACT_TO_COVER")
	_set_squad_alert_combat(target.global_position)
	issue_order(SquadOrder.Type.TAKE_COVER, target, Vector2.ZERO, null, 110, initial_cover_duration)

func _begin_ambush(target: Node2D) -> void:
	_contact_phase = ContactPhase.AMBUSH
	_engagement_active = true
	_engagement_time = 0.0
	_ambush_elapsed = 0.0
	_command_phase = 0
	_order_timer = ambush_timeout
	_active_suppressor = null
	blackboard.set_fact(&"contact_phase", _contact_phase)
	blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)
	blackboard.set_fact(&"tactical_plan", "AMBUSH_SETUP")
	blackboard.set_fact(&"ambush_ready_ratio", 0.0)
	blackboard.set_fact(&"ambush_aim_ready_ratio", 0.0)
	_ambush_target_assignments.clear()
	_ambush_assignment_target_count = 0
	_ambush_aim_started_msec = 0
	_ensure_ambush_cover_assignments(target)
	blackboard.set_fact(&"ambush_cover", _get_ambush_cover_summary())
	blackboard.set_fact(&"ambush_cover_count", _active_ambush_covers.size())
	var role_indices: Dictionary = {}
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var role: SquadCombatRole.Type = member.actor.get_combat_role()
		var role_index := int(role_indices.get(role, 0))
		role_indices[role] = role_index + 1
		var assigned_cover: Node = get_ambush_cover_for(member)
		var destination := _calculate_ambush_position(target, member, role_index)
		if is_instance_valid(assigned_cover):
			destination = (assigned_cover as Node2D).global_position
			if assigned_cover.has_method("reserve_cover_against"):
				var reserved_slot := assigned_cover.reserve_cover_against(member.actor, target.global_position) as Marker2D
				if is_instance_valid(reserved_slot):
					destination = reserved_slot.global_position
		issue_order(SquadOrder.Type.AMBUSH_POSITION, target, destination, assigned_cover, 120, -1.0, [member])

func _update_ambush(delta: float) -> void:
	_ambush_elapsed += delta
	var target := _find_primary_target()
	if target == null:
		_reset_contact_state()
		return
	var ready_count := 0
	var valid_count := 0
	var danger_close := false
	var squad_compromised := false
	var assignments_changed := _refresh_ambush_target_assignments(target)
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		valid_count += 1
		var order := member.get_current_order()
		if order != null and order.type == SquadOrder.Type.AMBUSH_POSITION:
			if is_instance_valid(order.assigned_cover):
				if member.actor.get_active_cover() == order.assigned_cover:
					ready_count += 1
			elif member.actor.global_position.distance_to(order.target_position) <= 75.0:
				ready_count += 1
		if member.actor.global_position.distance_to(target.global_position) <= ambush_danger_close_distance:
			danger_close = true
		if member.actor.has_method("is_under_direct_threat") and member.actor.is_under_direct_threat():
			squad_compromised = true
	var ready_ratio := float(ready_count) / float(maxi(1, valid_count))
	blackboard.set_fact(&"ambush_ready_ratio", ready_ratio)
	if _is_target_combat_aware(target) or squad_compromised:
		_open_ambush(&"compromised")
	elif danger_close:
		_open_ambush(&"danger_close")
	elif ready_ratio >= ambush_ready_ratio_required:
		if _ambush_aim_started_msec == 0 or assignments_changed:
			_ambush_aim_started_msec = Time.get_ticks_msec()
		var aim_ready_count := 0
		for member in members:
			if not is_instance_valid(member) or not is_instance_valid(member.actor):
				continue
			var assigned_target := get_ambush_target_for(member)
			if member.actor.has_method("prepare_ambush_shot"):
				member.actor.prepare_ambush_shot(assigned_target)
			if member.actor.has_method("is_ambush_shot_ready") and member.actor.is_ambush_shot_ready(ambush_aim_quality_required):
				aim_ready_count += 1
		var aim_ready_ratio := float(aim_ready_count) / float(maxi(1, valid_count))
		blackboard.set_fact(&"ambush_aim_ready_ratio", aim_ready_ratio)
		var aim_elapsed := float(Time.get_ticks_msec() - _ambush_aim_started_msec) / 1000.0
		if aim_ready_count >= valid_count:
			_open_ambush(&"aimed_ready")
		elif aim_elapsed >= ambush_aim_timeout:
			_open_ambush(&"aim_timeout")
	else:
		_ambush_aim_started_msec = 0
		blackboard.set_fact(&"ambush_aim_ready_ratio", 0.0)
		if _ambush_elapsed >= ambush_timeout:
			# An unaware target is not worth exposing the squad just because a timer elapsed.
			_begin_ambush(target)

func _open_ambush(reason: StringName) -> void:
	if _contact_phase != ContactPhase.AMBUSH:
		return
	var target := _find_primary_target()
	if target == null:
		_reset_contact_state()
		return
	_contact_phase = ContactPhase.COMBAT
	blackboard.set_fact(&"contact_phase", _contact_phase)
	blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_FREE)
	blackboard.set_fact(&"tactical_plan", "AMBUSH_VOLLEY")
	_set_squad_alert_combat(target.global_position)
	_opening_volley_until_msec = Time.get_ticks_msec() + int(ambush_opening_volley_duration * 1000.0)
	_order_timer = ambush_opening_volley_duration
	ambush_opened.emit(target, reason)
	for member in members:
		if is_instance_valid(member) and is_instance_valid(member.actor):
			var assigned_target := get_ambush_target_for(member)
			if not is_instance_valid(assigned_target):
				assigned_target = target
			issue_order(SquadOrder.Type.FOCUS_FIRE, assigned_target, Vector2.ZERO, get_ambush_cover_for(member), 130, ambush_opening_volley_duration, [member])
			if member.actor.has_method("release_ambush_shot"):
				member.actor.release_ambush_shot(assigned_target)

func get_active_ambush_cover() -> Node:
	return _active_ambush_cover if is_instance_valid(_active_ambush_cover) else null

func get_active_ambush_covers() -> Array[Node]:
	var result: Array[Node] = []
	for cover in _active_ambush_covers:
		if is_instance_valid(cover):
			result.append(cover)
	return result

func get_ambush_cover_for(member: SquadMember) -> Node:
	var cover_value: Variant = _ambush_cover_assignments.get(member)
	return cover_value as Node if is_instance_valid(cover_value) else null

func get_ambush_target_for(member: SquadMember) -> Node2D:
	var target_value: Variant = _ambush_target_assignments.get(member)
	return target_value as Node2D if is_instance_valid(target_value) else null

func _refresh_ambush_target_assignments(fallback_target: Node2D) -> bool:
	var targets := _collect_known_hostile_targets()
	if is_instance_valid(fallback_target) and not targets.has(fallback_target):
		targets.append(fallback_target)
	if targets.is_empty():
		return false
	var assignments_valid := targets.size() == _ambush_assignment_target_count
	if assignments_valid:
		for member in members:
			if is_instance_valid(member) and is_instance_valid(member.actor) and not targets.has(get_ambush_target_for(member)):
				assignments_valid = false
				break
	if assignments_valid:
		return false

	_ambush_target_assignments.clear()
	var available: Array[Node2D] = targets.duplicate()
	var assignment_order: Array[SquadMember] = []
	for role in [SquadCombatRole.Type.MARKSMAN, SquadCombatRole.Type.MACHINE_GUNNER, SquadCombatRole.Type.RIFLEMAN, SquadCombatRole.Type.SHOTGUNNER, SquadCombatRole.Type.PISTOL_SCOUT]:
		for member in members:
			if is_instance_valid(member) and is_instance_valid(member.actor) and member.actor.get_combat_role() == role:
				assignment_order.append(member)
	for member in assignment_order:
		var candidates: Array[Node2D] = available if not available.is_empty() else targets
		var selected := _select_role_ambush_target(member, candidates)
		if selected != null:
			_ambush_target_assignments[member] = selected
			available.erase(selected)
	_ambush_assignment_target_count = targets.size()
	blackboard.set_fact(&"ambush_assigned_target_count", _ambush_target_assignments.size())
	return true

func _select_role_ambush_target(member: SquadMember, candidates: Array[Node2D]) -> Node2D:
	var selected: Node2D = null
	var selected_score := -INF
	var role: SquadCombatRole.Type = member.actor.get_combat_role()
	for candidate in candidates:
		if not _is_hostile_target(candidate):
			continue
		var distance := member.actor.global_position.distance_to(candidate.global_position)
		var score := -distance
		match role:
			SquadCombatRole.Type.MARKSMAN:
				score = distance
			SquadCombatRole.Type.MACHINE_GUNNER:
				score = float(candidate.get_health_percentage()) * 1000.0 if candidate.has_method("get_health_percentage") else -distance
			SquadCombatRole.Type.SHOTGUNNER, SquadCombatRole.Type.PISTOL_SCOUT:
				score = -distance * 1.5
		if score > selected_score:
			selected_score = score
			selected = candidate
	return selected

func _calculate_ambush_position(target: Node2D, member: SquadMember, role_index: int) -> Vector2:
	var center := _get_squad_center()
	var approach := (target.global_position - center).normalized()
	if approach == Vector2.ZERO:
		approach = Vector2.RIGHT
	var lateral := Vector2(-approach.y, approach.x)
	var role: SquadCombatRole.Type = member.actor.get_combat_role()
	var standoff := 540.0
	match role:
		SquadCombatRole.Type.MARKSMAN:
			standoff = 900.0
		SquadCombatRole.Type.MACHINE_GUNNER:
			standoff = 680.0
		SquadCombatRole.Type.SHOTGUNNER:
			standoff = 275.0
		SquadCombatRole.Type.PISTOL_SCOUT:
			standoff = 380.0
	var side := -1.0 if role_index % 2 == 0 else 1.0
	var lane := (110.0 + float(role_index / 2) * 85.0) * side
	return target.global_position - approach * standoff + lateral * lane

func _ensure_ambush_cover_assignments(target: Node2D) -> void:
	for assigned_member in _ambush_cover_assignments.keys().duplicate():
		var assigned_cover_value: Variant = _ambush_cover_assignments.get(assigned_member)
		if not is_instance_valid(assigned_member) or not members.has(assigned_member) or not is_instance_valid(assigned_cover_value):
			_ambush_cover_assignments.erase(assigned_member)
	var all_members_assigned := not members.is_empty()
	for member in members:
		if is_instance_valid(member) and is_instance_valid(member.actor) and not is_instance_valid(_ambush_cover_assignments.get(member)):
			all_members_assigned = false
			break
	if all_members_assigned:
		_rebuild_active_ambush_cover_list()
		return

	_ambush_cover_assignments.clear()
	_active_ambush_covers.clear()
	_active_ambush_cover = null
	if not use_shared_ambush_cover:
		return
	var candidates := _find_ambush_cover_candidates(target)
	var cover_loads: Dictionary = {}
	for candidate in candidates:
		cover_loads[candidate.get("cover")] = 0
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var best_cover: Node = null
		var best_assignment_score := INF
		for candidate in candidates:
			var cover := candidate.get("cover") as Node
			if not is_instance_valid(cover):
				continue
			var load := int(cover_loads.get(cover, 0))
			var capacity := int(candidate.get("capacity", 0))
			if load >= capacity:
				continue
			var distance := member.actor.global_position.distance_to((cover as Node2D).global_position)
			var strategic_score := float(candidate.get("score", 0.0))
			var assignment_score := distance + strategic_score * 0.35 + float(load) * ambush_load_balance_weight
			if assignment_score < best_assignment_score:
				best_cover = cover
				best_assignment_score = assignment_score
		if is_instance_valid(best_cover):
			_ambush_cover_assignments[member] = best_cover
			cover_loads[best_cover] = int(cover_loads.get(best_cover, 0)) + 1
	_rebuild_active_ambush_cover_list()

func _rebuild_active_ambush_cover_list() -> void:
	_active_ambush_covers.clear()
	for member in members:
		var cover: Node = get_ambush_cover_for(member)
		if is_instance_valid(cover) and not _active_ambush_covers.has(cover):
			_active_ambush_covers.append(cover)
	_active_ambush_cover = _active_ambush_covers[0] if not _active_ambush_covers.is_empty() else null

func _get_ambush_cover_summary() -> String:
	var names: PackedStringArray = []
	for cover in _active_ambush_covers:
		if is_instance_valid(cover):
			names.append(cover.name)
	return ",".join(names) if not names.is_empty() else "NONE"

func _find_ambush_cover_candidates(target: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if target == null or not is_instance_valid(target):
		return result
	var target_facing := Vector2.RIGHT
	if target.has_method("get_facing_direction"):
		target_facing = target.get_facing_direction()
	if target_facing == Vector2.ZERO:
		target_facing = Vector2.RIGHT
	target_facing = target_facing.normalized()
	var squad_center := _get_squad_center()
	var approach := (target.global_position - squad_center).normalized()
	var advance_direction := search_direction_override.normalized() if search_direction_override != Vector2.ZERO else approach
	var approach_distance := maxf(1.0, advance_direction.dot(target.global_position - squad_center))
	var ideal_position := target.global_position - target_facing * 300.0
	var best_score := INF
	for cover in get_tree().get_nodes_in_group("cover"):
		if not cover is Node2D or not cover.has_method("get_available_slot_count_against"):
			continue
		var capacity := int(cover.get_available_slot_count_against(target.global_position))
		if capacity <= 0:
			continue
		var from_target: Vector2 = ((cover as Node2D).global_position - target.global_position).normalized()
		if target_facing.dot(from_target) > -0.20:
			continue
		if advance_direction != Vector2.ZERO:
			var forward_progress := advance_direction.dot(cover.global_position - squad_center)
			if forward_progress <= 0.0 or forward_progress < approach_distance * ambush_min_approach_progress:
				continue
		var score: float = (cover as Node2D).global_position.distance_to(ideal_position)
		best_score = minf(best_score, score)
		result.append({"cover": cover, "capacity": capacity, "score": score})
	if result.is_empty():
		return result
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("score", INF)) < float(b.get("score", INF)))
	var filtered: Array[Dictionary] = []
	for candidate in result:
		if filtered.size() >= maxi(1, ambush_max_cover_groups):
			break
		if float(candidate.get("score", INF)) <= best_score + ambush_cover_score_tolerance:
			filtered.append(candidate)
	return filtered

func _is_target_combat_aware(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var target_alert := target.get("alert_component") as AlertComponent
	return target_alert != null and target_alert.is_aware_of_combat()

func _set_squad_alert_combat(position: Vector2) -> void:
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var member_alert := member.actor.get("alert_component") as AlertComponent
		if member_alert:
			member_alert.enter_combat(position)

func _reset_contact_state() -> void:
	_contact_phase = ContactPhase.SEARCH
	_engagement_active = false
	_engagement_time = 0.0
	_ambush_elapsed = 0.0
	_command_phase = 0
	_order_timer = 0.0
	_active_suppressor = null
	_release_unused_ambush_reservations()
	_active_ambush_cover = null
	_active_ambush_covers.clear()
	_ambush_cover_assignments.clear()
	_ambush_target_assignments.clear()
	_ambush_assignment_target_count = 0
	_ambush_aim_started_msec = 0
	_opening_volley_until_msec = 0
	blackboard.set_shared_target(null)
	blackboard.set_fact(&"contact_phase", _contact_phase)
	blackboard.set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)
	blackboard.set_fact(&"ambush_ready_ratio", 0.0)
	blackboard.set_fact(&"ambush_aim_ready_ratio", 0.0)
	blackboard.set_fact(&"tactical_plan", "SEARCH_SWEEP")
	_set_squad_searching(_last_contact_position)
	_issue_search_sweep()
	_order_timer = search_order_interval

func _release_unused_ambush_reservations() -> void:
	for member in _ambush_cover_assignments:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var cover: Node = get_ambush_cover_for(member)
		if is_instance_valid(cover) and member.actor.get_active_cover() != cover and cover.has_method("release_cover"):
			cover.release_cover(member.actor)

func _update_engagement(delta: float) -> void:
	if _contact_phase == ContactPhase.SEARCH:
		return
	if _contact_phase == ContactPhase.AMBUSH:
		_engagement_time += delta
		_update_ambush(delta)
		return
	if _contact_phase == ContactPhase.COMBAT:
		var primary_target := _find_primary_target()
		if primary_target != null:
			_engagement_time += delta
			return
	_reset_contact_state()

func _find_primary_target() -> Node2D:
	var origin := Vector2.ZERO
	if leader != null and is_instance_valid(leader) and leader.actor != null and is_instance_valid(leader.actor):
		origin = leader.actor.global_position
	var nearest: Node2D = null
	var nearest_distance := INF
	if _is_hostile_target(blackboard.shared_target):
		nearest = blackboard.shared_target
		nearest_distance = origin.distance_to(nearest.global_position)
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var perception := member.actor.get("perception_component") as PerceptionComponent
		if perception == null:
			continue
		for contact_value in perception.contacts.values():
			var contact := contact_value as CombatContact
			if contact == null or not _is_hostile_target(contact.target):
				continue
			var detected_distance := origin.distance_to(contact.last_known_position)
			if detected_distance < nearest_distance:
				nearest = contact.target
				nearest_distance = detected_distance
	return nearest

func _collect_known_hostile_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var seen: Dictionary = {}
	for member in members:
		if not is_instance_valid(member) or not is_instance_valid(member.actor):
			continue
		var perception := member.actor.get("perception_component") as PerceptionComponent
		if perception == null:
			continue
		for contact_value in perception.contacts.values():
			var contact := contact_value as CombatContact
			if contact != null and _is_hostile_target(contact.target) and not seen.has(contact.target):
				seen[contact.target] = true
				result.append(contact.target)
	return result

func _is_hostile_target(candidate) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return false
	if candidate.has_method("is_combat_alive") and not candidate.is_combat_alive():
		return false
	var reference_actor: Node = null
	if leader != null and is_instance_valid(leader) and leader.actor != null and is_instance_valid(leader.actor):
		reference_actor = leader.actor
	if reference_actor == null:
		for member in members:
			if is_instance_valid(member) and is_instance_valid(member.actor):
				reference_actor = member.actor
				break
	if reference_actor == null:
		if candidate.is_in_group("player"):
			return can_target_players
		if candidate.is_in_group("combatant") and candidate.has_method("get_combat_team"):
			return candidate.get_combat_team() != combat_team
		return false
	if reference_actor.has_method("can_damage_target"):
		return bool(reference_actor.can_damage_target(candidate))
	return candidate.is_in_group("player")

func _get_members_out_of_cover() -> Array[SquadMember]:
	var result: Array[SquadMember] = []
	for member in members:
		if is_instance_valid(member.actor) and member.actor.get_active_cover() == null:
			result.append(member)
	return result

func _get_highest_pressure_member() -> SquadMember:
	var result := members[0]
	var highest_pressure := -1.0
	for member in members:
		var component := member.actor.get("will_component") as WillComponent
		var member_pressure := component.pressure if component else 0.0
		if member_pressure > highest_pressure:
			result = member
			highest_pressure = member_pressure
	return result

func _on_member_died(member: SquadMember) -> void:
	_casualties += 1
	for survivor in members:
		if survivor != member and is_instance_valid(survivor.actor) and survivor.actor.has_method("report_ally_death"):
			survivor.actor.report_ally_death()
	unregister_member(member)
