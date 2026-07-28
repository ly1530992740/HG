extends Node

const DEFENSE_SCENE := preload("res://tests/firearm_test/survival_defense_wave_scene.tscn")

var _failures: PackedStringArray = []
var _spawned_wave_numbers: Array[int] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var defense := DEFENSE_SCENE.instantiate()
	var spawner := defense.get_node("EnemyWaveSpawner") as SquadWaveSpawner
	var player := defense.get_node("Player")
	player.set("firearm_test_invulnerable", true)
	spawner.first_wave_delay = 0.05
	spawner.between_wave_delay = 0.05
	spawner.clear_check_interval = 0.02
	spawner.wave_spawned.connect(_on_wave_spawned)
	add_child(defense)
	await _wait_until(func(): return _spawned_wave_numbers.has(1), 2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(int(defense.get("initial_points")) == 100, "防守场景初始积分配置不是 100")
	_expect(SurvivalEconomy.points == 100, "防守场景启动后没有发放 100 初始积分")
	_expect(spawner.waves.size() == 3, "防守场景不是三波配置")
	_expect(_count_active_members(spawner) == 4, "第一波应为 4 名侦搜袭扰敌军")
	_assert_spawn_ring_facing_and_goal(spawner, player)
	defense.call("_update_squad_commands")
	var command_text := String((defense.get_node("CanvasLayer/SquadCommandPanel/Margin/VBox/Commands") as RichTextLabel).text)
	_expect(command_text.contains("队长：") and not command_text.contains("队长：无"), "波次敌军队长没有显示在右下角")
	_expect(command_text.contains("指令：") and not command_text.contains("指令：空"), "波次敌军队长没有显示当前命令")
	_kill_active_wave(spawner)

	await _wait_until(func(): return _spawned_wave_numbers.has(2), 2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_count_active_members(spawner) == 10, "第二波应为 10 名步枪与突击敌军")
	_assert_spawn_ring_facing_and_goal(spawner, player)
	_kill_active_wave(spawner)

	await _wait_until(func(): return _spawned_wave_numbers.has(3), 2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_count_active_members(spawner) == 16, "第三波应为 16 名重火力总攻敌军")
	_assert_spawn_ring_facing_and_goal(spawner, player)
	_kill_active_wave(spawner)
	await _wait_until(func(): return spawner.completed, 2.0)
	_expect(spawner.completed, "清空第三波后场景未报告防守完成")

	defense.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("Survival defense wave smoke test passed: 4 -> 10 -> 16 enemies.")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _on_wave_spawned(wave_number: int, _squads: Array[SquadGroup]) -> void:
	_spawned_wave_numbers.append(wave_number)

func _count_active_members(spawner: SquadWaveSpawner) -> int:
	var count := 0
	for squad in spawner.active_squads:
		if is_instance_valid(squad):
			count += squad.get_member_count()
	return count

func _assert_spawn_ring_facing_and_goal(spawner: SquadWaveSpawner, player: Node2D) -> void:
	for squad in spawner.active_squads:
		if not is_instance_valid(squad):
			continue
		var distance := squad.global_position.distance_to(spawner.global_position)
		_expect(absf(distance - spawner.spawn_radius) <= 1.0, "敌军没有生成在最大半径的最外圆环上")
		var expected_facing := (spawner.global_position - squad.global_position).normalized()
		_expect(squad is SquadCoordinator and squad.command_mode == SquadCoordinator.CommandMode.SQUAD_COMMANDER, "波次小队没有使用小队长指挥模式")
		var coordinator := squad as SquadCoordinator
		_expect(coordinator.elect_squad_leader and coordinator.leader != null, "波次小队没有选出小队长")
		_expect(coordinator.get_blackboard().shared_target == player, "小队长没有在出生时获得玩家目标")
		var current_order := coordinator.get_blackboard().current_order
		_expect(current_order != null and current_order.target == player, "小队长没有立即发布消灭玩家的接敌命令")
		for actor in squad.get_configured_member_actors():
			var initial_facing: Vector2 = actor.get("initial_facing_direction")
			_expect(initial_facing.dot(expected_facing) >= 0.95, "波次成员的初始朝向没有指向防守中心")
			_expect(actor.get("autonomous_objective_target") == player, "波次敌军没有把玩家设为初始消灭目标")
			_expect(actor.get("target") == player and actor.get("current_target") == player, "波次敌军没有立即锁定玩家位置")
			_expect(not bool(actor.get("autonomous_goap_enabled")), "有小队长的波次成员仍处于无队长自主模式")

func _kill_active_wave(spawner: SquadWaveSpawner) -> void:
	for squad in spawner.active_squads:
		if not is_instance_valid(squad):
			continue
		for actor in squad.get_configured_member_actors():
			if is_instance_valid(actor) and actor.is_combat_alive():
				actor.set("drops_ammo_on_death", false)
				actor.set("awards_player_score", false)
				actor.die()

func _wait_until(predicate: Callable, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
