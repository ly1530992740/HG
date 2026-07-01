extends Weapon
class_name FirearmWeapon

signal fired
signal reload_started
signal reload_finished
signal ammo_changed(magazine_ammo: int, reserve_ammo: int)

var magazine_ammo := 0
var reserve_ammo := 0
var cooldown_timer := 0.0
var reloading := false
var trigger_held := false
var trigger_target_position := Vector2.ZERO
var burst_active := false

var _shoot_audio: AudioStreamPlayer2D
var _reload_audio: AudioStreamPlayer2D
var _empty_audio: AudioStreamPlayer2D

func _ready() -> void:
	_setup_audio_players()
	if weapon_data:
		magazine_ammo = weapon_data.magazine_size
		reserve_ammo = weapon_data.reserve_ammo
		emit_signal("ammo_changed", magazine_ammo, reserve_ammo)

func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer = max(0.0, cooldown_timer - delta)

	if trigger_held and weapon_data and weapon_data.fire_mode == WeaponData.FireMode.AUTO:
		try_attack(trigger_target_position)

func try_attack(target_position: Vector2) -> bool:
	if not can_attack():
		emit_signal("attack_failed", "not_ready")
		return false

	if reloading:
		emit_signal("attack_failed", "reloading")
		return false

	if cooldown_timer > 0.0:
		emit_signal("attack_failed", "cooldown")
		return false

	if magazine_ammo <= 0:
		_play_audio(_empty_audio)
		emit_signal("attack_failed", "empty_magazine")
		return false

	match weapon_data.fire_mode:
		WeaponData.FireMode.SEMI_AUTO:
			_fire_once(target_position)
		WeaponData.FireMode.AUTO:
			_fire_once(target_position)
		WeaponData.FireMode.BURST:
			if burst_active:
				emit_signal("attack_failed", "burst_active")
				return false
			_fire_burst(target_position)

	return true

func start_trigger(target_position: Vector2) -> void:
	trigger_held = true
	trigger_target_position = target_position
	try_attack(target_position)

func update_trigger_target(target_position: Vector2) -> void:
	trigger_target_position = target_position

func stop_attack() -> void:
	trigger_held = false

func reload() -> bool:
	if weapon_data == null:
		return false

	if reloading:
		return false

	if magazine_ammo >= weapon_data.magazine_size:
		return false

	if reserve_ammo <= 0:
		_play_audio(_empty_audio)
		emit_signal("attack_failed", "no_reserve_ammo")
		return false

	_reload_async()
	return true

func add_reserve_ammo(amount: int) -> void:
	reserve_ammo = max(0, reserve_ammo + amount)
	emit_signal("ammo_changed", magazine_ammo, reserve_ammo)

func get_total_ammo() -> int:
	return magazine_ammo + reserve_ammo

func _reload_async() -> void:
	reloading = true
	_play_audio(_reload_audio)
	emit_signal("reload_started")

	await get_tree().create_timer(weapon_data.reload_time).timeout

	if weapon_data == null:
		reloading = false
		return

	var missing: int = weapon_data.magazine_size - magazine_ammo
	var loaded: int = min(missing, reserve_ammo)

	magazine_ammo += loaded
	reserve_ammo -= loaded
	reloading = false

	emit_signal("ammo_changed", magazine_ammo, reserve_ammo)
	emit_signal("reload_finished")

func _fire_once(target_position: Vector2) -> void:
	magazine_ammo -= 1
	cooldown_timer = weapon_data.fire_cooldown

	var origin := get_attack_origin()
	var direction := (target_position - origin).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	direction = _apply_spread(direction)

	_spawn_projectile(origin, direction)
	_spawn_muzzle_flash(origin, direction)
	_play_audio(_shoot_audio)

	emit_signal("ammo_changed", magazine_ammo, reserve_ammo)
	emit_signal("fired")

func _fire_burst(target_position: Vector2) -> void:
	burst_active = true
	for index in range(weapon_data.burst_count):
		if magazine_ammo <= 0:
			break
		if index > 0:
			await get_tree().create_timer(weapon_data.burst_delay).timeout
		if reloading or weapon_data == null:
			break
		_fire_once(target_position)
	burst_active = false

func _spawn_projectile(origin: Vector2, direction: Vector2) -> void:
	if weapon_data.projectile_scene == null:
		return

	var projectile := weapon_data.projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin

	if projectile.has_method("launch"):
		projectile.launch({
			"direction": direction,
			"speed": weapon_data.projectile_speed,
			"damage": weapon_data.damage,
			"lifetime": weapon_data.projectile_lifetime,
			"shooter": wielder,
			"hit_groups": weapon_data.hit_groups,
			"knockback": weapon_data.knockback
		})

func _spawn_muzzle_flash(origin: Vector2, direction: Vector2) -> void:
	if weapon_data.muzzle_flash_scene == null:
		return

	var fx := weapon_data.muzzle_flash_scene.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = origin
	fx.rotation = direction.angle()

func _apply_spread(direction: Vector2) -> Vector2:
	var spread := deg_to_rad(weapon_data.spread_degrees)
	return direction.rotated(randf_range(-spread, spread)).normalized()

func _setup_audio_players() -> void:
	_shoot_audio = _make_audio_player(weapon_data.shoot_sound if weapon_data else null)
	_reload_audio = _make_audio_player(weapon_data.reload_sound if weapon_data else null)
	_empty_audio = _make_audio_player(weapon_data.empty_sound if weapon_data else null)

func _make_audio_player(stream: AudioStream) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	add_child(player)
	return player

func _play_audio(player: AudioStreamPlayer2D) -> void:
	if player == null or player.stream == null:
		return
	player.global_position = get_attack_origin()
	player.play()
