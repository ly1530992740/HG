extends Node
class_name AlertComponent

signal state_changed(previous: State, current: State)

enum State {
	UNAWARE,
	SUSPICIOUS,
	SEARCHING,
	OBSERVING,
	CONTACT,
	COMBAT,
}

var actor: Node2D = null
var state: State = State.UNAWARE
var last_stimulus_position := Vector2.ZERO
var last_state_change_msec := 0

func setup(new_actor: Node2D) -> void:
	actor = new_actor
	last_state_change_msec = Time.get_ticks_msec()

func set_state(new_state: State, stimulus_position := Vector2.ZERO) -> void:
	if stimulus_position != Vector2.ZERO:
		last_stimulus_position = stimulus_position
	if state == new_state:
		return
	var previous := state
	state = new_state
	last_state_change_msec = Time.get_ticks_msec()
	state_changed.emit(previous, state)

func register_suspicion(position: Vector2) -> void:
	if state < State.SUSPICIOUS:
		set_state(State.SUSPICIOUS, position)
	else:
		last_stimulus_position = position

func register_observation(position: Vector2) -> void:
	if state < State.OBSERVING:
		set_state(State.OBSERVING, position)

func register_contact(position: Vector2) -> void:
	if state < State.CONTACT:
		set_state(State.CONTACT, position)

func enter_combat(position := Vector2.ZERO) -> void:
	set_state(State.COMBAT, position)

func is_aware_of_combat() -> bool:
	return state >= State.CONTACT

func get_state_name() -> String:
	return State.keys()[state]
