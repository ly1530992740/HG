extends RefCounted
class_name SquadDirective3D

enum Type {
	GUARD,
	MOVE,
	TAKE_COVER,
	AIM,
	ATTACK,
	SUPPRESS,
	FLANK,
	RECON,
	HOLD_SECTOR,
	WITHDRAW,
	USE_STRUCTURE,
}

enum RulesOfEngagement {
	WEAPONS_HOLD,
	RETURN_FIRE,
	WEAPONS_FREE,
}

enum ExecutionPolicy {
	COMMITTED,
	CAUTIOUS,
}

var type: Type = Type.GUARD
var version := 0
var target: Node3D
var target_position := Vector3.ZERO
var route: Array[Vector3] = []
var route_constraints: Array[Vector3] = []
var route_influence_version := 0
var route_total_cost := 0.0
var route_peak_threat := 0.0
var route_length := 0.0
var route_baseline_length := 0.0
var route_length_ratio := 1.0
var route_selection_reason := ""
var assigned_cover: TacticalCover3D
var assigned_structure: TacticalStructure3D
var duration := 0.0
var reason := ""
var zone_id: StringName = &""
var rules_of_engagement := RulesOfEngagement.WEAPONS_FREE
var observation_seconds := 1.5
var execution_policy := ExecutionPolicy.COMMITTED
var max_route_length_ratio := 1.65
var max_route_extra_distance := 10.0

func configure(
		new_type: Type,
		new_version: int,
		new_target: Node3D = null,
		new_position := Vector3.ZERO,
		new_route: Array[Vector3] = [],
		new_cover: TacticalCover3D = null,
		new_duration := 0.0,
		new_reason := "",
		new_zone_id: StringName = &"",
		new_rules_of_engagement: int = RulesOfEngagement.WEAPONS_FREE,
		new_structure: TacticalStructure3D = null,
		new_execution_policy: int = ExecutionPolicy.COMMITTED,
		new_max_route_length_ratio := 1.65,
		new_max_route_extra_distance := 10.0
) -> SquadDirective3D:
	type = new_type
	version = new_version
	target = new_target
	target_position = new_position
	route = new_route.duplicate()
	route_constraints = new_route.duplicate()
	assigned_cover = new_cover
	duration = new_duration
	reason = new_reason
	zone_id = new_zone_id
	rules_of_engagement = new_rules_of_engagement
	assigned_structure = new_structure
	execution_policy = new_execution_policy
	max_route_length_ratio = maxf(1.0, new_max_route_length_ratio)
	max_route_extra_distance = maxf(0.0, new_max_route_extra_distance)
	return self

func apply_route_plan(plan: Dictionary) -> void:
	var planned_route: Array[Vector3] = []
	planned_route.assign(plan.get("route", []))
	route = planned_route
	route_influence_version = int(plan.get("influence_version", 0))
	route_total_cost = float(plan.get("total_cost", 0.0))
	route_peak_threat = float(plan.get("peak_threat", 0.0))
	route_length = float(plan.get("route_length", 0.0))
	route_baseline_length = float(plan.get("baseline_length", route_length))
	route_length_ratio = float(plan.get("length_ratio", 1.0))
	route_selection_reason = String(plan.get("selection_reason", ""))

func requires_movement() -> bool:
	return type in [Type.GUARD, Type.MOVE, Type.TAKE_COVER, Type.FLANK, Type.RECON, Type.HOLD_SECTOR, Type.WITHDRAW, Type.USE_STRUCTURE]

func requires_cover() -> bool:
	return type == Type.TAKE_COVER

func requires_structure() -> bool:
	return type == Type.USE_STRUCTURE and is_instance_valid(assigned_structure)

func requires_target() -> bool:
	return type in [Type.AIM, Type.ATTACK, Type.SUPPRESS, Type.FLANK]

func requires_aim() -> bool:
	return type in [Type.AIM, Type.ATTACK, Type.SUPPRESS, Type.FLANK]

func get_label() -> String:
	if type == Type.USE_STRUCTURE:
		return "Use defensive structure"
	match type:
		Type.GUARD:
			return "原地警戒"
		Type.MOVE:
			return "移动"
		Type.TAKE_COVER:
			return "占领掩体"
		Type.AIM:
			return "瞄准目标"
		Type.ATTACK:
			return "消灭目标"
		Type.SUPPRESS:
			return "正面压制"
		Type.FLANK:
			return "侧翼包抄"
		Type.RECON:
			return "侦察区域"
		Type.HOLD_SECTOR:
			return "固守区域"
		Type.WITHDRAW:
			return "撤回原位"
	return "待命"
