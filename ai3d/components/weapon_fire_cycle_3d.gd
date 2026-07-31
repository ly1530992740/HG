extends Node
class_name WeaponFireCycle3D

enum Phase { READY, ACQUIRING, BURST, RECOVERING }

const ROLE_MARKSMAN := 3

var phase: Phase = Phase.READY
var aim_duration := 0.45
var reload_duration := 2.2
var shot_interval := 0.2
var target_switch_delay := 0.2
var burst_min := 1
var burst_max := 1
var recovery_min := 0.65
var recovery_max := 0.9
var setup_duration := 0.0
var fire_arc_half_angle_degrees := 180.0
var weapon_family := "rifle"

var _timer := 0.0
var _burst_remaining := 0
var _target_id := 0
var _setup_direction := Vector3.ZERO
var _is_setup := false
var _rng := RandomNumberGenerator.new()
var _cover_rng := RandomNumberGenerator.new()

func configure(definition: Dictionary, role: int, seed_value := 0) -> void:
	var family := String(definition.get("family", "rifle"))
	weapon_family = family
	aim_duration = maxf(0.0, float(definition.get("aim_settle_time", 0.45)))
	reload_duration = maxf(0.0, float(definition.get("reload_duration", 2.2)))
	shot_interval = maxf(0.03, float(definition.get("fire_interval", 0.2)))
	target_switch_delay = 0.2
	burst_min = 1
	burst_max = 1
	recovery_min = shot_interval
	recovery_max = shot_interval * 1.2
	setup_duration = 0.0
	fire_arc_half_angle_degrees = 180.0

	match family:
		"smg":
			burst_min = 3
			burst_max = 7
			recovery_min = 0.55
			recovery_max = 0.95
			target_switch_delay = 0.16
		"lmg":
			burst_min = 6
			burst_max = 12
			recovery_min = 0.95
			recovery_max = 1.45
			target_switch_delay = 0.35
			setup_duration = 0.75
			fire_arc_half_angle_degrees = 32.0
		"pistol":
			burst_min = 1
			burst_max = 2
			recovery_min = 0.45
			recovery_max = 0.75
		"shotgun":
			recovery_min = maxf(0.7, shot_interval)
			recovery_max = maxf(1.0, shot_interval * 1.25)
		"bolt_rifle":
			target_switch_delay = 0.28
			recovery_min = shot_interval
			recovery_max = shot_interval * 1.18
		_:
			recovery_min = maxf(0.45, shot_interval)
			recovery_max = maxf(0.7, shot_interval * 1.2)

	if role == ROLE_MARKSMAN:
		target_switch_delay = maxf(target_switch_delay, 0.45)
	var resolved_seed: int = seed_value if seed_value != 0 else hash(String(definition.get("id", "weapon")))
	_rng.seed = resolved_seed
	_cover_rng.seed = resolved_seed ^ 0x5F3759DF
	reset()

func process(delta: float) -> void:
	_timer = maxf(0.0, _timer - delta)
	if _timer <= 0.0 and phase in [Phase.ACQUIRING, Phase.RECOVERING]:
		phase = Phase.READY

func can_fire(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	var next_target_id := int(target.get_instance_id())
	if next_target_id != _target_id:
		_target_id = next_target_id
		_burst_remaining = 0
		phase = Phase.ACQUIRING
		_timer = target_switch_delay
		return false
	if phase == Phase.READY:
		_burst_remaining = _rng.randi_range(burst_min, burst_max)
		phase = Phase.BURST
	return phase == Phase.BURST and _timer <= 0.0 and _burst_remaining > 0

func record_shot() -> void:
	if phase != Phase.BURST:
		return
	_burst_remaining = maxi(0, _burst_remaining - 1)
	if _burst_remaining > 0:
		_timer = shot_interval
		return
	phase = Phase.RECOVERING
	_timer = _rng.randf_range(recovery_min, recovery_max)

func get_required_aim_duration() -> float:
	return aim_duration + (setup_duration if not _is_setup else 0.0)

func roll_cover_exposure_shot_budget(available_ammo: int, suppression_ratio: float) -> int:
	if available_ammo <= 0:
		return 0
	var maximum_shots := 4
	var magazine_dump_chance := 0.02
	match weapon_family:
		"bolt_rifle", "sniper_rifle":
			maximum_shots = 2
			magazine_dump_chance = 0.01
		"pistol":
			maximum_shots = 4
			magazine_dump_chance = 0.03
		"smg":
			maximum_shots = 10
			magazine_dump_chance = 0.07
		"lmg":
			maximum_shots = 18
			magazine_dump_chance = 0.11
		"shotgun":
			maximum_shots = 2
			magazine_dump_chance = 0.015
	var pressure := clampf(suppression_ratio, 0.0, 1.0)
	var adjusted_maximum := maxi(1, roundi(lerpf(float(maximum_shots), 1.0, pow(pressure, 0.65))))
	var adjusted_dump_chance := magazine_dump_chance * pow(1.0 - pressure, 3.0)
	if _cover_rng.randf() < adjusted_dump_chance:
		return available_ammo
	return mini(available_ammo, _cover_rng.randi_range(1, adjusted_maximum))

func complete_aim(direction: Vector3) -> void:
	if setup_duration <= 0.0:
		return
	var flat_direction := direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.001:
		return
	_setup_direction = flat_direction.normalized()
	_is_setup = true

func requires_reaim(direction: Vector3) -> bool:
	if not _is_setup or fire_arc_half_angle_degrees >= 179.0:
		return false
	var flat_direction := direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.001:
		return false
	return rad_to_deg(_setup_direction.angle_to(flat_direction.normalized())) > fire_arc_half_angle_degrees

func notify_movement_started() -> void:
	_is_setup = false
	_setup_direction = Vector3.ZERO
	if phase == Phase.BURST:
		phase = Phase.RECOVERING
		_burst_remaining = 0
		_timer = maxf(_timer, recovery_min)

func reset() -> void:
	phase = Phase.READY
	_timer = 0.0
	_burst_remaining = 0
	_target_id = 0
	_setup_direction = Vector3.ZERO
	_is_setup = false
