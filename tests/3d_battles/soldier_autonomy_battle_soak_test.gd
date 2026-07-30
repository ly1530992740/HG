extends Node

const BATTLE_SCENE := preload("res://tests/3d_battles/llm_commander_battle_3d.tscn")
const TEST_DURATION := 20.0
const SAMPLE_INTERVAL := 0.25

var _battle: Node3D
var _soldiers: Array[Soldier3D] = []
var _shots := {Soldier3D.Team.RED: 0, Soldier3D.Team.BLUE: 0}
var _deaths := {Soldier3D.Team.RED: 0, Soldier3D.Team.BLUE: 0}
var _goals_seen: Dictionary = {}
var _actions_seen: Dictionary = {}
var _cross_layer_action_errors := 0
var _failures := 0

func _ready() -> void:
	_battle = BATTLE_SCENE.instantiate() as Node3D
	var blue := _battle.get_node("BlueSquad") as SquadCoordinator3D
	var red := _battle.get_node("RedSquad") as SquadCoordinator3D
	blue.use_qwen = false
	red.use_qwen = false
	add_child(_battle)
	await get_tree().process_frame
	_soldiers.assign(blue.get_configured_member_actors() + red.get_configured_member_actors())
	for soldier in _soldiers:
		soldier.weapon_fired.connect(_on_weapon_fired)
		soldier.died.connect(_on_soldier_died)
		var agent := soldier.get("_goap_agent") as GoapAgent
		agent.goal_changed.connect(_on_goal_changed.bind(soldier))
		agent.action_changed.connect(_on_action_changed.bind(soldier))

	var elapsed := 0.0
	var next_report := 5.0
	while elapsed < TEST_DURATION:
		await get_tree().create_timer(SAMPLE_INTERVAL).timeout
		elapsed += SAMPLE_INTERVAL
		_sample_goap_runtime()
		if elapsed + 0.001 >= next_report:
			_print_snapshot(elapsed, blue, red)
			next_report += 5.0

	_expect(blue.current_plan != "WAITING" and red.current_plan != "WAITING",
		"Both squads must leave WAITING and issue a tactical plan")
	_expect(int(_shots[Soldier3D.Team.BLUE]) > 0 and int(_shots[Soldier3D.Team.RED]) > 0,
		"Both squads must execute weapon fire during the encounter")
	_expect(_goals_seen.has("执行小队指令"),
		"The runtime must execute the squad-directive GOAP goal")
	_expect(_goals_seen.has("SURVIVE_THREAT"),
		"At least one exposed soldier must execute the survival interrupt")
	_expect(_actions_seen.has("AUTONOMY_SEEK_COVER") or _actions_seen.has("AUTONOMY_DROP_PRONE"),
		"The battlefield must execute a concrete autonomous protection action")
	_expect(_cross_layer_action_errors == 0,
		"Autonomous goals must never execute directive movement or chase actions")

	var result_line := "shots_blue=%d shots_red=%d deaths_blue=%d deaths_red=%d goals=%s actions=%s" % [
			int(_shots[Soldier3D.Team.BLUE]),
			int(_shots[Soldier3D.Team.RED]),
			int(_deaths[Soldier3D.Team.BLUE]),
			int(_deaths[Soldier3D.Team.RED]),
			str(_goals_seen.keys()),
			str(_actions_seen.keys()),
		]
	if _failures == 0:
		print("SOLDIER_AUTONOMY_BATTLE_SOAK_PASS %s" % result_line)
	else:
		push_error("SOLDIER_AUTONOMY_BATTLE_SOAK_FAIL failures=%d %s" % [_failures, result_line])
	_battle.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)

func _sample_goap_runtime() -> void:
	for soldier in _soldiers:
		if not is_instance_valid(soldier) or soldier.dead:
			continue
		var agent := soldier.get("_goap_agent") as GoapAgent
		if agent == null:
			continue
		var goal := agent.get_current_goal()
		var action := agent.get_current_action()
		if goal != null:
			_goals_seen[String(goal.name)] = true
		if action != null:
			_actions_seen[String(action.name)] = true
		if goal is SoldierAutonomyGoal3D and action is SoldierDirectiveAction3D:
			_cross_layer_action_errors += 1

func _print_snapshot(elapsed: float, blue: SquadCoordinator3D, red: SquadCoordinator3D) -> void:
	print("[AUTONOMY_SOAK] t=%.0f blue_alive=%d red_alive=%d blue_plan=%s red_plan=%s shots=%d/%d" % [
		elapsed,
		_living_count(blue),
		_living_count(red),
		blue.current_plan,
		red.current_plan,
		int(_shots[Soldier3D.Team.BLUE]),
		int(_shots[Soldier3D.Team.RED]),
	])
	print("[AUTONOMY_SOAK] blue_stage=%d red_stage=%d" % [blue.current_stage, red.current_stage])
	for soldier in _soldiers:
		if not is_instance_valid(soldier) or soldier.dead:
			continue
		var agent := soldier.get("_goap_agent") as GoapAgent
		var goal := agent.get_current_goal()
		var action := agent.get_current_action()
		var directive := soldier.active_directive
		print("[AUTONOMY_MEMBER] name=%s team=%d hp=%d stance=%d cover=%s directive=%s version=%d/%d goal=%s action=%s" % [
			String(soldier.name),
			int(soldier.combat_team),
			soldier.health,
			int(soldier.stance),
			str(is_instance_valid(soldier.active_cover)),
			directive.get_label() if directive != null else "NONE",
			soldier.last_completed_directive_version,
			directive.version if directive != null else 0,
			String(goal.name) if goal != null else "NONE",
			String(action.name) if action != null else "NONE",
		])

func _living_count(squad: SquadCoordinator3D) -> int:
	var count := 0
	for soldier in squad.get_configured_member_actors():
		if is_instance_valid(soldier) and not soldier.dead:
			count += 1
	return count

func _on_weapon_fired(actor: Soldier3D, _target: Node3D) -> void:
	_shots[actor.combat_team] = int(_shots.get(actor.combat_team, 0)) + 1

func _on_soldier_died(actor: Soldier3D) -> void:
	_deaths[actor.combat_team] = int(_deaths.get(actor.combat_team, 0)) + 1

func _on_goal_changed(goal: GoapGoal, _soldier: Soldier3D) -> void:
	if goal != null:
		_goals_seen[String(goal.name)] = true

func _on_action_changed(action: GoapAction, soldier: Soldier3D) -> void:
	if action == null:
		return
	_actions_seen[String(action.name)] = true
	var agent := soldier.get("_goap_agent") as GoapAgent
	if agent.get_current_goal() is SoldierAutonomyGoal3D and action is SoldierDirectiveAction3D:
		_cross_layer_action_errors += 1

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("BATTLE SOAK FAILURE: %s" % message)
