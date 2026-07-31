extends Node3D

signal reinforcement_wave_spawned(squad: SquadCoordinator3D)

const REINFORCEMENT := preload("res://Prefab/Enemy3D/east_reinforcement_squad_3d.tscn")

@export_range(0.0, 10.0, 0.1) var reinforcement_delay := 3.0

var _initial_red: SquadCoordinator3D
var _blue: SquadCoordinator3D
var _clear_time := -1.0
var _spawned := false

func _ready() -> void:
	_blue = $BlueSquad
	_initial_red = $RedSquad
	_blue.set_runtime_mission_target(_initial_red.global_position, 12.0)
	_initial_red.set_runtime_mission_target(_initial_red.global_position, 10.0)
	$World/QwenDebugPanel3D.set_debug_visible(true)
	for member in _initial_red.get_configured_member_actors():
		member.aware_of_enemy = false
		member.initially_aware = false
		member.logical_forward = Vector3.FORWARD
		member.rotation.y = 0.0
	_initial_red.issue_hold_position_guard("初始全员背对蓝队")
	for member in _blue.get_configured_member_actors():
		member.aware_of_enemy = true
		member.logical_forward = Vector3.FORWARD
	var target := _initial_red.get_configured_member_actors()[0]
	_blue.set_known_combat_objective(target)

func _process(delta: float) -> void:
	if _spawned or _initial_red == null or _initial_red.is_squad_alive():
		return
	if _clear_time < 0.0:
		_clear_time = 0.0
		return
	_clear_time += delta
	if _blue.current_plan != "GUARD" or _blue.current_stage < 1:
		return
	if _clear_time >= reinforcement_delay:
		_spawn_east_wave()

func _spawn_east_wave() -> void:
	_spawned = true
	var squad := REINFORCEMENT.instantiate() as SquadCoordinator3D
	squad.can_target_players = false
	squad.knows_primary_target_at_start = false
	add_child(squad)
	squad.global_position = Vector3(18, 0, -2)
	squad.rotation.y = -PI * 0.5
	var blue_target := _blue.get_configured_member_actors()[0]
	squad.set_runtime_mission_target(_blue.global_position, 12.0)
	squad.set_known_combat_objective(blue_target)
	print("[AMBUSH3D] 东侧第二波已生成，人数=%d" % squad.get_configured_member_actors().size())
	reinforcement_wave_spawned.emit(squad)
