extends Node
class_name AimComponent

@export var hip_fire_spread_multiplier := 3.0
@export var moving_hip_fire_multiplier := 1.75
@export var aimed_spread_multiplier := 1.0
@export var moving_aim_multiplier := 1.5
@export var aimed_move_speed_multiplier := 0.55
@export var aim_settle_time := 0.75
@export var aim_loss_per_second := 4.0
@export var moving_settle_speed_multiplier := 0.55
@export var recoil_per_shot := 0.35
@export var maximum_recoil := 2.0
@export var recoil_recovery_per_second := 1.5

var aiming := false
var aim_quality := 0.0
var recoil_spread := 0.0

func set_aiming(value: bool) -> void:
	aiming = value

func is_aiming() -> bool:
	return aiming

func process(delta: float, is_moving: bool) -> void:
	recoil_spread = move_toward(recoil_spread, 0.0, recoil_recovery_per_second * delta)
	if aiming:
		var settle_rate := 1.0 / maxf(0.05, aim_settle_time)
		if is_moving:
			settle_rate *= moving_settle_speed_multiplier
		aim_quality = move_toward(aim_quality, 1.0, settle_rate * delta)
	else:
		aim_quality = move_toward(aim_quality, 0.0, aim_loss_per_second * delta)

func get_spread_multiplier(is_moving: bool) -> float:
	if aiming:
		var initial_multiplier := hip_fire_spread_multiplier * (moving_hip_fire_multiplier if is_moving else 1.0)
		var settled_multiplier := aimed_spread_multiplier * (moving_aim_multiplier if is_moving else 1.0)
		return lerpf(initial_multiplier, settled_multiplier, aim_quality) + recoil_spread
	return hip_fire_spread_multiplier * (moving_hip_fire_multiplier if is_moving else 1.0)

func get_movement_speed_multiplier() -> float:
	return aimed_move_speed_multiplier if aiming else 1.0

func get_aim_quality() -> float:
	return aim_quality

func is_settled(required_quality := 0.9) -> bool:
	return aiming and aim_quality >= required_quality

func report_shot() -> void:
	recoil_spread = minf(maximum_recoil, recoil_spread + recoil_per_shot)

func reset_aim() -> void:
	aim_quality = 0.0
