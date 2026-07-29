extends Node

const AMBUSH_SCENE := preload("res://tests/3d_battles/llm_ambush_battle_3d.tscn")
const FLANK_SCENE := preload("res://tests/3d_battles/llm_flank_battle_3d.tscn")
const SURVIVAL_SCENE := preload("res://survival3d/scenes/survival_defense_wave_scene_3d.tscn")
const FIREARM_SCENE := preload("res://tests/3d_battles/firearm_test_scene_3d.tscn")
const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")

func _ready() -> void:
	await get_tree().process_frame
	await _test_ambush_task_graph()
	await _test_flank_route_switching()
	await _test_wave_and_shop_systems()
	await _test_combat_pickups_and_melee()
	await _test_ai_posture_and_stamina()
	await _test_goap_action_chain()
	await _test_qwen_fallback()
	print("FULL_3D_MIGRATION_SMOKE_PASS")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func _test_ambush_task_graph() -> void:
	var scene := AMBUSH_SCENE.instantiate()
	(scene.get_node("BlueSquad") as SquadCoordinator3D).use_qwen = false
	(scene.get_node("RedSquad") as SquadCoordinator3D).use_qwen = false
	add_child(scene)
	await get_tree().process_frame
	var blue := scene.get_node("BlueSquad") as SquadCoordinator3D
	assert(blue.current_plan == "AMBUSH", "蓝队没有根据未警觉敌军选择伏击")
	assert(blue.current_stage == 1, "伏击没有先进入掩体就位阶段")
	_assert_directive_type(blue, SquadDirective3D.Type.TAKE_COVER)
	_complete_current_stage(blue)
	blue._process_plan_stage()
	assert(blue.current_stage == 2, "伏击未从掩体阶段进入全员瞄准")
	_assert_directive_type(blue, SquadDirective3D.Type.AIM)
	_complete_current_stage(blue)
	blue._process_plan_stage()
	assert(blue.current_stage == 3, "伏击未从瞄准阶段进入同步开火")
	_assert_directive_type(blue, SquadDirective3D.Type.ATTACK)
	scene.queue_free()
	await get_tree().process_frame

func _test_flank_route_switching() -> void:
	var scene := FLANK_SCENE.instantiate()
	(scene.get_node("BlueSquad") as SquadCoordinator3D).use_qwen = false
	(scene.get_node("RedSquad") as SquadCoordinator3D).use_qwen = false
	add_child(scene)
	await get_tree().process_frame
	var blue := scene.get_node("BlueSquad") as SquadCoordinator3D
	var red := scene.get_node("RedSquad") as SquadCoordinator3D
	assert(blue.current_plan == "SUPPRESS_FLANK", "火力劣势时未选择正面压制加侧翼包抄")
	var analyzer := blue.get("_route_analyzer") as SquadRouteAnalyzer3D
	var best := analyzer.get_best_available()
	assert(String(best.get("direction", "")) == "南侧", "长南墙没有成为首选隐蔽路线")
	var flank_count := 0
	var suppress_count := 0
	for member in blue.get_configured_member_actors():
		if member.active_directive.type == SquadDirective3D.Type.FLANK:
			flank_count += 1
		elif member.active_directive.type == SquadDirective3D.Type.SUPPRESS:
			suppress_count += 1
	assert(flank_count == 3 and suppress_count == 1, "包抄没有分成三人机动组和一人正面掩护组")
	var south := scene.get_node("SouthFlankWall") as TacticalCover3D
	var north := scene.get_node("NorthFlankWall") as TacticalCover3D
	south.remove_from_group("cover3d")
	north.cover_length = 17.0
	await get_tree().process_frame
	var center := Vector3.ZERO
	for member in blue.get_configured_member_actors():
		center += member.global_position
	center /= float(blue.get_configured_member_actors().size())
	analyzer.analyze(center, red.get_configured_member_actors()[0].global_position)
	best = analyzer.get_best_available()
	assert(String(best.get("direction", "")) == "北侧", "删除南墙并拉长北墙后没有自动改选北路")
	scene.queue_free()
	await get_tree().process_frame

func _test_wave_and_shop_systems() -> void:
	var scene := SURVIVAL_SCENE.instantiate()
	add_child(scene)
	await get_tree().process_frame
	var spawner := scene.get_node("EnemyWaveSpawner3D") as SquadWaveSpawner3D
	assert(spawner.waves.size() == 3, "3D防守地图没有配置三波敌军")
	spawner.set("_countdown", 0.0)
	spawner._process(0.0)
	assert(spawner.active_squads.size() == 1, "第一波没有生成一支敌军小队")
	assert(not spawner.active_squads[0].use_qwen, "波次敌军没有默认关闭Qwen")
	assert(spawner.active_squads[0].known_target == scene.get_node("World/Player3D"), "波次敌人没有在出生时获得玩家目标")
	_cancel_squad_qwen(spawner.active_squads[0])
	scene.queue_free()
	await get_tree().process_frame

	var range_scene := FIREARM_SCENE.instantiate()
	add_child(range_scene)
	await get_tree().process_frame
	var shop := range_scene.get_node("World/SurvivalShop3D") as SurvivalShopController3D
	SurvivalEconomy.reset(100)
	assert(shop.purchase_item_by_id("weapon_smg"), "商城找不到冲锋枪配置")
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("pickup3d").size() == 1, "购买武器后没有投放地面拾取物")
	assert(SurvivalEconomy.points == 94, "购买武器没有正确扣除积分")
	assert(shop.purchase_item_by_id("ally_defense_squad"), "商城找不到队友小队配置")
	await get_tree().process_frame
	var ally_found := false
	for candidate in get_tree().get_nodes_in_group("squad3d"):
		if candidate is SquadCoordinator3D and int(candidate.combat_team) == int(Soldier3D.Team.PLAYER):
			ally_found = true
			for ally in candidate.get_configured_member_actors():
				assert(ally.max_health >= 160, "购买生成的友军生命值没有提高")
	assert(ally_found, "购买队友后没有生成3D友军小队")
	assert(shop.purchase_item_by_id("cover_low_wall"), "商城找不到3D掩体配置")
	assert(shop.get("_preview") is TacticalCover3D, "购买建筑后没有进入3D预览放置状态")
	shop._confirm_building()
	assert(shop.pending_building.is_empty(), "确认建筑后没有退出放置状态")
	range_scene.queue_free()
	await get_tree().process_frame

func _test_combat_pickups_and_melee() -> void:
	var range_scene := FIREARM_SCENE.instantiate()
	add_child(range_scene)
	await get_tree().process_frame
	var player := range_scene.get_node("World/Player3D") as ThirdPersonPlayer3D
	assert(player.invulnerable, "3D测试场景玩家没有设置为无敌")
	assert(player.receive_weapon_pickup("pistol", 24), "玩家无法拾取新武器")
	assert(player.current_weapon_id == "pistol", "拾取武器后没有切换到该武器")
	player.cycle_weapon(-1)
	assert(player.current_weapon_id == "rifle", "Q/E武器轮换底层逻辑失效")
	player.invulnerable = false
	var health_before := player.health
	var head := player.get_node("HeadHitbox") as CombatHitbox3D
	head.receive_shot(10, player.get_aim_point(), null)
	assert(player.health == health_before - 20, "3D头部命中没有应用双倍伤害")

	var melee := SOLDIER_SCENE.instantiate() as Soldier3D
	melee.combat_team = Soldier3D.Team.RED
	melee.combat_role = Soldier3D.CombatRole.MELEE
	melee.awards_player_score = false
	melee.drops_ammo_on_death = false
	range_scene.add_child(melee)
	melee.global_position = player.global_position + Vector3(0, 0, 1.0)
	health_before = player.health
	assert(melee._try_attack_target(player), "近战兵进入攻击距离后没有执行攻击")
	assert(player.health < health_before, "近战攻击没有造成伤害")

	var shooter := SOLDIER_SCENE.instantiate() as Soldier3D
	shooter.combat_team = Soldier3D.Team.RED
	shooter.dropped_ammo_amount = 23
	range_scene.add_child(shooter)
	shooter.global_position = Vector3(8, 0, 8)
	var pickups_before := get_tree().get_nodes_in_group("pickup3d").size()
	shooter.receive_hit(999, "body", shooter.global_position, player)
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("pickup3d").size() == pickups_before + 1, "敌人死亡没有掉落3D弹药")
	await get_tree().create_timer(0.4).timeout
	range_scene.queue_free()
	await get_tree().process_frame

func _test_qwen_fallback() -> void:
	var brain := QwenSquadBrain3D.new()
	add_child(brain)
	await get_tree().process_frame
	assert("RETREAT" not in QwenSquadBrain3D.ALLOWED_PLANS, "Qwen仍可向敌人或队友下达撤退命令")
	var rule_decision := SquadRuleDecision3D.new()
	assert(rule_decision.choose_plan(true, 0.1, 0.3, true, 1.0, 1.0, false) == "COVER_ATTACK", "低生命小队仍会逃跑而不是依托掩体战斗")
	rule_decision.free()
	var received: Array = []
	brain.decision_ready.connect(func(plan, _reason, _raw, fallback, _latency): received.assign([plan, fallback]))
	brain.request_decision({"我方存活": 4, "已确认敌军": 5, "候选包抄路线": []}, "COVER_ATTACK")
	brain.get("_http").cancel_request()
	brain._on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	assert(received.size() == 2 and received[0] == "COVER_ATTACK" and bool(received[1]), "Qwen不可用时没有立即回退到规则战术")
	brain.queue_free()
	await get_tree().process_frame

func _test_ai_posture_and_stamina() -> void:
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	add_child(soldier)
	await get_tree().process_frame
	var flank := SquadDirective3D.new().configure(
		SquadDirective3D.Type.FLANK,
		1,
		null,
		Vector3(12.0, 0.0, 0.0),
		[Vector3(6.0, 0.0, 0.0), Vector3(12.0, 0.0, 0.0)],
		null,
		0.0,
		"沿侧路包抄"
	)
	soldier.receive_directive(flank)
	assert(soldier.movement_mode == Soldier3D.MoveMode.RUN, "AI 包抄时没有按指令选择跑步")
	var stamina_before := soldier.stamina
	soldier._update_stamina(0.5, true)
	assert(soldier.stamina < stamina_before, "AI 跑步没有消耗体力")
	soldier.set_stance(Soldier3D.Stance.CROUCH)
	assert(soldier.movement_mode == Soldier3D.MoveMode.WALK, "AI 下蹲后仍保持跑步")
	var crouch_visibility := soldier.get_visibility_multiplier()
	soldier.set_stance(Soldier3D.Stance.PRONE)
	assert(soldier.get_visibility_multiplier() < crouch_visibility, "AI 卧倒没有进一步降低可见度")
	soldier.set_stance(Soldier3D.Stance.STAND)
	var ambush := SquadDirective3D.new().configure(
		SquadDirective3D.Type.TAKE_COVER,
		2,
		null,
		Vector3(3.0, 0.0, 0.0),
		[],
		null,
		0.0,
		"隐蔽伏击就位"
	)
	soldier.receive_directive(ambush)
	assert(soldier.movement_mode == Soldier3D.MoveMode.QUIET, "AI 伏击就位时没有采用静步")
	soldier.queue_free()
	await get_tree().process_frame

func _test_goap_action_chain() -> void:
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	var target := SOLDIER_SCENE.instantiate() as Soldier3D
	soldier.combat_team = Soldier3D.Team.BLUE
	target.combat_team = Soldier3D.Team.RED
	soldier.awards_player_score = false
	target.awards_player_score = false
	add_child(soldier)
	add_child(target)
	await get_tree().process_frame
	soldier.set_physics_process(false)
	target.set_physics_process(false)
	soldier.global_position = Vector3.ZERO
	target.global_position = Vector3(40.0, 0.0, 0.0)

	var attack := SquadDirective3D.new().configure(SquadDirective3D.Type.ATTACK, 1, target)
	soldier.receive_directive(attack)
	var operations := _build_goap_plan_operations(soldier)
	assert(operations.has(SoldierDirectiveAction3D.Operation.APPROACH_TARGET), "超出射程时GOAP计划没有接近有效射程Action")
	assert(operations.has(SoldierDirectiveAction3D.Operation.AIM) and operations.has(SoldierDirectiveAction3D.Operation.ENGAGE), "攻击GOAP计划缺少瞄准或射击Action")

	soldier.magazine_ammo = 0
	attack = SquadDirective3D.new().configure(SquadDirective3D.Type.ATTACK, 2, target)
	soldier.receive_directive(attack)
	operations = _build_goap_plan_operations(soldier)
	assert(operations.has(SoldierDirectiveAction3D.Operation.RELOAD), "空弹匣时GOAP计划没有换弹Action")

	soldier.magazine_ammo = 1
	target.global_position = Vector3(10.0, 0.0, 0.0)
	attack = SquadDirective3D.new().configure(SquadDirective3D.Type.ATTACK, 3, target)
	soldier.receive_directive(attack)
	operations = _build_goap_plan_operations(soldier)
	assert(not operations.has(SoldierDirectiveAction3D.Operation.APPROACH_TARGET), "已在有效射程内仍重复规划接近Action")
	var staged_aim := SquadDirective3D.new().configure(SquadDirective3D.Type.AIM, 4, target)
	soldier.receive_directive(staged_aim)
	soldier.is_aimed = true
	(soldier.get("_goap_agent") as GoapAgent).get_world_state().set_state(&"aimed", true)
	attack = SquadDirective3D.new().configure(SquadDirective3D.Type.ATTACK, 5, target)
	soldier.receive_directive(attack)
	operations = _build_goap_plan_operations(soldier)
	assert(soldier.is_aimed and not operations.has(SoldierDirectiveAction3D.Operation.AIM), "同目标从瞄准切到开火时丢失了已稳定的瞄准状态")

	target.global_position = Vector3(40.0, 0.0, 0.0)
	soldier.set("_desired_velocity", Vector3.ZERO)
	assert(not soldier._try_attack_target(target), "超出射程时ENGAGE仍错误完成射击")
	assert((soldier.get("_desired_velocity") as Vector3).is_zero_approx(), "ENGAGE仍在内部驱动士兵直线冲锋")

	var cover := TacticalCover3D.new()
	add_child(cover)
	await get_tree().process_frame
	soldier.active_cover = cover
	soldier.active_cover_slot = Marker3D.new()
	cover.add_child(soldier.active_cover_slot)
	var aim := SquadDirective3D.new().configure(SquadDirective3D.Type.AIM, 6, target)
	soldier.receive_directive(aim)
	assert(soldier.active_cover == cover, "从占领掩体切换到瞄准时错误释放了掩体")

	soldier.queue_free()
	target.queue_free()
	cover.queue_free()
	await get_tree().process_frame

func _build_goap_plan_operations(soldier: Soldier3D) -> Array[int]:
	var agent := soldier.get("_goap_agent") as GoapAgent
	agent.process(0.0)
	var result: Array[int] = []
	for item in agent.get("_current_plan") as Array:
		if item is SoldierDirectiveAction3D:
			result.append((item as SoldierDirectiveAction3D).operation)
	return result

func _complete_current_stage(squad: SquadCoordinator3D) -> void:
	var versions: Dictionary = squad.get("_stage_versions")
	for member in squad.get_configured_member_actors():
		member.last_completed_directive_version = int(versions.get(member, 0))

func _assert_directive_type(squad: SquadCoordinator3D, expected: SquadDirective3D.Type) -> void:
	for member in squad.get_configured_member_actors():
		assert(member.active_directive != null and member.active_directive.type == expected, "成员收到的GOAP指令类型不符合阶段顺序")

func _cancel_squad_qwen(squad: SquadCoordinator3D) -> void:
	var brain := squad.get("_qwen_brain") as QwenSquadBrain3D
	if brain == null:
		return
	var request := brain.get("_http") as HTTPRequest
	if request != null:
		request.cancel_request()
	brain.pending = false
