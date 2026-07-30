extends Node

const PLAYER_SCENE := preload("res://survival3d/player/third_person_player_3d.tscn")
const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")
const CAMERA_SCENE := preload("res://survival3d/player/camera_rig_3d.tscn")

func _ready() -> void:
	await _test_weapon_catalog()
	await _test_world_pixel_post_process()
	await _test_player_presentation()
	await _test_enemy_presentation_and_gore()
	print("WWII_COMBAT_VERTICAL_SLICE_PASS")
	await get_tree().process_frame
	get_tree().quit()

func _test_world_pixel_post_process() -> void:
	var post_scene := load("res://survival3d/rendering/pixel_art_world_post_process_3d.tscn") as PackedScene
	assert(post_scene != null, "3D世界缺少统一像素后处理场景")
	var post_process := post_scene.instantiate() as PixelArtWorldPostProcess3D
	add_child(post_process)
	await get_tree().process_frame
	assert(post_process.layer < 0, "世界像素后处理必须位于HUD下方")
	assert(post_process.pixel_block_size <= 2.0, "像素采样块过大，会退化成粗糙方块风格")
	assert(post_process.color_levels >= 20.0, "色阶过低，会丢失参考风格需要的服装和面部细节")
	var effect := post_process.get_node("ScreenEffect") as ColorRect
	assert(effect.material is ShaderMaterial, "世界像素后处理没有ShaderMaterial")
	post_process.queue_free()
	await get_tree().process_frame

func _test_weapon_catalog() -> void:
	var expected := ["zhongzheng", "type_38", "mauser_c96", "ppsh41", "type_100", "dp28", "type_99_lmg"]
	var ids := WeaponCatalog3D.get_all_ids()
	for weapon_id in expected:
		assert(ids.has(weapon_id), "二战武器目录缺少 %s" % weapon_id)
	assert(WeaponCatalog3D.resolve_id("rifle") == "zhongzheng", "旧步枪ID没有兼容到中正式")
	assert(WeaponCatalog3D.resolve_id("smg") == "ppsh41", "旧冲锋枪ID没有兼容到波波沙")
	assert(bool(WeaponCatalog3D.get_definition("ppsh41").automatic), "波波沙没有配置自动射击")
	assert(int(WeaponCatalog3D.get_definition("ppsh41").magazine_size) == 71, "波波沙弹鼓容量不正确")
	assert(int(WeaponCatalog3D.get_definition("type_38").damage) > int(WeaponCatalog3D.get_definition("type_100").damage), "栓动步枪与冲锋枪伤害层次不正确")

func _test_player_presentation() -> void:
	var player := PLAYER_SCENE.instantiate() as ThirdPersonPlayer3D
	player.name = "Player3D"
	add_child(player)
	var camera := CAMERA_SCENE.instantiate() as CameraDirector3D
	camera.player_path = NodePath("../Player3D")
	add_child(camera)
	await get_tree().process_frame
	assert(player.current_weapon_id == "rifle", "旧存档默认武器ID发生破坏性变化")
	assert(player.get_weapon_display_name() == "中正式步枪", "玩家没有显示二战武器名称")
	assert(player.voxel_visual.visible, "俯视角玩家没有显示红军3D像素模型")
	assert(not player.visual.visible, "俯视角仍显示旧纸片角色")
	assert(camera.shoulder_distance <= 1.6 and camera.shoulder_offset >= 0.75 and camera.shoulder_offset <= 1.05, "越肩镜头没有保持近距离肩背构图和准星安全偏移")
	assert(player.shoulder_back_texture.get_width() >= 240 and player.shoulder_back_texture.get_height() >= 336, "Shoulder back sprite is below the high-resolution presentation target")
	var shoulder_height := float(player.shoulder_back_texture.get_height()) * player.shoulder_sprite_pixel_size
	assert(shoulder_height >= 1.0 and shoulder_height <= 1.3, "Shoulder sprite size no longer preserves the crosshair safe area")
	assert(player.weapon_model_root.get_child_count() >= 4, "中正式步枪缺少程序化模型部件")
	assert(player.muzzle.get_node_or_null("MuzzleFlash") != null, "玩家枪口缺少枪焰反馈节点")
	var rifle_muzzle_z := player.muzzle.position.z
	player.set_weapon("ppsh41")
	assert(player.automatic_fire and player.magazine_size == 71, "波波沙自动射击或弹鼓配置未应用")
	assert(player.weapon_model_root.get_node_or_null("DrumMagazine") != null, "波波沙模型缺少弹鼓轮廓")
	var ammo_before := player.current_ammo
	var shot := player.fire_at_world_point(player.global_position + Vector3.FORWARD * 20.0)
	assert(bool(shot.get("fired", false)) and player.current_ammo == ammo_before - 1, "玩家射击反馈链没有完成一次开火")
	assert(float(camera.get("_recoil_pitch")) > 0.0, "开火没有向镜头提交后坐冲量")
	player.set_weapon("mauser_c96")
	assert(player.weapon_model_root.get_node_or_null("Grip") != null, "毛瑟C96模型缺少握把")
	assert(player.muzzle.position.z > rifle_muzzle_z + 0.15, "短枪仍沿用长步枪枪口Socket")
	player.queue_free()
	camera.queue_free()
	for child in get_children():
		if child.name in ["SpentCasing", "AITracer"]:
			child.queue_free()
	await get_tree().process_frame

func _test_enemy_presentation_and_gore() -> void:
	var enemy := SOLDIER_SCENE.instantiate() as Soldier3D
	enemy.combat_team = Soldier3D.Team.RED
	enemy.combat_role = Soldier3D.CombatRole.RIFLEMAN
	add_child(enemy)
	await get_tree().process_frame
	assert(not enemy.visual.visible, "敌人仍显示旧Sprite3D纸片")
	assert(enemy.voxel_visual.faction == VoxelSoldierVisual3D.Faction.JAPANESE, "敌人没有使用日军3D像素外观")
	assert(enemy.voxel_visual.get_node_or_null("PixelRig/Head/Type90Helmet") != null, "日军模型缺少九〇式钢盔轮廓")
	var tunic_mesh := (enemy.voxel_visual.get_node("PixelRig/Torso/Tunic") as MeshInstance3D).mesh as ArrayMesh
	var tunic_material := tunic_mesh.surface_get_material(0) as StandardMaterial3D
	assert(tunic_mesh.get_surface_count() == 1 and tunic_mesh.surface_get_array_len(0) >= 300, "士兵身体仍然使用极低面数轮廓")
	assert(tunic_material.albedo_texture != null and tunic_material.albedo_texture.get_width() >= 128, "士兵军装缺少中等分辨率细节纹理")
	assert(enemy.voxel_visual.get_node_or_null("PixelRig/Torso/LeftPocket") != null, "士兵军装缺少胸袋细节")
	assert(enemy.voxel_visual.get_node_or_null("PixelRig/Head/LeftEar") != null, "士兵头部缺少面部轮廓细节")
	assert((enemy.voxel_visual.get_node("PixelRig/LeftArm/Elbow") as MeshInstance3D).mesh is SphereMesh, "低多边形人物仍使用方块肘部")
	assert(enemy.voxel_visual.get_node_or_null("PixelRig/LeftArm/ForearmPivot") != null, "士兵缺少可独立弯曲的前臂关节")
	assert((enemy.voxel_visual.get_node("PixelRig/LeftLeg/LowerLegPivot/Boot") as MeshInstance3D).mesh is SphereMesh, "低多边形人物仍使用方盒靴子")
	assert(enemy.voxel_visual.get_node_or_null("PixelRig/LeftLeg/LowerLegPivot") != null, "士兵缺少可独立弯曲的小腿关节")
	assert(enemy.weapon_component.weapon_id == "type_38", "日军步枪兵没有装备三八式")
	assert(enemy.weapon_model_root.get_child_count() >= 4, "AI三八式缺少程序化模型")
	for hitbox_name in ["HeadHitbox", "LeftArmHitbox", "RightArmHitbox", "LeftLegHitbox", "RightLegHitbox"]:
		assert(enemy.get_node_or_null(hitbox_name) is CombatHitbox3D, "敌人缺少分肢命中区 %s" % hitbox_name)
	var left_arm := enemy.voxel_visual.get_node("PixelRig/LeftArm") as Node3D
	assert(left_arm.visible, "断肢测试前左臂已经隐藏")
	var health_before := enemy.health
	var left_arm_hitbox := enemy.get_node("LeftArmHitbox") as CombatHitbox3D
	var pistol_metadata := WeaponCatalog3D.get_definition("mauser_c96")
	pistol_metadata["impact_normal"] = Vector3.BACK
	left_arm_hitbox.receive_shot(12, enemy.global_position + Vector3(-0.3, 1.25, 0.0), null, pistol_metadata)
	assert(enemy.health < health_before, "真实左臂Hitbox没有向角色传递伤害")
	assert(enemy.voxel_visual.get_bullet_wound_count() == 1, "枪弹命中没有留下跟随角色的弹孔")
	assert(left_arm.visible and not enemy.voxel_visual.is_limb_detached("left_arm"), "手枪错误地直接打断了完整肢体")
	var right_arm_hitbox := enemy.get_node("RightArmHitbox") as CombatHitbox3D
	var lmg_metadata := WeaponCatalog3D.get_definition("dp28")
	lmg_metadata["impact_normal"] = Vector3.BACK
	right_arm_hitbox.receive_shot(10, enemy.global_position + Vector3(0.3, 1.25, 0.0), null, lmg_metadata)
	assert(enemy.voxel_visual.is_limb_detached("right_arm"), "DP-28重火力命中没有立即打断手臂")
	var left_leg_hitbox := enemy.get_node("LeftLegHitbox") as CombatHitbox3D
	var marksman_metadata := WeaponCatalog3D.get_definition("type_38")
	marksman_metadata["impact_normal"] = Vector3.BACK
	left_leg_hitbox.receive_shot(10, enemy.global_position + Vector3(-0.15, 0.55, 0.0), null, marksman_metadata)
	assert(enemy.voxel_visual.is_limb_detached("left_leg"), "三八式精确射击没有立即打断命中的腿部")
	var right_leg_hitbox := enemy.get_node("RightLegHitbox") as CombatHitbox3D
	var shotgun_metadata := WeaponCatalog3D.get_definition("trench_gun")
	shotgun_metadata["impact_normal"] = Vector3.BACK
	right_leg_hitbox.receive_shot(10, enemy.global_position + Vector3(0.15, 0.55, 0.0), null, shotgun_metadata)
	assert(enemy.voxel_visual.is_limb_detached("right_leg"), "霰弹枪重火力命中没有立即打断腿部")
	enemy.queue_free()
	for child in get_children():
		if child is RigidBody3D and child.name.begins_with("Detached_"):
			child.queue_free()
	await get_tree().process_frame
