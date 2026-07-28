extends Node

signal reinforcement_wave_spawned(members: Array[Node2D])

const SHOOTER_SCENE := preload("res://unit/goblins/goblin shooter.tscn")

@export var auto_pause_after_opening_volley := false
@export_range(0.1, 1.0, 0.05) var pause_delay_seconds := 0.3

var _pause_scheduled := false
var _initial_red: Array[Node2D] = []
var _wave_one_cleared_msec := 0
var _guard_deployed_msec := 0
var _reinforcements_spawned := false
var reinforcement_members: Array[Node2D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var battle := get_parent()
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	alpha.allow_silent_ambush = true
	alpha.initial_guard_enabled = false
	alpha.ambush_ready_ratio_required = 1.0
	alpha.ambush_aim_quality_required = 0.9
	alpha.search_direction_override = Vector2.RIGHT
	bravo.allow_silent_ambush = true
	bravo.initial_guard_enabled = false
	bravo.hold_search_until_first_contact = true
	bravo.search_direction_override = Vector2.ZERO
	_initial_red.assign(bravo.get_configured_member_actors())
	for actor in alpha.get_configured_member_actors():
		var soldier := actor as GoblinBase
		soldier.initial_facing_direction = Vector2.RIGHT
		soldier.last_move_dir = Vector2.RIGHT
	for actor in _initial_red:
		var soldier := actor as GoblinBase
		soldier.initial_facing_direction = Vector2.RIGHT
		soldier.last_move_dir = Vector2.RIGHT
	_configure_first_wave_geometry(battle, alpha)
	if not alpha.ambush_opened.is_connected(_on_alpha_ambush_opened):
		alpha.ambush_opened.connect(_on_alpha_ambush_opened)
	call_deferred("_restart_search_orders")

func _process(_delta: float) -> void:
	if _reinforcements_spawned or _initial_red.is_empty():
		return
	for soldier in _initial_red:
		if is_instance_valid(soldier) and soldier.is_combat_alive():
			return
	if _wave_one_cleared_msec == 0:
		_wave_one_cleared_msec = Time.get_ticks_msec()
		return
	var battle := get_parent()
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	if not _is_guard_deployed(alpha):
		_guard_deployed_msec = 0
		return
	if _guard_deployed_msec == 0:
		_guard_deployed_msec = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _guard_deployed_msec >= 700:
		_spawn_east_reinforcements()

func _is_guard_deployed(alpha: LlmSquadCoordinator) -> bool:
	if alpha.task_scheduler == null or alpha.task_scheduler.active_plan == null:
		return false
	if alpha.task_scheduler.active_plan.intent != &"GUARD":
		return false
	var guard := alpha.task_scheduler.active_plan.get_task(&"perimeter_guard")
	if guard == null or guard.state not in [SquadTask.State.ACTIVE, SquadTask.State.READY]:
		return false
	for member_id in guard.recipient_ids:
		var member := alpha.task_scheduler.members_by_id.get(member_id) as SquadMember
		if member == null or not is_instance_valid(member.actor) or not member.actor.is_combat_alive():
			continue
		var destination := guard.get_position_for(member_id)
		if destination == Vector2.ZERO or member.actor.global_position.distance_to(destination) > 140.0:
			return false
	return true

func _configure_first_wave_geometry(battle: Node, alpha: SquadGroup) -> void:
	for actor in alpha.get_configured_member_actors():
		var soldier := actor as GoblinBase
		soldier.global_position.x = maxf(soldier.global_position.x, -820.0)
	var red_positions := [
		Vector2(850, -410), Vector2(900, -270), Vector2(875, -120), Vector2(920, 30),
		Vector2(865, 180), Vector2(910, 330), Vector2(820, 455), Vector2(960, 470),
	]
	for index in mini(_initial_red.size(), red_positions.size()):
		var soldier := _initial_red[index] as GoblinBase
		soldier.global_position = red_positions[index]
		soldier.initial_facing_direction = Vector2.RIGHT
		soldier.last_move_dir = Vector2.RIGHT
	for coordinator_name in ["EnemySquadCoordinator", "EnemySquadCoordinatorBravo"]:
		var coordinator := battle.get_node(coordinator_name) as LlmSquadCoordinator
		coordinator.get_blackboard().set_fact(&"scenario_name", "伏击后东侧增援")

func _spawn_east_reinforcements() -> void:
	_reinforcements_spawned = true
	var battle := get_parent()
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	var spawn_positions := [
		Vector2(1360, -430), Vector2(1400, -260), Vector2(1380, -80),
		Vector2(1380, 100), Vector2(1400, 280), Vector2(1360, 450),
	]
	var roles := [
		SquadCombatRole.Type.MACHINE_GUNNER,
		SquadCombatRole.Type.RIFLEMAN,
		SquadCombatRole.Type.MARKSMAN,
		SquadCombatRole.Type.RIFLEMAN,
		SquadCombatRole.Type.SHOTGUNNER,
		SquadCombatRole.Type.PISTOL_SCOUT,
	]
	for index in spawn_positions.size():
		var spawn := SquadMemberSpawn.new()
		spawn.member_id = StringName("BravoWave2_%d" % (index + 1))
		spawn.position = spawn_positions[index]
		spawn.combat_role = roles[index]
		spawn.initial_facing_direction = Vector2.LEFT
		var soldier := bravo.spawn_member(spawn, SHOOTER_SCENE)
		if soldier == null:
			continue
		soldier.global_position = spawn_positions[index]
		reinforcement_members.append(soldier)
		battle.register_dynamic_combatant(soldier, true)
	print("[SCENARIO1] WAVE2_SPAWN side=EAST count=%d situation_before_detection=%d" % [reinforcement_members.size(), (battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator).situation_version])
	reinforcement_wave_spawned.emit(reinforcement_members)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		_set_demo_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func _on_alpha_ambush_opened(_target: Node2D, _reason: StringName) -> void:
	if not auto_pause_after_opening_volley or _pause_scheduled:
		return
	_pause_scheduled = true
	await get_tree().create_timer(pause_delay_seconds, true, false, true).timeout
	_set_demo_paused(true)

func _set_demo_paused(paused: bool) -> void:
	var battle := get_parent()
	for node_name in ["EnemySquadCoordinator", "EnemySquadCoordinatorBravo"]:
		var commander := battle.get_node_or_null(node_name) as LlmSquadCoordinator
		if commander == null:
			continue
		commander.get_blackboard().set_fact(&"demo_paused", paused)
		commander._update_decision_label()
	get_tree().paused = paused

func _restart_search_orders() -> void:
	var battle := get_parent()
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	if not alpha.members.is_empty():
		alpha._issue_search_sweep()
	if not bravo.members.is_empty():
		bravo._issue_search_sweep()
