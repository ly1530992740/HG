extends Node
class_name WillComponent

signal mental_state_changed(state: MentalState)
signal pressure_changed(pressure: float)

enum Profile {
	INDOCTRINATED,
	REGULAR,
	TIMID,
}

enum MentalState {
	ZEALOUS,
	STEADY,
	AFRAID,
	RECOVERING,
	BROKEN,
	SURRENDERED,
}

@export var profile: Profile = Profile.REGULAR
@export var fear_entry_hold := 0.9
@export var afraid_min_duration := 12.0
@export var recovery_safe_duration := 6.0
@export var recovering_duration := 12.0

var actor: Node2D = null
var mental_state: MentalState = MentalState.STEADY
var pressure := 0.0
var confidence := 50.0
var time_since_threat := 0.0
var lock_to_steady := false

var _event_pressure := 0.0
var _state_elapsed := 0.0
var _fear_candidate_elapsed := 0.0
var _high_pressure_elapsed := 0.0
var _calm_elapsed := 0.0
var _severe_shock_pending := false

func setup(new_actor: Node2D, new_profile: Profile) -> void:
	actor = new_actor
	profile = new_profile
	match profile:
		Profile.INDOCTRINATED:
			confidence = 78.0
			mental_state = MentalState.ZEALOUS
		Profile.TIMID:
			confidence = 32.0
			mental_state = MentalState.STEADY
		_:
			confidence = 50.0
			mental_state = MentalState.STEADY

func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	time_since_threat += delta
	_state_elapsed += delta
	_event_pressure = move_toward(_event_pressure, 0.0, delta * 2.0)

	var target_pressure := _calculate_environment_pressure()
	var previous_pressure := pressure
	var pressure_rate := 8.0 if target_pressure > pressure else 2.5
	pressure = move_toward(pressure, target_pressure, delta * pressure_rate)
	pressure = clampf(pressure, 0.0, 100.0)
	if not is_equal_approx(previous_pressure, pressure):
		pressure_changed.emit(pressure)

	if time_since_threat > 10.0 and pressure < 30.0:
		confidence = minf(100.0, confidence + delta * 1.5)
	else:
		confidence = maxf(0.0, confidence - delta * pressure / 240.0)
	if lock_to_steady:
		if mental_state != MentalState.STEADY:
			_set_mental_state(MentalState.STEADY)
	else:
		_update_mental_state(delta)
	_severe_shock_pending = false

func set_lock_to_steady(enabled: bool) -> void:
	lock_to_steady = enabled
	if lock_to_steady:
		confidence = 50.0
		_set_mental_state(MentalState.STEADY)

func report_damage(amount: int) -> void:
	_event_pressure = minf(100.0, _event_pressure + 10.0 + float(amount) * 2.0)
	time_since_threat = 0.0
	confidence = maxf(0.0, confidence - 8.0)
	if amount >= 2:
		_severe_shock_pending = true

func report_near_miss() -> void:
	_event_pressure = minf(100.0, _event_pressure + 2.0)
	time_since_threat = 0.0
	confidence = maxf(0.0, confidence - 0.5)

func report_ally_death() -> void:
	_event_pressure = minf(100.0, _event_pressure + 24.0)
	time_since_threat = 0.0
	confidence = maxf(0.0, confidence - 12.0)
	_severe_shock_pending = true

func get_order_goal_priority() -> int:
	var result: int
	match profile:
		Profile.INDOCTRINATED:
			result = 100
		Profile.TIMID:
			result = 48
		_:
			result = 72
	match mental_state:
		MentalState.ZEALOUS:
			result += 18
		MentalState.AFRAID:
			result -= 22
		MentalState.RECOVERING:
			result -= 8
		MentalState.BROKEN:
			result -= 45
		MentalState.SURRENDERED:
			result = 0
	return maxi(0, result)

func get_survival_goal_priority() -> int:
	var result: int
	match profile:
		Profile.INDOCTRINATED:
			result = 18
		Profile.TIMID:
			result = 68
		_:
			result = 38
	match mental_state:
		MentalState.AFRAID:
			result += 45
		MentalState.RECOVERING:
			result += 18
		MentalState.BROKEN:
			result += 75
		MentalState.ZEALOUS:
			result -= 12
	return maxi(0, result)

func get_command_cost(base_cost: int) -> int:
	var multiplier := 1.0
	match profile:
		Profile.INDOCTRINATED:
			multiplier = 0.6
		Profile.TIMID:
			multiplier = 1.45
	match mental_state:
		MentalState.ZEALOUS:
			multiplier *= 0.75
		MentalState.AFRAID:
			multiplier *= 1.35
		MentalState.RECOVERING:
			multiplier *= 1.15
		MentalState.BROKEN:
			multiplier *= 2.0
	return maxi(1, int(round(float(base_cost) * multiplier)))

func should_seek_safety() -> bool:
	if lock_to_steady:
		return false
	return mental_state in [MentalState.AFRAID, MentalState.RECOVERING, MentalState.BROKEN]

func get_profile_name() -> String:
	return Profile.keys()[profile]

func get_state_name() -> String:
	return MentalState.keys()[mental_state]

func get_state_elapsed() -> float:
	return _state_elapsed

func _calculate_environment_pressure() -> float:
	var result := _event_pressure
	var max_health_value := maxi(1, int(actor.get("max_health")))
	var health_value := int(actor.get("health"))
	result += (1.0 - float(health_value) / float(max_health_value)) * 34.0

	var member := actor.get("squad_member") as SquadMember
	if member != null and member.blackboard != null:
		var board := member.blackboard
		var force_ratio := float(board.get_fact(&"force_ratio", 1.0))
		var casualties := float(board.get_fact(&"squad_casualties", 0))
		var initial_strength := maxf(1.0, float(board.get_fact(&"initial_squad_strength", 1)))
		result += maxf(0.0, 1.0 - force_ratio) * 38.0
		result += casualties / initial_strength * 42.0
		if not bool(board.get_fact(&"leader_alive", true)):
			result += 18.0

	if actor.has_method("get_active_cover") and actor.get_active_cover() != null:
		result -= 12.0
	return clampf(result, 0.0, 100.0)

func _update_mental_state(delta: float) -> void:
	if mental_state == MentalState.SURRENDERED or mental_state == MentalState.BROKEN:
		return

	var afraid_threshold := _get_afraid_threshold()
	var broken_threshold := _get_broken_threshold()
	var recovery_threshold := _get_recovery_threshold()

	if mental_state == MentalState.AFRAID:
		_update_broken_candidate(delta, broken_threshold)
		if mental_state == MentalState.BROKEN or _state_elapsed < _get_afraid_min_duration():
			return
		if pressure <= recovery_threshold and _is_safe_for_recovery():
			_calm_elapsed += delta
			if _calm_elapsed >= _get_recovery_safe_duration():
				_set_mental_state(MentalState.RECOVERING)
		else:
			_calm_elapsed = 0.0
		return

	if mental_state == MentalState.RECOVERING:
		if _severe_shock_pending or pressure >= afraid_threshold + 12.0:
			_set_mental_state(MentalState.AFRAID)
			return
		if _state_elapsed >= _get_recovering_duration() and pressure <= afraid_threshold:
			_set_mental_state(_get_stable_state())
		return

	_update_broken_candidate(delta, broken_threshold)
	if mental_state == MentalState.BROKEN:
		return
	if pressure >= afraid_threshold:
		_fear_candidate_elapsed += delta
		if _fear_candidate_elapsed >= _get_fear_entry_hold():
			_set_mental_state(MentalState.AFRAID)
	else:
		_fear_candidate_elapsed = 0.0
		if _state_elapsed >= 15.0:
			var stable_state := _get_stable_state()
			if mental_state != stable_state:
				_set_mental_state(stable_state)

func _update_broken_candidate(delta: float, threshold: float) -> void:
	if pressure >= threshold:
		_high_pressure_elapsed += delta
		if _high_pressure_elapsed >= 1.5:
			_set_mental_state(MentalState.BROKEN)
	else:
		_high_pressure_elapsed = 0.0

func _set_mental_state(new_state: MentalState) -> void:
	if new_state == mental_state:
		return
	mental_state = new_state
	_state_elapsed = 0.0
	_fear_candidate_elapsed = 0.0
	_high_pressure_elapsed = 0.0
	_calm_elapsed = 0.0
	mental_state_changed.emit(mental_state)

func _is_safe_for_recovery() -> bool:
	if time_since_threat < 3.0:
		return false
	if not actor.has_method("get_active_cover") or actor.get_active_cover() == null:
		return false
	var suppression_component := actor.get("suppression_component") as SuppressionComponent
	return suppression_component == null or not suppression_component.is_under_fire()

func _get_stable_state() -> MentalState:
	if profile == Profile.INDOCTRINATED:
		return MentalState.ZEALOUS
	if profile == Profile.REGULAR and confidence >= 82.0 and pressure <= 25.0:
		return MentalState.ZEALOUS
	return MentalState.STEADY

func _get_afraid_threshold() -> float:
	match profile:
		Profile.INDOCTRINATED:
			return 82.0
		Profile.TIMID:
			return 36.0
	return 62.0

func _get_broken_threshold() -> float:
	match profile:
		Profile.INDOCTRINATED:
			return 96.0
		Profile.TIMID:
			return 78.0
	return 90.0

func _get_recovery_threshold() -> float:
	match profile:
		Profile.INDOCTRINATED:
			return 66.0
		Profile.TIMID:
			return 22.0
	return 42.0

func _get_fear_entry_hold() -> float:
	match profile:
		Profile.INDOCTRINATED:
			return fear_entry_hold * 1.8
		Profile.TIMID:
			return fear_entry_hold * 0.55
	return fear_entry_hold

func _get_afraid_min_duration() -> float:
	match profile:
		Profile.INDOCTRINATED:
			return afraid_min_duration * 0.8
		Profile.TIMID:
			return afraid_min_duration * 1.25
	return afraid_min_duration

func _get_recovery_safe_duration() -> float:
	return recovery_safe_duration * (1.3 if profile == Profile.TIMID else 1.0)

func _get_recovering_duration() -> float:
	return recovering_duration * (1.25 if profile == Profile.TIMID else 1.0)
