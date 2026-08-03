extends RefCounted
class_name SquadTacticalOption3D

var option_id := ""
var kind := ""
var utility := 0.0
var reason := ""
var method_id := "STANDARD"
var metrics: Dictionary = {}
var plan_template: SquadCommandPlan3D

func configure(
		new_id: String,
		new_kind: String,
		new_utility: float,
		new_reason: String,
		new_method_id: String,
		new_metrics: Dictionary,
		new_plan_template: SquadCommandPlan3D
) -> SquadTacticalOption3D:
	option_id = new_id
	kind = new_kind
	utility = new_utility
	reason = new_reason
	method_id = new_method_id
	metrics = new_metrics.duplicate(true)
	plan_template = new_plan_template
	return self

func to_candidate() -> Dictionary:
	var candidate := {
		"id": option_id,
		"kind": kind,
		"utility": utility,
		"reason": reason,
		"method": method_id,
		"tactical_option": self,
	}
	for key in metrics:
		candidate[key] = metrics[key]
	return candidate

func materialize(plan_id: StringName, belief_version: int) -> SquadCommandPlan3D:
	if plan_template == null:
		return null
	var plan := plan_template.clone_for_patch()
	plan.plan_id = plan_id
	plan.belief_version = belief_version
	plan.created_msec = Time.get_ticks_msec()
	plan.source = "TACTICAL_OPTION:%s" % method_id
	plan.reason = reason
	return plan
