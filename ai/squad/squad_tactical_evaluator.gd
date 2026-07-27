extends RefCounted
class_name SquadTacticalEvaluator

enum Posture {
	ASSAULT,
	BALANCED,
	DEFENSIVE,
	ROUT,
}

var posture: Posture = Posture.BALANCED

func evaluate(blackboard: SquadBlackboard) -> Posture:
	var ally_count := int(blackboard.get_fact(&"ally_alive_count", 0))
	var force_ratio := float(blackboard.get_fact(&"force_ratio", 1.0))
	var casualties := float(blackboard.get_fact(&"squad_casualties", 0))
	var initial_strength := maxf(1.0, float(blackboard.get_fact(&"initial_squad_strength", 1)))
	var casualty_ratio := casualties / initial_strength
	var effective_ratio := force_ratio - casualty_ratio * 0.8

	if ally_count <= 2 and casualty_ratio >= 0.66 and force_ratio <= 1.0:
		posture = Posture.ROUT
		return posture

	match posture:
		Posture.ASSAULT:
			if effective_ratio < 3.2 or casualty_ratio >= 0.35:
				posture = Posture.BALANCED
		Posture.DEFENSIVE:
			if effective_ratio > 1.1 and casualty_ratio < 0.5:
				posture = Posture.BALANCED
		Posture.ROUT:
			if force_ratio > 1.25 and casualty_ratio < 0.66:
				posture = Posture.DEFENSIVE
		_:
			if effective_ratio >= 4.0 and casualty_ratio < 0.35:
				posture = Posture.ASSAULT
			elif effective_ratio < 0.9 or casualty_ratio >= 0.5:
				posture = Posture.DEFENSIVE

	return posture

func get_posture_name() -> String:
	return Posture.keys()[posture]
