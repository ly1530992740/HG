extends Node

const WALL_SCENE := preload("res://cover/low_wall.tscn")
const SQUAD_WALL_SCENE := preload("res://cover/squad_low_wall.tscn")

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var wall := WALL_SCENE.instantiate() as LowWall
	wall.position = Vector2(123.0, 77.0)
	wall.rotation = 0.35
	var authored_transform := wall.transform
	add_child(wall)
	await get_tree().process_frame
	assert(wall.get_cover_capacity_per_side() == 4, "The default wall did not generate four slots per side.")
	var initial_capacity := wall.get_cover_capacity_per_side()
	wall.wall_length = 420.0
	wall.wall_width = 40.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert(wall.transform.is_equal_approx(authored_transform), "Dimension rebuild changed the authored wall transform.")
	assert(wall.get_cover_capacity_per_side() > initial_capacity, "Increasing wall length did not generate more cover slots.")
	var wall_shape := (wall.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var interaction_shape := (wall.get_node("InteractionArea/CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	assert(wall_shape.size == Vector2(420.0, 40.0), "Wall collision did not follow the edited dimensions.")
	assert(interaction_shape.size == Vector2(490.0, 146.0), "Interaction range did not follow the edited dimensions.")
	assert(is_equal_approx(absf(wall.slots[0].position.y), 42.0), "Generated slots did not move outside the wider wall.")
	for slot_index in range(1, wall.get_cover_capacity_per_side()):
		assert(is_equal_approx(wall.slots[slot_index].position.x - wall.slots[slot_index - 1].position.x, wall.slot_spacing), "Generated slot spacing was stretched by wall length.")

	var squad_wall := SQUAD_WALL_SCENE.instantiate() as LowWall
	add_child(squad_wall)
	await get_tree().process_frame
	assert(squad_wall.get_cover_capacity_per_side() == 8, "The squad wall no longer provides eight generated slots per side.")
	print("Cover geometry smoke test passed: length/width drive visuals, collisions, interaction range, and slot capacity.")
	get_tree().quit(0)
