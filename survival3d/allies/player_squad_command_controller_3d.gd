extends Node
class_name PlayerSquadCommandController3D

signal defense_order_issued(position: Vector3, squad_count: int)

@export_category("队友指挥")
@export var command_key: Key = KEY_G
@export_range(2.0, 30.0, 0.5) var defense_radius := 8.0

var last_status := "G：命令全部友军到鼠标位置集结并坚守"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if (event as InputEventKey).physical_keycode != command_key:
		return
	var point = get_mouse_ground_position()
	if point != null:
		issue_defense_order(point as Vector3)
		get_viewport().set_input_as_handled()

func issue_defense_order(position: Vector3) -> int:
	var count := 0
	var registry := BattlefieldRegistry3D.find(get_tree())
	var candidates: Array = registry.get_squads() if registry != null else get_tree().get_nodes_in_group("squad3d")
	for candidate in candidates:
		if candidate is SquadCoordinator3D and int(candidate.combat_team) == int(Soldier3D.Team.PLAYER):
			(candidate as SquadCoordinator3D).issue_defense_order(position, defense_radius)
			count += 1
	last_status = "已命令 %d 支小队集结并坚守半径 %.1f 米" % [count, defense_radius]
	defense_order_issued.emit(position, count)
	return count

func get_mouse_ground_position() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(get_viewport().get_mouse_position())
	var direction := camera.project_ray_normal(get_viewport().get_mouse_position())
	if absf(direction.y) < 0.0001:
		return null
	var distance := -origin.y / direction.y
	return origin + direction * distance if distance >= 0.0 else null
