@tool
extends Node2D
class_name SquadWaveSpawner

signal wave_countdown_started(wave_number: int, seconds: float)
signal wave_spawned(wave_number: int, squads: Array[SquadGroup])
signal wave_cleared(wave_number: int)
signal all_waves_completed

@export_group("波次配置")
@export var waves: Array[SquadWaveDefinition] = []
@export var auto_start := true
@export_range(0.0, 60.0, 0.5) var first_wave_delay := 5.0
@export_range(0.0, 60.0, 0.5) var between_wave_delay := 5.0

@export_group("生成范围")
@export var show_spawn_radius_preview := true:
	set(value):
		show_spawn_radius_preview = value
		queue_redraw()
@export_range(0.0, 5000.0, 10.0) var spawn_radius := 320.0:
	set(value):
		spawn_radius = maxf(0.0, value)
		queue_redraw()
@export_range(0.0, 5000.0, 10.0) var minimum_spawn_radius := 0.0:
	set(value):
		minimum_spawn_radius = maxf(0.0, value)
		queue_redraw()
@export var spawn_on_outer_ring := true
@export var face_spawn_center := false
@export var assign_primary_target := false
@export var primary_target_path: NodePath
@export_range(0.1, 5.0, 0.1) var clear_check_interval := 0.5
@export var spawned_squads_parent_path: NodePath

var current_wave_index := -1
var active_squads: Array[SquadGroup] = []
var running := false
var completed := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_rng.randomize()
	if auto_start and not waves.is_empty():
		call_deferred("start_waves")

func _draw() -> void:
	if not Engine.is_editor_hint() or not show_spawn_radius_preview:
		return
	if spawn_radius > 0.0:
		draw_arc(Vector2.ZERO, spawn_radius, 0.0, TAU, 128, Color(0.95, 0.24, 0.18, 0.9), 4.0, true)
	if minimum_spawn_radius > 0.0:
		draw_arc(Vector2.ZERO, minimum_spawn_radius, 0.0, TAU, 128, Color(1.0, 0.78, 0.18, 0.95), 4.0, true)

func start_waves() -> void:
	if running or completed:
		return
	running = true
	for wave_index in waves.size():
		current_wave_index = wave_index
		var delay := first_wave_delay if wave_index == 0 else between_wave_delay
		wave_countdown_started.emit(wave_index + 1, delay)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		_spawn_wave(wave_index)
		while not _is_active_wave_cleared():
			await get_tree().create_timer(clear_check_interval).timeout
		_cleanup_finished_groups()
		wave_cleared.emit(wave_index + 1)
	running = false
	completed = true
	all_waves_completed.emit()

func _spawn_wave(wave_index: int) -> void:
	active_squads.clear()
	if wave_index < 0 or wave_index >= waves.size():
		return
	var definition := waves[wave_index]
	if definition == null:
		return
	var spawn_serial := 0
	for entry in definition.squads:
		if entry == null or entry.squad_scene == null:
			continue
		for _copy_index in entry.count:
			spawn_serial += 1
			var squad := entry.squad_scene.instantiate() as SquadGroup
			if squad == null:
				push_error("Wave %d scene must have SquadGroup as its root." % (wave_index + 1))
				continue
			_prepare_squad_identity(squad, wave_index, spawn_serial)
			var parent := _get_spawn_parent()
			var radius := entry.spawn_radius_override if entry.spawn_radius_override >= 0.0 else spawn_radius
			var spawn_position := global_position + _random_offset(radius)
			if parent is Node2D:
				squad.position = (parent as Node2D).to_local(spawn_position)
			else:
				squad.position = spawn_position
			parent.add_child(squad)
			squad.global_position = spawn_position
			if face_spawn_center:
				_orient_squad_toward_center(squad)
			if assign_primary_target:
				_assign_squad_objective(squad, _get_primary_target())
			active_squads.append(squad)
	wave_spawned.emit(wave_index + 1, active_squads)

func _prepare_squad_identity(squad: SquadGroup, wave_index: int, serial: int) -> void:
	var unique_id := StringName("%s_w%d_%d_%d" % [squad.squad_id, wave_index + 1, serial, get_instance_id()])
	squad.squad_id = unique_id
	squad.free_when_all_members_dead = true
	for actor in squad.get_configured_member_actors():
		actor.set("squad_id", unique_id)
		actor.set("combat_team", squad.combat_team)
		actor.set("can_target_players", squad.can_target_players)
		actor.set("team_display_name", squad.squad_display_name)
		actor.set("team_color", squad.team_color)

func _is_active_wave_cleared() -> bool:
	if active_squads.is_empty():
		return true
	for squad in active_squads:
		if not is_instance_valid(squad):
			continue
		for actor in squad.get_configured_member_actors():
			if is_instance_valid(actor) and (not actor.has_method("is_combat_alive") or actor.is_combat_alive()):
				return false
	return true

func _cleanup_finished_groups() -> void:
	for squad in active_squads:
		if is_instance_valid(squad):
			squad.queue_free()
	active_squads.clear()

func _get_spawn_parent() -> Node:
	if not spawned_squads_parent_path.is_empty():
		var configured := get_node_or_null(spawned_squads_parent_path)
		if configured != null:
			return configured
	return get_tree().current_scene if get_tree().current_scene != null else get_parent()

func _random_offset(radius: float) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var angle := _rng.randf_range(0.0, TAU)
	if spawn_on_outer_ring:
		return Vector2.RIGHT.rotated(angle) * radius
	var inner_radius := clampf(minimum_spawn_radius, 0.0, radius)
	var distance := sqrt(_rng.randf_range(inner_radius * inner_radius, radius * radius))
	return Vector2.RIGHT.rotated(angle) * distance

func _orient_squad_toward_center(squad: SquadGroup) -> void:
	var direction := (global_position - squad.global_position).normalized()
	if direction == Vector2.ZERO:
		return
	for actor in squad.get_configured_member_actors():
		actor.set("initial_facing_direction", direction)
		actor.set("last_move_dir", direction)

func _get_primary_target() -> Node2D:
	if not primary_target_path.is_empty():
		var configured := get_node_or_null(primary_target_path) as Node2D
		if configured != null:
			return configured
	if GlobalPlayer.active_player is Node2D:
		return GlobalPlayer.active_player as Node2D
	return get_tree().get_first_node_in_group("player") as Node2D

func _assign_squad_objective(squad: SquadGroup, objective: Node2D) -> void:
	if objective == null:
		return
	if squad is SquadCoordinator:
		(squad as SquadCoordinator).set_known_combat_objective(objective)
	for actor in squad.get_configured_member_actors():
		if actor.has_method("set_autonomous_combat_objective"):
			actor.set_autonomous_combat_objective(objective)
