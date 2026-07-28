extends Node2D
class_name SurvivalShopController

const WEAPON_PICKUP_SCENE := preload("res://survival/pickups/weapon_pickup.tscn")

signal item_purchased(item_id: String, item_type: String)
signal placement_started(item_id: String)
signal placement_cancelled

@export_file("*.json") var catalog_path := "res://survival/data/shop_catalog.json"
@export var player_path: NodePath
@export var world_parent_path: NodePath
@export var shop_key: Key = KEY_B
@export var shop_panel_path := NodePath("CanvasLayer/ShopPanel")
@export var points_label_path := NodePath("CanvasLayer/TopBar/Margin/HBox/Points")
@export var status_label_path := NodePath("CanvasLayer/ShopPanel/Margin/VBox/Status")
@export var placement_hint_path := NodePath("CanvasLayer/PlacementHint")
@export var purchase_toast_path := NodePath("CanvasLayer/PurchaseToast")

@export_group("响应式界面")
@export_range(4.0, 64.0, 1.0) var viewport_margin := 16.0
@export_range(240.0, 800.0, 10.0) var shop_min_width := 320.0
@export_range(280.0, 1000.0, 10.0) var shop_min_height := 360.0
@export_range(320.0, 1200.0, 10.0) var shop_max_width := 480.0
@export_range(360.0, 1200.0, 10.0) var shop_max_height := 560.0

var catalog_items: Array[Dictionary] = []
var pending_building: Dictionary = {}
var _player: Node2D = null
var _purchase_serial := 0
var _toast_version := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = _find_player()
	_load_catalog()
	_build_catalog_buttons()
	var shop_button := get_node("CanvasLayer/TopBar/Margin/HBox/ShopButton") as Button
	shop_button.pressed.connect(toggle_shop)
	var close_button := get_node("CanvasLayer/ShopPanel/Margin/VBox/Header/Close") as Button
	close_button.pressed.connect(func(): _set_shop_visible(false))
	SurvivalEconomy.points_changed.connect(_on_points_changed)
	SurvivalEconomy.purchase_failed.connect(_show_status)
	_on_points_changed(SurvivalEconomy.points, 0)
	get_viewport().size_changed.connect(_update_responsive_layout)
	call_deferred("_update_responsive_layout")

func _process(_delta: float) -> void:
	if pending_building.is_empty():
		return
	var preview := get_node("BuildingPreview") as Polygon2D
	preview.global_position = get_global_mouse_position()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == shop_key:
		toggle_shop()
		get_viewport().set_input_as_handled()
		return
	if pending_building.is_empty() or not event is InputEventMouseButton or not event.pressed:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_confirm_building_placement()
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_building_placement()
		get_viewport().set_input_as_handled()

func toggle_shop() -> void:
	if not pending_building.is_empty():
		_cancel_building_placement()
	var panel := get_node(shop_panel_path) as Control
	_set_shop_visible(not panel.visible)

func _set_shop_visible(visible_value: bool) -> void:
	var panel := get_node(shop_panel_path) as Control
	panel.visible = visible_value

func _load_catalog() -> void:
	catalog_items.clear()
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open shop catalog: %s" % catalog_path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Shop catalog root must be a dictionary.")
		return
	for value in parsed.get("items", []):
		if value is Dictionary:
			catalog_items.append(value)

func _build_catalog_buttons() -> void:
	var containers := {
		"weapon": get_node("CanvasLayer/ShopPanel/Margin/VBox/Tabs/武器/Items"),
		"ally": get_node("CanvasLayer/ShopPanel/Margin/VBox/Tabs/队友/Items"),
		"building": get_node("CanvasLayer/ShopPanel/Margin/VBox/Tabs/建筑/Items"),
	}
	for item in catalog_items:
		var category := String(item.get("category", ""))
		var container := containers.get(category) as VBoxContainer
		if container == null:
			continue
		var button := Button.new()
		button.text = "%s  %d分\n%s" % [item.get("name", item.get("id", "商品")), int(item.get("cost", 0)), item.get("description", "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.set_meta("shop_item_id", String(item.get("id", "")))
		button.pressed.connect(_purchase_item.bind(item))
		container.add_child(button)

func _update_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var shop_panel := get_node_or_null(shop_panel_path) as Control
	if shop_panel != null:
		var shop_rect := calculate_shop_rect(viewport_size)
		shop_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		shop_panel.position = shop_rect.position
		shop_panel.size = shop_rect.size
	var margin := _get_effective_viewport_margin(viewport_size)
	var top_bar := get_node_or_null("CanvasLayer/TopBar") as Control
	if top_bar != null:
		var top_bar_width := minf(220.0, maxf(1.0, viewport_size.x - margin * 2.0))
		top_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
		top_bar.position = Vector2(viewport_size.x - margin - top_bar_width, margin)
		top_bar.size = Vector2(top_bar_width, 38.0)
	var placement_hint := get_node_or_null(placement_hint_path) as Control
	if placement_hint != null:
		var hint_width := minf(360.0, maxf(1.0, viewport_size.x - margin * 2.0))
		placement_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
		placement_hint.position = Vector2((viewport_size.x - hint_width) * 0.5, viewport_size.y - margin - 38.0)
		placement_hint.size = Vector2(hint_width, 38.0)
	var purchase_toast := get_node_or_null(purchase_toast_path) as Control
	if purchase_toast != null:
		var toast_width := minf(420.0, maxf(1.0, viewport_size.x - margin * 2.0))
		purchase_toast.set_anchors_preset(Control.PRESET_TOP_LEFT)
		purchase_toast.position = Vector2((viewport_size.x - toast_width) * 0.5, margin + 8.0)
		purchase_toast.size = Vector2(toast_width, 38.0)

func calculate_shop_rect(viewport_size: Vector2) -> Rect2:
	var margin := _get_effective_viewport_margin(viewport_size)
	var available := Vector2(
		maxf(1.0, viewport_size.x - margin * 2.0),
		maxf(1.0, viewport_size.y - margin * 2.0)
	)
	var minimum := Vector2(minf(shop_min_width, available.x), minf(shop_min_height, available.y))
	var maximum := Vector2(minf(maxf(shop_max_width, minimum.x), available.x), minf(maxf(shop_max_height, minimum.y), available.y))
	var target_size := Vector2(
		clampf(viewport_size.x * 0.78, minimum.x, maximum.x),
		clampf(viewport_size.y * 0.78, minimum.y, maximum.y)
	)
	return Rect2((viewport_size - target_size) * 0.5, target_size)

func _get_effective_viewport_margin(viewport_size: Vector2) -> float:
	return minf(viewport_margin, maxf(4.0, minf(viewport_size.x, viewport_size.y) * 0.04))

func _purchase_item(item: Dictionary) -> void:
	match String(item.get("category", "")):
		"weapon":
			_purchase_weapon(item)
		"ally":
			_purchase_ally(item)
		"building":
			_begin_building_placement(item)

func _purchase_weapon(item: Dictionary) -> void:
	var player := _find_player()
	if player == null or not player.has_method("receive_weapon_pickup"):
		_show_status("没有可装备枪械的玩家")
		return
	var pickup := WEAPON_PICKUP_SCENE.instantiate() as Area2D
	if pickup == null:
		_show_status("武器拾取物无法生成")
		return
	var cost := int(item.get("cost", 0))
	if not SurvivalEconomy.try_spend(cost):
		pickup.free()
		return
	var weapon_id := String(item.get("weapon_id", ""))
	var display_name := String(item.get("name", weapon_id))
	pickup.set("weapon_id", weapon_id)
	pickup.set("ammo_amount", int(item.get("ammo_amount", 0)))
	pickup.set("display_name", display_name)
	_get_world_parent().add_child(pickup)
	_purchase_serial += 1
	var drop_angle := float(_purchase_serial % 8) * TAU / 8.0
	pickup.global_position = player.global_position + Vector2.RIGHT.rotated(drop_angle) * 90.0
	_set_shop_visible(false)
	_show_purchase_toast("%s 已投放到地面，靠近后拾取" % display_name)
	item_purchased.emit(String(item.get("id", "")), "weapon")

func _purchase_ally(item: Dictionary) -> void:
	var scene := load(String(item.get("scene", ""))) as PackedScene
	if scene == null:
		_show_status("队友预制体无法加载")
		return
	var cost := int(item.get("cost", 0))
	if not SurvivalEconomy.try_spend(cost):
		return
	var squad := scene.instantiate() as SquadGroup
	if squad == null:
		SurvivalEconomy.add_points(cost)
		_show_status("队友预制体根节点不是 SquadGroup")
		return
	var unique_id := StringName("player_allies_%d" % squad.get_instance_id())
	squad.squad_id = unique_id
	var member_actors := squad.get_configured_member_actors()
	for actor in member_actors:
		actor.set("squad_id", unique_id)
	var member_root := squad.get_node_or_null(squad.member_root_path)
	if member_root != null:
		for actor in member_actors:
			if actor.get_parent() == member_root:
				member_root.remove_child(actor)
				actor.owner = null
	var parent := _get_world_parent()
	parent.add_child(squad)
	var player := _find_player()
	squad.global_position = player.global_position + Vector2(150, 0) if player != null else get_global_mouse_position()
	_activate_squad_members_staggered(squad, member_root, member_actors)
	_set_shop_visible(false)
	_show_purchase_toast("守备小队已抵达，按 G 指挥集结")
	item_purchased.emit(String(item.get("id", "")), "ally")

func _activate_squad_members_staggered(squad: SquadGroup, member_root: Node, member_actors: Array[Node2D]) -> void:
	if member_root == null:
		return
	for actor in member_actors:
		await get_tree().process_frame
		if not is_instance_valid(squad) or not is_instance_valid(member_root) or not is_instance_valid(actor):
			return
		member_root.add_child(actor)
		squad.add_member_actor(actor)

func _begin_building_placement(item: Dictionary) -> void:
	pending_building = item.duplicate(true)
	add_to_group("active_building_placement")
	_set_shop_visible(false)
	var preview := get_node("BuildingPreview") as Polygon2D
	var half_length := float(item.get("wall_length", 200.0)) * 0.5
	var half_width := float(item.get("wall_width", 24.0)) * 0.5
	preview.polygon = PackedVector2Array([
		Vector2(-half_length, -half_width), Vector2(half_length, -half_width),
		Vector2(half_length, half_width), Vector2(-half_length, half_width),
	])
	preview.visible = true
	(get_node(placement_hint_path) as Control).visible = true
	placement_started.emit(String(item.get("id", "")))

func _confirm_building_placement() -> void:
	var scene := load(String(pending_building.get("scene", ""))) as PackedScene
	if scene == null:
		_show_status("建筑预制体无法加载")
		_cancel_building_placement()
		return
	if not SurvivalEconomy.try_spend(int(pending_building.get("cost", 0))):
		return
	var building := scene.instantiate() as Node2D
	if building == null:
		_show_status("建筑预制体根节点不是 Node2D")
		_cancel_building_placement()
		return
	_get_world_parent().add_child(building)
	building.global_position = get_global_mouse_position()
	if building is LowWall:
		building.wall_length = float(pending_building.get("wall_length", building.wall_length))
		building.wall_width = float(pending_building.get("wall_width", building.wall_width))
	var purchased_id := String(pending_building.get("id", ""))
	_show_purchase_toast("掩体已建造")
	_finish_placement()
	item_purchased.emit(purchased_id, "building")

func _cancel_building_placement() -> void:
	_finish_placement()
	placement_cancelled.emit()

func _finish_placement() -> void:
	pending_building.clear()
	remove_from_group("active_building_placement")
	(get_node("BuildingPreview") as Polygon2D).visible = false
	(get_node(placement_hint_path) as Control).visible = false

func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	if not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node2D
	if _player == null and GlobalPlayer.active_player is Node2D:
		_player = GlobalPlayer.active_player as Node2D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

func _get_world_parent() -> Node:
	if not world_parent_path.is_empty():
		var configured := get_node_or_null(world_parent_path)
		if configured != null:
			return configured
	return get_tree().current_scene if get_tree().current_scene != null else get_parent()

func _on_points_changed(points: int, _delta: int) -> void:
	var label := get_node_or_null(points_label_path) as Label
	if label != null:
		label.text = "积分 %d" % points

func _show_status(message: String) -> void:
	var label := get_node_or_null(status_label_path) as Label
	if label != null:
		label.text = message

func _show_purchase_toast(message: String) -> void:
	var label := get_node_or_null(purchase_toast_path) as Label
	if label == null:
		return
	_toast_version += 1
	var version := _toast_version
	label.text = message
	label.visible = true
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(label) and version == _toast_version:
		label.visible = false
