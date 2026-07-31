@tool
extends EditorInspectorPlugin

var _editor_plugin: EditorPlugin

func setup(value: EditorPlugin) -> void:
	_editor_plugin = value

func _can_handle(object: Object) -> bool:
	return object is SquadCoordinator3D

func _parse_begin(object: Object) -> void:
	var coordinator := object as SquadCoordinator3D
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "3D Squad Mission"
	title.add_theme_font_size_override("font_size", 14)
	panel.add_child(title)
	var button := Button.new()
	button.text = "Create or select mission target"
	button.tooltip_text = "Creates a movable Marker3D used as this squad's mission objective."
	button.pressed.connect(_on_select_mission_target.bind(coordinator))
	panel.add_child(button)
	add_custom_control(panel)

func _on_select_mission_target(coordinator: SquadCoordinator3D) -> void:
	if _editor_plugin == null or not is_instance_valid(coordinator):
		return
	var marker := coordinator.get_node_or_null(coordinator.mission_target_path) as Marker3D
	if marker == null:
		marker = Marker3D.new()
		marker.name = "MissionTarget"
		var edited_root := _editor_plugin.get_editor_interface().get_edited_scene_root()
		if edited_root == null:
			marker.free()
			return
		var undo_redo := _editor_plugin.get_undo_redo()
		undo_redo.create_action("Create 3D squad mission target")
		undo_redo.add_do_method(coordinator, &"add_child", marker, true)
		undo_redo.add_do_method(marker, &"set_owner", edited_root)
		undo_redo.add_do_property(coordinator, &"mission_target_path", NodePath("MissionTarget"))
		undo_redo.add_undo_property(coordinator, &"mission_target_path", coordinator.mission_target_path)
		undo_redo.add_undo_method(coordinator, &"remove_child", marker)
		undo_redo.add_do_reference(marker)
		undo_redo.commit_action()
	var selection := _editor_plugin.get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(marker)
