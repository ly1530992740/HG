extends Node
class_name SquadRuleDecision3D

func choose_plan(
		has_target: bool,
		health_ratio: float,
		low_health_cover_ratio: float,
		enemy_aware: bool,
		our_power: float,
		enemy_power: float,
		has_flank_route: bool
) -> String:
	if not has_target:
		return "GUARD"
	if health_ratio <= low_health_cover_ratio:
		return "COVER_ATTACK"
	if not enemy_aware:
		return "AMBUSH"
	if our_power < enemy_power * 0.9 and has_flank_route:
		return "SUPPRESS_FLANK"
	if our_power > enemy_power * 1.8:
		return "ASSAULT"
	return "COVER_ATTACK"
