extends Node

const BATTLE := preload("res://tests/3d_battles/llm_ambush_battle_3d.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var battle := BATTLE.instantiate()
	var blue := battle.get_node("BlueSquad") as SquadCoordinator3D
	var red := battle.get_node("RedSquad") as SquadCoordinator3D
	blue.use_qwen = false
	red.use_qwen = false
	add_child(battle)
	var saw_cover := false
	var saw_aim := false
	var saw_attack := false
	var saw_guard_after_clear := false
	var last_stage := -1
	var started := Time.get_ticks_msec()
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if blue.current_stage != last_stage:
			last_stage = blue.current_stage
			print("[AMBUSH3D_TEST] t=%dms plan=%s stage=%d red_alive=%s" % [Time.get_ticks_msec() - started, blue.current_plan, blue.current_stage, str(red.is_squad_alive())])
		saw_cover = saw_cover or (blue.current_plan == "AMBUSH" and blue.current_stage == 1)
		saw_aim = saw_aim or (blue.current_plan == "AMBUSH" and blue.current_stage == 2)
		saw_attack = saw_attack or (blue.current_plan == "AMBUSH" and blue.current_stage == 3)
		saw_guard_after_clear = saw_guard_after_clear or (not red.is_squad_alive() and blue.current_plan == "GUARD")
		if bool(battle.get("_spawned")):
			break
		await get_tree().physics_frame
	print("[AMBUSH3D_TEST] end t=%dms spawned=%s red_alive=%s plan=%s stage=%d" % [Time.get_ticks_msec() - started, str(battle.get("_spawned")), str(red.is_squad_alive()), blue.current_plan, blue.current_stage])
	for member in blue.get_configured_member_actors():
		var action: GoapAction = member.get("_goap_agent").get_current_action() as GoapAction
		print("[AMBUSH3D_TEST] member=%s pos=%s target=%s complete=%d action=%s" % [member.name, member.global_position, member.active_directive.target_position, member.last_completed_directive_version, action.name if action != null else "NONE"])
	_expect(saw_cover, "实时伏击未进入掩体就位阶段", failures)
	_expect(saw_aim, "实时伏击未等待全员瞄准", failures)
	_expect(saw_attack, "实时伏击未执行同步开火", failures)
	_expect(not red.is_squad_alive(), "蓝队伏击后未清除第一波红队", failures)
	_expect(saw_guard_after_clear, "清除第一波后蓝队未重新发布警戒", failures)
	_expect(bool(battle.get("_spawned")), "蓝队警戒后东侧第二波未生成", failures)
	if failures.is_empty():
		print("AMBUSH_3D_BEHAVIOR_PASS cover=%s aim=%s attack=%s guard=%s east_wave=%s" % [saw_cover, saw_aim, saw_attack, saw_guard_after_clear, battle.get("_spawned")])
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
