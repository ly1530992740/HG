extends GoapAction
class_name SoldierDirectiveAction3D

enum Operation {
	MOVE,
	ENTER_COVER,
	ACQUIRE_TARGET,
	APPROACH_TARGET,
	AIM,
	RELOAD,
	ENGAGE,
	GUARD,
	OBSERVE,
}

@export var operation: Operation = Operation.MOVE

func is_valid() -> bool:
	if not enabled or _actor == null or not _actor.has_method("get_active_directive"):
		return false
	if agent != null and agent.get_current_goal() is SoldierAutonomyGoal3D:
		return false
	var directive := _actor.get_active_directive() as SquadDirective3D
	if directive == null:
		return false
	match operation:
		Operation.MOVE:
			return directive.requires_movement()
		Operation.ENTER_COVER:
			return directive.requires_cover()
		Operation.ACQUIRE_TARGET:
			return directive.requires_target()
		Operation.APPROACH_TARGET:
			return directive.requires_target()
		Operation.AIM:
			return directive.requires_aim()
		Operation.RELOAD:
			return directive.requires_target() and _actor.has_method("can_reload_weapon") and _actor.can_reload_weapon()
		Operation.ENGAGE:
			return directive.type in [SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.SUPPRESS, SquadDirective3D.Type.FLANK]
		Operation.GUARD:
			return directive.type in [SquadDirective3D.Type.GUARD, SquadDirective3D.Type.HOLD_SECTOR]
		Operation.OBSERVE:
			return directive.type == SquadDirective3D.Type.RECON
	return false

func get_preconditions() -> Dictionary:
	var directive := _actor.get_active_directive() as SquadDirective3D if _actor != null else null
	if directive == null:
		return {}
	match operation:
		Operation.ENTER_COVER:
			return {&"at_destination": true}
		Operation.APPROACH_TARGET:
			return {&"target_acquired": true}
		Operation.AIM:
			var result := {&"target_acquired": true}
			if directive.type != SquadDirective3D.Type.AIM:
				result[&"in_weapon_range"] = true
			if directive.type == SquadDirective3D.Type.FLANK:
				result[&"at_destination"] = true
			return result
		Operation.ENGAGE:
			var result := {&"target_acquired": true, &"in_weapon_range": true, &"aimed": true}
			if _actor.has_method("uses_ammunition") and _actor.uses_ammunition():
				result[&"weapon_loaded"] = true
			if directive.type == SquadDirective3D.Type.FLANK:
				result[&"at_destination"] = true
			return result
		Operation.GUARD:
			return {&"at_destination": true}
		Operation.OBSERVE:
			return {&"at_destination": true}
	return {}

func get_effects() -> Dictionary:
	var directive := _actor.get_active_directive() as SquadDirective3D if _actor != null else null
	if directive == null:
		return {}
	match operation:
		Operation.MOVE:
			if directive.type in [SquadDirective3D.Type.MOVE, SquadDirective3D.Type.WITHDRAW]:
				return {&"at_destination": true, &"directive_complete": directive.version}
			return {&"at_destination": true}
		Operation.ENTER_COVER:
			return {&"in_cover": true, &"directive_complete": directive.version}
		Operation.ACQUIRE_TARGET:
			return {&"target_acquired": true}
		Operation.APPROACH_TARGET:
			return {&"in_weapon_range": true}
		Operation.AIM:
			if directive.type == SquadDirective3D.Type.AIM:
				return {&"aimed": true, &"directive_complete": directive.version}
			return {&"aimed": true}
		Operation.RELOAD:
			return {&"weapon_loaded": true}
		Operation.ENGAGE, Operation.GUARD, Operation.OBSERVE:
			return {&"directive_complete": directive.version}
	return {}

func enter() -> void:
	if _actor != null and _actor.has_method("begin_goap_operation"):
		_actor.begin_goap_operation(operation)

func perform(delta) -> bool:
	if _actor == null or not _actor.has_method("perform_goap_operation"):
		return false
	return _actor.perform_goap_operation(operation, float(delta))

func exit() -> void:
	if _actor != null and _actor.has_method("end_goap_operation"):
		_actor.end_goap_operation(operation)
