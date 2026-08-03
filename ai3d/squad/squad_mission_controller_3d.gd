extends RefCounted
class_name SquadMissionController3D

signal state_changed(previous: State, current: State)

enum MissionType { CAPTURE_AND_HOLD, ELIMINATE_AND_RETURN }
enum State { APPROACHING, CLEARING, HOLDING, RETURNING, COMPLETE }

var mission_type := MissionType.CAPTURE_AND_HOLD
var defensive_posture := false
var target_position := Vector3.ZERO
var target_radius := 8.0
var return_radius := 2.0
var clear_confirmation_seconds := 1.0
var origin_position := Vector3.ZERO
var state: State = State.APPROACHING
var _clear_elapsed := 0.0
var _objective_clear_confirmed := false

func configure(
		new_type: int,
		new_target_position: Vector3,
		new_target_radius: float,
		new_origin_position: Vector3,
		new_clear_confirmation_seconds: float,
		new_return_radius: float,
		new_defensive_posture := false
) -> void:
	mission_type = new_type
	defensive_posture = new_defensive_posture
	target_position = new_target_position
	target_radius = maxf(1.0, new_target_radius)
	origin_position = new_origin_position
	clear_confirmation_seconds = maxf(0.0, new_clear_confirmation_seconds)
	return_radius = maxf(0.5, new_return_radius)
	state = State.APPROACHING
	_clear_elapsed = 0.0
	_objective_clear_confirmed = defensive_posture

func update(delta: float, squad_center: Vector3, known_hostile_in_target: bool, objective_area_observed := false) -> void:
	var inside_target := _flat_distance(squad_center, target_position) <= target_radius * 0.72
	if known_hostile_in_target:
		_objective_clear_confirmed = false
		_clear_elapsed = 0.0
	elif objective_area_observed:
		_clear_elapsed += delta
		if _clear_elapsed >= clear_confirmation_seconds:
			_objective_clear_confirmed = true
	else:
		_clear_elapsed = 0.0
	match mission_type:
		MissionType.CAPTURE_AND_HOLD:
			if state == State.HOLDING:
				return
			if not inside_target:
				_set_state(State.APPROACHING)
			elif not _objective_clear_confirmed:
				_set_state(State.CLEARING)
			else:
				_set_state(State.HOLDING)
		MissionType.ELIMINATE_AND_RETURN:
			if state in [State.RETURNING, State.COMPLETE]:
				if _flat_distance(squad_center, origin_position) <= return_radius:
					_set_state(State.COMPLETE)
				return
			if not _objective_clear_confirmed:
				_set_state(State.CLEARING if inside_target else State.APPROACHING)
			else:
				_set_state(State.RETURNING)

func get_destination() -> Vector3:
	return origin_position if state in [State.RETURNING, State.COMPLETE] else target_position

func is_defense_locked() -> bool:
	return defensive_posture or state in [State.HOLDING, State.COMPLETE]

func is_objective_clear_confirmed() -> bool:
	return _objective_clear_confirmed

func get_state_name() -> String:
	return State.keys()[state]

func get_mission_type_name() -> String:
	return MissionType.keys()[mission_type]

func _set_state(next: State) -> void:
	if state == next:
		return
	var previous := state
	state = next
	state_changed.emit(previous, state)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
