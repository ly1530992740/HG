extends CanvasLayer
class_name QwenDebugPanel3D

@export var visible_on_start := false
@export var toggle_key: Key = KEY_F3
@export_range(0.1, 2.0, 0.1) var refresh_interval := 0.4

var _panel: PanelContainer
var _text: RichTextLabel
var _timer := 0.0

func _ready() -> void:
	layer = 18
	_build_ui()
	_panel.visible = visible_on_start
	get_viewport().size_changed.connect(_layout)
	_layout()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == toggle_key:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()

func set_debug_visible(value: bool) -> void:
	visible_on_start = value
	if _panel != null:
		_panel.visible = value

func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = refresh_interval
		_refresh()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "QwenDebugPanel"
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "本地 Qwen 决策调试 [F3]"
	title.add_theme_font_size_override("font_size", 17)
	column.add_child(title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.custom_minimum_size = Vector2(480, 220)
	column.add_child(_text)

func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var width := minf(540.0, size.x - 32.0)
	var height := minf(310.0, size.y * 0.45)
	_panel.position = Vector2(16, 16)
	_panel.size = Vector2(width, height)

func _refresh() -> void:
	var sections: Array[String] = []
	var registry := BattlefieldRegistry3D.find(get_tree())
	var candidates: Array = registry.get_squads() if registry != null else get_tree().get_nodes_in_group("squad3d")
	for candidate in candidates:
		if not candidate is SquadCoordinator3D:
			continue
		var squad := candidate as SquadCoordinator3D
		if not squad.use_qwen:
			sections.append("[b]%s[/b]\nQwen：未启用\n执行：%s" % [squad.squad_display_name, squad.last_command_summary if not squad.last_command_summary.is_empty() else "等待规则决策"])
			continue
		var input_summary := _summarize_input(squad.last_qwen_input)
		var output := squad.last_qwen_output.strip_edges()
		if output.is_empty():
			output = "尚未返回"
		elif output.length() > 220:
			output = output.left(220) + "..."
		var leader_name := String(squad.leader.name) if is_instance_valid(squad.leader) else "未选举"
		sections.append("[b]%s[/b]  队长 %s  延迟 %dms\n输入：%s\n输出：%s\n执行：%s" % [squad.squad_display_name, leader_name, squad.last_qwen_latency_ms, input_summary, output, squad.last_command_summary if not squad.last_command_summary.is_empty() else "空"])
	_text.text = "\n\n".join(sections) if not sections.is_empty() else "当前没有3D小队"

func _summarize_input(raw: String) -> String:
	if raw.is_empty():
		return "尚未提交态势"
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return raw.left(160)
	var squad: Dictionary = parsed.get("squad", {})
	var enemy: Dictionary = parsed.get("enemy", {})
	var routes: Array = parsed.get("routes", [])
	var reachable := 0
	for route in routes:
		if bool(route.get("reachable", false)):
			reachable += 1
	return "队长%s，我方%d，目标%s，可见者%d，可达路线%d" % [String(squad.get("leader_id", "NONE")), int(squad.get("living_count", 0)), String(enemy.get("id", "UNKNOWN")), (enemy.get("visible_by", []) as Array).size(), reachable]
