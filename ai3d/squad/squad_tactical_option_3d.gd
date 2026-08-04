extends RefCounted
class_name SquadTacticalOption3D

var option_id := ""
var kind := ""
var utility := 0.0
var reason := ""
var metrics: Dictionary = {}
var requirements: Array[Dictionary] = []

func configure(
		new_id: String,
		new_kind: String,
		new_utility: float,
		new_reason: String,
		new_metrics: Dictionary,
		new_requirements: Array[Dictionary] = []
) -> SquadTacticalOption3D:
	option_id = new_id
	kind = new_kind
	utility = new_utility
	reason = new_reason
	metrics = new_metrics.duplicate(true)
	requirements = new_requirements.duplicate(true)
	return self

func to_candidate() -> Dictionary:
	var candidate := {
		"id": option_id,
		"kind": kind,
		"utility": utility,
		"reason": reason,
		"requirements": requirements.duplicate(true),
	}
	for key in metrics:
		candidate[key] = metrics[key]
	return candidate
