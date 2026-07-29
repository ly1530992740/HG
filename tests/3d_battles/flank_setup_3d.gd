extends Node3D

func _ready() -> void:
	var blue := $BlueSquad as SquadCoordinator3D
	var red := $RedSquad as SquadCoordinator3D
	$World/QwenDebugPanel3D.set_debug_visible(true)
	var red_target := red.get_configured_member_actors()[0]
	var blue_target := blue.get_configured_member_actors()[0]
	for member in blue.get_configured_member_actors():
		member.aware_of_enemy = true
		member.current_target = red_target
	for member in red.get_configured_member_actors():
		member.aware_of_enemy = true
		member.current_target = blue_target
	blue.set_known_combat_objective(red_target)
	red.set_known_combat_objective(blue_target)
	call_deferred("_report_route")

func _report_route() -> void:
	await get_tree().process_frame
	var blue := $BlueSquad as SquadCoordinator3D
	var best: Dictionary = blue.get("_route_analyzer").get_best_available()
	print("[FLANK3D] 最优程序验证路线=%s" % (best.get("direction", "无")))
