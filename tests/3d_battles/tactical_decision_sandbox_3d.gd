extends Node3D
class_name TacticalDecisionSandbox3D

const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")
const COVER_SCENE := preload("res://ai3d/tactical_cover_3d.tscn")
const MACHINE_GUN_SCENE := preload("res://ai3d/structures/machine_gun_emplacement_3d.tscn")
const WATCHTOWER_SCENE := preload("res://ai3d/structures/watchtower_3d.tscn")
const BARBED_WIRE_SCENE := preload("res://ai3d/structures/barbed_wire_3d.tscn")
const SIGHT_VISUALIZER_SCRIPT := preload("res://tests/3d_battles/tactical_sandbox_sight_visualizer_3d.gd")

enum EditTool {
	INSPECT,
	ADD_COVER,
	ADD_GRASS,
	MOVE,
	DELETE,
	SET_BLUE_OBJECTIVE,
	SET_RED_OBJECTIVE,
	ADD_MACHINE_GUN,
	ADD_WATCHTOWER,
	ADD_BARBED_WIRE,
}

enum Intent {
	CAPTURE_AND_HOLD,
	DEFEND_AREA,
	ELIMINATE_AND_RETURN,
}

@export var start_paused := false
@export var build_user_interface := true
@export var camera_move_speed := 14.0
@export var camera_look_sensitivity := 0.003

var _world: Node3D
var _terrain_root: Node3D
var _actors_root: Node3D
var _camera: Camera3D
var _heatmap: TacticalSandboxHeatmap3D
var _sight_visualizer
var _ui_layer: CanvasLayer
var _blue_squad: SquadCoordinator3D
var _red_squad: SquadCoordinator3D
var _selected_edit_node: Node3D
var _dragged_soldier: Soldier3D
var _drag_offset := Vector3.ZERO
var _simulation_started := false
var _simulation_frame := 0
var _analysis_dirty := true
var _analysis_timer := 0.0
var _editable_sequence := 0
var _last_analysis: Dictionary = {}
var _analysis_by_squad: Dictionary = {}
var _perception_refresh_by_squad: Dictionary = {}
var _last_inspected_position := Vector3.ZERO
var _camera_look_active := false
var _camera_yaw := 0.0
var _camera_pitch := 0.0
var _ui_input_blockers: Array[Control] = []

var _tool_select: OptionButton
var _source_select: OptionButton
var _layer_select: OptionButton
var _heatmap_toggle: CheckButton
var _blue_intent: OptionButton
var _red_intent: OptionButton
var _analysis_text: RichTextLabel
var _selection_label: Label
var _cover_length_spin: SpinBox
var _cover_width_spin: SpinBox
var _syncing_cover_controls := false
var _role_spins: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scene_shell()
	if build_user_interface:
		_build_ui()
	_reset_scenario()
	_set_simulation_paused(start_paused)
	call_deferred("_finish_initialization")

func _exit_tree() -> void:
	_camera_look_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if get_tree() != null:
		get_tree().paused = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _camera_look_active:
		_camera_look_active = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	_update_camera_movement(delta)
	_analysis_timer -= delta
	if _analysis_dirty and _analysis_timer <= 0.0:
		_analysis_dirty = false
		_analysis_timer = 0.12
		_refresh_analysis(true)
	elif not get_tree().paused and _analysis_timer <= 0.0:
		_analysis_timer = 0.45
		_refresh_analysis(false)

func _physics_process(_delta: float) -> void:
	if get_tree() != null and not get_tree().paused:
		_simulation_frame += 1

func _input(event: InputEvent) -> void:
	if not _camera_look_active:
		return
	if event is InputEventMouseMotion:
		_apply_camera_look((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and not mouse_event.pressed:
			_camera_look_active = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_H:
			set_heatmap_visible(_heatmap_toggle == null or not _heatmap_toggle.button_pressed)
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F1:
			set_debug_ui_visible(_ui_layer == null or not _ui_layer.visible)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and is_instance_valid(_dragged_soldier):
		if _camera_look_active:
			_apply_camera_look((event as InputEventMouseMotion).relative)
			get_viewport().set_input_as_handled()
			return
		var drag_point: Variant = _ground_point((event as InputEventMouseMotion).position)
		if drag_point != null:
			_move_soldier_initial(_dragged_soldier, (drag_point as Vector3) + _drag_offset)
			_update_selection_label()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _camera_look_active:
		_apply_camera_look((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed and _is_screen_point_over_debug_ui(mouse_event.position):
				return
			_camera_look_active = mouse_event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_event.pressed else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed \
				and is_instance_valid(_dragged_soldier):
			_dragged_soldier = null
			_mark_analysis_dirty()
			get_viewport().set_input_as_handled()
			return
		if _is_screen_point_over_debug_ui(mouse_event.position):
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_camera(-2.0)
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_camera(2.0)
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var point: Variant = _ground_point(mouse_event.position)
			if point != null:
				if not _try_begin_soldier_drag(point as Vector3):
					_edit_at(point as Vector3)
				get_viewport().set_input_as_handled()

func set_simulation_paused(value: bool) -> void:
	_set_simulation_paused(value)

func reset_scenario() -> void:
	_reset_scenario()

func force_debug_analysis() -> void:
	if get_tree() != null and get_tree().paused:
		_refresh_analysis(true, true)
	else:
		_mark_analysis_dirty()

func set_debug_ui_visible(value: bool) -> void:
	if _ui_layer == null:
		return
	_ui_layer.visible = value

func set_heatmap_visible(value: bool) -> void:
	if _heatmap_toggle != null:
		_heatmap_toggle.set_pressed_no_signal(value)
	if _heatmap != null:
		_heatmap.visible = value
	_mark_analysis_dirty()

func get_sandbox_debug_snapshot() -> Dictionary:
	return {
		"paused": get_tree().paused if get_tree() != null else true,
		"ui_visible": _ui_layer.visible if _ui_layer != null else false,
		"blue_members": _blue_squad.get_configured_member_actors().size() if is_instance_valid(_blue_squad) else 0,
		"red_members": _red_squad.get_configured_member_actors().size() if is_instance_valid(_red_squad) else 0,
		"editable_covers": _count_editables("cover"),
		"editable_grass": _count_editables("grass"),
		"editable_machine_guns": _count_editables("machine_gun"),
		"editable_watchtowers": _count_editables("watchtower"),
		"editable_barbed_wire": _count_editables("barbed_wire"),
		"heat_cells": _heatmap.get_visible_cell_count() if _heatmap != null else 0,
		"heatmap_visible": _heatmap.visible if _heatmap != null else false,
		"heatmap_version": _heatmap.get_render_version() if _heatmap != null else 0,
		"sight_rays": _sight_visualizer.get_visible_ray_count() if _sight_visualizer != null else 0,
		"sight_version": _sight_visualizer.render_version if _sight_visualizer != null else 0,
		"structure_range_visible": _sight_visualizer.visible if _sight_visualizer != null \
			and _selected_edit_node is TacticalStructure3D else false,
		"structure_range_rays": _sight_visualizer.get_visible_ray_count() if _sight_visualizer != null \
			and _selected_edit_node is TacticalStructure3D else 0,
		"simulation_frame": _simulation_frame,
		"camera_position": _camera.position if _camera != null else Vector3.ZERO,
		"camera_rotation": _camera.rotation if _camera != null else Vector3.ZERO,
		"viewport_size": get_viewport().get_visible_rect().size,
		"ui_blocker_rects": _ui_input_blockers.map(func(control: Control): return control.get_global_rect()),
		"selected_source": String((_selected_source()).get("key", "")),
		"analysis_squad_count": _analysis_by_squad.size(),
		"analysis_by_squad": _analysis_by_squad.duplicate(true),
		"perception_refresh": _perception_refresh_by_squad.duplicate(true),
		"analysis": _last_analysis.duplicate(true),
	}

func debug_select_source(key: String) -> bool:
	if _source_select == null:
		return false
	for index in _source_select.item_count:
		var metadata := _source_select.get_item_metadata(index) as Dictionary
		if String(metadata.get("key", "")) == key:
			_source_select.select(index)
			_mark_analysis_dirty()
			return true
	return false

func debug_add_cover(position_value: Vector3) -> TacticalCover3D:
	var cover := _add_cover(position_value, 5.0, 0.0)
	_mark_analysis_dirty()
	return cover

func debug_add_grass(position_value: Vector3) -> TacticalZone3D:
	var grass := _add_grass(position_value)
	_mark_analysis_dirty()
	return grass

func debug_add_machine_gun(position_value: Vector3, rotation_y := 0.0) -> MachineGunEmplacement3D:
	var emplacement := _add_machine_gun(position_value, rotation_y)
	_mark_analysis_dirty()
	return emplacement

func debug_add_watchtower(position_value: Vector3, rotation_y := 0.0) -> Watchtower3D:
	var tower := _add_watchtower(position_value, rotation_y)
	_mark_analysis_dirty()
	return tower

func debug_add_barbed_wire(position_value: Vector3, rotation_y := 0.0) -> BarbedWire3D:
	var wire := _add_barbed_wire(position_value, rotation_y)
	_mark_analysis_dirty()
	return wire

func debug_select_editable(node: Node3D) -> bool:
	if not is_instance_valid(node) or not node.has_meta("editable_kind"):
		return false
	_selected_edit_node = node
	_update_selection_label()
	return true

func debug_move_soldier_initial(member_name: String, position_value: Vector3) -> bool:
	for squad in [_blue_squad, _red_squad]:
		if not is_instance_valid(squad):
			continue
		var coordinator := squad as SquadCoordinator3D
		var soldier: Soldier3D = coordinator.get_member_by_id(member_name)
		if soldier != null:
			return _move_soldier_initial(soldier, position_value)
	return false

func _build_scene_shell() -> void:
	var registry := BattlefieldRegistry3D.new()
	registry.name = "BattlefieldRegistry3D"
	add_child(registry)

	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.55, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.92, 1.0)
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.position = Vector3(0.0, 31.0, 25.0)
	_camera.fov = 48.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera_pitch = _camera.rotation.x
	_camera_yaw = _camera.rotation.y

	_world = Node3D.new()
	_world.name = "SandboxWorld"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	_terrain_root = Node3D.new()
	_terrain_root.name = "Terrain"
	_world.add_child(_terrain_root)
	_actors_root = Node3D.new()
	_actors_root.name = "Actors"
	_world.add_child(_actors_root)

	_heatmap = TacticalSandboxHeatmap3D.new()
	_heatmap.name = "Heatmap"
	_heatmap.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_heatmap)
	_sight_visualizer = SIGHT_VISUALIZER_SCRIPT.new()
	_sight_visualizer.name = "SightVisualizer"
	_sight_visualizer.process_mode = Node.PROCESS_MODE_DISABLED
	_sight_visualizer.clear_view()
	add_child(_sight_visualizer)
	_build_floor()

func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.collision_layer = 1
	floor.collision_mask = 0
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(52.0, 0.2, 44.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.31, 0.23)
	material.roughness = 1.0
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position.y = -0.1
	floor.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(52.0, 0.2, 44.0)
	collision.shape = shape
	collision.position.y = -0.1
	floor.add_child(collision)
	_world.add_child(floor)

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "SandboxUI"
	_ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_layer)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 12

	var toolbar := PanelContainer.new()
	toolbar.offset_left = 12.0
	toolbar.offset_top = 12.0
	toolbar.offset_right = 620.0
	toolbar.offset_bottom = 58.0
	toolbar.theme = ui_theme
	toolbar.clip_contents = true
	toolbar.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.04, 0.94)))
	_ui_layer.add_child(toolbar)
	_ui_input_blockers.append(toolbar)
	var toolbar_row := HBoxContainer.new()
	toolbar_row.add_theme_constant_override("separation", 7)
	toolbar.add_child(toolbar_row)
	toolbar_row.add_child(_button("启动", _on_run_pressed, "启动或继续战斗模拟"))
	toolbar_row.add_child(_button("暂停", _on_pause_pressed, "冻结战斗，保持沙盒编辑功能"))
	toolbar_row.add_child(_button("重新分析", _on_analyze_pressed, "按当前暂停帧刷新双方有限情报、热力图、Utility、HTN 与单兵指令"))
	toolbar_row.add_child(_button("重置", _on_reset_pressed, "恢复默认地图与双方兵力"))
	toolbar_row.add_child(_button("旋转", _on_rotate_pressed, "将选中的掩体或草丛区域旋转 90 度"))
	toolbar_row.add_child(_button("隐藏界面 F1", func(): set_debug_ui_visible(false), "按 F1 可重新显示调试界面"))

	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -304.0
	side.offset_top = 12.0
	side.offset_right = -12.0
	side.offset_bottom = -12.0
	side.theme = ui_theme
	side.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.04, 0.94)))
	_ui_layer.add_child(side)
	_ui_input_blockers.append(side)
	var tabs := TabContainer.new()
	side.add_child(tabs)

	var setup_scroll := ScrollContainer.new()
	setup_scroll.name = "场景配置"
	tabs.add_child(setup_scroll)
	var setup := VBoxContainer.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override("separation", 7)
	setup_scroll.add_child(setup)
	setup.add_child(_section_label("地图编辑"))
	_tool_select = OptionButton.new()
	for tool_name in ["查看", "添加掩体", "添加草丛", "拖动/移动", "删除", "设置蓝方目标点", "设置红方目标点"]:
		_tool_select.add_item(tool_name)
	_tool_select.add_item("添加机枪阵地", EditTool.ADD_MACHINE_GUN)
	_tool_select.add_item("添加岗哨塔", EditTool.ADD_WATCHTOWER)
	_tool_select.add_item("添加铁丝网", EditTool.ADD_BARBED_WIRE)
	_tool_select.item_selected.connect(func(_index: int): _selected_edit_node = null; _update_selection_label())
	setup.add_child(_tool_select)
	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.text = "未选择对象"
	setup.add_child(_selection_label)
	setup.add_child(_section_label("选中掩体尺寸"))
	var cover_size_grid := GridContainer.new()
	cover_size_grid.columns = 2
	cover_size_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_child(cover_size_grid)
	var cover_length_label := Label.new()
	cover_length_label.text = "长度"
	cover_size_grid.add_child(cover_length_label)
	_cover_length_spin = SpinBox.new()
	_cover_length_spin.min_value = 0.5
	_cover_length_spin.max_value = 30.0
	_cover_length_spin.step = 0.5
	_cover_length_spin.allow_greater = false
	_cover_length_spin.allow_lesser = false
	_cover_length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cover_length_spin.value_changed.connect(_on_cover_length_changed)
	cover_size_grid.add_child(_cover_length_spin)
	var cover_width_label := Label.new()
	cover_width_label.text = "厚度"
	cover_size_grid.add_child(cover_width_label)
	_cover_width_spin = SpinBox.new()
	_cover_width_spin.min_value = 0.15
	_cover_width_spin.max_value = 3.0
	_cover_width_spin.step = 0.1
	_cover_width_spin.allow_greater = false
	_cover_width_spin.allow_lesser = false
	_cover_width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cover_width_spin.value_changed.connect(_on_cover_width_changed)
	cover_size_grid.add_child(_cover_width_spin)
	_update_cover_controls()

	setup.add_child(_section_label("蓝方作战意图"))
	_blue_intent = _intent_select(Intent.CAPTURE_AND_HOLD)
	setup.add_child(_blue_intent)
	_add_force_controls(setup, "blue", {0: 3, 1: 1, 2: 0, 3: 0, 4: 0})
	setup.add_child(_section_label("红方作战意图"))
	_red_intent = _intent_select(Intent.DEFEND_AREA)
	setup.add_child(_red_intent)
	_add_force_controls(setup, "red", {0: 3, 1: 0, 2: 1, 3: 0, 4: 0})
	setup.add_child(_button("应用兵力与任务配置", _on_apply_configuration, "保留当前地形并重新生成双方小队"))

	var analysis := VBoxContainer.new()
	analysis.name = "决策分析"
	analysis.add_theme_constant_override("separation", 7)
	tabs.add_child(analysis)
	analysis.add_child(_section_label("感知视图来源"))
	_source_select = OptionButton.new()
	_source_select.item_selected.connect(func(_index: int): _mark_analysis_dirty())
	analysis.add_child(_source_select)
	analysis.add_child(_section_label("热力图图层"))
	_heatmap_toggle = CheckButton.new()
	_heatmap_toggle.text = "显示热力图（H）"
	_heatmap_toggle.button_pressed = true
	_heatmap_toggle.toggled.connect(set_heatmap_visible)
	analysis.add_child(_heatmap_toggle)
	_layer_select = OptionButton.new()
	for layer_name in ["综合风险", "敌军威胁", "火力压制", "掩体价值", "隐蔽价值", "情报价值", "区域与咽喉"]:
		_layer_select.add_item(layer_name)
	_layer_select.item_selected.connect(func(_index: int): _mark_analysis_dirty())
	analysis.add_child(_layer_select)
	var analysis_hint := Label.new()
	analysis_hint.text = "综合风险：绿色较安全，红色较危险；地形价值使用青色深浅显示。"
	analysis_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	analysis_hint.modulate = Color(0.72, 0.8, 0.8)
	analysis.add_child(analysis_hint)

	var decision_panel := PanelContainer.new()
	decision_panel.anchor_top = 1.0
	decision_panel.anchor_bottom = 1.0
	decision_panel.offset_left = 12.0
	decision_panel.offset_top = -238.0
	decision_panel.offset_right = 380.0
	decision_panel.offset_bottom = -12.0
	decision_panel.theme = ui_theme
	decision_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.04, 0.92)))
	_ui_layer.add_child(decision_panel)
	_ui_input_blockers.append(decision_panel)
	_analysis_text = RichTextLabel.new()
	_analysis_text.bbcode_enabled = true
	_analysis_text.fit_content = false
	_analysis_text.scroll_active = true
	_analysis_text.add_theme_font_size_override("normal_font_size", 11)
	_analysis_text.add_theme_font_size_override("bold_font_size", 11)
	_analysis_text.add_theme_font_size_override("italics_font_size", 11)
	_analysis_text.add_theme_font_size_override("bold_italics_font_size", 11)
	_analysis_text.add_theme_font_size_override("mono_font_size", 11)
	_analysis_text.text = "正在等待战术分析……"
	decision_panel.add_child(_analysis_text)

func _add_force_controls(parent: VBoxContainer, team_key: String, defaults: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	var role_names := ["步枪兵", "冲锋枪兵", "机枪兵", "狙击手", "霰弹枪兵"]
	for role in role_names.size():
		var label := Label.new()
		label.text = role_names[role]
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 8
		spin.step = 1
		spin.value = int(defaults.get(role, 0))
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(spin)
		_role_spins["%s_%d" % [team_key, role]] = spin

func _intent_select(selected: Intent) -> OptionButton:
	var select := OptionButton.new()
	select.add_item("攻占后固守", Intent.CAPTURE_AND_HOLD)
	select.add_item("原地防守", Intent.DEFEND_AREA)
	select.add_item("消灭敌人后返回", Intent.ELIMINATE_AND_RETURN)
	select.select(int(selected))
	return select

func _button(label: String, callback: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

func _section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.94, 0.78, 0.28))
	return label

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.38, 0.48, 0.48, 0.8)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style

func _reset_scenario() -> void:
	_set_simulation_paused(true)
	_simulation_frame = 0
	if _tool_select != null:
		_tool_select.select(EditTool.INSPECT)
	_clear_editable_terrain()
	_add_cover(Vector3(-7.5, 0.0, 4.5), 5.0, 0.0)
	_add_cover(Vector3(1.0, 0.0, 5.0), 5.5, 0.0)
	_add_cover(Vector3(7.5, 0.0, -4.5), 5.0, 0.0)
	_add_cover(Vector3(-1.0, 0.0, -5.0), 5.5, 0.0)
	_add_cover(Vector3(-11.0, 0.0, 0.0), 6.5, PI * 0.5)
	_add_machine_gun(Vector3(0.0, 0.0, -8.5), PI)
	_add_watchtower(Vector3(-5.0, 0.0, -11.0), PI)
	_add_barbed_wire(Vector3(4.5, 0.0, -7.0), 0.0)
	_add_barbed_wire(Vector3(-4.5, 0.0, -7.0), 0.0)
	_add_grass(Vector3(10.5, 0.0, 3.0), Vector2(6.0, 9.0))
	_add_grass(Vector3(-10.0, 0.0, -3.0), Vector2(6.0, 9.0))
	_restore_default_configuration_values()
	_rebuild_actors()

func _restore_default_configuration_values() -> void:
	if not build_user_interface or _role_spins.is_empty():
		return
	var defaults := {"blue_0": 3, "blue_1": 1, "blue_2": 0, "blue_3": 0, "blue_4": 0,
		"red_0": 3, "red_1": 0, "red_2": 1, "red_3": 0, "red_4": 0}
	for key in defaults:
		(_role_spins[key] as SpinBox).value = defaults[key]
	_blue_intent.select(Intent.CAPTURE_AND_HOLD)
	_red_intent.select(Intent.DEFEND_AREA)

func _clear_editable_terrain() -> void:
	if _terrain_root == null:
		return
	for child in _terrain_root.get_children():
		child.free()
	_selected_edit_node = null

func _rebuild_actors() -> void:
	_set_simulation_paused(true)
	_simulation_started = false
	_dragged_soldier = null
	_analysis_by_squad.clear()
	_perception_refresh_by_squad.clear()
	# Drop UI metadata before freeing the soldiers referenced by it.
	if _source_select != null:
		_source_select.clear()
	for child in _actors_root.get_children():
		child.free()
	_blue_squad = _create_squad("BlueSquad", Soldier3D.Team.BLUE, _get_intent("blue"), Vector3(0.0, 0.0, 13.0), Vector3(0.0, 0.0, -10.0))
	_red_squad = _create_squad("RedSquad", Soldier3D.Team.RED, _get_intent("red"), Vector3(0.0, 0.0, -13.0), Vector3(0.0, 0.0, 10.0))
	_actors_root.add_child(_blue_squad)
	_actors_root.add_child(_red_squad)
	_selected_edit_node = null
	_last_inspected_position = Vector3.ZERO
	_update_selection_label()
	call_deferred("_finish_actor_rebuild")

func _create_squad(node_name: String, team: Soldier3D.Team, intent: Intent, spawn_center: Vector3, enemy_position: Vector3) -> SquadCoordinator3D:
	var squad := SquadCoordinator3D.new()
	squad.name = node_name
	squad.squad_id = StringName(node_name.to_lower())
	squad.squad_display_name = "蓝方测试小队" if team == Soldier3D.Team.BLUE else "红方测试小队"
	squad.combat_team = team
	squad.can_target_players = false
	squad.use_advanced_tactics = true
	squad.defensive_posture = intent == Intent.DEFEND_AREA
	squad.use_qwen = false
	squad.evaluation_interval = 1.2
	squad.contact_report_delay_min = 0.25
	squad.contact_report_delay_max = 0.7
	squad.mission_radius = 8.0
	squad.mission_clear_confirmation_seconds = 0.6
	squad.mission_type = SquadMissionController3D.MissionType.ELIMINATE_AND_RETURN \
		if intent == Intent.ELIMINATE_AND_RETURN else SquadMissionController3D.MissionType.CAPTURE_AND_HOLD
	var target := Marker3D.new()
	target.name = "MissionTarget"
	target.position = spawn_center if intent == Intent.DEFEND_AREA else enemy_position
	target.set_meta("editable_kind", "objective")
	target.set_meta("team", int(team))
	_add_objective_visual(target, team)
	squad.add_child(target)
	squad.mission_target_path = NodePath("MissionTarget")
	var members := Node3D.new()
	members.name = "Members"
	squad.add_child(members)
	var roles := _configured_roles("blue" if team == Soldier3D.Team.BLUE else "red")
	if roles.is_empty():
		roles.append(Soldier3D.CombatRole.RIFLEMAN)
	for index in roles.size():
		var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
		var role := int(roles[index])
		soldier.name = "%s_%s_%02d" % ["Blue" if team == Soldier3D.Team.BLUE else "Red", _role_short_name(role), index + 1]
		soldier.combat_team = team
		soldier.combat_role = role
		soldier.can_target_players = false
		soldier.awards_player_score = false
		soldier.drops_ammo_on_death = false
		soldier.show_status_label = true
		var column := index % 4
		var row := index / 4
		soldier.position = spawn_center + Vector3((float(column) - 1.5) * 1.45, 0.0, float(row) * (1.5 if team == Soldier3D.Team.BLUE else -1.5))
		soldier.rotation.y = 0.0 if team == Soldier3D.Team.BLUE else PI
		members.add_child(soldier)
	return squad

func _configured_roles(team_key: String) -> Array[int]:
	var result: Array[int] = []
	for role in 5:
		var spin := _role_spins.get("%s_%d" % [team_key, role]) as SpinBox
		var count := int(spin.value) if spin != null else (3 if role == 0 else 0)
		for _index in count:
			result.append(role)
	return result

func _get_intent(team_key: String) -> Intent:
	var select := _blue_intent if team_key == "blue" else _red_intent
	return select.get_selected_id() as Intent if select != null else (Intent.CAPTURE_AND_HOLD if team_key == "blue" else Intent.DEFEND_AREA)

func _add_cover(position_value: Vector3, length: float, rotation_y: float) -> TacticalCover3D:
	_editable_sequence += 1
	var cover := COVER_SCENE.instantiate() as TacticalCover3D
	cover.name = "SandboxCover%02d" % _editable_sequence
	cover.position = position_value
	cover.rotation.y = rotation_y
	cover.cover_length = length
	cover.material_color = Color(0.36, 0.39, 0.36)
	cover.set_meta("editable_kind", "cover")
	_terrain_root.add_child(cover)
	return cover

func _add_machine_gun(position_value: Vector3, rotation_y: float) -> MachineGunEmplacement3D:
	_editable_sequence += 1
	var emplacement := MACHINE_GUN_SCENE.instantiate() as MachineGunEmplacement3D
	emplacement.name = "SandboxMachineGun%02d" % _editable_sequence
	emplacement.position = position_value
	emplacement.rotation.y = rotation_y
	emplacement.assigned_team = Soldier3D.Team.RED
	emplacement.set_meta("editable_kind", "machine_gun")
	_terrain_root.add_child(emplacement)
	return emplacement

func _add_watchtower(position_value: Vector3, rotation_y: float) -> Watchtower3D:
	_editable_sequence += 1
	var tower := WATCHTOWER_SCENE.instantiate() as Watchtower3D
	tower.name = "SandboxWatchtower%02d" % _editable_sequence
	tower.position = position_value
	tower.rotation.y = rotation_y
	tower.assigned_team = Soldier3D.Team.RED
	tower.set_meta("editable_kind", "watchtower")
	_terrain_root.add_child(tower)
	return tower

func _add_barbed_wire(position_value: Vector3, rotation_y: float) -> BarbedWire3D:
	_editable_sequence += 1
	var wire := BARBED_WIRE_SCENE.instantiate() as BarbedWire3D
	wire.name = "SandboxBarbedWire%02d" % _editable_sequence
	wire.position = position_value
	wire.rotation.y = rotation_y
	wire.set_meta("editable_kind", "barbed_wire")
	_terrain_root.add_child(wire)
	return wire

func _add_grass(position_value: Vector3, size_value := Vector2(5.0, 6.0)) -> TacticalZone3D:
	_editable_sequence += 1
	var zone := TacticalZone3D.new()
	zone.name = "SandboxGrass%02d" % _editable_sequence
	zone.zone_id = StringName("sandbox_grass_%02d" % _editable_sequence)
	zone.display_name = "Sandbox grass %02d" % _editable_sequence
	zone.position = position_value
	zone.size = size_value
	zone.concealment = 0.9
	zone.cover_value = 0.0
	zone.route_exposure = 0.12
	zone.information_value = 1.3
	zone.zone_color = Color(0.12, 0.62, 0.2, 0.14)
	zone.set_meta("editable_kind", "grass")
	var observation := Marker3D.new()
	observation.name = "ObservationPoint"
	observation.position = Vector3(0.0, 0.0, -size_value.y * 0.28)
	zone.add_child(observation)
	zone.observation_point_path = NodePath("ObservationPoint")
	zone.recon_waypoints.append(Vector3(0.0, 0.0, size_value.y * 0.35))
	zone.recon_waypoints.append(Vector3(0.0, 0.0, -size_value.y * 0.25))
	_add_grass_visuals(zone, size_value)
	_terrain_root.add_child(zone)
	return zone

func _add_grass_visuals(zone: TacticalZone3D, size_value: Vector2) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.46, 0.16)
	material.roughness = 1.0
	for x in 3:
		for z in 4:
			var blade := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.22, 0.85 + 0.12 * float((x + z) % 2), 0.22)
			mesh.material = material
			blade.mesh = mesh
			blade.position = Vector3(
				lerpf(-size_value.x * 0.34, size_value.x * 0.34, float(x) / 2.0),
				0.46,
				lerpf(-size_value.y * 0.36, size_value.y * 0.36, float(z) / 3.0)
			)
			zone.add_child(blade)

func _add_objective_visual(marker: Marker3D, team: Soldier3D.Team) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ObjectiveVisual"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.035
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.12, 0.48, 1.0, 0.62) if team == Soldier3D.Team.BLUE else Color(0.94, 0.16, 0.12, 0.62)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.04
	marker.add_child(mesh_instance)

func _finish_initialization() -> void:
	await get_tree().process_frame
	_finish_actor_rebuild()

func _finish_actor_rebuild() -> void:
	await get_tree().process_frame
	_refresh_source_options()
	_mark_analysis_dirty()

func _edit_at(point: Vector3) -> void:
	var tool := _tool_select.get_selected_id() if _tool_select != null else EditTool.INSPECT
	if not get_tree().paused and tool != EditTool.INSPECT:
		return
	match tool:
		EditTool.ADD_COVER:
			_selected_edit_node = _add_cover(point, 5.0, 0.0)
		EditTool.ADD_GRASS:
			_selected_edit_node = _add_grass(point)
		EditTool.ADD_MACHINE_GUN:
			_selected_edit_node = _add_machine_gun(point, 0.0)
		EditTool.ADD_WATCHTOWER:
			_selected_edit_node = _add_watchtower(point, 0.0)
		EditTool.ADD_BARBED_WIRE:
			_selected_edit_node = _add_barbed_wire(point, 0.0)
		EditTool.MOVE:
			if is_instance_valid(_selected_edit_node):
				if _selected_edit_node is TacticalCover3D:
					_prepare_cover_for_layout_edit(_selected_edit_node as TacticalCover3D)
				elif _selected_edit_node is TacticalStructure3D:
					_prepare_structure_for_layout_edit(_selected_edit_node as TacticalStructure3D)
				_selected_edit_node.global_position = point
				_selected_edit_node = null
			else:
				_selected_edit_node = _nearest_editable(point, true)
		EditTool.DELETE:
			var target := _nearest_editable(point, false)
			if target != null:
				if target is TacticalCover3D:
					_prepare_cover_for_layout_edit(target as TacticalCover3D)
				elif target is TacticalStructure3D:
					_prepare_structure_for_layout_edit(target as TacticalStructure3D)
				target.queue_free()
		EditTool.SET_BLUE_OBJECTIVE:
			_move_objective(_blue_squad, point)
		EditTool.SET_RED_OBJECTIVE:
			_move_objective(_red_squad, point)
		_:
			var inspected_editable := _nearest_editable(point, false)
			var inspected_soldier := _nearest_soldier(point)
			_selected_edit_node = inspected_editable if inspected_editable is TacticalStructure3D \
				else (inspected_soldier if inspected_soldier != null else _nearest_editable(point, true))
			if inspected_soldier != null and not inspected_editable is TacticalStructure3D:
				_select_source_for_soldier(inspected_soldier)
	_last_inspected_position = point
	_update_selection_label()
	_mark_analysis_dirty()

func _try_begin_soldier_drag(point: Vector3) -> bool:
	if not get_tree().paused or _tool_select == null or _tool_select.get_selected_id() != EditTool.MOVE:
		return false
	var soldier := _nearest_soldier(point)
	if soldier == null:
		return false
	_dragged_soldier = soldier
	_selected_edit_node = soldier
	_select_source_for_soldier(soldier)
	_drag_offset = soldier.global_position - point
	_update_selection_label()
	return true

func _nearest_soldier(point: Vector3) -> Soldier3D:
	var nearest: Soldier3D
	var nearest_distance := 1.8
	for squad in [_blue_squad, _red_squad]:
		if not is_instance_valid(squad):
			continue
		for member in squad.get_living_members():
			var distance := Vector2(member.global_position.x - point.x, member.global_position.z - point.z).length()
			if distance < nearest_distance:
				nearest = member
				nearest_distance = distance
	return nearest

func _move_soldier_initial(soldier: Soldier3D, position_value: Vector3) -> bool:
	if soldier == null or not get_tree().paused:
		return false
	soldier.relocate_for_scenario_setup(position_value)
	_mark_analysis_dirty()
	return true

func _nearest_editable(point: Vector3, include_actors: bool) -> Node3D:
	var candidates: Array[Node3D] = []
	for child in _terrain_root.get_children():
		if child is Node3D and child.has_meta("editable_kind"):
			candidates.append(child as Node3D)
	if include_actors:
		for squad in [_blue_squad, _red_squad]:
			if not is_instance_valid(squad):
				continue
			var target := squad.get_node_or_null("MissionTarget") as Node3D
			if target != null:
				candidates.append(target)
			for member in squad.get_configured_member_actors():
				if member.is_combat_alive():
					candidates.append(member)
	var best: Node3D
	var best_distance := 2.3
	for candidate in candidates:
		var distance := Vector2(candidate.global_position.x - point.x, candidate.global_position.z - point.z).length()
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _move_objective(squad: SquadCoordinator3D, point: Vector3) -> void:
	if not is_instance_valid(squad):
		return
	var marker := squad.get_node_or_null("MissionTarget") as Node3D
	if marker != null:
		marker.global_position = point
		var advanced := squad.get_advanced_tactics()
		if advanced != null:
			advanced.refresh_mission_configuration()

func _ground_point(screen_position: Vector2) -> Variant:
	if _camera == null:
		return null
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return null
	var distance := -origin.y / direction.y
	if distance <= 0.0:
		return null
	var point := origin + direction * distance
	point.x = clampf(point.x, -25.0, 25.0)
	point.z = clampf(point.z, -21.0, 21.0)
	point.y = 0.0
	return point

func _is_screen_point_over_debug_ui(screen_position: Vector2) -> bool:
	if _ui_layer == null or not _ui_layer.visible:
		return false
	for control in _ui_input_blockers:
		if is_instance_valid(control) and control.is_visible_in_tree() \
				and control.get_global_rect().has_point(screen_position):
			return true
	return false

func _zoom_camera(amount: float) -> void:
	if _camera == null:
		return
	var forward := -_camera.global_transform.basis.z.normalized()
	var next_position := _camera.position + forward * -amount
	next_position.y = clampf(next_position.y, 3.0, 60.0)
	_camera.position = next_position

func _update_camera_movement(delta: float) -> void:
	if _camera == null:
		return
	var input_direction := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	)
	var vertical_input := float(Input.is_key_pressed(KEY_SPACE)) - float(Input.is_key_pressed(KEY_CTRL))
	if input_direction.length_squared() <= 0.0 and is_zero_approx(vertical_input):
		return
	var speed_multiplier := 2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	_apply_camera_pan(input_direction, delta, speed_multiplier)
	_apply_camera_vertical(vertical_input, delta, speed_multiplier)

func _apply_camera_pan(input_direction: Vector2, delta: float, speed_multiplier := 1.0) -> void:
	if _camera == null or input_direction.length_squared() <= 0.0:
		return
	input_direction = input_direction.normalized()
	var forward := _camera_ground_forward()
	var right := forward.cross(Vector3.UP).normalized()
	var speed := camera_move_speed * maxf(0.0, speed_multiplier)
	_camera.position += (right * input_direction.x + forward * input_direction.y) * speed * delta
	_camera.position.x = clampf(_camera.position.x, -60.0, 60.0)
	_camera.position.z = clampf(_camera.position.z, -60.0, 60.0)

func _camera_ground_forward() -> Vector3:
	if _camera == null or get_viewport() == null:
		return Vector3.FORWARD
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	var sight_direction := _camera.project_ray_normal(screen_center)
	var ground_forward := Vector3(sight_direction.x, 0.0, sight_direction.z)
	if ground_forward.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return ground_forward.normalized()

func _apply_camera_vertical(direction: float, delta: float, speed_multiplier := 1.0) -> void:
	if _camera == null or is_zero_approx(direction):
		return
	var speed := camera_move_speed * maxf(0.0, speed_multiplier)
	_camera.position.y = clampf(
		_camera.position.y + clampf(direction, -1.0, 1.0) * speed * delta,
		3.0,
		60.0
	)

func _apply_camera_look(relative: Vector2) -> void:
	if _camera == null:
		return
	_camera_yaw -= relative.x * camera_look_sensitivity
	_camera_pitch = clampf(
		_camera_pitch - relative.y * camera_look_sensitivity,
		deg_to_rad(-88.0),
		deg_to_rad(35.0)
	)
	_camera.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)

func _refresh_source_options() -> void:
	if _source_select == null:
		return
	var previous := ""
	if _source_select.item_count > 0:
		var old_meta := _source_select.get_item_metadata(_source_select.selected) as Dictionary
		previous = String(old_meta.get("key", ""))
	if previous.is_empty():
		previous = "red_squad"
	_source_select.clear()
	_add_source_item("蓝方小队共享认知", "blue_squad", "squad", _blue_squad)
	_add_source_item("红方小队共享认知", "red_squad", "squad", _red_squad)
	for squad in [_blue_squad, _red_squad]:
		if not is_instance_valid(squad):
			continue
		for member in squad.get_living_members():
			_add_source_item("%s 的单兵威胁场" % member.name, String(member.name), "soldier", member)
	for index in _source_select.item_count:
		var metadata := _source_select.get_item_metadata(index) as Dictionary
		if String(metadata.get("key", "")) == previous:
			_source_select.select(index)
			break

func _add_source_item(label: String, key: String, kind: String, node: Node) -> void:
	_source_select.add_item(label)
	_source_select.set_item_metadata(_source_select.item_count - 1, {"key": key, "kind": kind, "node": node})

func _select_source_for_soldier(soldier: Soldier3D) -> void:
	if soldier == null or _source_select == null:
		return
	for index in _source_select.item_count:
		var metadata := _source_select.get_item_metadata(index) as Dictionary
		if _source_node(metadata) == soldier:
			_source_select.select(index)
			return

func _refresh_analysis(force_preview: bool, apply_current_frame_plan := false) -> void:
	var source := _selected_source()
	var squad := _source_squad(source)
	if not is_instance_valid(squad) or squad.get_advanced_tactics() == null:
		_heatmap.clear_map()
		_sight_visualizer.clear_view()
		_last_analysis = {}
		_update_analysis_text(squad, source)
		return
	if get_tree().paused and apply_current_frame_plan:
		_perception_refresh_by_squad.clear()
		for candidate_squad in [_blue_squad, _red_squad]:
			if not is_instance_valid(candidate_squad) or candidate_squad.get_advanced_tactics() == null:
				continue
			_perception_refresh_by_squad[_squad_cache_key(candidate_squad)] = \
				candidate_squad.get_advanced_tactics().debug_refresh_current_frame_perception()
		for candidate_squad in [_blue_squad, _red_squad]:
			if not is_instance_valid(candidate_squad) or candidate_squad.get_advanced_tactics() == null:
				continue
			var refreshed: Dictionary = candidate_squad.get_advanced_tactics().debug_force_reanalyze_current_frame()
			refreshed["simulation_frame"] = _simulation_frame
			_analysis_by_squad[_squad_cache_key(candidate_squad)] = refreshed
	elif force_preview or get_tree().paused:
		for candidate_squad in [_blue_squad, _red_squad]:
			if not is_instance_valid(candidate_squad) or candidate_squad.get_advanced_tactics() == null:
				continue
			var preview: Dictionary = candidate_squad.get_advanced_tactics().build_debug_analysis_preview()
			preview["simulation_frame"] = _simulation_frame
			_analysis_by_squad[_squad_cache_key(candidate_squad)] = preview
	else:
		var live := squad.get_advanced_tactics().get_debug_snapshot()
		live["simulation_frame"] = _simulation_frame
		_analysis_by_squad[_squad_cache_key(squad)] = live
	var advanced := squad.get_advanced_tactics()
	_last_analysis = (_analysis_by_squad.get(_squad_cache_key(squad), {}) as Dictionary).duplicate(true)
	_last_analysis["simulation_frame"] = _simulation_frame
	var heatmap_visible := _heatmap_toggle == null or _heatmap_toggle.button_pressed
	_heatmap.visible = heatmap_visible
	if String(source.get("kind", "")) == "soldier":
		var soldier := source.get("node") as Soldier3D
		if heatmap_visible:
			_heatmap.show_soldier_map(soldier)
		else:
			_heatmap.clear_map()
		if _layer_select != null:
			_layer_select.disabled = true
	else:
		var layer := _layer_select.get_selected_id() if _layer_select != null else TacticalSandboxHeatmap3D.Layer.COMPOSITE_RISK
		if heatmap_visible:
			if layer == TacticalSandboxHeatmap3D.Layer.TACTICAL_TOPOLOGY:
				_heatmap.show_topology(advanced.topology)
			else:
				_heatmap.show_squad_map(advanced.influence, layer as TacticalSandboxHeatmap3D.Layer)
		else:
			_heatmap.clear_map()
		if _layer_select != null:
			_layer_select.disabled = not heatmap_visible
	_update_range_or_sight_visualizer(source)
	_update_analysis_text(squad, source)

func _update_range_or_sight_visualizer(source: Dictionary) -> void:
	if _sight_visualizer == null:
		return
	var source_node := _source_node(source)
	if _selected_edit_node is TacticalStructure3D:
		_sight_visualizer.show_structure(_selected_edit_node as TacticalStructure3D)
	elif String(source.get("kind", "")) == "soldier" and source_node is Soldier3D:
		_sight_visualizer.show_soldier(source_node as Soldier3D)
	else:
		_sight_visualizer.clear_view()

func _squad_cache_key(squad: SquadCoordinator3D) -> String:
	return String(squad.squad_id) if is_instance_valid(squad) else ""

func _selected_source() -> Dictionary:
	if _source_select == null or _source_select.item_count == 0:
		return {"key": "blue_squad", "kind": "squad", "node": _blue_squad}
	return _source_select.get_item_metadata(_source_select.selected) as Dictionary

func _source_node(source: Dictionary) -> Node:
	var raw_node: Variant = source.get("node", null)
	if raw_node == null or not is_instance_valid(raw_node):
		return null
	return raw_node as Node

func _source_squad(source: Dictionary) -> SquadCoordinator3D:
	var node := _source_node(source)
	if node is SquadCoordinator3D:
		return node as SquadCoordinator3D
	if node is Soldier3D:
		var soldier := node as Soldier3D
		if is_instance_valid(_blue_squad) and _blue_squad.is_member(soldier):
			return _blue_squad
		if is_instance_valid(_red_squad) and _red_squad.is_member(soldier):
			return _red_squad
	return null

func _update_analysis_text(squad: SquadCoordinator3D, source: Dictionary) -> void:
	if _analysis_text == null:
		return
	if not is_instance_valid(squad) or _last_analysis.is_empty():
		_analysis_text.text = "[b]当前没有可用的战术分析[/b]"
		return
	var belief := _last_analysis.get("belief", {}) as Dictionary
	var fire := _last_analysis.get("fire_superiority", {}) as Dictionary
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]  |  %s" % [squad.squad_display_name, "暂停帧分析" if get_tree().paused else "实时运行"])
	lines.append("视图来源：%s" % _source_display_name(source))
	lines.append("采样战斗帧：%d" % int(_last_analysis.get("simulation_frame", 0)))
	lines.append("任务：%s  |  已知敌军：%d  |  认知版本 v%d" % [
		_mission_state_name(String(_last_analysis.get("mission_state", "UNKNOWN"))),
		int(belief.get("estimated_enemy_count", 0)),
		int(belief.get("belief_version", 0)),
	])
	var selected_candidate := String(_last_analysis.get("selected_candidate", ""))
	_append_structure_status(lines, squad)
	lines.append("")
	lines.append("作战意图：%s [%s]" % [_candidate_name(selected_candidate), selected_candidate])
	lines.append("火力态势：%s  压力比 %.2f  压制率 %.2f" % [
		_fire_state_name(String(fire.get("state_name", "UNKNOWN"))),
		float(fire.get("pressure_ratio", 0.0)),
		float(fire.get("suppression_ratio", 0.0)),
	])
	lines.append("")
	lines.append("[color=#f1c94a][b]Utility 候选战术[/b][/color]")
	var selected := selected_candidate
	for candidate_value in _last_analysis.get("candidates", []):
		var candidate := candidate_value as Dictionary
		var candidate_id := String(candidate.get("id", ""))
		lines.append("%s %6.1f  %s [%s]" % [">" if candidate_id == selected else " ", float(candidate.get("utility", 0.0)), _candidate_name(candidate_id), candidate_id])
		lines.append("    %s" % _candidate_reason(candidate_id, String(candidate.get("reason", ""))))
		for component_value in candidate.get("considerations", []):
			var component := component_value as Dictionary
			lines.append("      %+6.1f  %s  raw=%s curve=%s" % [
				float(component.get("contribution", 0.0)),
				String(component.get("label", component.get("id", ""))),
				str(component.get("raw", "")),
				String(component.get("curve", "")),
			])
		for gate_value in candidate.get("gates", []):
			var gate := gate_value as Dictionary
			lines.append("      GATE %s  %s  raw=%s required=%s" % [
				"PASS" if bool(gate.get("passed", false)) else "FAIL",
				String(gate.get("id", "")),
				str(gate.get("raw", "")),
				str(gate.get("required", "")),
			])
		if int(candidate.get("choke_count", 0)) > 0 or bool(candidate.get("destination_dead_end", false)):
			lines.append("      topology: chokes=%d narrowest=%.1fm dead_end=%s" % [
				int(candidate.get("choke_count", 0)),
				float(candidate.get("narrowest_width", 0.0)),
				str(bool(candidate.get("destination_dead_end", false))),
			])
	lines.append("")
	var selected_method := String(_last_analysis.get("htn_method", "NONE"))
	lines.append("[color=#68d6e8][b]HTN 分解方法[/b][/color] %s [%s]" % [_htn_method_name(selected_method), selected_method])
	for method_value in _last_analysis.get("htn_methods", []):
		var method := method_value as Dictionary
		var method_id := String(method.get("id", ""))
		lines.append("  %6.1f  %s [%s]" % [float(method.get("score", 0.0)), _htn_method_name(method_id), method_id])
	var allocation := _last_analysis.get("role_assignments", {}) as Dictionary
	lines.append("[color=#9ed7ff][b]Tactical role slots[/b][/color] score=%.1f complete=%s" % [
		float(allocation.get("score", 0.0)), str(bool(allocation.get("complete", false))),
	])
	for assignment_value in allocation.get("assignments", []):
		var assignment := assignment_value as Dictionary
		lines.append("  %s -> %s  score=%.1f" % [
			String(assignment.get("role", "")),
			String(assignment.get("member_id", "")),
			float(assignment.get("score", 0.0)),
		])
	var topology_summary := _last_analysis.get("topology", {}) as Dictionary
	lines.append("[color=#ffd27d][b]Tactical topology[/b][/color] regions=%d chokes=%d dead_ends=%d cells=%d" % [
		int(topology_summary.get("regions", 0)),
		int(topology_summary.get("chokepoints", 0)),
		int(topology_summary.get("dead_ends", 0)),
		int(topology_summary.get("walkable_cells", 0)),
	])
	var replan := _last_analysis.get("replan_decision", {}) as Dictionary
	if not replan.is_empty():
		lines.append("Replan: %s reason=%s committed=%.1f/%.1fs margin=%.1f" % [
			"APPLY" if bool(replan.get("applied", false)) else "KEEP",
			String(replan.get("reason", "")),
			float(replan.get("committed_seconds", 0.0)),
			float(replan.get("minimum_commitment_seconds", 0.0)),
			float(replan.get("switch_margin", 0.0)),
		])
	lines.append("")
	lines.append("[color=#8ddf82][b]HTN 任务分解[/b][/color]")
	var tasks: Array = _last_analysis.get("preview_tasks", _last_analysis.get("active_tasks", []))
	if tasks.is_empty():
		lines.append("  当前没有任务图")
	for task_value in tasks:
		var task := task_value as Dictionary
		lines.append("  %s [%s] -> %s" % [_task_type_name(String(task.get("type", ""))), _task_state_name(String(task.get("state", ""))), "、".join(task.get("members", []))])
		if not String(task.get("zone", "")).is_empty():
			lines.append("    区域：%s" % String(task.get("zone", "")))
	lines.append("")
	lines.append("[color=#f0a6ff][b]单兵指令分配[/b][/color]")
	var selected_node := source.get("node") as Node
	var directives: Array = _last_analysis.get("member_directives", [])
	if directives.is_empty():
		lines.append("  当前没有已下发指令")
	for directive_value in directives:
		var directive := directive_value as Dictionary
		var member_id := String(directive.get("id", ""))
		var target_position := directive.get("target_position", Vector3.ZERO) as Vector3
		var selected_marker := ">" if selected_node is Soldier3D and String(selected_node.name) == member_id else " "
		lines.append("%s %s（%s） v%d：%s -> (%.1f, %.1f)" % [
			selected_marker,
			member_id,
			_role_name(String(directive.get("role", ""))),
			int(directive.get("directive_version", 0)),
			_directive_name(String(directive.get("directive", "NONE"))),
			target_position.x,
			target_position.z,
		])
		if not String(directive.get("reason", "")).is_empty():
			lines.append("    %s" % String(directive.get("reason", "")))
	lines.append("")
	lines.append("[color=#b6b6b6][b]Decision timeline[/b][/color]")
	for event_value in _last_analysis.get("decision_timeline", []):
		var timeline_event := event_value as Dictionary
		lines.append("  %7.2fs  #%d  %s" % [
			float(timeline_event.get("elapsed_msec", 0)) / 1000.0,
			int(timeline_event.get("sequence", 0)),
			String(timeline_event.get("event", "")),
		])
	var trace_path := String(_last_analysis.get("decision_trace_path", ""))
	if not trace_path.is_empty():
		lines.append("  JSONL: %s" % trace_path)
	_analysis_text.text = "\n".join(lines)

func _append_structure_status(lines: PackedStringArray, squad: SquadCoordinator3D) -> void:
	lines.append("[color=#ffcf70][b]防御建筑状态[/b][/color]")
	var registry := BattlefieldRegistry3D.find(get_tree())
	var structures: Array = registry.get_structures() if registry != null else get_tree().get_nodes_in_group("tactical_structure3d")
	if structures.is_empty():
		lines.append("  当前地图没有可用防御建筑")
		return
	for node in structures:
		if not node is TacticalStructure3D:
			continue
		var structure := node as TacticalStructure3D
		var user := structure.get_user() as Soldier3D
		var state := "空闲"
		if user != null:
			state = "操作中" if structure.is_occupied_by(user) else "正在接近"
			if not squad.is_member(user):
				state = "其他小队占用"
		var label := "机枪阵地" if structure.structure_kind == TacticalStructure3D.Kind.MACHINE_GUN else "岗哨塔"
		lines.append("  %s  %s  %s" % [label, user.name if user != null else "-", state])

func _update_selection_label() -> void:
	if _selection_label == null:
		return
	if is_instance_valid(_selected_edit_node):
		if _selected_edit_node is TacticalCover3D:
			var cover := _selected_edit_node as TacticalCover3D
			_selection_label.text = "已选择：%s，坐标 (%.1f, %.1f)\n槽位：每侧 %d 个" % [
				cover.name,
				cover.global_position.x,
				cover.global_position.z,
				cover.get_cover_capacity_per_side(),
			]
		elif _selected_edit_node is TacticalStructure3D:
			var structure := _selected_edit_node as TacticalStructure3D
			var user := structure.get_user() as Soldier3D
			_selection_label.text = "已选择：%s，坐标 (%.1f, %.1f)\n射程：%.1f 米  射界：%.0f°  操作员：%s" % [
				"机枪阵地" if structure.structure_kind == TacticalStructure3D.Kind.MACHINE_GUN else "岗哨塔",
				structure.global_position.x,
				structure.global_position.z,
				structure.get_effective_fire_range(),
				structure.firing_arc_degrees,
				user.name if user != null else "无",
			]
		else:
			_selection_label.text = "已选择：%s，坐标 (%.1f, %.1f)" % [_selected_edit_node.name, _selected_edit_node.global_position.x, _selected_edit_node.global_position.z]
	else:
		_selection_label.text = "查看坐标：(%.1f, %.1f)" % [_last_inspected_position.x, _last_inspected_position.z]
	_update_cover_controls()
	_update_range_or_sight_visualizer(_selected_source())

func _update_cover_controls() -> void:
	if _cover_length_spin == null or _cover_width_spin == null:
		return
	var cover := _selected_edit_node as TacticalCover3D
	var enabled := is_instance_valid(cover) and get_tree() != null and get_tree().paused
	_cover_length_spin.editable = enabled
	_cover_width_spin.editable = enabled
	if not enabled:
		return
	_syncing_cover_controls = true
	_cover_length_spin.value = cover.cover_length
	_cover_width_spin.value = cover.cover_width
	_syncing_cover_controls = false

func _on_cover_length_changed(value: float) -> void:
	if _syncing_cover_controls or get_tree() == null or not get_tree().paused:
		return
	var cover := _selected_edit_node as TacticalCover3D
	if not is_instance_valid(cover):
		return
	_prepare_cover_for_layout_edit(cover)
	cover.cover_length = value
	_update_selection_label()
	_mark_analysis_dirty()

func _on_cover_width_changed(value: float) -> void:
	if _syncing_cover_controls or get_tree() == null or not get_tree().paused:
		return
	var cover := _selected_edit_node as TacticalCover3D
	if not is_instance_valid(cover):
		return
	_prepare_cover_for_layout_edit(cover)
	cover.cover_width = value
	_update_selection_label()
	_mark_analysis_dirty()

func _prepare_cover_for_layout_edit(cover: TacticalCover3D) -> void:
	if cover == null:
		return
	for squad in [_blue_squad, _red_squad]:
		if not is_instance_valid(squad):
			continue
		for member in squad.get_living_members():
			if member.active_cover == cover:
				member.relocate_for_scenario_setup(member.global_position)

func _prepare_structure_for_layout_edit(structure: TacticalStructure3D) -> void:
	if structure != null:
		structure.evacuate()

func _set_simulation_paused(value: bool) -> void:
	if get_tree() == null:
		return
	get_tree().paused = value
	if not value:
		_simulation_started = true
		_mark_analysis_dirty()
	else:
		_analysis_dirty = false
		_analysis_timer = 0.12
		_refresh_analysis(true)

func _mark_analysis_dirty() -> void:
	_analysis_dirty = true
	_analysis_timer = 0.0

func _on_run_pressed() -> void:
	_set_simulation_paused(false)

func _on_pause_pressed() -> void:
	_set_simulation_paused(true)

func _on_analyze_pressed() -> void:
	force_debug_analysis()

func _on_reset_pressed() -> void:
	_reset_scenario()

func _on_apply_configuration() -> void:
	_rebuild_actors()

func _on_rotate_pressed() -> void:
	if get_tree().paused and is_instance_valid(_selected_edit_node) and _selected_edit_node.has_meta("editable_kind"):
		if _selected_edit_node is TacticalCover3D:
			_prepare_cover_for_layout_edit(_selected_edit_node as TacticalCover3D)
		elif _selected_edit_node is TacticalStructure3D:
			_prepare_structure_for_layout_edit(_selected_edit_node as TacticalStructure3D)
		_selected_edit_node.rotation.y = snappedf(_selected_edit_node.rotation.y + PI * 0.5, PI * 0.5)
		_update_selection_label()
		_mark_analysis_dirty()

func _directive_name(value: String) -> String:
	if value == "USE_STRUCTURE":
		return "使用防御建筑"
	return {
		"NONE": "待命",
		"GUARD": "警戒",
		"MOVE": "移动",
		"TAKE_COVER": "进入掩体",
		"AIM": "瞄准",
		"ATTACK": "攻击",
		"SUPPRESS": "压制",
		"FLANK": "侧翼机动",
		"RECON": "侦察",
		"HOLD_SECTOR": "固守扇区",
		"WITHDRAW": "撤离",
	}.get(value, value)

func _role_name(value: String) -> String:
	return {
		"RIFLEMAN": "步枪兵",
		"SMG": "冲锋枪兵",
		"MACHINE_GUNNER": "机枪兵",
		"MARKSMAN": "狙击手",
		"SHOTGUNNER": "霰弹枪兵",
		"MELEE": "近战兵",
	}.get(value, value)

func _source_display_name(source: Dictionary) -> String:
	var node := _source_node(source)
	if node is SquadCoordinator3D:
		return "%s共享认知" % (node as SquadCoordinator3D).squad_display_name
	if node is Soldier3D:
		return "%s单兵威胁场" % node.name
	return "未知来源"

func _mission_state_name(value: String) -> String:
	return {
		"APPROACHING": "向任务区推进",
		"CLEARING": "清剿任务区",
		"HOLDING": "固守任务区",
		"RETURNING": "返回出发点",
		"COMPLETE": "任务完成",
	}.get(value, value)

func _fire_state_name(value: String) -> String:
	return {
		"WINNING": "占据火力优势",
		"CONTESTED": "火力相持",
		"LOSING": "火力劣势",
		"PINNED": "遭到压制",
	}.get(value, value)

func _candidate_name(candidate_id: String) -> String:
	if candidate_id.begins_with("FLANK_"):
		return "压制并从侧翼突击"
	return {
		"MISSION_MOVE": "继续执行任务",
		"HOLD_OBJECTIVE": "固守目标区域",
		"CONTACT_COVER": "接敌后立即寻找掩体",
		"DEFEND_CONTACT": "对已知敌情展开防御",
		"RECON_SPLIT": "分兵侦察未知路线",
		"SUPPRESS_AND_FLANK": "压制并侧翼机动",
		"ESTABLISH_BASE_OF_FIRE": "建立火力支撑点",
		"FIX_AND_SUPPRESS": "牵制并压制敌军",
		"BOUNDING_ADVANCE": "交替掩护推进",
		"DIRECT_ASSAULT": "正面强攻",
		"AMBUSH": "组织伏击",
		"COUNTER_FLANK": "应对侧翼威胁",
		"REPOSITION": "重新部署",
		"RECOVER_IN_COVER": "进入掩体恢复战斗力",
		"BREAK_CONTACT": "脱离接触",
		"FALLBACK_DEFENSE": "收缩防线",
		"SEARCH_LAST_CONTACT": "搜索最后接触位置",
		"CONSOLIDATE": "整队巩固",
	}.get(candidate_id, candidate_id)

func _candidate_reason(candidate_id: String, fallback: String) -> String:
	if candidate_id.begins_with("FLANK_"):
		return "使用已确认且风险较低的路线实施同步侧翼进攻"
	return {
		"MISSION_MOVE": "尚无确认敌情，继续完成当前任务",
		"HOLD_OBJECTIVE": "目标区内没有确认威胁，保持防守",
		"CONTACT_COVER": "刚刚接敌，所有成员优先建立防护",
		"DEFEND_CONTACT": "保持当前掩体并持续监视已知敌军",
		"RECON_SPLIT": "保留正面火力，同时侦察尚未确认的路线",
		"ESTABLISH_BASE_OF_FIRE": "利用支援武器取得火力优势",
		"FIX_AND_SUPPRESS": "压制已知敌军，为后续机动创造条件",
		"BOUNDING_ADVANCE": "由火力组和机动组交替掩护推进",
		"DIRECT_ASSAULT": "没有更安全的可用路线，只能正面突破",
		"AMBUSH": "保持隐蔽，等待同步射击条件",
		"COUNTER_FLANK": "多个方向出现敌情，需要重新分配防守力量",
		"REPOSITION": "当前位置战术价值不足，需要重新部署",
		"RECOVER_IN_COVER": "小队压制程度过高，先恢复再继续行动",
		"BREAK_CONTACT": "当前交战条件不利，组织掩护撤离",
		"FALLBACK_DEFENSE": "收缩到更小且更安全的防御范围",
		"SEARCH_LAST_CONTACT": "敌军脱离视野，搜索最后确认位置",
		"CONSOLIDATE": "战斗间隙重新集结并恢复队形",
	}.get(candidate_id, fallback if not fallback.is_empty() else "根据当前战场信息生成的合法候选战术")

func _htn_method_name(method_id: String) -> String:
	return {
		"STANDARD": "标准任务分解",
		"MG_BASE_OF_FIRE": "机枪火力支撑",
		"DISTRIBUTED_RIFLE_FIRE": "步枪组交替压制",
		"MINIMAL_TEAM_FLANK": "小规模侧翼机动",
		"DIRECT_ASSAULT_FALLBACK": "强攻备用方案",
		"SYNCHRONIZED_VOLLEY": "同步齐射",
		"COMPROMISED_CONTACT_DRILL": "伏击暴露后的接敌处置",
		"SINGLE_AXIS_DEFENSE": "单方向防御",
		"MULTI_AXIS_DEFENSE": "多方向防御",
		"TWO_ELEMENT_BOUNDS": "双组交替跃进",
		"HASTY_ASSAULT": "快速突击",
		"NONE": "无",
	}.get(method_id, method_id)

func _task_type_name(value: String) -> String:
	return {
		"MOVE_TO_OBJECTIVE": "移动到任务目标",
		"TAKE_COVER": "进入掩体",
		"RECON_ZONE": "侦察区域",
		"SUPPRESS_CONTACT": "压制已知敌军",
		"FLANK_ZONE": "侧翼机动",
		"ATTACK_CONTACT": "攻击已知敌军",
		"HOLD_OBJECTIVE": "固守目标",
		"RETURN_TO_ORIGIN": "返回出发点",
		"RECOVER_IN_COVER": "在掩体内恢复",
		"AIM_CONTACT": "瞄准已知敌军",
	}.get(value, value)

func _task_state_name(value: String) -> String:
	return {
		"PENDING": "等待前置任务",
		"ACTIVE": "执行中",
		"READY": "已就位",
		"SUCCEEDED": "已完成",
		"FAILED": "失败",
		"CANCELLED": "已取消",
	}.get(value, value)

func _role_short_name(role: int) -> String:
	return ["Rifle", "SMG", "MG", "Marksman", "Shotgun", "Melee"][clampi(role, 0, 5)]

func _count_editables(kind: String) -> int:
	var count := 0
	if _terrain_root == null:
		return count
	for child in _terrain_root.get_children():
		count += 1 if String(child.get_meta("editable_kind", "")) == kind else 0
	return count
