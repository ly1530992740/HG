extends RefCounted
class_name SquadTask

enum Type {
	GUARD_AREA,
	OCCUPY_COVER,
	AIM_TARGET,
	SUPPRESS_TARGET,
	NEUTRALIZE_TARGET,
	MOVE_TO_ZONE,
	WITHDRAW_TO_ZONE,
}

enum State { PENDING, ACTIVE, READY, SUCCEEDED, FAILED, CANCELLED }
enum CompletionPolicy { ALL_SUCCEEDED, ALL_READY, ANY_SUCCEEDED }

var task_id: StringName = &""
var type: Type = Type.GUARD_AREA
var depends_on: Array[StringName] = []
var recipient_ids: PackedStringArray = []
var target_id: StringName = &""
var zone_id: StringName = &""
var priority := 100
var completion_policy: CompletionPolicy = CompletionPolicy.ALL_SUCCEEDED
var persistent := false
var timeout_seconds := 15.0
var state: State = State.PENDING

# Concrete scene objects are resolved and validated by the commander, never invented by Qwen.
var target: Node2D = null
var member_targets: Dictionary = {}
var member_positions: Dictionary = {}
var member_covers: Dictionary = {}
var member_states: Dictionary = {}

func configure(new_id: StringName, new_type: Type, new_recipients: PackedStringArray = []) -> SquadTask:
	task_id = new_id
	type = new_type
	recipient_ids = new_recipients
	persistent = type in [Type.GUARD_AREA, Type.SUPPRESS_TARGET]
	completion_policy = CompletionPolicy.ALL_READY if persistent else CompletionPolicy.ALL_SUCCEEDED
	return self

func clone_for_member(member_id: String) -> SquadTask:
	var result := SquadTask.new()
	result.task_id = task_id
	result.type = type
	result.depends_on = depends_on.duplicate()
	result.recipient_ids = PackedStringArray([member_id])
	result.target_id = target_id
	result.zone_id = zone_id
	result.priority = priority
	result.completion_policy = completion_policy
	result.persistent = persistent
	result.timeout_seconds = timeout_seconds
	result.target = member_targets.get(member_id, target)
	result.member_positions[member_id] = member_positions.get(member_id, Vector2.ZERO)
	result.member_covers[member_id] = member_covers.get(member_id, null)
	return result

func get_position_for(member_id: String) -> Vector2:
	return member_positions.get(member_id, Vector2.ZERO) as Vector2

func get_cover_for(member_id: String) -> Node:
	return member_covers.get(member_id, null) as Node

func get_target_for(member_id: String) -> Node2D:
	return member_targets.get(member_id, target) as Node2D

func get_type_name() -> String:
	return Type.keys()[type]

func get_state_name() -> String:
	return State.keys()[state]

func dependencies_satisfied(tasks_by_id: Dictionary) -> bool:
	for dependency_id in depends_on:
		var dependency := tasks_by_id.get(dependency_id) as SquadTask
		if dependency == null or dependency.state not in [State.READY, State.SUCCEEDED]:
			return false
	return true

