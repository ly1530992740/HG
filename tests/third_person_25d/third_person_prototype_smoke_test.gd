extends Node

const PROTOTYPE := preload("res://tests/third_person_25d/third_person_prototype.tscn")

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var prototype := PROTOTYPE.instantiate()
	add_child(prototype)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player := prototype.get_node("Player") as ThirdPersonPlayer3D
	var camera_director := prototype.get_node("CameraDirector") as CameraDirector3D
	var camera := prototype.get_node("CameraDirector/Camera3D") as Camera3D
	var open_target := prototype.get_node("OpenTarget") as TargetDummy3D
	var covered_target := prototype.get_node("CoveredTarget") as TargetDummy3D
	var visual := player.get_node("Visual") as Sprite3D
	var crosshair := prototype.get_node("CanvasLayer/Crosshair") as WeaponSpreadCrosshair3D
	var top_down_texture := visual.texture

	_expect(prototype is Node3D, "原型根节点不是 Node3D")
	_expect(player != null and player is CharacterBody3D, "玩家没有迁移到 CharacterBody3D")
	_expect(camera_director != null and camera != null, "双模式 Camera3D 未建立")
	_expect(open_target.get_node_or_null("HeadHitbox") is Area3D, "头部 Area3D 受击盒缺失")
	_expect(prototype.get_node_or_null("CoveredTargetWall") is StaticBody3D, "3D 掩体缺失")
	var top_down_forward := -camera.global_transform.basis.z.normalized()
	_expect(top_down_forward.dot(Vector3.DOWN) > 0.68 and top_down_forward.dot(Vector3.DOWN) < 0.73, "默认相机不是约45度战术俯视")
	_expect(absf(camera.global_position.z - player.global_position.z) > 10.0, "45度俯视相机仍位于玩家正上方")
	_expect(player.top_down_direction_steps == 8, "俯视玩家没有配置为8方位表现")
	player.rotation.y = player._quantize_top_down_yaw(deg_to_rad(68.0))
	_expect(is_equal_approx(rad_to_deg(player.rotation.y), 90.0), "俯视玩家朝向没有按45度台阶量化")
	var pose_time_before := float(player.voxel_visual.get("_time"))
	player.set("_top_down_pose_accumulator", 0.0)
	player._update_sprite(0.04, true)
	_expect(is_equal_approx(float(player.voxel_visual.get("_time")), pose_time_before), "俯视动作仍在每个渲染帧平滑推进")
	player._update_sprite(0.1, true)
	_expect(float(player.voxel_visual.get("_time")) > pose_time_before, "俯视动作没有按低帧率台阶推进")
	var top_down_aim_point := player.get_top_down_aim_point(Vector3(6.0, 20.0, -3.0), Vector3.DOWN)
	var top_down_direction := (top_down_aim_point - player.muzzle.global_position).normalized()
	_expect(absf(top_down_direction.y) < 0.0001, "俯视鼠标投影仍产生向地面的射击方向")
	var saw_vertical_spread := false
	for _sample in 24:
		var spread_direction := player.ballistics_component.apply_spread(Vector3.FORWARD, deg_to_rad(8.0))
		if absf(spread_direction.y) > 0.001:
			saw_vertical_spread = true
	_expect(saw_vertical_spread, "俯视弹道没有在默认高度中心线上保留上下散布")

	var standing_collision_height := (player.get_node("Collision") as CollisionShape3D).position.y
	player.set_stance(ThirdPersonPlayer3D.Stance.CROUCH)
	_expect((player.get_node("Collision") as CollisionShape3D).position.y < standing_collision_height, "玩家下蹲没有降低碰撞体")
	_expect(player.get_aim_point().y < player.global_position.y + 1.1, "玩家下蹲没有降低命中和瞄准高度")
	player.set_stance(ThirdPersonPlayer3D.Stance.PRONE)
	_expect(player.get_visibility_multiplier() < 0.5, "玩家卧倒没有降低可见度")
	player.set_stance(ThirdPersonPlayer3D.Stance.STAND)
	player._set_movement_mode(ThirdPersonPlayer3D.MoveMode.RUN)
	var stamina_before := player.stamina
	player._update_stamina(0.5, true)
	_expect(player.stamina < stamina_before, "玩家跑步没有消耗体力")
	player.set_stance(ThirdPersonPlayer3D.Stance.CROUCH)
	_expect(player.movement_mode == ThirdPersonPlayer3D.MoveMode.WALK, "玩家下蹲后仍保持跑步")
	player.set_stance(ThirdPersonPlayer3D.Stance.STAND)

	camera_director.set_aiming(true)
	await get_tree().create_timer(0.2).timeout
	_expect(camera_director.is_aiming(), "右键瞄准状态未生效")
	_expect(not camera_director.is_shoulder_view(), "右键举枪仍然切换到了越肩视角")
	_expect(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "右键举枪改变了45度俯视投影")
	_expect(visual.texture == top_down_texture, "右键举枪错误切换了越肩背部贴图")
	camera_director.set_shoulder_view(true)
	await get_tree().create_timer(0.2).timeout
	_expect(camera_director.is_shoulder_view(), "视角切换键底层没有进入越肩模式")
	_expect(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "越肩视角没有切换透视投影")
	_expect(crosshair != null and crosshair.visible, "越肩举枪没有显示动态准星")
	_expect(player.shoulder_back_texture != null and player.shoulder_animation_set.values().has(visual.texture), "越肩瞄准没有切换到角色动画贴图")
	_expect(player.shoulder_animator.current_state == "aim" and visual.hframes == 4, "越肩举枪没有进入四帧瞄准动画")
	_expect(visual.texture != top_down_texture, "越肩瞄准仍在使用俯视贴图")

	_expect(visual.visible and not player.voxel_visual.visible, "Shoulder view must only show the pixel character sprite")
	_expect(not player.weapon_pivot.visible, "Shoulder view must hide the 3D weapon")
	_expect(is_equal_approx(visual.pixel_size, player.shoulder_sprite_pixel_size), "Shoulder sprite scale was not applied")
	var shoulder_frame_width := float(visual.texture.get_width()) / float(maxi(1, visual.hframes))
	_expect(shoulder_frame_width * visual.pixel_size < 0.9, "Shoulder animation frame is wide enough to obstruct the center crosshair")
	var rifle_shoulder_texture := player.shoulder_back_texture
	player.set_weapon("lmg")
	_expect(player.shoulder_back_texture != rifle_shoulder_texture and player.shoulder_animation_set.values().has(visual.texture), "Shoulder pixel animation must refresh after switching weapons")
	_expect(not player.weapon_pivot.visible, "Switching weapons in shoulder view must keep the 3D weapon hidden")
	_expect(player.automatic_fire, "轻机枪没有启用按住连续射击")
	var lmg_profile := [player.aimed_spread_degrees, player.aim_settle_time, player.recoil_per_shot_degrees]
	var lmg_ammo_before := player.current_ammo
	Input.action_press("fire_weapon")
	await get_tree().create_timer(0.36).timeout
	Input.action_release("fire_weapon")
	_expect(lmg_ammo_before - player.current_ammo >= 3, "按住左键时轻机枪没有连续发射")
	_expect(player.shoulder_animator.current_state == "fire" and visual.hframes == 4, "连续开火没有播放越肩后坐动画")

	player.set_weapon("marksman")
	var marksman_profile := [player.aimed_spread_degrees, player.aim_settle_time, player.recoil_per_shot_degrees]
	_expect(lmg_profile != marksman_profile, "轻机枪和精确射手步枪仍共用同一套精度参数")
	var initial_aim_spread := player.get_current_spread_degrees()
	var initial_crosshair_gap := crosshair.calculate_gap_pixels(initial_aim_spread, 690.0, camera_director.shoulder_fov)
	player._update_accuracy(player.aim_settle_time)
	var settled_aim_spread := player.get_current_spread_degrees()
	var settled_crosshair_gap := crosshair.calculate_gap_pixels(settled_aim_spread, 690.0, camera_director.shoulder_fov)
	_expect(settled_aim_spread < initial_aim_spread, "持续瞄准没有让弹道逐步收敛")
	_expect(settled_crosshair_gap < initial_crosshair_gap, "准星没有随瞄准精度提高而收紧")
	player.fire_cooldown = 0.0
	var recoil_test_point := player.muzzle.global_position + Vector3.RIGHT * 4.0
	player.fire_at_world_point(recoil_test_point)
	_expect(player.get_current_spread_degrees() > settled_aim_spread, "开火后没有累积精度惩罚")
	_expect(crosshair.calculate_gap_pixels(player.get_current_spread_degrees(), 690.0, camera_director.shoulder_fov) > settled_crosshair_gap, "准星没有随开火后坐扩张")

	player.current_ammo = 0
	player.reload_duration = 0.4
	_expect(player.reload(), "空弹匣且有备弹时没有开始换弹")
	_expect(player.is_reloading and player.current_ammo == 0, "换弹开始时提前把弹药装入弹匣")
	var blocked_shot := player.fire_at_world_point(recoil_test_point)
	_expect(String(blocked_shot.get("reason", "")) == "reloading", "换弹过程中仍然可以开火")
	player._update_reload(0.2)
	_expect(player.current_ammo == 0 and player.get_reload_progress() > 0.45, "换弹中途错误完成或没有推进进度")
	_expect(player.shoulder_animator.current_state == "reload" and visual.hframes == 8 and visual.frame >= 3, "换弹进度没有推进越肩装填动画")
	_expect(crosshair.visible, "换弹过程中准星中央没有显示加载动画")
	player._update_reload(0.21)
	_expect(not player.is_reloading and player.current_ammo > 0, "换弹计时完成后没有装入弹药")

	player.set_weapon("rifle")
	player.fire_cooldown = 0.0
	player.hip_spread_degrees = 0.0
	player.aimed_initial_spread_degrees = 0.0

	player.aimed_spread_degrees = 0.0
	player.recoil_per_shot_degrees = 0.0
	player.accuracy_component.reset_recoil()
	player.fire_cooldown = 0.0
	var head_position := (open_target.get_node("HeadHitbox") as Area3D).global_position
	var head_result := player.fire_at_world_point(head_position)
	await get_tree().physics_frame
	_expect(bool(head_result.get("fired", false)), "玩家没有成功发射 3D 射线")
	_expect(open_target.health == maxi(0, open_target.max_health - player.body_damage * 2), "头部伤害倍率未生效")

	player.fire_cooldown = 0.0
	var short_target := player.muzzle.global_position + Vector3.RIGHT * 4.0
	var short_result := player.fire_at_world_point(short_target)
	var short_end := short_result.get("end", Vector3.ZERO) as Vector3
	_expect(is_equal_approx(float(short_result.get("shot_distance", 0.0)), player.maximum_range), "鼠标落点错误截断了武器最大射程")
	if not short_result.has("collider"):
		_expect(player.muzzle.global_position.distance_to(short_end) > 4.01, "无障碍时子弹没有越过鼠标落点继续飞行")
	_expect(is_equal_approx(player.tracer_speed, ThirdPersonPlayer3D.TRACER_SPEED_BASELINE * 0.65), "曳光弹速度没有降低35%")

	player.fire_cooldown = 0.0
	var covered_head := (covered_target.get_node("HeadHitbox") as Area3D).global_position
	player.fire_at_world_point(covered_head)
	await get_tree().physics_frame
	_expect(covered_target.health == covered_target.max_health, "子弹穿过 3D 掩体命中了目标")

	camera_director.set_aiming(false)
	await get_tree().create_timer(0.1).timeout
	_expect(camera_director.is_shoulder_view() and camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "松开右键错误退出了越肩视角")
	_expect(player.shoulder_animation_set.values().has(visual.texture), "松开右键错误恢复了俯视贴图")
	camera_director.set_shoulder_view(false)
	await get_tree().create_timer(0.2).timeout
	_expect(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "切回战术视角后未恢复正交投影")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "切回战术视角后鼠标未恢复")
	_expect(visual.texture == top_down_texture, "切回战术视角后没有恢复俯视贴图")
	camera_director.yaw = 1.2
	_expect(camera_director.get_movement_forward().is_equal_approx(Vector3.FORWARD), "战术视角移动方向仍受越肩Yaw影响")
	_expect(camera_director.get_movement_right().is_equal_approx(Vector3.RIGHT), "战术视角横向移动仍受越肩Yaw影响")

	var tactical_cover := TacticalCover3D.new()
	tactical_cover.cover_length = 3.0
	tactical_cover.cover_height = 1.2
	tactical_cover.position = player.position + Vector3(0.0, 0.0, -1.4)
	prototype.add_child(tactical_cover)
	await get_tree().physics_frame
	_expect(player.try_enter_nearest_cover(), "玩家无法用 C 逻辑进入附近3D掩体")
	_expect(player.is_in_cover() and not player.is_cover_peeking(), "进入掩体后没有默认保持蹲伏盲射")
	_expect(player.stance == ThirdPersonPlayer3D.Stance.CROUCH, "进入掩体后没有下蹲")
	player.blind_fire_spread_degrees = 0.0
	player.fire_cooldown = 0.0
	var blind_result := player.fire_at_world_point((open_target.get_node("HeadHitbox") as Area3D).global_position)
	_expect(bool(blind_result.get("fired", false)) and bool(blind_result.get("blind_fire", false)), "掩体内直接开火没有标记为盲射")
	_expect(player.toggle_cover() and player.is_cover_peeking() and player.stance == ThirdPersonPlayer3D.Stance.STAND, "掩体内按 C 没有站起探身")
	_expect(player.toggle_cover() and not player.is_cover_peeking() and player.stance == ThirdPersonPlayer3D.Stance.CROUCH, "再次按 C 没有缩回掩体")
	player.exit_cover()
	_expect(not player.is_in_cover() and player.stance == ThirdPersonPlayer3D.Stance.STAND, "移动离开掩体所需的退出状态失效")
	tactical_cover.queue_free()

	if failures.is_empty():
		print("THIRD_PERSON_25D_SMOKE_PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
