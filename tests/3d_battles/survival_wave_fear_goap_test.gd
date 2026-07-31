extends Node

const SURVIVAL_SCENE := preload("res://survival3d/scenes/survival_defense_wave_scene_3d.tscn")

func _ready() -> void:
	var battle := SURVIVAL_SCENE.instantiate()
	var spawner := battle.get_node("EnemyWaveSpawner3D") as SquadWaveSpawner3D
	spawner.auto_start = false
	add_child(battle)
	await get_tree().process_frame
	spawner.start_waves()
	spawner.call("_spawn_current_wave")
	await get_tree().process_frame
	assert(not spawner.active_squads.is_empty(), "The defense map must spawn a formal enemy squad.")
	for squad in spawner.active_squads:
		assert(squad.use_advanced_tactics and not squad.use_qwen,
			"Defense-wave squads must use deterministic tactics without Qwen.")
		for member in squad.get_configured_member_actors():
			assert(member.working_memory != null, "Wave soldiers must own personal working memory.")
			var agent := member.get("_goap_agent") as GoapAgent
			assert(agent != null and agent.get("_goals").size() >= 7,
				"Wave soldiers must use the expanded individual GOAP repertoire.")
	print("SURVIVAL_WAVE_FEAR_GOAP_PASS squads=%d" % spawner.active_squads.size())
	battle.queue_free()
	await get_tree().process_frame
	get_tree().quit()
