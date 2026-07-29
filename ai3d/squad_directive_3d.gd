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
}

var type: Type = Type.GUARD
var version := 0
var target: Node3D
var target_position := Vector3.ZERO
var route: Array[Vector3] = []
var assigned_cover: TacticalCover3D
var duration := 0.0
var reason := ""

func configure(
		new_type: Type,
		new_version: int,
		new_target: Node3D = null,
		new_position := Vector3.ZERO,
		new_route: Array[Vector3] = [],
		new_cover: TacticalCover3D = null,
		new_duration := 0.0,
		new_reason := ""
) -> SquadDirective3D:
	type = new_type
	version = new_version
	target = new_target
	target_position = new_position
	route = new_route.duplicate()
	assigned_cover = new_cover
	duration = new_duration
	reason = new_reason
	return self

func requires_movement() -> bool:
	return type in [Type.GUARD, Type.MOVE, Type.TAKE_COVER, Type.FLANK]

func requires_cover() -> bool:
	return type == Type.TAKE_COVER

func requires_target() -> bool:
	return type in [Type.AIM, Type.ATTACK, Type.SUPPRESS, Type.FLANK]

func requires_aim() -> bool:
	return type in [Type.AIM, Type.ATTACK, Type.SUPPRESS, Type.FLANK]

func get_label() -> String:
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
	return "待命"
