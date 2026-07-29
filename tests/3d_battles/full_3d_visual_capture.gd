extends Node

const SCENE := preload("res://survival3d/scenes/survival_defense_wave_scene_3d.tscn")

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var battle := SCENE.instantiate()
	var spawner := battle.get_node("EnemyWaveSpawner3D") as SquadWaveSpawner3D
	spawner.first_wave_delay = 0.0
	add_child(battle)
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var top_path := "user://full_3d_battle_top_down.png"
	get_viewport().get_texture().get_image().save_png(top_path)

	var camera := battle.get_node("World/CameraDirector3D") as CameraDirector3D
	camera.set_shoulder_view(true)
	camera.set_aiming(true)
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var shoulder_path := "user://full_3d_battle_shoulder.png"
	get_viewport().get_texture().get_image().save_png(shoulder_path)
	camera.set_aiming(false)
	camera.set_shoulder_view(false)

	print("FULL_3D_TOP_CAPTURE=%s" % ProjectSettings.globalize_path(top_path))
	print("FULL_3D_SHOULDER_CAPTURE=%s" % ProjectSettings.globalize_path(shoulder_path))
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().quit()
