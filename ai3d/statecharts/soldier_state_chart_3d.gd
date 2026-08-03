extends Node
class_name SoldierStateChart3D

enum RootState {
	DEAD,
	SURVIVAL_OVERRIDE,
	EXECUTE_ORDER,
	IDLE_SECURITY,
}

enum OrderState {
	NONE,
	MOVE,
	TAKE_COVER,
	ATTACK,
	SUPPRESS,
	FLANK,
	RECON,
	HOLD_SECTOR,
	WITHDRAW,
	USE_STRUCTURE,
}

enum ReactionState {
	NONE,
	EMERGENCY_COVER,
	EVADE_DANGER,
	PRONE,
	PINNED_WAIT,
	RETURN_FIRE,
}

enum Action {
	NONE,
	MOVE,
	ENTER_COVER,
	ACQUIRE_TARGET,
	APPROACH_TARGET,
	AIM,
	RELOAD,
	ENGAGE,
	ENTER_STRUCTURE,
	OPERATE_STRUCTURE,
	GUARD,
	OBSERVE,
	SEEK_COVER,
	DROP_PRONE,
	TAKE_KNEE,
	RECOVER_MOVEMENT_POSTURE,
	FLINCH_AND_ASSESS,
	ORIENT_TO_THREAT,
	COMMUNICATE_CONTACT,
	ACQUIRE_VISIBLE_TARGET,
	RELOAD_COVERED,
	RELOAD_SAFE,
	RETURN_FIRE,
	WAIT_FOR_OPENING,
	SCAN_THREAT_SECTOR,
	GUARD_SECTOR,
	EVADE_DANGER,
	ENTER_DEFENSIVE_STRUCTURE,
}

const EVENT_DIRECTIVE_RECEIVED := &"directive_received"
const EVENT_DIRECTIVE_CLEARED := &"directive_cleared"
const EVENT_DANGER_DETECTED := &"danger_detected"
const EVENT_DANGER_CLEARED_WITH_ORDER := &"danger_cleared_with_order"
const EVENT_DANGER_CLEARED_WITHOUT_ORDER := &"danger_cleared_without_order"
const EVENT_ACTOR_DIED := &"actor_died"

var root_state := RootState.IDLE_SECURITY
var order_state := OrderState.NONE
var reaction_state := ReactionState.NONE
var current_action := Action.NONE

var _actor: Soldier3D
var _chart: StateChart
var _directive_version := 0
var _at_order_destination := false
var _action_elapsed := 0.0
var _survival_actions: Array[int] = []
var _survival_index := 0
var _resume_order_state := OrderState.NONE
var _chart_started := false

func setup(actor: Soldier3D) -> void:
	_actor = actor
	_chart = $StateChart as StateChart

func tick(delta: float) -> void:
	if not is_instance_valid(_actor) or not _chart_started:
		return
	_actor.state_chart_refresh_context()
	if _actor.dead:
		if root_state != RootState.DEAD:
			_chart.send_event(EVENT_ACTOR_DIED)
		return
	_sync_directive()
	if root_state != RootState.SURVIVAL_OVERRIDE and _actor.state_chart_should_survival_override():
		_chart.send_event(EVENT_DANGER_DETECTED)
	match root_state:
		RootState.SURVIVAL_OVERRIDE:
			_process_survival(delta)
		RootState.EXECUTE_ORDER:
			_process_order(delta)
		RootState.IDLE_SECURITY:
			_process_idle(delta)

func notify_directive_received() -> void:
	if not is_instance_valid(_actor):
		return
	var version := _actor.get_directive_version()
	if version == _directive_version:
		return
	_directive_version = version
	_at_order_destination = false
	order_state = _map_order_state(_actor.get_active_directive())
	if root_state == RootState.SURVIVAL_OVERRIDE:
		_resume_order_state = order_state
	elif _chart_started:
		_chart.send_event(EVENT_DIRECTIVE_RECEIVED)

func notify_actor_died() -> void:
	if _chart_started and root_state != RootState.DEAD:
		_chart.send_event(EVENT_ACTOR_DIED)

func reset_runtime_state() -> void:
	_finish_action()
	_directive_version = _actor.get_directive_version() if is_instance_valid(_actor) else 0
	_at_order_destination = false
	_survival_actions.clear()
	_survival_index = 0
	reaction_state = ReactionState.NONE
	order_state = _map_order_state(_actor.get_active_directive()) if is_instance_valid(_actor) and _actor.has_active_directive() else OrderState.NONE
	if not _chart_started:
		return
	if order_state != OrderState.NONE:
		match root_state:
			RootState.IDLE_SECURITY:
				_chart.send_event(EVENT_DIRECTIVE_RECEIVED)
			RootState.SURVIVAL_OVERRIDE:
				_chart.send_event(EVENT_DANGER_CLEARED_WITH_ORDER)
	else:
		match root_state:
			RootState.EXECUTE_ORDER:
				_chart.send_event(EVENT_DIRECTIVE_CLEARED)
			RootState.SURVIVAL_OVERRIDE:
				_chart.send_event(EVENT_DANGER_CLEARED_WITHOUT_ORDER)

func get_debug_snapshot() -> Dictionary:
	return {
		"root_state": RootState.keys()[root_state],
		"order_state": OrderState.keys()[order_state],
		"reaction_state": ReactionState.keys()[reaction_state],
		"action": Action.keys()[current_action],
		"directive_version": _directive_version,
		"resume_order_state": OrderState.keys()[_resume_order_state],
		"at_order_destination": _at_order_destination,
		"state_chart_active": _chart_started,
	}

func get_state_chart() -> StateChart:
	return _chart

func is_return_fire_active() -> bool:
	return root_state == RootState.SURVIVAL_OVERRIDE and reaction_state == ReactionState.RETURN_FIRE

func _on_root_state_entered(next_state: int) -> void:
	var previous_state := root_state
	root_state = next_state
	_chart_started = true
	match next_state:
		RootState.SURVIVAL_OVERRIDE:
			_resume_order_state = order_state if previous_state == RootState.EXECUTE_ORDER else OrderState.NONE
			reaction_state = ReactionState.NONE
			_survival_actions = _actor.state_chart_build_survival_actions()
			_survival_index = 0
		RootState.EXECUTE_ORDER:
			order_state = _resume_order_state if _resume_order_state != OrderState.NONE else _map_order_state(_actor.get_active_directive())
			_resume_order_state = OrderState.NONE
			reaction_state = ReactionState.NONE
		RootState.IDLE_SECURITY:
			order_state = OrderState.NONE
			reaction_state = ReactionState.NONE
		RootState.DEAD:
			order_state = OrderState.NONE
			reaction_state = ReactionState.NONE

func _on_root_state_exited(leaving_state: int) -> void:
	_finish_action()
	if leaving_state == RootState.SURVIVAL_OVERRIDE:
		_survival_actions.clear()
		_survival_index = 0
		reaction_state = ReactionState.NONE

func _sync_directive() -> void:
	if _actor.has_active_directive():
		if _actor.get_directive_version() != _directive_version:
			notify_directive_received()
		elif root_state == RootState.IDLE_SECURITY:
			order_state = _map_order_state(_actor.get_active_directive())
			_chart.send_event(EVENT_DIRECTIVE_RECEIVED)
		return
	if root_state == RootState.EXECUTE_ORDER:
		order_state = OrderState.NONE
		_chart.send_event(EVENT_DIRECTIVE_CLEARED)

func _process_survival(delta: float) -> void:
	if current_action == Action.NONE:
		if _survival_index >= _survival_actions.size():
			_actor.state_chart_on_survival_sequence_completed()
			if _actor.state_chart_should_survival_override():
				_survival_actions = _actor.state_chart_build_survival_actions()
				_survival_index = 0
			if _survival_actions.is_empty() or _survival_index >= _survival_actions.size():
				_leave_survival_override()
				return
		_start_action(_survival_actions[_survival_index])
		_update_reaction_state(current_action)
	var completed := _actor.state_chart_perform_action(current_action, delta)
	_action_elapsed += delta
	if completed:
		_finish_action()
		_survival_index += 1
	elif _action_elapsed >= _get_action_timeout(current_action):
		_actor.state_chart_on_action_failed(current_action)
		_finish_action()
		_survival_actions = _actor.state_chart_build_survival_actions()
		_survival_index = 0

func _leave_survival_override() -> void:
	_finish_action()
	if _actor.has_active_directive():
		if _resume_order_state == OrderState.NONE:
			_resume_order_state = _map_order_state(_actor.get_active_directive())
		_chart.send_event(EVENT_DANGER_CLEARED_WITH_ORDER)
	else:
		_resume_order_state = OrderState.NONE
		_chart.send_event(EVENT_DANGER_CLEARED_WITHOUT_ORDER)

func _process_order(delta: float) -> void:
	if not _actor.has_active_directive():
		_chart.send_event(EVENT_DIRECTIVE_CLEARED)
		return
	var next_action := _select_order_action()
	if next_action == Action.NONE:
		_finish_action()
		_actor.on_directive_plan_completed()
		return
	if current_action != next_action:
		_finish_action()
		_start_action(next_action)
	var completed := _actor.state_chart_perform_action(current_action, delta)
	_action_elapsed += delta
	if completed:
		var completed_action := current_action
		_finish_action()
		if completed_action == Action.MOVE:
			_at_order_destination = true
		elif completed_action in [Action.ENTER_COVER, Action.ENGAGE, Action.GUARD, Action.OBSERVE, Action.OPERATE_STRUCTURE]:
			_actor.on_directive_plan_completed()

func _select_order_action() -> int:
	var directive := _actor.get_active_directive()
	if directive == null:
		return Action.NONE
	if directive.requires_movement() and not _at_order_destination:
		return Action.MOVE
	if directive.requires_cover():
		return Action.NONE if _actor.state_chart_is_assigned_cover_active() else Action.ENTER_COVER
	if directive.requires_structure():
		if not _actor.state_chart_is_assigned_structure_active():
			return Action.ENTER_STRUCTURE
		return Action.OPERATE_STRUCTURE
	if directive.requires_target():
		if not _actor.state_chart_has_valid_target():
			return Action.ACQUIRE_TARGET
		if directive.type != SquadDirective3D.Type.AIM and not _actor.state_chart_target_in_weapon_range():
			return Action.APPROACH_TARGET
		if _actor.uses_ammunition() and _actor.magazine_ammo <= 0 and _actor.reserve_ammo > 0:
			return Action.RELOAD
		if not _actor.is_aimed:
			return Action.AIM
		if directive.type == SquadDirective3D.Type.AIM:
			return Action.NONE
		return Action.ENGAGE
	match directive.type:
		SquadDirective3D.Type.GUARD, SquadDirective3D.Type.HOLD_SECTOR:
			return Action.GUARD
		SquadDirective3D.Type.RECON:
			return Action.OBSERVE
	return Action.NONE

func _process_idle(delta: float) -> void:
	var next_action := _actor.state_chart_select_idle_action()
	if current_action != next_action:
		_finish_action()
		if next_action != Action.NONE:
			_start_action(next_action)
	if current_action == Action.NONE:
		return
	var completed := _actor.state_chart_perform_action(current_action, delta)
	_action_elapsed += delta
	if completed:
		_actor.state_chart_on_idle_action_completed(current_action)
		_finish_action()

func _start_action(action: int) -> void:
	current_action = action
	_action_elapsed = 0.0
	_actor.state_chart_begin_action(action)

func _finish_action() -> void:
	if current_action != Action.NONE and is_instance_valid(_actor):
		_actor.state_chart_end_action(current_action)
	current_action = Action.NONE
	_action_elapsed = 0.0

func _update_reaction_state(action: int) -> void:
	match action:
		Action.SEEK_COVER:
			reaction_state = ReactionState.EMERGENCY_COVER
		Action.EVADE_DANGER:
			reaction_state = ReactionState.EVADE_DANGER
		Action.DROP_PRONE, Action.TAKE_KNEE:
			reaction_state = ReactionState.PRONE
		Action.WAIT_FOR_OPENING:
			reaction_state = ReactionState.PINNED_WAIT
		Action.FLINCH_AND_ASSESS, Action.ORIENT_TO_THREAT, Action.COMMUNICATE_CONTACT, \
		Action.ACQUIRE_VISIBLE_TARGET, Action.RELOAD_COVERED, Action.AIM, Action.RETURN_FIRE, Action.SCAN_THREAT_SECTOR:
			reaction_state = ReactionState.RETURN_FIRE
		_:
			reaction_state = ReactionState.NONE

func _map_order_state(directive: SquadDirective3D) -> int:
	if directive == null:
		return OrderState.NONE
	match directive.type:
		SquadDirective3D.Type.MOVE:
			return OrderState.MOVE
		SquadDirective3D.Type.TAKE_COVER:
			return OrderState.TAKE_COVER
		SquadDirective3D.Type.AIM, SquadDirective3D.Type.ATTACK:
			return OrderState.ATTACK
		SquadDirective3D.Type.SUPPRESS:
			return OrderState.SUPPRESS
		SquadDirective3D.Type.FLANK:
			return OrderState.FLANK
		SquadDirective3D.Type.RECON:
			return OrderState.RECON
		SquadDirective3D.Type.GUARD, SquadDirective3D.Type.HOLD_SECTOR:
			return OrderState.HOLD_SECTOR
		SquadDirective3D.Type.WITHDRAW:
			return OrderState.WITHDRAW
		SquadDirective3D.Type.USE_STRUCTURE:
			return OrderState.USE_STRUCTURE
	return OrderState.NONE

func _get_action_timeout(action: int) -> float:
	match action:
		Action.SEEK_COVER, Action.EVADE_DANGER, Action.ENTER_DEFENSIVE_STRUCTURE:
			return 7.0
		Action.ACQUIRE_VISIBLE_TARGET:
			return 1.2
		Action.AIM, Action.RELOAD_COVERED, Action.RELOAD_SAFE:
			return 4.0
	return 3.0
