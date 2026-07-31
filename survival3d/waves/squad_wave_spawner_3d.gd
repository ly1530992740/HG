@tool
extends Node3D
class_name SquadWaveSpawner3D

signal wave_countdown_started(wave_number: int, seconds: float)
signal wave_spawned(wave_number: int, squads: Array[SquadCoordinator3D])
signal wave_cleared(wave_number: int)
signal all_waves_completed

@export_category("波次配置")
@export var waves: Array[SquadWaveDefinition3D] = []
@export var auto_start := true
@export_range(0.0, 60.0, 0.5) var first_wave_delay := 5.0
@export_range(0.0, 60.0, 0.5) var between_wave_delay := 5.0
@export var target_path: NodePath

@export_category("外圈生成区域")
@export_range(2.0, 100.0, 0.5) var spawn_radius := 18.0:
	set(value):
		spawn_radius = maxf(2.0, value)
		_rebuild_ring()
@export_range(0.1, 10.0, 0.1) var ring_thickness := 2.0:
	set(value):
		ring_thickness = clampf(value, 0.1, spawn_radius)
		_rebuild_ring()
@export var show_spawn_ring := true:
	set(value):
		show_spawn_ring = value
		_rebuild_ring()

var current_wave_index := -1
var active_squads: Array[SquadCoordinator3D] = []
var _running := false
var _countdown := 0.0
var _waiting_for_clear := false

func _ready() -> void:
	_rebuild_ring()
	if not Engine.is_editor_hint() and auto_start and not waves.is_empty():
		start_waves()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _running:
		return
	if _waiting_for_clear:
		_prune_squads()
		if active_squads.is_empty():
			wave_cleared.emit(current_wave_index + 1)
			_waiting_for_clear = false
			_begin_next_wave()
		return
	_countdown -= delta
	if _countdown <= 0.0:
		_spawn_current_wave()

func start_waves() -> void:
	if _running or waves.is_empty():
		if not Engine.is_editor_hint():
			print("[WAVE3D] 未启动：running=%s waves=%d" % [str(_running), waves.size()])
		return
	_running = true
	current_wave_index = -1
	print("[WAVE3D] 启动波次，共%d波" % waves.size())
	_begin_next_wave()

func _begin_next_wave() -> void:
	current_wave_index += 1
	if current_wave_index >= waves.size():
		_running = false
		all_waves_completed.emit()
		return
	_countdown = first_wave_delay if current_wave_index == 0 else between_wave_delay
	wave_countdown_started.emit(current_wave_index + 1, _countdown)

func _spawn_current_wave() -> void:
	active_squads.clear()
	var definition := waves[current_wave_index]
	var serial := 0
	for entry in definition.squads:
		if entry == null or entry.squad_scene == null:
			continue
		for _index in entry.quantity:
			var squad := entry.squad_scene.instantiate() as SquadCoordinator3D
			if squad == null:
				push_error("3D波次预制体根节点必须是 SquadCoordinator3D")
				continue
			serial += 1
			squad.squad_id = StringName("wave3d_%d_%d_%d" % [current_wave_index + 1, serial, get_instance_id()])
			squad.free_when_all_members_dead = true
			squad.use_advanced_tactics = true
			squad.use_qwen = false
			var target := _find_target()
			if target != null:
				squad.set_runtime_mission_target(target.global_position, 9.0)
			get_tree().current_scene.add_child(squad)
			squad.global_position = _random_ring_position()
			if target != null:
				squad.set_known_combat_objective(target)
			active_squads.append(squad)
	_waiting_for_clear = true
	print("[WAVE3D] 第%d波已生成，活动小队=%d" % [current_wave_index + 1, active_squads.size()])
	wave_spawned.emit(current_wave_index + 1, active_squads)

func _random_ring_position() -> Vector3:
	var angle := randf() * TAU
	var inner := maxf(0.0, spawn_radius - ring_thickness)
	var radius := sqrt(lerpf(inner * inner, spawn_radius * spawn_radius, randf()))
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius

func _find_target() -> Node3D:
	if not target_path.is_empty():
		var configured := get_node_or_null(target_path) as Node3D
		if configured != null:
			return configured
	return get_tree().get_first_node_in_group("player3d") as Node3D

func _prune_squads() -> void:
	for index in range(active_squads.size() - 1, -1, -1):
		var squad := active_squads[index]
		if not is_instance_valid(squad) or not squad.is_squad_alive():
			active_squads.remove_at(index)

func _rebuild_ring() -> void:
	if not is_inside_tree():
		return
	var mesh_instance := get_node_or_null("SpawnRingPreview") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "SpawnRingPreview"
		add_child(mesh_instance)
	mesh_instance.visible = show_spawn_ring
	var torus := TorusMesh.new()
	var inner := maxf(0.05, spawn_radius - ring_thickness)
	torus.inner_radius = inner
	torus.outer_radius = spawn_radius
	torus.rings = 64
	torus.ring_segments = 8
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.9, 0.22, 0.12, 0.22)
	torus.material = material
	mesh_instance.mesh = torus
	mesh_instance.position.y = 0.04
