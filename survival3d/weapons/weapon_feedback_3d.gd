extends Node
class_name WeaponFeedback3D

const AUDIO_RATE := 22050
const AUDIO_POOL_SIZE := 5

static var _shot_stream_cache: Dictionary = {}
static var _mechanism_stream_cache: Dictionary = {}

var actor: Node3D
var model_root: Node3D
var muzzle: Marker3D
var definition: Dictionary = {}
var _kick_distance := 0.0
var _kick_rotation := 0.0
var _base_model_position := Vector3.ZERO
var _base_model_rotation := Vector3.ZERO
var _audio_players: Array[AudioStreamPlayer3D] = []
var _audio_cursor := 0
var _muzzle_flash: MeshInstance3D
var _muzzle_light: OmniLight3D
var _flash_time := 0.0
var tracer_enabled := false
var preserve_external_yaw := false

func setup(owner_actor: Node3D, weapon_model_root: Node3D, muzzle_marker: Marker3D, enable_tracer := false, keep_external_yaw := false) -> void:
	actor = owner_actor
	model_root = weapon_model_root
	muzzle = muzzle_marker
	tracer_enabled = enable_tracer
	preserve_external_yaw = keep_external_yaw
	if model_root != null:
		_base_model_position = model_root.position
		_base_model_rotation = model_root.rotation
	_build_audio_pool()
	_build_muzzle_flash()
	set_process(true)

func configure(new_definition: Dictionary, rebuild_weapon_model := true) -> void:
	definition = new_definition.duplicate(true)
	if model_root != null and rebuild_weapon_model:
		WeaponModelFactory3D.rebuild(model_root, definition)
	if muzzle != null and model_root != null and rebuild_weapon_model:
		muzzle.position.z = WeaponModelFactory3D.get_muzzle_local_z(definition, model_root.position.z)

func get_recoil_amount() -> float:
	return _kick_distance

func is_muzzle_flash_visible() -> bool:
	return _muzzle_flash != null and _muzzle_flash.visible

func play_fire(direction: Vector3, hit_result: Dictionary = {}) -> void:
	var report := String(definition.get("report", "rifle"))
	_play_stream(_get_shot_stream(report), -2.0 if report in ["rifle", "shotgun", "lmg"] else -4.0)
	var recoil_distance := float(definition.get("recoil_distance", 0.13 if report in ["rifle", "shotgun"] else 0.075))
	_kick_distance = maxf(_kick_distance, recoil_distance)
	_kick_rotation += deg_to_rad(float(definition.get("camera_kick", 0.8)) * 0.9)
	_flash_time = 0.055
	if _muzzle_flash != null:
		_muzzle_flash.visible = true
	if _muzzle_light != null:
		_muzzle_light.visible = true
	_spawn_shell(direction)
	if tracer_enabled:
		_spawn_tracer(direction, hit_result)
	if hit_result.has("position"):
		_spawn_impact(hit_result.get("position", Vector3.ZERO) as Vector3, hit_result.get("normal", Vector3.UP) as Vector3, hit_result.get("collider") as Node)

func play_reload() -> void:
	_play_stream(_get_mechanism_stream("reload"), -7.0)

func play_empty() -> void:
	_play_stream(_get_mechanism_stream("empty"), -5.0)

func play_hit_confirm(headshot := false) -> void:
	_play_stream(_get_mechanism_stream("headshot" if headshot else "hit"), -10.0)

func _process(delta: float) -> void:
	_kick_distance = move_toward(_kick_distance, 0.0, delta * 1.5)
	_kick_rotation = move_toward(_kick_rotation, 0.0, delta * 9.0)
	if model_root != null:
		if preserve_external_yaw:
			model_root.position = _base_model_position + Vector3(0.0, 0.0, _kick_distance).rotated(Vector3.UP, model_root.rotation.y)
			model_root.rotation = Vector3(_base_model_rotation.x + _kick_rotation, model_root.rotation.y, _base_model_rotation.z)
		else:
			model_root.position = _base_model_position + Vector3(0.0, 0.0, _kick_distance)
			model_root.rotation = _base_model_rotation + Vector3(_kick_rotation, 0.0, 0.0)
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			if _muzzle_flash != null:
				_muzzle_flash.visible = false
			if _muzzle_light != null:
				_muzzle_light.visible = false

func _build_audio_pool() -> void:
	if not _audio_players.is_empty():
		return
	for index in AUDIO_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "WeaponVoice%d" % index
		player.max_distance = 80.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = 6.0
		add_child(player)
		_audio_players.append(player)

func _build_muzzle_flash() -> void:
	if muzzle == null or _muzzle_flash != null:
		return
	_muzzle_flash = MeshInstance3D.new()
	_muzzle_flash.name = "MuzzleFlash"
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.35
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.64, 0.12, 0.96)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.24, 0.02)
	material.emission_energy_multiplier = 5.0
	mesh.material = material
	_muzzle_flash.mesh = mesh
	_muzzle_flash.rotation.x = PI * 0.5
	_muzzle_flash.position.z = -0.11
	_muzzle_flash.visible = false
	muzzle.add_child(_muzzle_flash)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "MuzzleLight"
	_muzzle_light.light_color = Color(1.0, 0.48, 0.12)
	_muzzle_light.light_energy = 2.4
	_muzzle_light.omni_range = 3.2
	_muzzle_light.shadow_enabled = false
	_muzzle_light.visible = false
	muzzle.add_child(_muzzle_light)

func _play_stream(stream: AudioStream, volume_db: float) -> void:
	if stream == null or _audio_players.is_empty():
		return
	var player := _audio_players[_audio_cursor % _audio_players.size()]
	_audio_cursor += 1
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.97, 1.035)
	player.play()

func _spawn_shell(direction: Vector3) -> void:
	if actor == null or muzzle == null or actor.get_tree().current_scene == null:
		return
	if String(definition.get("family", "")) == "melee":
		return
	var shell := RigidBody3D.new()
	shell.name = "SpentCasing"
	shell.collision_layer = 0
	shell.collision_mask = 1
	shell.mass = 0.015
	var mesh_instance := MeshInstance3D.new()
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.018
	shell_mesh.bottom_radius = 0.018
	shell_mesh.height = 0.085
	shell_mesh.radial_segments = 6
	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color(0.56, 0.39, 0.12)
	shell_material.metallic = 0.78
	shell_material.roughness = 0.28
	shell_mesh.material = shell_material
	mesh_instance.mesh = shell_mesh
	mesh_instance.rotation.z = PI * 0.5
	shell.add_child(mesh_instance)
	actor.get_tree().current_scene.add_child(shell)
	shell.global_position = muzzle.global_position + actor.global_transform.basis.x * 0.1
	var eject_right := actor.global_transform.basis.x.normalized()
	shell.apply_central_impulse(eject_right * randf_range(0.7, 1.15) + Vector3.UP * randf_range(0.75, 1.1) - direction * 0.1)
	shell.apply_torque_impulse(Vector3(randf(), randf(), randf()) * 0.035)
	actor.get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(shell):
			shell.queue_free()
	)

func _spawn_impact(position: Vector3, normal: Vector3, collider: Node) -> void:
	if actor == null or actor.get_tree().current_scene == null:
		return
	var particles := GPUParticles3D.new()
	particles.name = "BloodImpact" if collider is CombatHitbox3D else "SurfaceImpact"
	particles.amount = 10 if collider is CombatHitbox3D else 7
	particles.lifetime = 0.32
	particles.one_shot = true
	particles.explosiveness = 1.0
	var particle_mesh := BoxMesh.new()
	particle_mesh.size = Vector3(0.035, 0.035, 0.035)
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.albedo_color = Color(0.42, 0.025, 0.018) if collider is CombatHitbox3D else Color(0.62, 0.54, 0.34)
	particle_mesh.material = particle_material
	particles.draw_pass_1 = particle_mesh
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	process_material.spread = 55.0
	process_material.initial_velocity_min = 2.2
	process_material.initial_velocity_max = 4.6
	process_material.gravity = Vector3(0.0, -9.8, 0.0)
	particles.process_material = process_material
	actor.get_tree().current_scene.add_child(particles)
	particles.global_position = position
	particles.emitting = true
	actor.get_tree().create_timer(0.75).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _spawn_tracer(direction: Vector3, hit_result: Dictionary) -> void:
	if actor == null or muzzle == null or actor.get_tree().current_scene == null:
		return
	var destination := hit_result.get("position", muzzle.global_position + direction * float(definition.get("maximum_range", 35.0))) as Vector3
	var distance := muzzle.global_position.distance_to(destination)
	if distance <= 0.1:
		return
	var tracer := MeshInstance3D.new()
	tracer.name = "AITracer"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.014, 0.014, minf(0.5, distance))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.68, 0.17)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.25, 0.03)
	mesh.material = material
	tracer.mesh = mesh
	actor.get_tree().current_scene.add_child(tracer)
	tracer.global_position = muzzle.global_position.lerp(destination, 0.5)
	tracer.look_at(destination, Vector3.UP)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "transparency", 1.0, 0.09)
	tween.tween_callback(tracer.queue_free)

static func _get_shot_stream(report: String) -> AudioStreamWAV:
	if _shot_stream_cache.has(report):
		return _shot_stream_cache[report]
	var duration := 0.2
	var low_frequency := 94.0
	var crack_frequency := 1350.0
	match report:
		"pistol":
			duration = 0.16; low_frequency = 132.0; crack_frequency = 1650.0
		"smg":
			duration = 0.13; low_frequency = 118.0; crack_frequency = 1500.0
		"lmg":
			duration = 0.2; low_frequency = 82.0; crack_frequency = 1250.0
		"shotgun":
			duration = 0.28; low_frequency = 68.0; crack_frequency = 980.0
	var stream := _synthesize_impulse(duration, low_frequency, crack_frequency)
	_shot_stream_cache[report] = stream
	return stream

static func _get_mechanism_stream(kind: String) -> AudioStreamWAV:
	if _mechanism_stream_cache.has(kind):
		return _mechanism_stream_cache[kind]
	var stream := _synthesize_mechanism(kind)
	_mechanism_stream_cache[kind] = stream
	return stream

static func _synthesize_impulse(duration: float, low_frequency: float, crack_frequency: float) -> AudioStreamWAV:
	var sample_count := int(duration * AUDIO_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(low_frequency * 100.0 + crack_frequency)
	for index in sample_count:
		var time := float(index) / AUDIO_RATE
		var envelope := exp(-time * 18.0)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-time * 46.0)
		var body := sin(TAU * low_frequency * time) * exp(-time * 13.0)
		var snap := sin(TAU * crack_frequency * time) * exp(-time * 62.0)
		var tail := rng.randf_range(-0.25, 0.25) * envelope
		var sample := clampf(crack * 0.62 + body * 0.58 + snap * 0.26 + tail, -1.0, 1.0)
		bytes.encode_s16(index * 2, int(sample * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = AUDIO_RATE
	stream.stereo = false
	stream.data = bytes
	return stream

static func _synthesize_mechanism(kind: String) -> AudioStreamWAV:
	var duration := 0.12 if kind in ["empty", "hit", "headshot"] else 0.42
	var sample_count := int(duration * AUDIO_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / AUDIO_RATE
		var sample_value := 0.0
		if kind == "reload":
			sample_value = sin(TAU * 730.0 * time) * exp(-fmod(time, 0.18) * 34.0) * (0.55 if time < 0.18 or time > 0.29 else 0.05)
		elif kind == "headshot":
			sample_value = (sin(TAU * 1460.0 * time) + sin(TAU * 2190.0 * time) * 0.5) * exp(-time * 24.0) * 0.45
		elif kind == "hit":
			sample_value = sin(TAU * 980.0 * time) * exp(-time * 28.0) * 0.35
		else:
			sample_value = sin(TAU * 510.0 * time) * exp(-time * 45.0) * 0.38
		bytes.encode_s16(index * 2, int(clampf(sample_value, -1.0, 1.0) * 28000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = AUDIO_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
