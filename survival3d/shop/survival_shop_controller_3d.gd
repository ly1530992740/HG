extends Node
class_name SurvivalShopController3D

signal item_purchased(item_id: String, category: String)
signal placement_started(item_id: String)
signal placement_cancelled

@export_category("商城配置")
@export_file("*.json") var catalog_path := "res://survival3d/data/shop_catalog_3d.json"
@export var player_path: NodePath
@export var world_parent_path: NodePath
@export var shop_key: Key = KEY_B
@export var initial_points := 100
@export var reset_points_on_ready := true

@export_category("界面适配")
@export_range(4.0, 64.0, 1.0) var viewport_margin := 16.0
@export_range(280.0, 800.0, 10.0) var minimum_width := 340.0
@export_range(320.0, 1000.0, 10.0) var minimum_height := 400.0
@export_range(360.0, 1200.0, 10.0) var maximum_width := 520.0
@export_range(420.0, 1200.0, 10.0) var maximum_height := 620.0

var catalog_items: Array[Dictionary] = []
var pending_building: Dictionary:
	get: return _placement_service.pending_item if is_instance_valid(_placement_service) else {}
var _player: Node3D
var _preview: TacticalCover3D:
	get: return _placement_service.preview if is_instance_valid(_placement_service) else null
var _canvas: CanvasLayer
var _panel: PanelContainer
var _points_label: Label
var _status_label: Label
var _toast_label: Label
var _tabs: TabContainer
var _purchase_service: SurvivalPurchaseService3D
var _placement_service: BuildingPlacementService3D
var _mouse_mode_before_shop := Input.MOUSE_MODE_VISIBLE
var _tree_was_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_purchase_service = SurvivalPurchaseService3D.new()
	_purchase_service.name = "PurchaseService3D"
	add_child(_purchase_service)
	_placement_service = BuildingPlacementService3D.new()
	_placement_service.name = "BuildingPlacementService3D"
	add_child(_placement_service)
	_player = _find_player()
	if reset_points_on_ready:
		SurvivalEconomy.reset(initial_points)
	_load_catalog()
	_build_ui()
	SurvivalEconomy.points_changed.connect(_on_points_changed)
	SurvivalEconomy.purchase_failed.connect(_set_status)
	_on_points_changed(SurvivalEconomy.points, 0)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()

func _exit_tree() -> void:
	if _panel != null and _panel.visible:
		_set_shop_open(false)

func _process(_delta: float) -> void:
	if _placement_service.is_active():
		var point: Variant = get_mouse_ground_position()
		if point != null:
			_placement_service.update_position(point as Vector3)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == shop_key:
		if not _placement_service.is_active():
			_set_shop_open(not _panel.visible)
		else:
			_cancel_building()
		get_viewport().set_input_as_handled()
		return
	if not _placement_service.is_active() or not event is InputEventMouseButton or not event.pressed:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		_confirm_building()
		get_viewport().set_input_as_handled()
	elif mouse.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_building()
		get_viewport().set_input_as_handled()

func toggle_shop() -> void:
	if not pending_building.is_empty():
		_cancel_building()
	_set_shop_open(not _panel.visible)

func get_mouse_ground_position() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return null
	var distance := -origin.y / direction.y
	if distance < 0.0:
		return null
	return origin + direction * distance

func purchase_item_by_id(item_id: String) -> bool:
	for item in catalog_items:
		if String(item.get("id", "")) == item_id:
			return _purchase_item(item)
	return false

func _load_catalog() -> void:
	catalog_items = ShopCatalogRepository3D.load_items(catalog_path)

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	add_child(_canvas)

	var top := HBoxContainer.new()
	top.name = "ShopTopBar"
	_canvas.add_child(top)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 18)
	top.add_child(_points_label)
	var open_button := Button.new()
	open_button.text = "商城 [B]"
	open_button.pressed.connect(toggle_shop)
	top.add_child(open_button)

	_panel = PanelContainer.new()
	_panel.name = "ShopPanel3D"
	_panel.visible = false
	_canvas.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "战场积分商城"
	title.add_theme_font_size_override("font_size", 21)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func(): _set_shop_open(false))
	header.add_child(close)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	for category in [["weapon", "武器"], ["ally", "队友"], ["building", "建筑"]]:
		var scroll := ScrollContainer.new()
		scroll.name = category[1]
		var items := VBoxContainer.new()
		items.name = category[0]
		items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(items)
		_tabs.add_child(scroll)
	_status_label = Label.new()
	_status_label.text = "购买武器会投放到地面；建筑需在战场上确认位置。"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	_toast_label = Label.new()
	_toast_label.visible = false
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 18)
	_canvas.add_child(_toast_label)

	for item in catalog_items:
		var container := _tabs.find_child(String(item.get("category", "")), true, false) as VBoxContainer
		if container == null:
			continue
		var button := Button.new()
		button.text = "%s  %d分\n%s" % [item.get("name", "商品"), int(item.get("cost", 0)), item.get("description", "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 60.0
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_purchase_item.bind(item))
		container.add_child(button)

func _update_layout() -> void:
	if _canvas == null:
		return
	var size := get_viewport().get_visible_rect().size
	var margin := minf(viewport_margin, minf(size.x, size.y) * 0.04)
	var top := _canvas.get_node("ShopTopBar") as Control
	top.position = Vector2(size.x - minf(235.0, size.x - margin * 2.0) - margin, margin)
	top.size = Vector2(minf(235.0, size.x - margin * 2.0), 38.0)
	var available := Vector2(maxf(1.0, size.x - margin * 2.0), maxf(1.0, size.y - margin * 2.0))
	var panel_size := Vector2(clampf(size.x * 0.72, minf(minimum_width, available.x), minf(maximum_width, available.x)), clampf(size.y * 0.78, minf(minimum_height, available.y), minf(maximum_height, available.y)))
	_panel.position = (size - panel_size) * 0.5
	_panel.size = panel_size
	_toast_label.position = Vector2(margin, 62.0)
	_toast_label.size = Vector2(size.x - margin * 2.0, 34.0)

func _purchase_item(item: Dictionary) -> bool:
	match String(item.get("category", "")):
		"weapon": return _apply_purchase_result(item, _purchase_service.purchase_weapon(item, _find_player(), _get_world_parent()))
		"ally": return _apply_purchase_result(item, _purchase_service.purchase_ally(item, _find_player(), _get_world_parent()))
		"building": return _begin_building(item)
	return false

func _apply_purchase_result(item: Dictionary, result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		_set_status(String(result.get("message", "购买失败")))
		return false
	var message := String(result.get("message", "购买成功"))
	_set_status(message)
	_show_toast(message)
	item_purchased.emit(String(item.get("id", "")), String(result.get("category", "")))
	return true

func _begin_building(item: Dictionary) -> bool:
	if not SurvivalEconomy.can_afford(int(item.get("cost", 0))):
		_set_status("积分不足")
		return false
	if not _placement_service.begin(item, _get_world_parent()):
		_set_status("建筑预制体无法加载")
		return false
	_set_shop_open(false)
	_show_toast("移动鼠标选择位置，左键建造，右键取消")
	placement_started.emit(String(item.get("id", "")))
	return true

func _set_shop_open(open: bool) -> void:
	if _panel == null or _panel.visible == open:
		return
	if open:
		_mouse_mode_before_shop = Input.mouse_mode
		_tree_was_paused = get_tree().paused
		_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
	else:
		_panel.visible = false
		get_tree().paused = _tree_was_paused
		Input.mouse_mode = _mouse_mode_before_shop

func _confirm_building() -> void:
	if not _placement_service.is_active() or not SurvivalEconomy.try_spend(int(_placement_service.pending_item.get("cost", 0))):
		return
	var item_id := _placement_service.finalize()
	_show_toast("掩体已建造，自动掩体点位已生成")
	item_purchased.emit(item_id, "building")

func _cancel_building() -> void:
	_placement_service.cancel()
	placement_cancelled.emit()

func _find_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	if not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player3d") as Node3D
	return _player

func _get_world_parent() -> Node:
	if not world_parent_path.is_empty():
		var configured := get_node_or_null(world_parent_path)
		if configured != null:
			return configured
	return get_tree().current_scene

func _on_points_changed(points: int, _delta: int) -> void:
	if _points_label != null:
		_points_label.text = "积分 %d" % points

func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message

func _show_toast(message: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = message
	_toast_label.visible = true
	var label := _toast_label
	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(label) and label.text == message:
		label.visible = false
