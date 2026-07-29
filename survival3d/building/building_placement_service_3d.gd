extends Node
class_name BuildingPlacementService3D

var pending_item: Dictionary = {}
var preview: TacticalCover3D

func begin(item: Dictionary, world_parent: Node) -> bool:
	cancel()
	var scene := load(String(item.get("scene", ""))) as PackedScene
	preview = scene.instantiate() as TacticalCover3D if scene != null else null
	if preview == null:
		return false
	pending_item = item.duplicate(true)
	preview.cover_length = float(item.get("cover_length", 5.0))
	preview.cover_width = float(item.get("cover_width", 0.55))
	preview.cover_height = float(item.get("cover_height", 1.2))
	preview.collision_layer = 0
	preview.material_color = Color(0.2, 0.75, 0.72, 0.45)
	world_parent.add_child(preview)
	return true

func update_position(position: Vector3) -> void:
	if is_instance_valid(preview):
		preview.global_position = position

func finalize() -> String:
	if not is_instance_valid(preview):
		return ""
	preview.collision_layer = 1
	preview.material_color = Color(0.38, 0.4, 0.38, 1.0)
	preview = null
	var item_id := String(pending_item.get("id", ""))
	pending_item.clear()
	return item_id

func cancel() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	preview = null
	pending_item.clear()

func is_active() -> bool:
	return is_instance_valid(preview) and not pending_item.is_empty()
