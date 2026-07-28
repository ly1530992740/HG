extends Resource
class_name SquadMemberSpawn

@export var member_id: StringName = &"Soldier"
@export var position := Vector2.ZERO
@export var combat_role: SquadCombatRole.Type = SquadCombatRole.Type.RIFLEMAN
@export_range(0, 2, 1) var firearm_loadout := 0
@export var initial_facing_direction := Vector2.RIGHT
@export var lock_steady_morale := true

func apply_to(actor: Node2D) -> void:
	actor.name = String(member_id)
	actor.position = position
	actor.set("combat_role", combat_role)
	actor.set("firearm_loadout", firearm_loadout)
	actor.set("initial_facing_direction", initial_facing_direction)
	actor.set("lock_steady_morale", lock_steady_morale)
