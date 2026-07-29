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
	add_child(info)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	info.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 18)
	column.add_child(_weapon_label)
	_health_label = Label.new()
	column.add_child(_health_label)
	var stamina_row := HBoxContainer.new()
	column.add_child(stamina_row)
	var stamina_title := Label.new()
	stamina_title.text = "体力"
	stamina_title.custom_minimum_size.x = 38.0
	stamina_row.add_child(stamina_title)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.custom_minimum_size = Vector2(180, 16)
	_stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamina_bar.show_percentage = false
	stamina_row.add_child(_stamina_bar)
	_movement_label = Label.new()
	_movement_label.add_theme_font_size_override("font_size", 13)
	column.add_child(_movement_label)
	var hint := Label.new()
	hint.text = "V切换视角  右键举枪  Q/E切枪  R换弹  Shift跑步  Alt静步  Ctrl下蹲  C掩体  Z卧倒"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.72, 0.78, 0.78)
	column.add_child(hint)

	var commands := PanelContainer.new()
	commands.name = "CommandPanel"
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
	title.text = "小队指令 / 规则 + GOAP"
	title.add_theme_font_size_override("font_size", 16)
	command_column.add_child(title)
	_command_label = Label.new()
	_command_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_command_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_command_label.clip_text = true
	_command_label.add_theme_font_size_override("font_size", 13)
	_command_label.custom_minimum_size = Vector2(280, 118)
	command_column.add_child(_command_label)

	_crosshair = WeaponSpreadCrosshair3D.new()
	_crosshair.name = "Crosshair"
	_crosshair.visible = false
	add_child(_crosshair)
	_crosshair.bind_player(_player)

func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var player_info := get_node("PlayerInfo") as Control
	player_info.position = Vector2(16, size.y - 154)
	player_info.size = Vector2(minf(390, size.x - 32), 138)
	var commands := get_node("CommandPanel") as Control
	var panel_width := minf(320.0, size.x * 0.4)
	commands.position = Vector2(size.x - panel_width - 16, size.y - 178)
	commands.size = Vector2(panel_width, 162)
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
	_weapon_label.text = "%s  %d / %d" % [_weapon_name(_player.current_weapon_id), current, reserve]

func _on_health_changed(current: int, maximum: int) -> void:
	_health_label.text = "生命 %d / %d    积分 %d" % [current, maximum, SurvivalEconomy.points]

func _on_points_changed(_points: int, _delta: int) -> void:
	if _player != null:
		_on_health_changed(_player.health, _player.max_health)

func _on_stamina_changed(current: float, maximum: float) -> void:
	if _stamina_bar == null:
		return
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current

func _refresh_movement_status() -> void:
	if _movement_label == null or _player == null:
		return
	_movement_label.text = "%s / %s" % [_player.get_stance_label(), _player.get_movement_mode_label()]

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
		var source := "Qwen" if squad.last_command_source == "LOCAL_QWEN" else ("Qwen护栏" if squad.last_command_source == "QWEN_GUARDED" else ("规则" if squad.last_command_source in ["RULES", "RULE_FALLBACK"] else squad.last_command_source))
		var summary := squad.last_command_summary if not squad.last_command_summary.is_empty() else "空"
		lines.append("%s [%s]：%s" % [squad.squad_display_name, source, summary])
	_command_label.text = "\n".join(lines) if not lines.is_empty() else "当前没有小队指令"

func _weapon_name(id: String) -> String:
	return {"rifle":"步枪", "pistol":"手枪", "smg":"冲锋枪", "shotgun":"霰弹枪", "lmg":"轻机枪", "marksman":"精确步枪"}.get(id, id)
