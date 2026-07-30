extends Node

const PROTOTYPE := preload("res://tests/third_person_25d/third_person_prototype.tscn")

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var prototype := PROTOTYPE.instantiate()
	add_child(prototype)
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var top_down_path := "user://third_person_25d_top_down.png"
	get_viewport().get_texture().get_image().save_png(top_down_path)

	var camera_director := prototype.get_node("CameraDirector") as CameraDirector3D
	var player := prototype.get_node("Player") as ThirdPersonPlayer3D
	camera_director.set_shoulder_view(true)
	camera_director.set_aiming(true)
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var shoulder_path := "user://third_person_25d_shoulder.png"
	get_viewport().get_texture().get_image().save_png(shoulder_path)
	player.fire_cooldown = 0.0
	player.fire_at_world_point(player.muzzle.global_position + camera_director.get_flat_forward() * 30.0)
	await get_tree().create_timer(0.055).timeout
	await RenderingServer.frame_post_draw
	var fire_path := "user://third_person_25d_fire.png"
	get_viewport().get_texture().get_image().save_png(fire_path)
	camera_director.set_aiming(false)
	player.current_ammo = 0
	player.reload_duration = 1.0
	player.reload()
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var reload_path := "user://third_person_25d_reload.png"
	get_viewport().get_texture().get_image().save_png(reload_path)
	camera_director.set_shoulder_view(false)

	print("TOP_DOWN_CAPTURE=%s" % ProjectSettings.globalize_path(top_down_path))
	print("SHOULDER_CAPTURE=%s" % ProjectSettings.globalize_path(shoulder_path))
	print("FIRE_CAPTURE=%s" % ProjectSettings.globalize_path(fire_path))
	print("RELOAD_CAPTURE=%s" % ProjectSettings.globalize_path(reload_path))
	get_tree().quit()
