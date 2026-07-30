extends CanvasLayer
class_name BattleHud3D

@export var player_path: NodePath
@export_range(0.1, 2.0, 0.1) var refresh_interval := 0.35

var _player: ThirdPersonPlayer3D
var _weapon_label: Label
var _health_label: Label
var _stamina_bar: ProgressBar
var _movement_label: Label
var _command_label: Label
var _crosshair: WeaponSpreadCrosshair3D
var _refresh_timer := 0.0

func _ready() -> void:
	layer = 12
	_player = get_node_or_null(player_path) as ThirdPersonPlayer3D if not player_path.is_empty() else get_tree().get_first_node_in_group("player3d") as ThirdPersonPlayer3D
	_build_ui()
	if _player != null:
		_player.ammo_changed.connect(_on_ammo_changed)
		_player.health_changed.connect(_on_health_changed)
		_player.weapon_changed.connect(func(_id): _refresh_player())
		_player.stamina_changed.connect(_on_stamina_changed)
		_player.stance_changed.connect(func(_stance): _refresh_movement_status())
		_player.movement_mode_changed.connect(func(_mode): _refresh_movement_status())
		_player.cover_state_changed.connect(func(_in_cover, _peeking): _refresh_movement_status())
		_refresh_player()
	SurvivalEconomy.points_changed.connect(_on_points_changed)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = refresh_interval
		_refresh_commands()

func _build_ui() -> void:
	var info := PanelContainer.new()
	info.name = "PlayerInfo"
	info.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.04, 0.9), Color(0.42, 0.5, 0.36, 0.65)))
	add_child(info)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 7)
	info.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 14)
	_weapon_label.add_theme_color_override("font_color", Color(0.94, 0.91, 0.76))
	column.add_child(_weapon_label)
	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_health_label)
	var stamina_row := HBoxContainer.new()
	column.add_child(stamina_row)
	var stamina_title := Label.new()
	stamina_title.text = "体力"
	stamina_title.add_theme_font_size_override("font_size", 11)
	stamina_title.custom_minimum_size.x = 38.0
	stamina_row.add_child(stamina_title)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.custom_minimum_size = Vector2(116, 8)
	_stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamina_bar.show_percentage = false
	stamina_row.add_child(_stamina_bar)
	_movement_label = null
	var commands := PanelContainer.new()
	commands.name = "CommandPanel"
	commands.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.04, 0.86), Color(0.32, 0.39, 0.3, 0.6)))
	add_child(commands)
	var command_margin := MarginContainer.new()
	command_margin.add_theme_constant_override("margin_left", 10)
	command_margin.add_theme_constant_override("margin_top", 8)
	command_margin.add_theme_constant_override("margin_right", 10)
	command_margin.add_theme_constant_override("margin_bottom", 8)
	commands.add_child(command_margin)
	var command_column := VBoxContainer.new()
	command_margin.add_child(command_column)
	var title := Label.new()
	title.text = "战术通讯"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.76, 0.82, 0.65))
	command_column.add_child(title)
	_command_label = Label.new()
	_command_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_command_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_command_label.clip_text = true
	_command_label.add_theme_font_size_override("font_size", 11)
	_command_label.custom_minimum_size = Vector2(205, 46)
	command_column.add_child(_command_label)

	_crosshair = WeaponSpreadCrosshair3D.new()
	_crosshair.name = "Crosshair"
	_crosshair.visible = false
	add_child(_crosshair)
	_crosshair.bind_player(_player)

func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var player_info := get_node("PlayerInfo") as Control
	player_info.position = Vector2(16, size.y - 90)
	player_info.size = Vector2(minf(255, size.x - 32), 74)
	var commands := get_node("CommandPanel") as Control
	var panel_width := minf(240.0, size.x * 0.3)
	commands.position = Vector2(size.x - panel_width - 16, size.y - 96)
	commands.size = Vector2(panel_width, 80)
	_crosshair.position = Vector2.ZERO
	_crosshair.size = size

func _refresh_player() -> void:
	if _player == null:
		return
	_on_ammo_changed(_player.current_ammo, _player.reserve_ammo)
	_on_health_changed(_player.health, _player.max_health)
	_on_stamina_changed(_player.stamina, _player.max_stamina)
	_refresh_movement_status()

func _on_ammo_changed(current: int, reserve: int) -> void:
	_weapon_label.text = "%s  %d / %d" % [_player.get_weapon_display_name(), current, reserve]

func _on_health_changed(current: int, maximum: int) -> void:
	var posture := "%s/%s" % [_player.get_stance_label(), _player.get_movement_mode_label()] if _player != null else ""
	_health_label.text = "生命 %d/%d   %s   积分 %d" % [current, maximum, posture, SurvivalEconomy.points]

func _on_points_changed(_points: int, _delta: int) -> void:
	if _player != null:
		_on_health_changed(_player.health, _player.max_health)

func _on_stamina_changed(current: float, maximum: float) -> void:
	if _stamina_bar == null:
		return
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current

func _refresh_movement_status() -> void:
	if _player == null:
		return
	_on_health_changed(_player.health, _player.max_health)

func _refresh_commands() -> void:
	if _command_label == null:
		return
	var lines: Array[String] = []
	var registry := BattlefieldRegistry3D.find(get_tree())
	var candidates: Array = registry.get_squads() if registry != null else get_tree().get_nodes_in_group("squad3d")
	for candidate in candidates:
		if not candidate is SquadCoordinator3D:
			continue
		var squad := candidate as SquadCoordinator3D
		var source := "Qwen" if squad.last_command_source == "LOCAL_QWEN" else ("Qwen护栏" if squad.last_command_source == "QWEN_GUARDED" else ("Qwen拒绝" if squad.last_command_source == "QWEN_REJECTED" else ("规则" if squad.last_command_source in ["RULES", "RULE_FALLBACK"] else squad.last_command_source)))
		var summary := squad.last_command_summary if not squad.last_command_summary.is_empty() else "空"
		lines.append("%s [%s]：%s" % [squad.squad_display_name, source, summary])
	_command_label.text = "\n".join(lines) if not lines.is_empty() else "当前没有小队指令"

func _weapon_name(id: String) -> String:
	return WeaponCatalog3D.get_display_name(id)

func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
