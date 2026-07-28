extends Node

const FLANK_SCENE := preload("res://tests/firearm_test/llm_flank_battle.tscn")

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var battle := FLANK_SCENE.instantiate()
	battle.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as SquadCoordinator
	var target := bravo.get_member_actor(&"BravoA")
	assert(alpha is SquadGroup, "The coordinator did not inherit SquadGroup.")
	for legacy_property in [&"generate_members_on_ready", &"member_scene", &"member_spawns"]:
		assert(not _has_property(alpha, legacy_property), "Legacy runtime roster property still exists: %s" % legacy_property)
	assert(alpha.get_configured_member_actors().size() == 8, "The Group does not expose its scene-authored roster.")
	assert(alpha.members.size() == 8, "The Group did not register its scene-authored roster.")
	alpha.refresh_group_analysis(target)
	var initial_best := alpha.get_best_route_candidate()
	assert(not initial_best.is_empty(), "The route analyzer found no route in the flank scene.")
	assert(String(initial_best.get("id", "")).begins_with("SOUTH_"), "The long South wall was not recognized as the best protected route.")
	var south_wall := battle.get_node("SouthFlankWall") as LowWall
	battle.remove_child(south_wall)
	south_wall.queue_free()
	var north_wall := battle.get_node("NorthFlankWall") as LowWall
	north_wall.position = Vector2(412.0, -556.0)
	north_wall.wall_length = 1481.0
	north_wall.wall_width = 33.0
	north_wall._rebuild_geometry()
	await get_tree().process_frame
	alpha.refresh_group_analysis(target)
	var changed_best := alpha.get_best_route_candidate()
	assert(not changed_best.is_empty(), "The route analyzer found no route after the cover layout changed.")
	assert(String(changed_best.get("id", "")).begins_with("NORTH_"), "Removing South and lengthening North did not switch the best route north.")
	for route in alpha.last_route_candidates:
		assert(not String(route.get("id", "")).begins_with("SOUTH_SOUTHFLANKWALL"), "The removed South wall remained in the route candidates.")
	print("Squad Group analysis smoke test passed: %s -> %s after the cover layout changed." % [initial_best.get("id"), changed_best.get("id")])
	get_tree().quit(0)

func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false
