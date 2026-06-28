extends Node2D

@onready var ghost_parent: Node2D = _get_or_create_ghost_parent()
@export var ground_tilemap_group := "ground_tilemap"
@export var building_parent: Node2D

var moving_building: StaticBody2D = null
var moving_original_position: Vector2

@export var ghost_scenes := {
	"house1": preload("res://buildings/unit construction/ghosts/house1_ghost.tscn"),
	"house2": preload("res://buildings/unit construction/ghosts/house2_ghost.tscn"),
	"house3": preload("res://buildings/unit construction/ghosts/house3_ghost.tscn"),
	"archery_tower": preload("res://buildings/unit construction/ghosts/archery_ghost.tscn"),
	"barracks": preload("res://buildings/unit construction/ghosts/barracks_ghost.tscn"),
	"tower": preload("res://buildings/unit construction/ghosts/tower_ghost.tscn"),
	"monastery": preload("res://buildings/unit construction/ghosts/monastery_ghost.tscn")
}

@export var building_scenes := {
	"house1": preload("res://buildings/Houses/house1.tscn"),
	"house2": preload("res://buildings/Houses/house2.tscn"),
	"house3": preload("res://buildings/Houses/house3.tscn"),
	"archery_tower": preload("res://buildings/archery/archery.tscn"),
	"barracks": preload("res://buildings/barracks/barracks.tscn"),
	"tower": preload("res://buildings/Towers/Tower.tscn"),
	"monastery": preload("res://buildings/monastery/monastery.tscn")
}

var ghost: Area2D = null
var current_id := ""
var can_place := false

# -----------------------
# COSTS
# -----------------------
var cost_map := {
	"house1": {"wood": 2, "gold": 2},
	"house2": {"wood": 2, "gold": 2},
	"house3": {"wood": 2, "gold": 2},
	"archery_tower": {"wood": 5, "gold": 5},
	"barracks": {"wood": 5, "gold": 5},
	"tower": {"wood": 5, "gold": 5},
	"monastery": {"wood": 5, "gold": 5}
}

# -----------------------
# PROCESS
# -----------------------
func _process(_delta: float) -> void:
	if ghost == null:
		return

	var ground := _get_ground_under_mouse()
	if ground == null:
		can_place = false
		return

	var mouse_pos := get_global_mouse_position()
	var tile_pos := ground.local_to_map(ground.to_local(mouse_pos))
	var world_pos := ground.map_to_local(tile_pos)

	ghost.global_position = ghost.global_position.lerp(world_pos, 0.35)
	_validate_placement()

# -----------------------
# BUILD SELECTION
# -----------------------
func select_building(id: String) -> void:
	if not _has_enough_resources(id):
		if ghost:
			_feedback_insufficient_ghost()
		return

	if ghost:
		ghost.queue_free()

	current_id = id
	ghost = ghost_scenes[id].instantiate()
	ghost_parent.add_child(ghost)

# -----------------------
# PLACEMENT VALIDATION
# -----------------------
func _validate_placement() -> void:
	can_place = true

	# Resource check
	if not _has_enough_resources(current_id):
		can_place = false

	# Collision check
	for body in ghost.get_overlapping_bodies():
		if body.is_in_group("block_building"):
			can_place = false
			break

	var sprite := ghost.get_node("anim")
	sprite.modulate = Color(0, 1, 0, 0.6) if can_place else Color(1, 0, 0, 0.6)

# -----------------------
# INPUT
# -----------------------
func _input(event: InputEvent) -> void:
	if ghost == null:
		return

	if event.is_action_pressed("confirm_build") and can_place:
		_place_building()

	if event.is_action_pressed("cancel_build"):
		_cancel_building()

# -----------------------
# PLACE BUILDING
# -----------------------
func _place_building() -> void:
	if current_id != "":
		if not _subtract_resources(current_id):
			return

	# MOVING EXISTING BUILDING
	if moving_building:
		moving_building.global_position = ghost.global_position
		moving_building.visible = true
		moving_building.set_physics_process(true)

		var tween = moving_building.create_tween()
		tween.tween_property(
			moving_building,
			"global_position",
			ghost.global_position,
			0.25
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		moving_building = null
	else:
		# NEW BUILDING
		var building = building_scenes[current_id].instantiate()
		building.global_position = ghost.global_position
		building_parent.add_child(building)

		if building.has_method("play_build_animation"):
			building.play_build_animation()

	ghost.queue_free()
	ghost = null
	current_id = ""

# -----------------------
# CANCEL BUILDING
# -----------------------
func _cancel_building() -> void:
	if moving_building:
		moving_building.global_position = moving_original_position
		moving_building.visible = true
		moving_building.set_physics_process(true)
		moving_building = null

	if ghost:
		ghost.queue_free()

	ghost = null
	current_id = ""

# -----------------------
# GROUND DETECTION
# -----------------------
func _get_ground_under_mouse() -> TileMapLayer:
	var mouse_pos: Vector2 = get_global_mouse_position()

	for node in get_tree().get_nodes_in_group(ground_tilemap_group):
		if not node is TileMapLayer:
			continue

		var local_pos: Vector2 = node.to_local(mouse_pos)
		var cell: Vector2i = node.local_to_map(local_pos)

		if node.get_cell_source_id(cell) != -1:
			return node

	return null


# -----------------------
# MOVE EXISTING BUILDING
# -----------------------
func request_move(building: StaticBody2D) -> void:
	building.set_physics_process(false)
	building.visible = false

	moving_building = building
	moving_original_position = building.global_position

	var id := _get_building_id_from_scene(building)
	current_id = id

	ghost = ghost_scenes[id].instantiate()
	ghost.global_position = building.global_position
	ghost_parent.add_child(ghost)

# -----------------------
# BUILDING ID RESOLUTION
# -----------------------
func _get_building_id_from_scene(building: Node) -> String:
	for id in building_scenes.keys():
		if building.scene_file_path == building_scenes[id].resource_path:
			return id
	return ""

# -----------------------
# GHOST PARENT
# -----------------------
func _get_or_create_ghost_parent() -> Node2D:
	var current_scene = get_tree().current_scene
	if not current_scene:
		push_error("No current scene loaded!")
		@warning_ignore("confusable_local_declaration")
		var new_node = Node2D.new()
		new_node.name = "Ghosts"
		get_tree().root.add_child(new_node)
		return new_node

	var node = current_scene.get_node_or_null("Ghosts")
	if node:
		return node as Node2D

	var new_node = Node2D.new()
	new_node.name = "Ghosts"
	current_scene.add_child(new_node)
	return new_node

# -----------------------
# RESOURCE MANAGEMENT
# -----------------------
func _has_enough_resources(id: String) -> bool:
	var cost = cost_map.get(id)
	if not cost:
		return false

	return Global.gold >= cost.gold and Global.wood >= cost.wood

func _subtract_resources(id: String) -> bool:
	var cost = cost_map.get(id)
	if not cost:
		return false

	if Global.gold < cost.gold or Global.wood < cost.wood:
		return false

	Global.consume_gold(cost.gold)
	Global.consume_wood(cost.wood)
	return true

# -----------------------
# INSUFFICIENT RESOURCE FEEDBACK
# -----------------------
func _feedback_insufficient_ghost() -> void:
	if not ghost:
		return

	var sprite = ghost.get_node("anim") if ghost.has_node("anim") else ghost
	var original_position = ghost.position
	var original_modulate = sprite.modulate

	sprite.modulate = Color(1, 0, 0, 0.8)

	var tween = ghost.create_tween()
	tween.tween_property(ghost, "position:x", original_position.x + 10, 0.05)
	tween.tween_property(ghost, "position:x", original_position.x - 10, 0.1)
	tween.tween_property(ghost, "position:x", original_position.x, 0.05)

	tween.tween_callback(func():
		sprite.modulate = original_modulate
	)
