extends Node3D

@export var blue_path := NodePath("BlueSquad")
@export var red_path := NodePath("RedSquad")

func _ready() -> void:
	var blue := get_node(blue_path) as SquadCoordinator3D
	var red := get_node(red_path) as SquadCoordinator3D
	get_node("World/QwenDebugPanel3D").set_debug_visible(true)
	blue.set_runtime_mission_target(red.global_position, 12.0)
	red.set_runtime_mission_target(blue.global_position, 12.0)
	_set_contact(blue, red)
	_set_contact(red, blue)

func _set_contact(squad: SquadCoordinator3D, hostile_squad: SquadCoordinator3D) -> void:
	var hostile := hostile_squad.get_configured_member_actors()[0]
	for member in squad.get_configured_member_actors():
		member.aware_of_enemy = true
		member.current_target = hostile
	squad.set_known_combat_objective(hostile)
