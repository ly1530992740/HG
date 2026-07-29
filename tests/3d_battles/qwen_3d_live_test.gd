extends Node

const BATTLE := preload("res://tests/3d_battles/llm_flank_battle_3d.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var battle := BATTLE.instantiate()
	var blue := battle.get_node("BlueSquad") as SquadCoordinator3D
	var red := battle.get_node("RedSquad") as SquadCoordinator3D
	blue.use_qwen = true
	red.use_qwen = true
	add_child(battle)
	var deadline := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < deadline:
		if not blue.last_qwen_output.is_empty() and not red.last_qwen_output.is_empty() and not blue.last_qwen_output.begins_with("等待") and not red.last_qwen_output.begins_with("等待"):
			break
		await get_tree().process_frame
	_print_decision(blue)
	_print_decision(red)
	var success := blue.last_command_source in ["LOCAL_QWEN", "QWEN_GUARDED"] and red.last_command_source in ["LOCAL_QWEN", "QWEN_GUARDED"]
	if success:
		print("QWEN_3D_LIVE_PASS")
		get_tree().quit(0)
	else:
		push_error("两支3D小队均未获得有效本地Qwen决策")
		get_tree().quit(1)

func _print_decision(squad: SquadCoordinator3D) -> void:
	print("[QWEN3D_LIVE] 小队=%s 延迟=%dms 来源=%s" % [squad.squad_display_name, squad.last_qwen_latency_ms, squad.last_command_source])
	print("[QWEN3D_LIVE] 输入=%s" % squad.last_qwen_input.replace("\n", " "))
	print("[QWEN3D_LIVE] 输出=%s" % squad.last_qwen_output.replace("\n", " "))
	print("[QWEN3D_LIVE] GOAP=%s" % squad.last_command_summary)
