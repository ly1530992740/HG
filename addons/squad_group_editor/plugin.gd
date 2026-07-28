@tool
extends EditorPlugin

const SquadInspectorPlugin := preload("res://addons/squad_group_editor/squad_group_inspector_plugin.gd")

var _inspector_plugin: EditorInspectorPlugin

func _enter_tree() -> void:
	_inspector_plugin = SquadInspectorPlugin.new()
	_inspector_plugin.setup(self)
	add_inspector_plugin(_inspector_plugin)

func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
