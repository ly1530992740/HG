extends Node
class_name PlayerAccuracyComponent3D

var aim_hold_time := 0.0
var recoil_spread_degrees := 0.0

func process(delta: float, aiming: bool, recoil_recovery_per_second: float) -> void:
	recoil_spread_degrees = move_toward(recoil_spread_degrees, 0.0, recoil_recovery_per_second * delta)
	if aiming:
		aim_hold_time += delta
	else:
		aim_hold_time = 0.0

func reset_aim() -> void:
	aim_hold_time = 0.0

func reset_recoil() -> void:
	recoil_spread_degrees = 0.0

func report_shot(recoil_per_shot: float, maximum_recoil: float) -> void:
	recoil_spread_degrees = minf(maximum_recoil, recoil_spread_degrees + recoil_per_shot)

func get_spread(
		blind_fire: bool,
		aiming: bool,
		hip_spread: float,
		blind_spread: float,
		aimed_initial_spread: float,
		aimed_spread: float,
		settle_time: float
) -> float:
	var base_spread := hip_spread
	if blind_fire:
		base_spread = blind_spread
	elif aiming:
		var settle_progress := clampf(aim_hold_time / maxf(0.01, settle_time), 0.0, 1.0)
		base_spread = lerpf(aimed_initial_spread, aimed_spread, settle_progress)
	return base_spread + recoil_spread_degrees
