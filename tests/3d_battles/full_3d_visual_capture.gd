extends Node

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene_resource := load("res://survival3d/scenes/survival_defense_wave_scene_3d.tscn") as PackedScene
	var soldier_resource := load("res://ai3d/soldier_3d.tscn") as PackedScene
	var battle := scene_resource.instantiate()
	var spawner := battle.get_node("EnemyWaveSpawner3D") as SquadWaveSpawner3D
	spawner.first_wave_delay = 0.0
	add_child(battle)
	await get_tree().create_timer(0.45).timeout
	var player := battle.get_node("World/Player3D") as ThirdPersonPlayer3D
	var showcase_enemy := soldier_resource.instantiate() as Soldier3D
	showcase_enemy.name = "JapaneseShowcaseSoldier"
	showcase_enemy.combat_team = Soldier3D.Team.RED
	showcase_enemy.combat_role = Soldier3D.CombatRole.RIFLEMAN
	showcase_enemy.initially_aware = false
	battle.add_child(showcase_enemy)
	showcase_enemy.global_position = player.global_position + Vector3(1.55, 0.0, -3.85)
	showcase_enemy.rotation.y = PI
	showcase_enemy.set_physics_process(false)
	await RenderingServer.frame_post_draw
	var top_path := "user://full_3d_battle_top_down.png"
	var top_image := get_viewport().get_texture().get_image()
	_assert_capture_readable(top_image, "top_down")
	top_image.save_png(top_path)

	var camera := battle.get_node("World/CameraDirector3D") as CameraDirector3D
	camera.set_shoulder_view(true)
	camera.set_aiming(true)
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var shoulder_path := "user://full_3d_battle_shoulder.png"
	var shoulder_image := get_viewport().get_texture().get_image()
	_assert_capture_readable(shoulder_image, "shoulder")
	shoulder_image.save_png(shoulder_path)

	player.set_weapon("ppsh41")
	player.fire_cooldown = 0.0
	player.fire_at_world_point(showcase_enemy.get_aim_point())
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var fire_path := "user://full_3d_battle_fire.png"
	var fire_image := get_viewport().get_texture().get_image()
	_assert_capture_readable(fire_image, "fire")
	fire_image.save_png(fire_path)

	var heavy_metadata := WeaponCatalog3D.get_definition("dp28")
	heavy_metadata["impact_normal"] = Vector3.BACK
	showcase_enemy.receive_hit(30, "left_arm", showcase_enemy.global_position + Vector3(-0.3, 1.3, 0.0), player, heavy_metadata)
	await get_tree().create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	var gore_path := "user://full_3d_battle_gore.png"
	var gore_image := get_viewport().get_texture().get_image()
	_assert_capture_readable(gore_image, "gore")
	gore_image.save_png(gore_path)
	camera.set_aiming(false)
	camera.set_shoulder_view(false)

	print("FULL_3D_TOP_CAPTURE=%s" % ProjectSettings.globalize_path(top_path))
	print("FULL_3D_SHOULDER_CAPTURE=%s" % ProjectSettings.globalize_path(shoulder_path))
	print("FULL_3D_FIRE_CAPTURE=%s" % ProjectSettings.globalize_path(fire_path))
	print("FULL_3D_GORE_CAPTURE=%s" % ProjectSettings.globalize_path(gore_path))
	battle.queue_free()
	await get_tree().create_timer(0.15).timeout
	scene_resource = null
	soldier_resource = null
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().quit()

func _assert_capture_readable(image: Image, label: String) -> void:
	var samples := 0
	var readable_samples := 0
	var brightest := 0.0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var color := image.get_pixel(x, y)
			var luminance := color.get_luminance()
			brightest = maxf(brightest, luminance)
			readable_samples += 1 if luminance >= 0.075 else 0
			samples += 1
	var readable_ratio := float(readable_samples) / maxf(1.0, float(samples))
	assert(brightest >= 0.55, "%s capture has no usable highlights" % label)
	assert(readable_ratio >= 0.18, "%s capture is too dark to read gameplay" % label)
