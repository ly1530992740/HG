extends Node2D
class_name PlayerSquadCommandController

signal defense_order_issued(position: Vector2, member_count: int)

@export var ally_team: StringName = &"player_allies"
@export_range(100.0, 2000.0, 25.0) var defense_radius := 650.0
@export_range(20.0, 200.0, 5.0) var formation_spacing := 70.0
@export var command_key: Key = KEY_G
@export var status_label_path := NodePath("CanvasLayer/CommandStatus")

var _marker_hide_msec := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_status("G：命令全部队友到鼠标位置守防区")

func _process(_delta: float) -> void:
	var marker := get_node_or_null("WorldMarker") as Node2D
	if marker != null and marker.visible and Time.get_ticks_msec() >= _marker_hide_msec:
		marker.visible = false

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if (event as InputEventKey).physical_keycode != command_key:
		return
	issue_defense_order(get_global_mouse_position())
	get_viewport().set_input_as_handled()

func issue_defense_order(target_position: Vector2) -> int:
	var allies: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group("combatant"):
		if candidate is Node2D \
				and candidate.has_method("get_combat_team") \
				and candidate.get_combat_team() == ally_team \
				and candidate.has_method("set_defense_anchor") \
				and (not candidate.has_method("is_combat_alive") or candidate.is_combat_alive()):
			allies.append(candidate)
	for index in allies.size():
		var offset := _formation_offset(index, allies.size())
		allies[index].set_defense_anchor(target_position + offset, defense_radius)
	_show_world_marker(target_position)
	_update_status("已命令 %d 名队友集结并坚守半径 %.0f" % [allies.size(), defense_radius])
	defense_order_issued.emit(target_position, allies.size())
	return allies.size()

func _formation_offset(index: int, count: int) -> Vector2:
	if count <= 1:
		return Vector2.ZERO
	var ring := 1 + int(index / 8)
	var ring_index := index % 8
	return Vector2.RIGHT.rotated(TAU * float(ring_index) / 8.0) * formation_spacing * float(ring)

func _show_world_marker(position_value: Vector2) -> void:
	var marker := get_node_or_null("WorldMarker") as Node2D
	if marker == null:
		return
	marker.global_position = position_value
	marker.visible = true
	_marker_hide_msec = Time.get_ticks_msec() + 2200

func _update_status(text_value: String) -> void:
	var label := get_node_or_null(status_label_path) as Label
	if label != null:
		label.text = text_value
