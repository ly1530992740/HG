extends RefCounted
class_name FireSuperiorityAssessment3D

enum State { WINNING, CONTESTED, LOSING, PINNED }

func assess(members: Array[Soldier3D], known_enemy_power: float) -> Dictionary:
	if members.is_empty():
		return _result(State.PINNED, 0.0, 0.0, 0.0, 0)
	var suppression_total := 0.0
	var pinned_count := 0
	var covered_count := 0
	var available_shooters := 0
	var effective_power := 0.0
	for member in members:
		var suppression := member.get_suppression_ratio()
		suppression_total += suppression
		pinned_count += 1 if member.is_pinned() else 0
		covered_count += 1 if is_instance_valid(member.active_cover) else 0
		if not member.is_pinned() and (not member.uses_ammunition() or member.magazine_ammo > 0):
			available_shooters += 1
		var cover_factor := 1.15 if is_instance_valid(member.active_cover) else 0.9
		effective_power += member.get_combat_power() * maxf(0.12, 1.0 - suppression * 0.82) * cover_factor
	var count := float(members.size())
	var suppression_ratio := suppression_total / count
	var pinned_ratio := float(pinned_count) / count
	var cover_ratio := float(covered_count) / count
	var enemy_pressure := maxf(0.1, known_enemy_power)
	var friendly_pressure := effective_power
	var pressure_ratio := friendly_pressure / enemy_pressure
	var state := State.CONTESTED
	if pinned_ratio >= 0.5 or available_shooters == 0:
		state = State.PINNED
	elif pressure_ratio >= 1.35 and suppression_ratio < 0.28:
		state = State.WINNING
	elif pressure_ratio < 0.72 or suppression_ratio >= 0.48:
		state = State.LOSING
	return _result(state, suppression_ratio, pinned_ratio, cover_ratio, available_shooters, pressure_ratio)

func _result(
		state: State,
		suppression_ratio: float,
		pinned_ratio: float,
		cover_ratio: float,
		available_shooters: int,
		pressure_ratio := 0.0
) -> Dictionary:
	return {
		"state": state,
		"state_name": State.keys()[state],
		"suppression_ratio": suppression_ratio,
		"pinned_ratio": pinned_ratio,
		"cover_ratio": cover_ratio,
		"available_shooters": available_shooters,
		"pressure_ratio": pressure_ratio,
	}
