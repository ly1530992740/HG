extends Node

const ENEMY_SQUAD_SCENE := preload("res://Prefab/Enemy/goap_raider_squad.tscn")
const ALLY_SQUAD_SCENE := preload("res://Prefab/Ally/ally_defense_squad.tscn")
const PLAYER_SCENE := preload("res://unit/pawn_/pawn black.tscn")
const SHOP_SCENE := preload("res://survival/shop/survival_shop.tscn")
const COMMAND_SCENE := preload("res://survival/allies/player_squad_command_controller.tscn")
const AMMO_SCENE := preload("res://survival/pickups/ammo_pickup.tscn")
const PLAYER_MELEE_EFFECT_SCENE := preload("res://unit/player/attack_effect.tscn")

class PlayerProbe:
	extends Node2D
	var received_ammo := 0
	var received_damage := 0

	func receive_ammo_pickup(amount: int) -> void:
		received_ammo += amount

	func take_damage(amount: int, _source_position := Vector2.ZERO) -> void:
		received_damage += amount

class HostileProbe:
	extends Node2D

	func get_combat_team() -> StringName:
		return &"hostile"

var _failures: PackedStringArray = []
var _spawned_waves: Array[int] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	SurvivalEconomy.reset()
	await _test_autonomous_squad_score_ammo_and_cleanup()
	await _test_wave_sequence()
	await _test_player_ammo_shop_and_ally_orders()
	if _failures.is_empty():
		print("Survival systems smoke test passed.")
		await _cleanup_and_quit(0)
		return
	for failure in _failures:
		push_error(failure)
	await _cleanup_and_quit(1)

func _test_autonomous_squad_score_ammo_and_cleanup() -> void:
	var squad := ENEMY_SQUAD_SCENE.instantiate() as SquadCoordinator
	squad.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(squad)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(squad.command_mode == SquadCoordinator.CommandMode.AUTONOMOUS_GOAP, "敌军预制体未启用单兵自主 GOAP 模式")
	_expect(squad.leader == null and not squad.elect_squad_leader, "无 Qwen 模式仍选举了小队长")
	_expect(squad.get_node_or_null("LlmHttpRequest") == null, "无 Qwen 模式创建了 HTTP 请求节点")
	_expect(squad.members.size() == 4, "敌军预制体没有注册四名场景士兵")
	for member in squad.members:
		_expect(bool(member.actor.get("autonomous_goap_enabled")), "自主小队成员未启用自主 GOAP")
	var melee_actor := squad.get_member_actor(&"RaiderMelee1")
	_expect(melee_actor != null and melee_actor.get("firearm_weapon") == null, "纯近战兵仍然持有枪械")
	_expect(melee_actor != null and melee_actor.get("melee_weapon") is MeleeWeapon, "纯近战兵没有小刀武器")

	var player_probe := PlayerProbe.new()
	player_probe.add_to_group("player")
	add_child(player_probe)
	var melee_weapon := melee_actor.get("melee_weapon") as MeleeWeapon
	melee_weapon.hitbox_spawned.connect(func(hitbox: Area2D):
		melee_weapon._on_hitbox_body_entered(player_probe, hitbox)
	, CONNECT_ONE_SHOT)
	melee_weapon.try_attack(player_probe.global_position + Vector2.RIGHT)
	await get_tree().physics_frame
	_expect(player_probe.received_damage == int(melee_actor.get("melee_damage")), "纯近战兵的小刀没有对玩家造成配置伤害")
	var player_melee_effect := PLAYER_MELEE_EFFECT_SCENE.instantiate()
	player_melee_effect.configure_attack(player_probe, 2)
	add_child(player_melee_effect)
	var melee_effect_victim := squad.get_member_actor(&"RaiderRifle1")
	var health_before_effect := int(melee_effect_victim.get("health"))
	player_melee_effect._on_attack_effect_body_entered(melee_effect_victim)
	_expect(int(melee_effect_victim.get("health")) == health_before_effect - 2, "玩家近战工具特效没有对敌人造成伤害")
	player_melee_effect.queue_free()

	var coordinator := squad as SquadCoordinator
	coordinator.get_blackboard().set_fact(&"roe", RulesOfEngagement.Type.WEAPONS_FREE)
	coordinator._issue_contact_fire_plan(player_probe)
	var suppress_orders := 0
	var focus_orders := 0
	for member in coordinator.members:
		var issued_order := member.get_current_order()
		if issued_order != null and issued_order.type == SquadOrder.Type.SUPPRESS:
			suppress_orders += 1
		elif issued_order != null and issued_order.type == SquadOrder.Type.FOCUS_FIRE:
			focus_orders += 1
			_expect(bool(member.actor.call("_is_fire_authorized", player_probe)), "掩体后的精确开火命令仍被个人视线门槛阻止")
	_expect(suppress_orders >= 1 and focus_orders >= 1, "步枪小队进入掩体后没有收到压制与精确开火命令")
	var scored_actor := squad.get_member_actor(&"RaiderRifle1")
	scored_actor.set("drops_ammo_on_death", false)
	scored_actor.receive_melee_hit(999, Vector2.ZERO, player_probe)
	await get_tree().process_frame
	_expect(SurvivalEconomy.points == 1, "玩家击杀没有获得 1 积分")

	var hostile_probe := HostileProbe.new()
	add_child(hostile_probe)
	var unscored_actor := squad.get_member_actor(&"RaiderRifle2")
	unscored_actor.set("drops_ammo_on_death", false)
	unscored_actor.receive_melee_hit(999, Vector2.ZERO, hostile_probe)
	await get_tree().process_frame
	_expect(SurvivalEconomy.points == 1, "敌对 AI 互相击杀错误增加了玩家积分")

	var pickup := AMMO_SCENE.instantiate() as AmmoPickup
	pickup.ammo_amount = 17
	add_child(pickup)
	pickup._on_body_entered(player_probe)
	await get_tree().process_frame
	_expect(player_probe.received_ammo == 17, "弹药拾取没有把弹药交给玩家")

	for actor in squad.get_configured_member_actors():
		if is_instance_valid(actor) and actor.is_combat_alive():
			actor.set("drops_ammo_on_death", false)
			actor.set("awards_player_score", false)
			actor.die()
	await get_tree().create_timer(0.7).timeout
	_expect(not is_instance_valid(squad), "最后一名成员死亡后小队 Group 没有自动销毁")
	player_probe.queue_free()
	hostile_probe.queue_free()

func _test_wave_sequence() -> void:
	var entry := SquadWaveEntry.new()
	entry.squad_scene = ENEMY_SQUAD_SCENE
	entry.count = 1
	entry.spawn_radius_override = 0.0
	var wave_one := SquadWaveDefinition.new()
	wave_one.wave_name = "测试第一波"
	wave_one.squads = [entry]
	var wave_two := SquadWaveDefinition.new()
	wave_two.wave_name = "测试第二波"
	wave_two.squads = [entry]
	var spawner := SquadWaveSpawner.new()
	spawner.auto_start = false
	spawner.first_wave_delay = 0.05
	spawner.between_wave_delay = 0.05
	spawner.clear_check_interval = 0.02
	spawner.waves = [wave_one, wave_two]
	spawner.wave_spawned.connect(_on_test_wave_spawned)
	add_child(spawner)
	spawner.start_waves()
	await _wait_until(func(): return _spawned_waves.has(1), 2.0)
	_expect(_spawned_waves.has(1) and spawner.active_squads.size() == 1, "第一波没有按倒计时生成")
	var first_group := spawner.active_squads[0] if not spawner.active_squads.is_empty() else null
	_kill_active_wave(spawner)
	await _wait_until(func(): return _spawned_waves.has(2), 2.0)
	_expect(_spawned_waves.has(2), "第一波全灭后没有生成第二波")
	_expect(first_group == null or not is_instance_valid(first_group), "清空第一波后仍保留旧小队 Group")
	_kill_active_wave(spawner)
	await _wait_until(func(): return spawner.completed, 2.0)
	_expect(spawner.completed, "第二波全灭后波次生成器没有完成")
	spawner.queue_free()

func _test_player_ammo_shop_and_ally_orders() -> void:
	_expect(_action_has_mouse_button(&"fire_weapon", MOUSE_BUTTON_LEFT), "开火没有绑定鼠标左键")
	_expect(_action_has_mouse_button(&"aim_weapon", MOUSE_BUTTON_RIGHT), "精确瞄准没有绑定鼠标右键")
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var aim := player.get("aim_component") as AimComponent
	_expect(aim != null and is_equal_approx(aim.get_spread_multiplier(false), 3.0), "玩家腰射散布惩罚不正确")
	if aim != null:
		aim.set_aiming(true)
		aim.process(1.0, false)
		_expect(aim.is_settled() and aim.get_spread_multiplier(false) <= 0.1, "右键稳定瞄准后弹道仍有明显散布惩罚")
		aim.report_shot()
		_expect(aim.get_spread_multiplier(false) <= 0.3, "精确瞄准后的单发后坐力惩罚过大")
	player.unlock_firearm("pistol", false)
	player.set_firearm_weapon("rifle")
	var rifle := player.get("firearm_weapon") as FirearmWeapon
	rifle.magazine_ammo = 2
	rifle.reserve_ammo = 7
	player.set_firearm_weapon("pistol")
	player.set_firearm_weapon("rifle")
	_expect(rifle.magazine_ammo == 2 and rifle.reserve_ammo == 7, "Q/E 切枪后步枪弹药被重置")
	player.receive_ammo_pickup(9)
	_expect(rifle.reserve_ammo == 16, "玩家拾取弹药后备用弹药没有增加")

	SurvivalEconomy.reset(50)
	var shop := SHOP_SCENE.instantiate() as SurvivalShopController
	add_child(shop)
	await get_tree().process_frame
	shop._player = player
	_assert_shop_rect_fits(shop, Vector2(360.0, 640.0), "窄屏竖屏")
	_assert_shop_rect_fits(shop, Vector2(640.0, 360.0), "窄屏横屏")
	_assert_shop_rect_fits(shop, Vector2(2560.0, 1440.0), "宽屏")
	_expect(shop.catalog_items.size() >= 8, "商城 JSON 没有加载完整商品")
	var pistol_item := _find_catalog_item(shop, "weapon_pistol")
	shop._purchase_weapon(pistol_item)
	_expect(SurvivalEconomy.points == 47, "购买武器没有按 JSON 价格扣分")
	await get_tree().process_frame
	var weapon_pickup := get_tree().get_first_node_in_group("weapon_pickup") as Area2D
	_expect(weapon_pickup != null and String(weapon_pickup.get("weapon_id")) == "pistol", "购买武器没有在玩家附近投放拾取物")
	if weapon_pickup != null:
		weapon_pickup._on_body_entered(player)
	await get_tree().process_frame
	_expect(player.get("current_firearm_id") == "pistol", "玩家接触地面武器后没有装备该武器")
	_expect(weapon_pickup == null or not is_instance_valid(weapon_pickup), "武器被拾取后仍留在地面")

	var squad_count_before := get_tree().get_nodes_in_group("squad_group").size()
	shop._purchase_ally(_find_catalog_item(shop, "ally_defense_squad"))
	await _wait_until(func():
		var spawned := _find_latest_ally_squad()
		return spawned != null and spawned.get_member_count() == 4
	, 2.0)
	_expect(get_tree().get_nodes_in_group("squad_group").size() == squad_count_before + 1, "商城没有生成队友小队预制体")
	var ally_squad := _find_latest_ally_squad()
	_expect(ally_squad != null and ally_squad.command_mode == SquadCoordinator.CommandMode.AUTONOMOUS_GOAP, "购买的队友没有使用自主 GOAP")

	var wall_count_before := get_tree().get_nodes_in_group("cover").size()
	shop._begin_building_placement(_find_catalog_item(shop, "cover_low_wall"))
	shop._confirm_building_placement()
	await get_tree().process_frame
	_expect(get_tree().get_nodes_in_group("cover").size() == wall_count_before + 1, "商城没有生成可用掩体")

	var command := COMMAND_SCENE.instantiate() as PlayerSquadCommandController
	add_child(command)
	await get_tree().process_frame
	var order_position := Vector2(420.0, 180.0)
	var ordered_count := command.issue_defense_order(order_position)
	_expect(ally_squad != null and ordered_count == ally_squad.get_member_count(), "G 指挥没有覆盖全部玩家队友")
	if ally_squad != null:
		for actor in ally_squad.get_configured_member_actors():
			_expect(bool(actor.get("_defense_anchor_active")), "队友没有收到新的防守中心")
			_expect(float(actor.get("defense_radius")) == command.defense_radius, "队友防守半径没有更新")

func _kill_active_wave(spawner: SquadWaveSpawner) -> void:
	for squad in spawner.active_squads:
		if not is_instance_valid(squad):
			continue
		for actor in squad.get_configured_member_actors():
			if is_instance_valid(actor) and actor.is_combat_alive():
				actor.set("drops_ammo_on_death", false)
				actor.set("awards_player_score", false)
				actor.die()

func _on_test_wave_spawned(wave_number: int, _squads: Array[SquadGroup]) -> void:
	_spawned_waves.append(wave_number)

func _find_catalog_item(shop: SurvivalShopController, item_id: String) -> Dictionary:
	for item in shop.catalog_items:
		if String(item.get("id", "")) == item_id:
			return item
	_expect(false, "商城 JSON 缺少商品：%s" % item_id)
	return {}

func _find_latest_ally_squad() -> SquadCoordinator:
	for candidate in get_tree().get_nodes_in_group("squad_group"):
		if candidate is SquadCoordinator and candidate.combat_team == &"player_allies":
			return candidate
	return null

func _action_has_mouse_button(action: StringName, button_index: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button_index:
			return true
	return false

func _assert_shop_rect_fits(shop: SurvivalShopController, viewport_size: Vector2, label: String) -> void:
	var rect := shop.calculate_shop_rect(viewport_size)
	_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0, "%s商城面板超出屏幕左上边界" % label)
	_expect(rect.end.x <= viewport_size.x + 0.1 and rect.end.y <= viewport_size.y + 0.1, "%s商城面板超出屏幕右下边界" % label)
	_expect(rect.size.x > 0.0 and rect.size.y > 0.0, "%s商城面板尺寸无效" % label)

func _wait_until(predicate: Callable, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _cleanup_and_quit(exit_code: int) -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
