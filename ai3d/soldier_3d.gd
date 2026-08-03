extends CharacterBody3D
class_name Soldier3D

const DAMAGE_RULES_3D := preload("res://combat3d/combat_damage_rules_3d.gd")
const SOLDIER_STATE_CHART_SCENE := preload("res://ai3d/statecharts/soldier_state_chart_3d.tscn")
const ROUTE_REPLAN_INTERVAL_MSEC := 750

signal died(actor: Soldier3D)
signal health_changed(current: int, maximum: int)
signal contact_spotted(actor: Soldier3D, hostile: Node3D)
signal combat_sound_heard(actor: Soldier3D, position: Vector3, confidence: float)
signal perception_report_ready(actor: Soldier3D, hostile: Node3D, position: Vector3, confidence: float, stimulus: StringName)
signal directive_changed(actor: Soldier3D, directive: SquadDirective3D)
signal directive_completed(actor: Soldier3D, directive: SquadDirective3D)
signal weapon_fired(actor: Soldier3D, target: Node3D)
signal stamina_changed(actor: Soldier3D, current: float, maximum: float)
signal stance_changed(actor: Soldier3D, stance: Stance)
signal movement_mode_changed(actor: Soldier3D, mode: MoveMode)
signal squad_leader_role_changed(actor: Soldier3D, is_leader: bool)
signal death_reward_requested(actor: Soldier3D, instigator: Node, score: int, ammo: int)

enum Team { PLAYER, RED, BLUE }
enum CombatRole { RIFLEMAN, SMG, MACHINE_GUNNER, MARKSMAN, SHOTGUNNER, MELEE }
enum Stance { STAND, CROUCH, PRONE }
enum MoveMode { WALK, QUIET, RUN }

@export_category("小队身份")
@export var squad_id: StringName = &"default"
@export var combat_team: Team = Team.RED
@export var combat_role: CombatRole = CombatRole.RIFLEMAN
@export var can_target_players := true
@export var team_display_name := "红队"
@export var show_status_label := false
@export var can_be_squad_leader := true
@export_range(-100, 100, 1) var leader_priority := 0

@export_category("战斗属性")
@export var max_health := 100
@export var move_speed := 3.4
@export var run_speed := 5.3
@export var quiet_speed := 1.65
@export var crouch_speed := 2.1
@export var prone_speed := 0.95
@export var max_stamina := 100.0
@export var run_stamina_cost_per_second := 18.0
@export var stamina_recovery_per_second := 14.0
@export var stamina_recovery_delay := 1.0
@export var stamina_required_to_resume_run := 30.0
@export var sight_range := 34.0
@export_range(30.0, 360.0, 5.0) var field_of_view_degrees := 150.0
@export var reaction_delay := 0.45
@export var hearing_range := 46.0
@export var dangerous_sound_range := 24.0
@export var threat_memory_seconds := 6.0
@export var immediate_threat_seconds := 2.8
@export var emergency_cover_max_distance := 15.0
@export var autonomy_return_fire_seconds := 0.9
@export var autonomy_scan_seconds := 1.2
@export var security_cycle_interval := 1.5
@export var autonomy_defensive_posture := false
@export_range(10.0, 100.0, 1.0) var environmental_danger_threshold := 48.0
@export_range(10.0, 120.0, 1.0) var route_danger_threshold := 58.0
@export_range(0.0, 30.0, 1.0) var environmental_danger_hysteresis := 8.0
@export_range(2.0, 20.0, 0.5) var autonomy_escape_distance := 10.0
@export var initially_aware := false
@export var awards_player_score := true
@export var score_reward := 1
@export var drops_ammo_on_death := true
@export_range(0, 200, 1) var dropped_ammo_amount := 18

@onready var visual: Sprite3D = $Visual
@onready var voxel_visual: VoxelSoldierVisual3D = $VoxelVisual
@onready var collision: CollisionShape3D = $Collision
@onready var muzzle: Marker3D = $WeaponPivot/Muzzle
@onready var body_hitbox: Area3D = $BodyHitbox
@onready var body_hitbox_shape: CollisionShape3D = $BodyHitbox/Shape
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var weapon_model_root: Node3D = $WeaponPivot/WeaponModelRoot
@onready var status_label: Label3D = $StatusLabel
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var weapon_component: SoldierWeaponComponent3D = $Components/Weapon
@onready var perception_component: SoldierPerceptionComponent3D = $Components/Perception
@onready var health_component: HealthComponent3D = $Components/Health
@onready var stamina_component: StaminaComponent3D = $Components/Stamina
@onready var limb_damage_component: LimbDamageComponent3D = $Components/LimbDamage
@onready var suppression_component: SuppressionComponent3D = $Components/Suppression
@onready var fire_cycle_component: WeaponFireCycle3D = $Components/FireCycle

var health: int:
	get: return health_component.current if is_instance_valid(health_component) else 0
var magazine_ammo: int:
	get: return weapon_component.magazine_ammo if is_instance_valid(weapon_component) else 0
	set(value):
		if is_instance_valid(weapon_component):
			weapon_component.magazine_ammo = maxi(0, value)
var reserve_ammo: int:
	get: return weapon_component.reserve_ammo if is_instance_valid(weapon_component) else 0
	set(value):
		if is_instance_valid(weapon_component):
			weapon_component.reserve_ammo = maxi(0, value)
var logical_forward := Vector3.FORWARD
var current_target: Node3D
var active_cover: TacticalCover3D
var active_cover_slot: Marker3D
var cover_exposed := false
var active_structure: TacticalStructure3D
var active_directive: SquadDirective3D
var last_completed_directive_version := 0
var aware_of_enemy := false
var is_aimed := false
var dead := false
var is_squad_leader := false
var last_weapon_fired_msec := -100000
var stance: Stance = Stance.STAND
var movement_mode: MoveMode = MoveMode.WALK
var stamina: float:
	get: return stamina_component.current if is_instance_valid(stamina_component) else 0.0

var _state_chart_controller: SoldierStateChart3D
var working_memory: SoldierWorkingMemory3D
var local_threat_field: SoldierLocalThreatField3D
var _operation_elapsed := 0.0
var _structure_enter_animation_remaining := 0.0
var _directive_started_msec := 0
var _route_index := 0
var _route_constraint_index := 0
var _last_directive_route_plan_msec := -100000
var _last_directive_route_check_version := 0
var _heatmap_route_planner := SquadHeatmapRoutePlanner3D.new()
var _runtime_route: Array[Vector3] = []
var _runtime_route_index := 0
var _runtime_route_destination := Vector3.ZERO
var _runtime_route_influence_version := 0
var _last_runtime_route_plan_msec := -100000
var _scan_timer := 0.0
var _reaction_timer := 0.0
var _desired_velocity := Vector3.ZERO
var _animation_time := 0.0
var _last_instigator: Node
var weapon_feedback_component: WeaponFeedback3D
var _threat_position := Vector3.ZERO
var _threat_memory_timer := 0.0
var _immediate_threat_timer := 0.0
var _emergency_prone_timer := 0.0
var _threat_confidence := 0.0
var _threat_actor: Node3D
var _contact_response_complete := true
var _security_cycle_timer := 0.0
var _autonomy_cover_candidate: TacticalCover3D
var _autonomy_cover_slot: Marker3D
var _autonomy_structure_candidate: TacticalStructure3D
var _autonomy_escape_position := Vector3.ZERO
var _autonomy_escape_available := false
var _autonomy_operation_completed := false
var _environmental_danger := false
var _environment_current_risk := 0.0
var _environment_route_risk := 0.0
var _autonomy_defense_anchor := Vector3.ZERO
var _movement_constraint_enabled := false
var _movement_constraint_center := Vector3.ZERO
var _movement_constraint_radius := 0.0
var _movement_requested_last_frame := false
var _last_movement_destination := Vector3.ZERO
var _movement_best_distance := INF
var _movement_stall_timer := 0.0
var _movement_detour_timer := 0.0
var _movement_detour_direction := Vector3.ZERO
var _movement_detour_target := Vector3.ZERO
var _has_local_waypoint := false
var _local_waypoint := Vector3.ZERO
var _local_waypoint_destination := Vector3.ZERO
var _local_navigation_decisions := 0
var _local_direct_risk := 0.0
var _local_selected_risk := 0.0
var _last_collision_normal := Vector3.ZERO
var _last_collision_cover: TacticalCover3D
var _cover_exposure_shots_remaining := 0

func _ready() -> void:
	add_to_group("combatant3d")
	add_to_group("soldier3d")
	var registry := BattlefieldRegistry3D.find(get_tree())
	if registry != null:
		registry.register_node(self)
	health_component.configure(max_health)
	stamina_component.configure(max_stamina, run_stamina_cost_per_second, stamina_recovery_per_second, stamina_recovery_delay, stamina_required_to_resume_run)
	aware_of_enemy = initially_aware
	logical_forward = -global_transform.basis.z
	_make_stance_shapes_unique()
	_apply_stance_geometry()
	weapon_component.configure(combat_role, combat_team)
	fire_cycle_component.configure(weapon_component.definition, combat_role, int(get_instance_id()))
	weapon_feedback_component = WeaponFeedback3D.new()
	weapon_feedback_component.name = "WeaponFeedback"
	$Components.add_child(weapon_feedback_component)
	weapon_feedback_component.setup(self, weapon_model_root, muzzle, true)
	weapon_feedback_component.configure(weapon_component.definition)
	limb_damage_component.configure(self, voxel_visual)
	perception_component.configure(self)
	suppression_component.configure(self)
	working_memory = SoldierWorkingMemory3D.new()
	working_memory.name = "WorkingMemory"
	$Components.add_child(working_memory)
	working_memory.configure(self)
	local_threat_field = SoldierLocalThreatField3D.new()
	local_threat_field.configure(self, working_memory)
	_apply_team_visual()
	status_label.visible = show_status_label
	_setup_state_chart()
	_update_status()
	stamina_changed.emit(self, stamina, max_stamina)

func _physics_process(delta: float) -> void:
	if dead:
		return
	_update_movement_stall(delta)
	fire_cycle_component.process(delta)
	working_memory.tick(delta)
	_reaction_timer = maxf(0.0, _reaction_timer - delta)
	_threat_memory_timer = maxf(0.0, _threat_memory_timer - delta)
	_immediate_threat_timer = maxf(0.0, _immediate_threat_timer - delta)
	_emergency_prone_timer = maxf(0.0, _emergency_prone_timer - delta)
	_security_cycle_timer = maxf(0.0, _security_cycle_timer - delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.22
		_scan_for_hostiles()
	_desired_velocity = Vector3.ZERO
	_select_tactical_movement()
	if _state_chart_controller != null:
		_state_chart_controller.tick(delta)
	if is_instance_valid(active_structure):
		active_structure.align_operator(self)
		_desired_velocity = Vector3.ZERO
	if is_pinned():
		_desired_velocity = Vector3.ZERO
		if is_instance_valid(active_cover):
			if cover_exposed:
				set_cover_exposed(false)
		else:
			set_stance(Stance.PRONE)
	_update_stamina(delta, _desired_velocity.length_squared() > 0.01)
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if is_instance_valid(active_structure):
		velocity = Vector3.ZERO
		active_structure.align_operator(self)
	elif not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = move_toward(velocity.x, _desired_velocity.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, _desired_velocity.z, 14.0 * delta)
	move_and_slide()
	_capture_movement_collision()
	_update_visual_animation(delta)

func receive_directive(directive: SquadDirective3D) -> void:
	if directive == null or directive.version <= get_directive_version():
		return
	var preserves_aim := is_aimed and active_directive != null \
		and active_directive.type == SquadDirective3D.Type.AIM \
		and directive.type in [SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.SUPPRESS] \
		and is_instance_valid(current_target) and current_target == directive.target
	var previous_structure: TacticalStructure3D = active_directive.assigned_structure if active_directive != null else null
	if is_instance_valid(previous_structure) and (directive.type != SquadDirective3D.Type.USE_STRUCTURE \
			or directive.assigned_structure != previous_structure):
		previous_structure.release(self)
	if is_instance_valid(active_structure) and (directive.type != SquadDirective3D.Type.USE_STRUCTURE \
			or directive.assigned_structure != active_structure):
		_clear_structure_state(false)
	if is_instance_valid(_autonomy_structure_candidate) and not is_instance_valid(active_structure):
		_autonomy_structure_candidate.release(self)
		_autonomy_structure_candidate = null
	var keeps_cover := directive.type in [
		SquadDirective3D.Type.GUARD,
		SquadDirective3D.Type.HOLD_SECTOR,
		SquadDirective3D.Type.TAKE_COVER,
		SquadDirective3D.Type.AIM,
		SquadDirective3D.Type.ATTACK,
		SquadDirective3D.Type.SUPPRESS,
	]
	if directive.type == SquadDirective3D.Type.TAKE_COVER and active_cover != directive.assigned_cover:
		_clear_cover_state()
	if active_cover != null and not keeps_cover:
		var departure_target := directive.route[0] if not directive.route.is_empty() else directive.target_position
		var departure_route := active_cover.get_departure_route(active_cover_slot, departure_target)
		if not departure_route.is_empty():
			directive.route = departure_route + directive.route
		_clear_cover_state()
	active_directive = directive
	if directive.requires_movement() and (directive.route.is_empty() or directive.route_influence_version <= 0):
		directive.apply_route_plan(build_minimum_cost_route(directive.target_position, directive.route_constraints))
	_reset_local_waypoint()
	_directive_started_msec = Time.get_ticks_msec()
	if working_memory != null:
		working_memory.remember_task(
			StringName("directive_%d" % directive.version),
			directive.target_position,
			maxf(6.0, directive.duration + 2.0),
			{"directive_type": directive.type, "reason": directive.reason}
		)
	is_aimed = preserves_aim
	_route_index = 0
	_route_constraint_index = 0
	_last_directive_route_plan_msec = Time.get_ticks_msec()
	_last_directive_route_check_version = directive.route_influence_version
	_reset_runtime_heatmap_route()
	_select_tactical_movement()
	_select_tactical_stance()
	if is_instance_valid(directive.target):
		current_target = directive.target
	elif not is_instance_valid(current_target):
		current_target = null
	if _state_chart_controller != null:
		_state_chart_controller.notify_directive_received()
	directive_changed.emit(self, directive)
	_update_status()

func has_active_directive() -> bool:
	return active_directive != null and active_directive.version > last_completed_directive_version

func get_active_directive() -> SquadDirective3D:
	return active_directive

func set_squad_influence_map(value: SquadInfluenceMap3D) -> void:
	if local_threat_field != null:
		local_threat_field.set_shared_influence(value)

func get_squad_influence_map() -> SquadInfluenceMap3D:
	return local_threat_field.shared_influence if local_threat_field != null else null

func is_route_segment_clear(origin: Vector3, destination: Vector3) -> bool:
	return local_threat_field == null or local_threat_field.is_segment_clear(origin, destination)

func build_minimum_cost_route(
		destination: Vector3,
		constraints: Array[Vector3] = [],
		max_length_ratio := -1.0,
		max_extra_distance := -1.0
) -> Dictionary:
	if max_length_ratio < 1.0:
		max_length_ratio = active_directive.max_route_length_ratio if active_directive != null else 1.65
	if max_extra_distance < 0.0:
		max_extra_distance = active_directive.max_route_extra_distance if active_directive != null else 10.0
	return _heatmap_route_planner.build_route(
		global_position,
		destination,
		get_squad_influence_map(),
		constraints,
		Callable(self, "is_route_segment_clear"),
		max_length_ratio,
		max_extra_distance
	)

func get_local_navigation_debug() -> Dictionary:
	return {
		"has_waypoint": _has_local_waypoint,
		"waypoint": _local_waypoint,
		"decisions": _local_navigation_decisions,
		"direct_risk": snappedf(_local_direct_risk, 0.1),
		"selected_risk": snappedf(_local_selected_risk, 0.1),
		"runtime_route_points": maxi(0, _runtime_route.size() - _runtime_route_index),
		"runtime_route_influence_version": _runtime_route_influence_version,
	}

func relocate_for_scenario_setup(position_value: Vector3) -> void:
	_clear_cover_state()
	_clear_structure_state()
	global_position = Vector3(position_value.x, 0.0, position_value.z)
	velocity = Vector3.ZERO
	_desired_velocity = Vector3.ZERO
	set_stance(Stance.STAND)
	set_movement_mode(MoveMode.WALK)
	is_aimed = false
	_route_index = 0
	_route_constraint_index = 0
	_reset_runtime_heatmap_route()
	_reset_local_waypoint()
	_movement_requested_last_frame = false
	_last_movement_destination = global_position
	_movement_best_distance = INF
	_movement_stall_timer = 0.0
	_movement_detour_timer = 0.0
	_movement_detour_direction = Vector3.ZERO
	_movement_detour_target = Vector3.ZERO
	_last_collision_normal = Vector3.ZERO
	_last_collision_cover = null
	if _state_chart_controller != null:
		_state_chart_controller.reset_runtime_state()
	_update_status()

func get_directive_version() -> int:
	return active_directive.version if active_directive != null else 0

func get_directive_goal_relevance() -> float:
	if active_directive == null:
		return 0.0
	match active_directive.type:
		SquadDirective3D.Type.TAKE_COVER:
			return 145.0
		SquadDirective3D.Type.SUPPRESS:
			return 120.0
		SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.FLANK:
			return 110.0
		SquadDirective3D.Type.AIM:
			return 105.0
		SquadDirective3D.Type.RECON:
			return 85.0
		SquadDirective3D.Type.MOVE, SquadDirective3D.Type.WITHDRAW:
			return 80.0
		SquadDirective3D.Type.GUARD, SquadDirective3D.Type.HOLD_SECTOR:
			return 70.0
		SquadDirective3D.Type.USE_STRUCTURE:
			return 92.0
	return 100.0

func on_directive_plan_completed() -> void:
	if active_directive == null or last_completed_directive_version >= active_directive.version:
		return
	last_completed_directive_version = active_directive.version
	directive_completed.emit(self, active_directive)
	_update_status()

func _begin_directive_action(operation: SoldierStateChart3D.Action) -> void:
	_operation_elapsed = 0.0
	if operation == SoldierStateChart3D.Action.APPROACH_TARGET:
		_reset_runtime_heatmap_route()
	if operation in [SoldierStateChart3D.Action.ENTER_STRUCTURE, SoldierStateChart3D.Action.OPERATE_STRUCTURE]:
		print("[SOLDIER3D_STRUCTURE_STATE_CHART] member=%s operation=%s structure=%s directive=%d" % [
			name, SoldierStateChart3D.Action.keys()[operation],
			active_directive.assigned_structure.name if active_directive != null and is_instance_valid(active_directive.assigned_structure) else "NONE",
			active_directive.version if active_directive != null else 0,
		])
	if operation == SoldierStateChart3D.Action.APPROACH_TARGET and active_cover != null:
		_clear_cover_state()
	if operation in [SoldierStateChart3D.Action.MOVE, SoldierStateChart3D.Action.ENTER_COVER, SoldierStateChart3D.Action.ENTER_STRUCTURE, SoldierStateChart3D.Action.APPROACH_TARGET]:
		is_aimed = false
		fire_cycle_component.notify_movement_started()
	_update_status(_operation_label(operation))

func _perform_directive_action(operation: SoldierStateChart3D.Action, delta: float) -> bool:
	_operation_elapsed += delta
	match operation:
		SoldierStateChart3D.Action.MOVE:
			return _perform_move()
		SoldierStateChart3D.Action.ENTER_COVER:
			return _perform_enter_cover()
		SoldierStateChart3D.Action.ACQUIRE_TARGET:
			return _perform_acquire_target()
		SoldierStateChart3D.Action.APPROACH_TARGET:
			return _perform_approach_target()
		SoldierStateChart3D.Action.AIM:
			return _perform_aim()
		SoldierStateChart3D.Action.RELOAD:
			return _perform_reload()
		SoldierStateChart3D.Action.ENGAGE:
			return _perform_engage()
		SoldierStateChart3D.Action.ENTER_STRUCTURE:
			return _perform_enter_structure()
		SoldierStateChart3D.Action.OPERATE_STRUCTURE:
			return _perform_operate_structure()
		SoldierStateChart3D.Action.GUARD:
			return _perform_guard()
		SoldierStateChart3D.Action.OBSERVE:
			return _perform_observe()
	return false

func _end_directive_action(operation: SoldierStateChart3D.Action) -> void:
	_desired_velocity = Vector3.ZERO
	if operation == SoldierStateChart3D.Action.APPROACH_TARGET:
		_reset_runtime_heatmap_route()
	if operation == SoldierStateChart3D.Action.ENGAGE and is_instance_valid(active_cover):
		is_aimed = false
		set_cover_exposed(false)

func _perform_move() -> bool:
	if active_directive == null:
		return false
	_refresh_directive_route_if_needed()
	_advance_route_constraint_progress()
	var destination := active_directive.target_position
	if not active_directive.route.is_empty() and _route_index < active_directive.route.size():
		destination = active_directive.route[_route_index]
		while _route_index < active_directive.route.size() and _flat_distance_to(destination) <= 0.55:
			_route_index += 1
			if _route_index < active_directive.route.size():
				destination = active_directive.route[_route_index]
	if _flat_distance_to(destination) <= 0.5:
		_desired_velocity = Vector3.ZERO
		return active_directive.route.is_empty() or _route_index >= active_directive.route.size()
	_move_toward(_get_local_movement_target(destination))
	return false

func _perform_enter_cover() -> bool:
	if active_directive == null or not is_instance_valid(active_directive.assigned_cover):
		return false
	var cover := active_directive.assigned_cover
	if active_cover_slot == null:
		var threat_position := active_directive.target.global_position if is_instance_valid(active_directive.target) else global_position + logical_forward * 10.0
		active_cover_slot = cover.get_reserved_slot(self)
		if active_cover_slot == null:
			active_cover_slot = cover.reserve_reachable_slot(self, threat_position)
	if active_cover_slot == null:
		return false
	global_position = active_cover_slot.global_position
	set_stance(Stance.STAND)
	active_cover = cover
	set_cover_exposed(false)
	set_movement_mode(MoveMode.WALK)
	_desired_velocity = Vector3.ZERO
	return true

func _perform_enter_structure() -> bool:
	if active_directive == null or not is_instance_valid(active_directive.assigned_structure):
		return false
	var structure: TacticalStructure3D = active_directive.assigned_structure
	if is_instance_valid(active_structure) and active_structure != structure:
		_clear_structure_state()
	if not structure.occupy(self):
		return false
	_clear_cover_state()
	active_structure = structure
	_structure_enter_animation_remaining = 0.48
	set_stance(Stance.STAND)
	set_movement_mode(MoveMode.WALK)
	is_aimed = false
	_desired_velocity = Vector3.ZERO
	var forward: Vector3 = structure.global_transform.basis * Vector3.FORWARD
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		logical_forward = forward.normalized()
		rotation.y = atan2(-logical_forward.x, -logical_forward.z)
	structure.align_operator(self)
	print("[SOLDIER3D_STRUCTURE_OCCUPIED] member=%s structure=%s directive=%d" % [name, structure.name, active_directive.version])
	return true

func _perform_operate_structure() -> bool:
	if active_directive == null or not is_instance_valid(active_structure) \
			or active_structure != active_directive.assigned_structure or not active_structure.is_occupied_by(self):
		return false
	active_structure.align_operator(self)
	_desired_velocity = Vector3.ZERO
	var target := active_directive.target if is_instance_valid(active_directive.target) \
		and is_hostile_target(active_directive.target) and is_combat_target_alive(active_directive.target) else null
	if target == null or not perception_component.can_see(target) or not active_structure.can_engage_target(target):
		target = perception_component.find_best_hostile(true)
		if target != null and not active_structure.can_engage_target(target):
			target = null
	if target != null:
		current_target = target
		_face_position(target.global_position)
		active_structure.aim_at(target.global_position)
		if not is_pinned() and _operation_elapsed >= 0.2:
			if active_structure.has_fixed_weapon():
				active_structure.try_fixed_weapon_fire(self, target)
			else:
				is_aimed = true
				_try_attack_target(target)
	else:
		var sweep := sin(_operation_elapsed * 1.8) * minf(0.8, deg_to_rad(active_structure.firing_arc_degrees * 0.42))
		var base_forward: Vector3 = active_structure.global_transform.basis * Vector3.FORWARD
		_face_position(global_position + base_forward.rotated(Vector3.UP, sweep) * 8.0)
		_scan_for_hostiles()
	return active_directive.duration > 0.0 and _operation_elapsed >= maxf(0.7, active_directive.duration)

func _perform_acquire_target() -> bool:
	if active_directive != null and is_instance_valid(active_directive.target) and is_hostile_target(active_directive.target):
		_face_position(active_directive.target.global_position)
		if active_directive.type == SquadDirective3D.Type.SUPPRESS or perception_component.can_see(active_directive.target):
			current_target = active_directive.target
	elif not is_instance_valid(current_target) or not perception_component.can_see(current_target):
		current_target = perception_component.find_best_hostile(true)
	return is_instance_valid(current_target)

func _perform_approach_target() -> bool:
	if not is_instance_valid(current_target) or not is_combat_target_alive(current_target):
		return false
	if _is_target_in_weapon_range(current_target):
		_desired_velocity = Vector3.ZERO
		return true
	var route_target := _get_runtime_heatmap_route_target(current_target.global_position)
	_move_toward(_get_autonomy_safe_movement_target(route_target))
	return false

func get_directive_action_cost(operation: SoldierStateChart3D.Action) -> int:
	if local_threat_field == null:
		return 1
	if operation not in [SoldierStateChart3D.Action.MOVE, SoldierStateChart3D.Action.APPROACH_TARGET]:
		return 1
	var destination := global_position
	if operation == SoldierStateChart3D.Action.APPROACH_TARGET and is_instance_valid(current_target):
		destination = current_target.global_position
	elif active_directive != null:
		destination = active_directive.target_position
		if not active_directive.route.is_empty() and _route_index < active_directive.route.size():
			destination = active_directive.route[_route_index]
	var distance := minf(4.0, _flat_distance_to(destination))
	if distance <= 0.05:
		return 1
	var direction := destination - global_position
	direction.y = 0.0
	var endpoint := global_position + direction.normalized() * distance
	return 1 + clampi(ceili(local_threat_field.score_segment(global_position, endpoint) / 22.0), 0, 12)

func _get_local_movement_target(destination: Vector3) -> Vector3:
	var uses_tactical_steering := active_directive != null and active_directive.type in [
		SquadDirective3D.Type.MOVE,
		SquadDirective3D.Type.TAKE_COVER,
		SquadDirective3D.Type.WITHDRAW,
		SquadDirective3D.Type.RECON,
		SquadDirective3D.Type.FLANK,
		SquadDirective3D.Type.USE_STRUCTURE,
	]
	var precision_distance := 5.0 if active_directive != null and not active_directive.route.is_empty() else 1.2
	if local_threat_field == null or not uses_tactical_steering or _flat_distance_to(destination) <= precision_distance:
		_reset_local_waypoint()
		return destination
	var destination_changed := _flat_distance(_local_waypoint_destination, destination) > 0.75
	var waypoint_reached := _has_local_waypoint and _flat_distance_to(_local_waypoint) <= 0.42
	if not _has_local_waypoint or destination_changed or waypoint_reached:
		var choice := local_threat_field.choose_local_detour(global_position, destination, 3.0, 4.0)
		_local_waypoint = choice.get("point", destination) as Vector3
		_local_waypoint_destination = destination
		_local_direct_risk = float(choice.get("direct_risk", 0.0))
		_local_selected_risk = float(choice.get("selected_risk", _local_direct_risk))
		_has_local_waypoint = true
		_local_navigation_decisions += 1
	return _local_waypoint

func _reset_local_waypoint() -> void:
	_has_local_waypoint = false
	_local_waypoint = Vector3.ZERO
	_local_waypoint_destination = Vector3.ZERO

func _refresh_directive_route_if_needed() -> void:
	if active_directive == null or not active_directive.requires_movement():
		return
	var influence := get_squad_influence_map()
	if influence == null or influence.version <= _last_directive_route_check_version:
		return
	var now := Time.get_ticks_msec()
	if now - _last_directive_route_plan_msec < ROUTE_REPLAN_INTERVAL_MSEC:
		return
	_last_directive_route_check_version = influence.version
	var remaining_route: Array[Vector3] = []
	for index in range(_route_index, active_directive.route.size()):
		remaining_route.append(active_directive.route[index])
	if remaining_route.is_empty() and _flat_distance_to(active_directive.target_position) > 0.5:
		remaining_route.append(active_directive.target_position)
	var current_metrics := _heatmap_route_planner.evaluate_route(global_position, remaining_route, influence)
	var current_cost := float(current_metrics.get("total_cost", 0.0))
	var current_peak := float(current_metrics.get("peak_threat", 0.0))
	var route_worsened := current_peak > active_directive.route_peak_threat + 8.0 \
		or current_cost > active_directive.route_total_cost + 10.0
	if not route_worsened:
		return
	var remaining_constraints: Array[Vector3] = []
	for index in range(_route_constraint_index, active_directive.route_constraints.size()):
		remaining_constraints.append(active_directive.route_constraints[index])
	var plan := build_minimum_cost_route(active_directive.target_position, remaining_constraints)
	active_directive.apply_route_plan(plan)
	_route_index = 0
	_last_directive_route_plan_msec = now
	_last_directive_route_check_version = active_directive.route_influence_version
	_reset_local_waypoint()
	print("[SOLDIER3D_ROUTE_REPLAN] member=%s directive=%d points=%d cost=%.1f peak=%.1f length=%.1f/%.1f reason=%s influence=%d" % [
		name, active_directive.version, active_directive.route.size(), active_directive.route_total_cost,
		active_directive.route_peak_threat, active_directive.route_length, active_directive.route_baseline_length,
		active_directive.route_selection_reason, active_directive.route_influence_version,
	])

func _advance_route_constraint_progress() -> void:
	if active_directive == null:
		return
	while _route_constraint_index < active_directive.route_constraints.size() \
			and _flat_distance_to(active_directive.route_constraints[_route_constraint_index]) <= 0.8:
		_route_constraint_index += 1

func _get_runtime_heatmap_route_target(destination: Vector3) -> Vector3:
	var influence := get_squad_influence_map()
	var influence_version := influence.version if influence != null else 0
	var destination_changed := _flat_distance(_runtime_route_destination, destination) > 0.9
	var stale := influence_version > _runtime_route_influence_version \
		and Time.get_ticks_msec() - _last_runtime_route_plan_msec >= ROUTE_REPLAN_INTERVAL_MSEC
	if _runtime_route.is_empty() or destination_changed or stale:
		var plan := build_minimum_cost_route(destination)
		_runtime_route.assign(plan.get("route", []))
		_runtime_route_index = 0
		_runtime_route_destination = destination
		_runtime_route_influence_version = int(plan.get("influence_version", influence_version))
		_last_runtime_route_plan_msec = Time.get_ticks_msec()
		_reset_local_waypoint()
	while _runtime_route_index < _runtime_route.size() \
			and _flat_distance_to(_runtime_route[_runtime_route_index]) <= 0.55:
		_runtime_route_index += 1
	return _runtime_route[_runtime_route_index] if _runtime_route_index < _runtime_route.size() else destination

func _reset_runtime_heatmap_route() -> void:
	_runtime_route.clear()
	_runtime_route_index = 0
	_runtime_route_destination = Vector3.ZERO
	_runtime_route_influence_version = 0
	_last_runtime_route_plan_msec = -100000

func _perform_aim() -> bool:
	if not is_instance_valid(current_target):
		return false
	if is_pinned():
		is_aimed = false
		if is_instance_valid(active_cover):
			set_cover_exposed(false)
		return false
	if is_instance_valid(active_cover):
		_begin_cover_exposure()
	_face_position(current_target.global_position)
	var settle_time := fire_cycle_component.get_required_aim_duration()
	is_aimed = _operation_elapsed >= settle_time
	if is_aimed:
		fire_cycle_component.complete_aim(current_target.global_position - global_position)
	return is_aimed

func _perform_reload() -> bool:
	_desired_velocity = Vector3.ZERO
	if magazine_ammo > 0:
		return true
	if reserve_ammo <= 0:
		return false
	if _operation_elapsed < fire_cycle_component.reload_duration:
		return false
	var reloaded := weapon_component.reload()
	if reloaded and weapon_feedback_component != null:
		weapon_feedback_component.play_reload()
	return reloaded

func _perform_engage() -> bool:
	if not is_instance_valid(current_target) or not is_combat_target_alive(current_target):
		return true
	if active_directive != null and active_directive.type != SquadDirective3D.Type.SUPPRESS \
		and not perception_component.can_see(current_target):
		current_target = null
		is_aimed = false
		return false
	if is_pinned():
		is_aimed = false
		if is_instance_valid(active_cover):
			set_cover_exposed(false)
		return false
	if is_instance_valid(active_cover):
		_begin_cover_exposure()
	if fire_cycle_component.requires_reaim(current_target.global_position - global_position):
		is_aimed = false
		return false
	_face_position(current_target.global_position)
	var fired := false
	if _reaction_timer <= 0.0:
		fired = _try_attack_target(current_target)
	if _update_cover_exposure_after_shot(fired):
		return false
	if active_directive != null and active_directive.type == SquadDirective3D.Type.SUPPRESS:
		var directive_elapsed := float(Time.get_ticks_msec() - _directive_started_msec) / 1000.0
		return directive_elapsed >= maxf(1.5, active_directive.duration)
	return not is_instance_valid(current_target) or not is_combat_target_alive(current_target)

func _perform_guard() -> bool:
	_desired_velocity = Vector3.ZERO
	var hold_duration := active_directive.duration if active_directive != null else 0.0
	return _operation_elapsed >= maxf(0.35, hold_duration)

func _perform_observe() -> bool:
	_desired_velocity = Vector3.ZERO
	if active_directive == null:
		return false
	var sweep := sin(_operation_elapsed * 2.4) * 0.7
	var base_direction := active_directive.target_position - global_position
	base_direction.y = 0.0
	if base_direction.length_squared() <= 0.01:
		base_direction = logical_forward
	var direction := base_direction.normalized().rotated(Vector3.UP, sweep)
	_face_position(global_position + direction * 8.0)
	_scan_for_hostiles()
	return _operation_elapsed >= maxf(0.5, active_directive.observation_seconds)

func _move_toward(destination: Vector3) -> void:
	if _movement_constraint_enabled:
		var offset := destination - _movement_constraint_center
		offset.y = 0.0
		if offset.length() > _movement_constraint_radius:
			destination = _movement_constraint_center + offset.normalized() * _movement_constraint_radius
	var direction := destination - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	var destination_delta := destination - _last_movement_destination
	destination_delta.y = 0.0
	if destination_delta.length() > 0.5:
		_movement_best_distance = direction.length()
		_movement_stall_timer = 0.0
	_last_movement_destination = destination
	direction = direction.normalized()
	if _movement_detour_timer > 0.0 and _movement_detour_direction.length_squared() > 0.01:
		if _movement_detour_target != Vector3.ZERO:
			var detour_offset := _movement_detour_target - global_position
			detour_offset.y = 0.0
			if detour_offset.length() <= 0.35:
				_movement_detour_timer = 0.0
				_movement_detour_target = Vector3.ZERO
			else:
				direction = detour_offset.normalized()
		else:
			direction = _movement_detour_direction
	elif _movement_stall_timer >= 0.55:
		_begin_movement_detour(direction, destination)
		direction = _movement_detour_direction
	logical_forward = direction
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 0.18)
	_desired_velocity = direction * get_current_move_speed()
	_movement_requested_last_frame = true

func _update_movement_stall(delta: float) -> void:
	if _movement_requested_last_frame:
		var current_distance := _flat_distance_to(_last_movement_destination)
		if current_distance + 0.03 < _movement_best_distance:
			_movement_best_distance = current_distance
			_movement_stall_timer = 0.0
		else:
			_movement_stall_timer += delta
	else:
		_movement_stall_timer = 0.0
		_movement_best_distance = INF
	_movement_requested_last_frame = false
	_movement_detour_timer = maxf(0.0, _movement_detour_timer - delta)

func _begin_movement_detour(desired_direction: Vector3, destination: Vector3) -> void:
	if is_instance_valid(_last_collision_cover):
		_movement_detour_target = _select_reachable_bypass(_last_collision_cover, destination)
		var bypass_direction := _movement_detour_target - global_position
		bypass_direction.y = 0.0
		if bypass_direction.length_squared() > 0.01:
			_movement_detour_direction = bypass_direction.normalized()
			_movement_detour_timer = clampf(bypass_direction.length() / maxf(0.5, get_current_move_speed()) + 0.8, 1.0, 4.0)
			_movement_stall_timer = 0.0
			return
	var normal := _last_collision_normal
	normal.y = 0.0
	if normal.length_squared() <= 0.01:
		normal = Vector3(-desired_direction.z, 0.0, desired_direction.x)
	normal = normal.normalized()
	var tangent := desired_direction.slide(normal)
	if tangent.length_squared() <= 0.01:
		tangent = Vector3(-normal.z, 0.0, normal.x)
	if tangent.dot(desired_direction) < 0.0:
		tangent = -tangent
	_movement_detour_direction = (tangent.normalized() + normal * 0.45).normalized()
	_movement_detour_timer = 0.8
	_movement_detour_target = Vector3.ZERO
	_movement_stall_timer = 0.0

func _select_reachable_bypass(cover: TacticalCover3D, destination: Vector3) -> Vector3:
	var points := cover.get_bypass_points(global_position, destination)
	var best_point := points[0]
	var best_score := INF
	for point in points:
		var from := global_position + Vector3.UP * 0.55
		var to := (point as Vector3) + Vector3.UP * 0.55
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [get_rid(), cover.get_rid()]
		query.collide_with_areas = false
		var blocked := not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		var score := global_position.distance_to(point) + (point as Vector3).distance_to(destination)
		if blocked:
			score += 10000.0
		if score < best_score:
			best_score = score
			best_point = point
	return best_point

func _capture_movement_collision() -> void:
	if get_slide_collision_count() <= 0:
		return
	var collision_info := get_slide_collision(get_slide_collision_count() - 1)
	if collision_info != null:
		_last_collision_normal = collision_info.get_normal()
		_last_collision_cover = collision_info.get_collider() as TacticalCover3D

func _try_attack_target(target: Node3D) -> bool:
	if target == null or is_pinned():
		return false
	if is_instance_valid(active_cover) and not cover_exposed:
		return false
	if active_directive != null:
		if active_directive.rules_of_engagement == SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD and _immediate_threat_timer <= 0.0:
			return false
		if active_directive.rules_of_engagement == SquadDirective3D.RulesOfEngagement.RETURN_FIRE \
			and _immediate_threat_timer <= 0.0 and not perception_component.can_see(target) \
			and not (cover_exposed and target == _threat_actor and _has_known_cover_threat()):
			return false
	if not weapon_component.is_target_in_range(self, target):
		return false
	if weapon_component.uses_ammunition() and weapon_component.magazine_ammo <= 0:
		return false
	if weapon_component.uses_ammunition() and not fire_cycle_component.can_fire(target):
		return false
	if not weapon_component.try_attack(self, target, _get_fire_origin(), 9, get_combat_ray_exclusions()):
		return false
	if weapon_component.uses_ammunition():
		fire_cycle_component.record_shot()
	if weapon_feedback_component != null:
		var direction := (weapon_component.get_target_point(target) - _get_fire_origin()).normalized()
		weapon_feedback_component.play_fire(direction, weapon_component.last_hit_result)
	last_weapon_fired_msec = Time.get_ticks_msec()
	aware_of_enemy = true
	get_tree().call_group("soldier3d", "hear_combat_sound", global_position, self, 1.0)
	weapon_fired.emit(self, target)
	return true

func notify_structure_weapon_fired(target: Node3D, hit_result: Dictionary) -> void:
	last_weapon_fired_msec = Time.get_ticks_msec()
	aware_of_enemy = true
	if weapon_feedback_component != null and is_instance_valid(active_structure) and not active_structure.has_fixed_weapon():
		var direction: Vector3 = (target.get_aim_point() - active_structure.get_muzzle_position()).normalized() \
			if target.has_method("get_aim_point") else (target.global_position - active_structure.get_muzzle_position()).normalized()
		weapon_feedback_component.play_fire(direction, hit_result)
	if get_tree() != null:
		get_tree().call_group("soldier3d", "hear_combat_sound", global_position, self, 1.2)
	weapon_fired.emit(self, target)

func _get_fire_origin() -> Vector3:
	if active_cover != null:
		return global_position + Vector3.UP * (active_cover.cover_height + 0.18)
	return muzzle.global_position

func _scan_for_hostiles() -> void:
	var hostile := perception_component.find_best_hostile(true)
	if hostile == null:
		return
	_register_autonomy_threat(hostile.global_position, hostile, 1.0, false)
	current_target = hostile
	aware_of_enemy = true
	contact_spotted.emit(self, hostile)
	perception_report_ready.emit(self, hostile, hostile.global_position, 1.0, &"visual")

func receive_hit(damage: int, hit_location: String, hit_position: Vector3, instigator: Node, weapon_metadata := {}) -> void:
	if dead or damage <= 0:
		return
	if not DAMAGE_RULES_3D.can_damage(instigator, self):
		return
	if not health_component.apply_damage(damage):
		return
	_last_instigator = instigator
	aware_of_enemy = true
	_reaction_timer = reaction_delay
	if instigator is Node3D and is_hostile_target(instigator):
		_emergency_prone_timer = maxf(_emergency_prone_timer, immediate_threat_seconds)
		current_target = instigator
		_register_autonomy_threat((instigator as Node3D).global_position, instigator, 1.0, true)
		contact_spotted.emit(self, instigator)
		perception_report_ready.emit(self, instigator, (instigator as Node3D).global_position, 1.0, &"damage")
	else:
		_emergency_prone_timer = maxf(_emergency_prone_timer, immediate_threat_seconds)
		_register_autonomy_threat(hit_position, null, 0.85, true)
	health_changed.emit(health, health_component.maximum)
	if suppression_component != null:
		var source_position := (instigator as Node3D).global_position if instigator is Node3D else hit_position
		suppression_component.report_damage(damage, source_position)
	if voxel_visual != null and String(weapon_metadata.get("family", "")) != "melee":
		voxel_visual.add_bullet_wound(hit_position, weapon_metadata.get("impact_normal", Vector3.ZERO) as Vector3, hit_location)
	var force_sever := float(weapon_metadata.get("dismember_power", 0.0)) >= 1.0
	limb_damage_component.report_damage(damage, hit_location, hit_position, instigator, health <= 0, force_sever)
	if health <= 0:
		_die()
	else:
		_flash_hit()

func apply_reaction_delay(seconds: float) -> void:
	_reaction_timer = maxf(_reaction_timer, maxf(0.0, seconds))

func hear_combat_sound(source_position: Vector3, instigator: Node = null, intensity := 1.0) -> void:
	if dead or instigator == self:
		return
	if instigator != null and not is_hostile_target(instigator):
		return
	var distance := global_position.distance_to(source_position)
	if distance > hearing_range * maxf(0.25, intensity):
		return
	var confidence := clampf(1.0 - distance / maxf(1.0, hearing_range), 0.2, 0.8)
	# Nearby gunfire demands an immediate survival response without identifying an unseen shooter.
	var immediate := _threat_memory_timer <= 0.0 \
		and distance <= hearing_range * 0.3 * clampf(intensity, 0.5, 1.5)
	_register_autonomy_threat(source_position, instigator as Node3D if instigator is Node3D else null, confidence, immediate)
	combat_sound_heard.emit(self, source_position, confidence)
	var visually_identified := instigator is Node3D and perception_component.can_see(instigator as Node3D)
	perception_report_ready.emit(self, instigator as Node3D if visually_identified else null, source_position, confidence, &"gunshot")

func notify_near_miss(source_position: Vector3, instigator: Node = null, intensity := 1.0) -> void:
	if dead or (instigator != null and not is_hostile_target(instigator)):
		return
	_emergency_prone_timer = maxf(_emergency_prone_timer, immediate_threat_seconds)
	_register_autonomy_threat(source_position, instigator if instigator is Node3D else null, 0.95, true)
	if suppression_component != null:
		suppression_component.report_near_miss(source_position, intensity)
	perception_report_ready.emit(self, instigator as Node3D if instigator is Node3D else null, source_position, 0.9, &"near_miss")

func notify_cover_impact(source_position: Vector3, intensity := 1.0) -> void:
	if dead or suppression_component == null:
		return
	suppression_component.report_cover_impact(source_position, intensity)
	_register_autonomy_threat(source_position, null, 0.5, true)

func is_protected_from_position(threat_position: Vector3) -> bool:
	if stance == Stance.PRONE:
		return true
	if not is_instance_valid(active_cover) or not is_instance_valid(active_cover_slot):
		return false
	if cover_exposed:
		return false
	if _flat_distance_to(active_cover_slot.global_position) > 0.9:
		return false
	return active_cover_slot in active_cover.get_slots_against(threat_position)

func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * _get_aim_height()

func set_stance(new_stance: Stance) -> void:
	if is_instance_valid(active_cover) and new_stance != Stance.STAND:
		return
	if stance == new_stance:
		return
	stance = new_stance
	if stance != Stance.STAND and movement_mode == MoveMode.RUN:
		set_movement_mode(MoveMode.WALK)
	_apply_stance_geometry()
	stance_changed.emit(self, stance)
	_update_status()

func is_cover_exposed() -> bool:
	return is_instance_valid(active_cover) and is_instance_valid(active_cover_slot) and cover_exposed

func set_cover_exposed(exposed: bool) -> void:
	var next_exposed := exposed and is_instance_valid(active_cover) and is_instance_valid(active_cover_slot)
	if cover_exposed == next_exposed:
		if is_instance_valid(active_cover):
			_apply_stance_geometry()
		return
	cover_exposed = next_exposed
	if not cover_exposed:
		is_aimed = false
		_cover_exposure_shots_remaining = 0
	_apply_stance_geometry()
	_update_status()

func _begin_cover_exposure() -> void:
	if not is_instance_valid(active_cover) or not is_instance_valid(active_cover_slot):
		return
	var starts_new_window := not cover_exposed
	set_cover_exposed(true)
	if starts_new_window or _cover_exposure_shots_remaining <= 0:
		_cover_exposure_shots_remaining = fire_cycle_component.roll_cover_exposure_shot_budget(
			magazine_ammo,
			get_suppression_ratio()
		)

func _update_cover_exposure_after_shot(fired: bool) -> bool:
	if not fired or not is_instance_valid(active_cover):
		return false
	_cover_exposure_shots_remaining = maxi(0, _cover_exposure_shots_remaining - 1)
	if _cover_exposure_shots_remaining > 0 and magazine_ammo > 0:
		return false
	set_cover_exposed(false)
	return true

func _clear_cover_state(release_slot := true) -> void:
	var had_cover := active_cover != null or active_cover_slot != null or cover_exposed
	if release_slot and is_instance_valid(active_cover):
		active_cover.release_slot(self)
	active_cover = null
	active_cover_slot = null
	cover_exposed = false
	_cover_exposure_shots_remaining = 0
	if had_cover:
		_apply_stance_geometry()

func _clear_structure_state(release_slot := true) -> void:
	var structure: TacticalStructure3D = active_structure
	active_structure = null
	_structure_enter_animation_remaining = 0.0
	if release_slot and is_instance_valid(structure):
		structure.release(self)

func notify_structure_released(structure: TacticalStructure3D) -> void:
	if active_structure != structure:
		return
	_clear_structure_state(false)

func get_structure_sight_multiplier() -> float:
	return active_structure.vision_multiplier if is_instance_valid(active_structure) else 1.0

func get_combat_ray_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = [get_rid()]
	if is_instance_valid(active_structure):
		exclusions.append(active_structure.get_rid())
	return exclusions

func set_movement_mode(new_mode: MoveMode) -> void:
	if new_mode == MoveMode.RUN and (stance != Stance.STAND or not stamina_component.can_run()):
		new_mode = MoveMode.WALK
	if movement_mode == new_mode:
		return
	movement_mode = new_mode
	movement_mode_changed.emit(self, movement_mode)
	_update_status()

func get_current_move_speed() -> float:
	var base_speed := move_speed
	match stance:
		Stance.CROUCH:
			base_speed = crouch_speed
		Stance.PRONE:
			base_speed = prone_speed
		_:
			match movement_mode:
				MoveMode.RUN:
					base_speed = run_speed
				MoveMode.QUIET:
					base_speed = quiet_speed
	var suppression_multiplier := suppression_component.get_movement_multiplier() if suppression_component != null else 1.0
	return maxf(0.0, base_speed * suppression_multiplier)

func get_visibility_multiplier() -> float:
	var multiplier := 1.0
	match stance:
		Stance.CROUCH:
			multiplier *= 0.72
		Stance.PRONE:
			multiplier *= 0.48
	if movement_mode == MoveMode.QUIET:
		multiplier *= 0.72
	elif movement_mode == MoveMode.RUN:
		multiplier *= 1.18
	if get_tree() != null and Time.get_ticks_msec() - last_weapon_fired_msec > 1600:
		var zone := TacticalZone3D.find_at(get_tree(), global_position)
		if zone != null:
			multiplier *= maxf(0.14, 1.0 - zone.concealment)
	return multiplier

func get_suppression_ratio() -> float:
	return suppression_component.suppression / 100.0 if suppression_component != null else 0.0

func is_suppressed() -> bool:
	return suppression_component != null and suppression_component.level != SuppressionComponent3D.Level.NORMAL

func is_pinned() -> bool:
	return suppression_component != null and suppression_component.is_pinned()

func get_suppression_accuracy_multiplier() -> float:
	return suppression_component.get_accuracy_multiplier() if suppression_component != null else 1.0

func get_mobility_ratio() -> float:
	var ratio := 1.0
	for leg in ["left_leg", "right_leg"]:
		var damage_ratio := clampf(
			float(limb_damage_component.accumulated_damage.get(leg, 0)) \
				/ maxf(1.0, float(limb_damage_component.leg_sever_threshold)),
			0.0,
			1.0
		)
		var leg_penalty := damage_ratio * 0.32
		if voxel_visual != null and voxel_visual.is_limb_detached(leg):
			leg_penalty = 0.45
		ratio -= leg_penalty
	return clampf(ratio, 0.1, 1.0)

func get_stance_label() -> String:
	if is_instance_valid(active_cover):
		return "掩体站立" if cover_exposed else "掩体隐藏"
	return ["站立", "下蹲", "卧倒"][int(stance)]

func get_movement_mode_label() -> String:
	return ["行走", "静步", "跑步"][int(movement_mode)]

func is_combat_alive() -> bool:
	return not dead and health_component.is_alive()

func get_combat_power() -> float:
	match combat_role:
		CombatRole.MACHINE_GUNNER:
			return 3.2
		CombatRole.MARKSMAN:
			return 2.6
		CombatRole.RIFLEMAN:
			return 1.8
		CombatRole.SMG:
			return 1.6
		CombatRole.SHOTGUNNER:
			return 1.4
		CombatRole.MELEE:
			return 0.7
	return 1.0

func get_combat_role_name() -> String:
	match combat_role:
		CombatRole.RIFLEMAN:
			return "RIFLEMAN"
		CombatRole.SMG:
			return "SMG"
		CombatRole.MACHINE_GUNNER:
			return "MACHINE_GUNNER"
		CombatRole.MARKSMAN:
			return "MARKSMAN"
		CombatRole.SHOTGUNNER:
			return "SHOTGUNNER"
		CombatRole.MELEE:
			return "MELEE"
	return "UNKNOWN"

func set_squad_leader(value: bool) -> void:
	if is_squad_leader == value:
		return
	is_squad_leader = value
	squad_leader_role_changed.emit(self, value)
	_update_status()

func is_hostile_target(candidate: Node) -> bool:
	if candidate == self or not candidate.has_method("get_combat_team"):
		return false
	var other_team := int(candidate.get_combat_team())
	if other_team == int(combat_team):
		return false
	if not can_target_players and other_team == int(Team.PLAYER):
		return false
	return true

func get_combat_team() -> int:
	return int(combat_team)

func is_combat_target_alive(candidate: Node) -> bool:
	return candidate != null and (not candidate.has_method("is_combat_alive") or bool(candidate.is_combat_alive()))

func _die() -> void:
	dead = true
	if _state_chart_controller != null:
		_state_chart_controller.notify_actor_died()
	velocity = Vector3.ZERO
	if active_cover != null:
		_clear_cover_state()
	if active_structure != null:
		_clear_structure_state()
	death_reward_requested.emit(
		self,
		_last_instigator,
		score_reward if awards_player_score else 0,
		dropped_ammo_amount if drops_ammo_on_death else 0
	)
	died.emit(self)
	if voxel_visual != null:
		voxel_visual.play_death()
	visual.visible = false
	collision.disabled = true
	set_physics_process(false)
	await get_tree().create_timer(1.6).timeout
	queue_free()

func _setup_state_chart() -> void:
	_state_chart_controller = SOLDIER_STATE_CHART_SCENE.instantiate() as SoldierStateChart3D
	_state_chart_controller.setup(self)
	$Components.add_child(_state_chart_controller)

func uses_ammunition() -> bool:
	return weapon_component.uses_ammunition()

func can_reload_weapon() -> bool:
	return weapon_component.can_reload()

func _is_target_in_weapon_range(target: Node3D) -> bool:
	if not is_instance_valid(target) or not is_combat_target_alive(target):
		return false
	return weapon_component.is_target_in_range(self, target)

func state_chart_refresh_context() -> void:
	if _threat_memory_timer <= 0.0 and _threat_confidence > 0.0:
		_threat_confidence = 0.0
		_threat_actor = null
		_contact_response_complete = true
	_refresh_environmental_danger()

func _register_autonomy_threat(position_value: Vector3, source: Node3D, confidence: float, immediate: bool) -> void:
	if dead:
		return
	var memory_expired := _threat_memory_timer <= 0.0
	var source_changed := is_instance_valid(source) and source != _threat_actor
	var renewed_immediate := immediate and _immediate_threat_timer <= 0.0
	var starts_new_response := memory_expired or source_changed or renewed_immediate
	_threat_position = position_value
	_threat_confidence = maxf(_threat_confidence, clampf(confidence, 0.0, 1.0))
	_threat_memory_timer = maxf(_threat_memory_timer, threat_memory_seconds)
	if is_instance_valid(source):
		_threat_actor = source
	elif memory_expired:
		_threat_actor = null
	if immediate:
		_immediate_threat_timer = maxf(_immediate_threat_timer, immediate_threat_seconds)
	var directly_observed := is_instance_valid(source) and perception_component.can_see(source)
	if working_memory != null:
		working_memory.remember_threat(source, position_value, confidence, threat_memory_seconds,
			directly_observed, immediate, &"visual" if directly_observed else (&"danger" if immediate else &"sound"))
	if not starts_new_response:
		return
	if immediate:
		_reaction_timer = maxf(_reaction_timer, reaction_delay)
	_contact_response_complete = false

func receive_squad_contact(position_value: Vector3, source: Node3D, confidence: float) -> void:
	if dead or confidence <= 0.0:
		return
	if is_instance_valid(source) and not is_hostile_target(source):
		return
	if working_memory != null:
		working_memory.remember_threat(source, position_value, minf(0.65, confidence), threat_memory_seconds * 0.75,
			false, false, &"squad_report")
	# A radio report provides a search sector, never personal visual confirmation.
	if _threat_memory_timer <= 0.0 or confidence > _threat_confidence:
		_threat_position = position_value
		_threat_actor = source if is_instance_valid(source) else null
		_threat_confidence = minf(0.65, confidence)
		_threat_memory_timer = threat_memory_seconds * 0.75
		_contact_response_complete = false

func _is_protected_from_threat() -> bool:
	return is_protected_from_position(_threat_position)

func _refresh_environmental_danger() -> void:
	var was_dangerous := _environmental_danger
	_environment_current_risk = local_threat_field.score_position(global_position) if local_threat_field != null else 0.0
	_environment_route_risk = 0.0
	if local_threat_field != null and has_active_directive() and active_directive.requires_movement():
		var destination := active_directive.target_position
		if not active_directive.route.is_empty() and _route_index < active_directive.route.size():
			destination = active_directive.route[_route_index]
		var offset := destination - global_position
		offset.y = 0.0
		if offset.length_squared() > 0.01:
			var probe := global_position + offset.normalized() * minf(8.0, offset.length())
			_environment_route_risk = local_threat_field.score_segment(global_position, probe)
	var current_threshold := environmental_danger_threshold
	var route_threshold := route_danger_threshold
	if was_dangerous:
		current_threshold = maxf(0.0, current_threshold - environmental_danger_hysteresis)
		route_threshold = maxf(0.0, route_threshold - environmental_danger_hysteresis)
	_environmental_danger = _environment_current_risk >= current_threshold \
		or _environment_route_risk >= route_threshold
	if _environmental_danger and _immediate_threat_timer <= 0.0 and local_threat_field != null:
		var peak := local_threat_field.find_peak_threat_position(global_position, maxf(18.0, autonomy_escape_distance * 1.8))
		if _flat_distance(peak, global_position) > 0.25:
			_threat_position = peak
	if _environmental_danger != was_dangerous:
		print("[SOLDIER3D_STATE_CHART_ENVIRONMENT] member=%s danger=%s current=%.1f route=%.1f" % [
			name, _environmental_danger, _environment_current_risk, _environment_route_risk,
		])

func _has_survival_pressure() -> bool:
	return is_pinned() or _immediate_threat_timer > 0.0 or _environmental_danger

func _has_committed_movement_order() -> bool:
	return has_active_directive() \
		and active_directive.execution_policy == SquadDirective3D.ExecutionPolicy.COMMITTED \
		and active_directive.requires_movement()

func _has_reactive_survival_pressure() -> bool:
	if is_pinned():
		return true
	if _has_committed_movement_order():
		return _immediate_threat_timer > 0.0 and not _contact_response_complete
	return _immediate_threat_timer > 0.0 or _environmental_danger

func _is_order_movement_safe() -> bool:
	if is_pinned():
		return false
	if _has_committed_movement_order():
		return true
	if _immediate_threat_timer > 0.0:
		return is_instance_valid(active_cover) and _is_protected_from_threat()
	if not _environmental_danger:
		return true
	if not is_instance_valid(active_cover) or not _is_protected_from_threat():
		return false
	if local_threat_field == null or active_directive == null:
		return true
	var destination := active_directive.target_position
	if not active_directive.route.is_empty() and _route_index < active_directive.route.size():
		destination = active_directive.route[_route_index]
	var detour := local_threat_field.choose_local_detour(global_position, destination, 4.5, 4.0)
	return bool(detour.get("valid", false)) and float(detour.get("selected_risk", INF)) < route_danger_threshold

func _has_available_autonomy_structure() -> bool:
	return autonomy_defensive_posture and not has_active_directive() and not is_instance_valid(active_structure) \
		and is_instance_valid(_find_best_autonomy_structure(false))

func _directive_allows_contact_response() -> bool:
	if not has_active_directive():
		return true
	return active_directive.type in [
		SquadDirective3D.Type.MOVE,
		SquadDirective3D.Type.TAKE_COVER,
		SquadDirective3D.Type.RECON,
	]

func is_movement_return_fire_context() -> bool:
	return has_active_directive() and active_directive.type in [
		SquadDirective3D.Type.MOVE,
		SquadDirective3D.Type.TAKE_COVER,
		SquadDirective3D.Type.RECON,
	]

func is_cover_response_context() -> bool:
	return _has_known_cover_threat()

func _is_controlled_cover_response() -> bool:
	return cover_exposed and _has_known_cover_threat() and _state_chart_controller != null and _state_chart_controller.is_return_fire_active()

func state_chart_should_survival_override() -> bool:
	if is_pinned():
		return true
	if _has_reactive_survival_pressure() and not _is_protected_from_threat() and not is_instance_valid(active_structure):
		return true
	return not _contact_response_complete and _threat_memory_timer > 0.0 \
		and _directive_allows_contact_response() \
		and (_has_confirmed_visible_threat() or _has_known_cover_threat()) \
		and _is_target_in_weapon_range(_threat_actor)

func state_chart_build_survival_actions() -> Array[int]:
	var actions: Array[int] = []
	_autonomy_cover_candidate = null
	_autonomy_escape_available = false
	if is_pinned():
		actions.append(SoldierStateChart3D.Action.WAIT_FOR_OPENING if is_instance_valid(active_cover) else SoldierStateChart3D.Action.DROP_PRONE)
		return actions
	var committed_movement := _has_committed_movement_order()
	if committed_movement and _immediate_threat_timer > 0.0 and not _contact_response_complete \
			and not _is_protected_from_threat() and not is_instance_valid(active_structure):
		actions.append(SoldierStateChart3D.Action.DROP_PRONE)
	elif _has_reactive_survival_pressure() and not _is_protected_from_threat() and not is_instance_valid(active_structure):
		_autonomy_cover_candidate = _find_emergency_cover()
		if is_instance_valid(_autonomy_cover_candidate):
			actions.append(SoldierStateChart3D.Action.SEEK_COVER)
		elif local_threat_field != null and not committed_movement:
			var escape := local_threat_field.find_safest_escape(global_position, _threat_position, autonomy_escape_distance)
			_autonomy_escape_available = bool(escape.get("valid", false))
			_autonomy_escape_position = escape.get("point", global_position) as Vector3
			if _autonomy_escape_available:
				actions.append(SoldierStateChart3D.Action.EVADE_DANGER)
		if actions.is_empty():
			actions.append(SoldierStateChart3D.Action.DROP_PRONE if _environmental_danger or _emergency_prone_timer > 0.0 else SoldierStateChart3D.Action.TAKE_KNEE)
	if not _contact_response_complete and _threat_memory_timer > 0.0:
		if _has_confirmed_visible_threat() or _has_known_cover_threat():
			if _immediate_threat_timer > 0.0:
				actions.append(SoldierStateChart3D.Action.FLINCH_AND_ASSESS)
			actions.append(SoldierStateChart3D.Action.ORIENT_TO_THREAT)
			actions.append(SoldierStateChart3D.Action.COMMUNICATE_CONTACT)
			actions.append(SoldierStateChart3D.Action.ACQUIRE_VISIBLE_TARGET)
			if uses_ammunition() and magazine_ammo <= 0 and reserve_ammo > 0:
				actions.append(SoldierStateChart3D.Action.RELOAD_COVERED)
			actions.append(SoldierStateChart3D.Action.AIM)
			actions.append(SoldierStateChart3D.Action.RETURN_FIRE)
		else:
			actions.append(SoldierStateChart3D.Action.ORIENT_TO_THREAT)
			actions.append(SoldierStateChart3D.Action.SCAN_THREAT_SECTOR)
	return actions

func state_chart_on_survival_sequence_completed() -> void:
	_contact_response_complete = true
	is_aimed = false
	if is_instance_valid(active_cover):
		set_cover_exposed(false)
	_update_status()

func state_chart_select_idle_action() -> int:
	if is_instance_valid(active_structure) and active_structure.is_occupied_by(self):
		return SoldierStateChart3D.Action.GUARD_SECTOR
	if autonomy_defensive_posture and not _has_survival_pressure():
		if not is_instance_valid(_autonomy_structure_candidate):
			_autonomy_structure_candidate = _find_best_autonomy_structure(true)
		if is_instance_valid(_autonomy_structure_candidate):
			return SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE
	if can_reload_weapon() and (_immediate_threat_timer <= 0.0 or _is_protected_from_threat()):
		return SoldierStateChart3D.Action.RELOAD_SAFE
	if _security_cycle_timer <= 0.0:
		return SoldierStateChart3D.Action.GUARD_SECTOR
	return SoldierStateChart3D.Action.NONE

func state_chart_on_idle_action_completed(action: int) -> void:
	if action == SoldierStateChart3D.Action.GUARD_SECTOR and not is_instance_valid(active_structure):
		_security_cycle_timer = security_cycle_interval
	_update_status()

func state_chart_on_action_failed(action: int) -> void:
	if action == SoldierStateChart3D.Action.SEEK_COVER and is_instance_valid(_autonomy_cover_candidate):
		_autonomy_cover_candidate.release_slot(self)
		_autonomy_cover_candidate = null
		_autonomy_cover_slot = null
	if action == SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE and is_instance_valid(_autonomy_structure_candidate):
		_autonomy_structure_candidate.release(self)
		_autonomy_structure_candidate = null

func state_chart_has_valid_target() -> bool:
	return is_instance_valid(current_target) and is_hostile_target(current_target) and is_combat_target_alive(current_target)

func state_chart_target_in_weapon_range() -> bool:
	return _is_target_in_weapon_range(current_target)

func state_chart_is_assigned_cover_active() -> bool:
	return active_directive != null and is_instance_valid(active_directive.assigned_cover) \
		and active_cover == active_directive.assigned_cover and is_instance_valid(active_cover_slot)

func state_chart_is_assigned_structure_active() -> bool:
	return active_directive != null and is_instance_valid(active_directive.assigned_structure) \
		and active_structure == active_directive.assigned_structure and active_structure.is_occupied_by(self)

func state_chart_begin_action(action: int) -> void:
	if _is_autonomy_state_chart_action(action):
		_begin_autonomy_action(action)
	else:
		_begin_directive_action(action)

func state_chart_perform_action(action: int, delta: float) -> bool:
	return _perform_autonomy_action(action, delta) if _is_autonomy_state_chart_action(action) \
		else _perform_directive_action(action, delta)

func state_chart_end_action(action: int) -> void:
	if _is_autonomy_state_chart_action(action):
		_end_autonomy_action(action)
	else:
		_end_directive_action(action)

func _is_autonomy_state_chart_action(action: int) -> bool:
	return action >= SoldierStateChart3D.Action.SEEK_COVER \
		or (_state_chart_controller != null and _state_chart_controller.root_state != SoldierStateChart3D.RootState.EXECUTE_ORDER)

func _begin_autonomy_action(operation: SoldierStateChart3D.Action) -> void:
	_operation_elapsed = 0.0
	_autonomy_operation_completed = false
	_desired_velocity = Vector3.ZERO
	if operation == SoldierStateChart3D.Action.SEEK_COVER:
		is_aimed = false
		_reset_local_waypoint()
		_reset_runtime_heatmap_route()
		if is_instance_valid(active_cover) and not _is_protected_from_threat():
			_clear_cover_state()
		if is_instance_valid(_autonomy_cover_candidate):
			_autonomy_cover_slot = _autonomy_cover_candidate.reserve_reachable_slot(self, _threat_position)
	elif operation in [
		SoldierStateChart3D.Action.EVADE_DANGER,
		SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE,
	]:
		is_aimed = false
		_reset_local_waypoint()
		_reset_runtime_heatmap_route()
		if operation == SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE \
				and is_instance_valid(active_cover):
			_clear_cover_state()
	else:
		_autonomy_cover_slot = null
	_update_status(_autonomy_operation_label(operation))

func _perform_autonomy_action(operation: SoldierStateChart3D.Action, delta: float) -> bool:
	_operation_elapsed += delta
	match operation:
		SoldierStateChart3D.Action.SEEK_COVER:
			if not is_instance_valid(_autonomy_cover_candidate) or not is_instance_valid(_autonomy_cover_slot):
				_autonomy_cover_candidate = null
				_autonomy_cover_slot = null
				return false
			set_stance(Stance.STAND)
			set_movement_mode(MoveMode.RUN if stamina_component.can_run() else MoveMode.WALK)
			if _flat_distance_to(_autonomy_cover_slot.global_position) > 0.45:
				var route_target := _get_runtime_heatmap_route_target(_autonomy_cover_slot.global_position)
				_move_toward(_get_autonomy_safe_movement_target(route_target))
				return false
			global_position = _autonomy_cover_slot.global_position
			set_stance(Stance.STAND)
			active_cover = _autonomy_cover_candidate
			active_cover_slot = _autonomy_cover_slot
			set_cover_exposed(false)
			set_movement_mode(MoveMode.WALK)
			_desired_velocity = Vector3.ZERO
			_autonomy_operation_completed = true
			return true
		SoldierStateChart3D.Action.DROP_PRONE:
			_desired_velocity = Vector3.ZERO
			set_stance(Stance.PRONE)
			_autonomy_operation_completed = true
			return true
		SoldierStateChart3D.Action.TAKE_KNEE:
			_desired_velocity = Vector3.ZERO
			set_stance(Stance.CROUCH)
			_autonomy_operation_completed = _operation_elapsed >= 0.22
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.RECOVER_MOVEMENT_POSTURE:
			_desired_velocity = Vector3.ZERO
			set_stance(Stance.STAND)
			_autonomy_operation_completed = _operation_elapsed >= 0.18
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.FLINCH_AND_ASSESS:
			_desired_velocity = Vector3.ZERO
			_face_position(_threat_position)
			if is_instance_valid(active_cover):
				set_cover_exposed(false)
			_autonomy_operation_completed = _operation_elapsed >= maxf(0.25, reaction_delay * 0.7)
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.ORIENT_TO_THREAT:
			_desired_velocity = Vector3.ZERO
			_face_position(_threat_position)
			_autonomy_operation_completed = _operation_elapsed >= 0.2
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.COMMUNICATE_CONTACT:
			_desired_velocity = Vector3.ZERO
			_face_position(_threat_position)
			if _operation_elapsed >= 0.18 and not _autonomy_operation_completed:
				if _has_confirmed_visible_threat():
					perception_report_ready.emit(self, _threat_actor, _threat_position, _threat_confidence, &"visual")
				_autonomy_operation_completed = true
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.ACQUIRE_VISIBLE_TARGET:
			if _has_known_cover_threat() and not cover_exposed:
				_face_position(_threat_position)
				_begin_cover_exposure()
				_trace_autonomy("cover peek started")
				return false
			if _has_confirmed_visible_threat():
				current_target = _threat_actor
				aware_of_enemy = true
				_autonomy_operation_completed = true
				return true
			if _has_known_cover_threat() and cover_exposed and _operation_elapsed >= 0.18:
				current_target = _threat_actor
				aware_of_enemy = true
				_autonomy_operation_completed = true
				_trace_autonomy("cover target acquired from memory")
				return true
			if is_instance_valid(active_cover) and _operation_elapsed < 0.48:
				return false
			if is_instance_valid(active_cover):
				set_cover_exposed(false)
			_abort_contact_response()
			return false
		SoldierStateChart3D.Action.AIM:
			if not _has_confirmed_visible_threat() and not _has_known_cover_threat():
				_abort_contact_response()
				return false
			_autonomy_operation_completed = _perform_aim()
			if _autonomy_operation_completed:
				_trace_autonomy("cover aim complete")
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.RELOAD_COVERED, SoldierStateChart3D.Action.RELOAD_SAFE:
			_autonomy_operation_completed = _perform_reload()
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.RETURN_FIRE:
			_desired_velocity = Vector3.ZERO
			if (not _has_confirmed_visible_threat() and not _has_known_cover_threat()) \
					or not _is_target_in_weapon_range(_threat_actor):
				_autonomy_operation_completed = true
				return true
			current_target = _threat_actor
			if is_instance_valid(active_cover):
				_begin_cover_exposure()
			_face_position(current_target.global_position)
			var return_fire_shot := false
			if _reaction_timer <= 0.0:
				return_fire_shot = _try_attack_target(current_target)
				_trace_autonomy("return fire attempted fired=%s exposed=%s visible=%s ammo=%d phase=%s timer=%.2f target_id=%d/%d" % [
					return_fire_shot,
					cover_exposed,
					perception_component.can_see(current_target),
					magazine_ammo,
					WeaponFireCycle3D.Phase.keys()[fire_cycle_component.phase],
					fire_cycle_component._timer,
					fire_cycle_component._target_id,
					int(current_target.get_instance_id()),
				])
				if return_fire_shot and active_directive != null:
					print("[SOLDIER3D_STATE_CHART_RETURN_FIRE] member=%s directive=%s target=%s" % [
						name,
						SquadDirective3D.Type.keys()[active_directive.type],
						current_target.name,
					])
			if _update_cover_exposure_after_shot(return_fire_shot):
				is_aimed = false
				_autonomy_operation_completed = true
				return true
			_autonomy_operation_completed = _operation_elapsed >= autonomy_return_fire_seconds \
				or not is_combat_target_alive(current_target)
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.WAIT_FOR_OPENING:
			_desired_velocity = Vector3.ZERO
			is_aimed = false
			if is_instance_valid(active_cover):
				set_cover_exposed(false)
			if active_directive != null:
				_autonomy_operation_completed = _operation_elapsed >= 0.35 and _is_order_movement_safe()
				if _autonomy_operation_completed and not is_instance_valid(active_cover):
					set_stance(Stance.STAND)
			else:
				_autonomy_operation_completed = _operation_elapsed >= 0.65
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.SCAN_THREAT_SECTOR:
			_desired_velocity = Vector3.ZERO
			_face_position(_threat_position)
			_autonomy_operation_completed = _operation_elapsed >= autonomy_scan_seconds
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.GUARD_SECTOR:
			_autonomy_operation_completed = _perform_autonomy_guard_sector()
			return _autonomy_operation_completed
		SoldierStateChart3D.Action.EVADE_DANGER:
			if not _autonomy_escape_available:
				return false
			set_stance(Stance.STAND)
			set_movement_mode(MoveMode.RUN if stamina_component.can_run() else MoveMode.WALK)
			if _flat_distance_to(_autonomy_escape_position) > 0.5:
				var route_target := _get_runtime_heatmap_route_target(_autonomy_escape_position)
				_move_toward(_get_autonomy_safe_movement_target(route_target))
				return false
			_desired_velocity = Vector3.ZERO
			_autonomy_operation_completed = true
			print("[SOLDIER3D_STATE_CHART_EVADE_COMPLETE] member=%s risk=%.1f position=%s" % [
				name,
				local_threat_field.score_position(global_position) if local_threat_field != null else 0.0,
				str(global_position),
			])
			return true
		SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE:
			_autonomy_operation_completed = _perform_autonomy_enter_structure()
			return _autonomy_operation_completed
	return false

func _end_autonomy_action(operation: SoldierStateChart3D.Action) -> void:
	_desired_velocity = Vector3.ZERO
	if operation == SoldierStateChart3D.Action.RETURN_FIRE and is_instance_valid(active_cover):
		is_aimed = false
		set_cover_exposed(false)
	if operation == SoldierStateChart3D.Action.SEEK_COVER \
		and not _autonomy_operation_completed and is_instance_valid(_autonomy_cover_candidate):
		_autonomy_cover_candidate.release_slot(self)
		_autonomy_cover_slot = null
	if operation in [
		SoldierStateChart3D.Action.SEEK_COVER,
		SoldierStateChart3D.Action.EVADE_DANGER,
		SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE,
	]:
		_reset_local_waypoint()
		_reset_runtime_heatmap_route()
	if operation == SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE \
			and not _autonomy_operation_completed and is_instance_valid(_autonomy_structure_candidate):
		_autonomy_structure_candidate.release(self)
		_autonomy_structure_candidate = null

func _get_autonomy_safe_movement_target(destination: Vector3) -> Vector3:
	if local_threat_field == null or _flat_distance_to(destination) <= 1.2:
		return destination
	var destination_changed := _flat_distance(_local_waypoint_destination, destination) > 0.75
	var waypoint_reached := _has_local_waypoint and _flat_distance_to(_local_waypoint) <= 0.42
	if not _has_local_waypoint or destination_changed or waypoint_reached:
		var choice := local_threat_field.choose_local_detour(global_position, destination, 4.5, 4.0)
		_local_waypoint = choice.get("point", destination) as Vector3
		_local_waypoint_destination = destination
		_local_direct_risk = float(choice.get("direct_risk", 0.0))
		_local_selected_risk = float(choice.get("selected_risk", _local_direct_risk))
		_has_local_waypoint = true
		_local_navigation_decisions += 1
	return _local_waypoint

func _perform_autonomy_enter_structure() -> bool:
	if not is_instance_valid(_autonomy_structure_candidate) \
			or not _autonomy_structure_candidate.is_reserved_by(self):
		return false
	var destination := _autonomy_structure_candidate.get_operator_position()
	set_stance(Stance.STAND)
	set_movement_mode(MoveMode.RUN if stamina_component.can_run() else MoveMode.WALK)
	if _flat_distance_to(destination) > 0.45:
		var route_target := _get_runtime_heatmap_route_target(destination)
		_move_toward(_get_autonomy_safe_movement_target(route_target))
		return false
	if not _autonomy_structure_candidate.occupy(self):
		return false
	active_structure = _autonomy_structure_candidate
	_structure_enter_animation_remaining = 0.48
	set_movement_mode(MoveMode.WALK)
	_desired_velocity = Vector3.ZERO
	var forward: Vector3 = active_structure.global_transform.basis * Vector3.FORWARD
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		logical_forward = forward.normalized()
		rotation.y = atan2(-logical_forward.x, -logical_forward.z)
	active_structure.align_operator(self)
	print("[SOLDIER3D_STATE_CHART_STRUCTURE_OCCUPIED] member=%s structure=%s" % [name, active_structure.name])
	return true

func _perform_autonomy_guard_sector() -> bool:
	_desired_velocity = Vector3.ZERO
	if not is_instance_valid(active_structure) or not active_structure.is_occupied_by(self):
		return _operation_elapsed >= 0.45
	active_structure.align_operator(self)
	var target := perception_component.find_best_hostile(true)
	if is_instance_valid(target) and active_structure.can_engage_target(target):
		current_target = target
		_face_position(target.global_position)
		active_structure.aim_at(target.global_position)
		if not is_pinned() and _operation_elapsed >= 0.2:
			if active_structure.has_fixed_weapon():
				active_structure.try_fixed_weapon_fire(self, target)
			else:
				is_aimed = true
				_try_attack_target(target)
	else:
		var sweep := sin(_operation_elapsed * 1.8) * minf(0.8, deg_to_rad(active_structure.firing_arc_degrees * 0.42))
		var forward: Vector3 = active_structure.global_transform.basis * Vector3.FORWARD
		_face_position(global_position + forward.rotated(Vector3.UP, sweep) * 8.0)
		_scan_for_hostiles()
	return _operation_elapsed >= 0.7

func _find_best_autonomy_structure(reserve_candidate: bool) -> TacticalStructure3D:
	if not autonomy_defensive_posture or has_active_directive() or is_instance_valid(active_structure):
		return null
	var registry := BattlefieldRegistry3D.find(get_tree())
	var candidates: Array = registry.get_structures() if registry != null else get_tree().get_nodes_in_group("tactical_structure3d")
	var best: TacticalStructure3D
	var best_score := -INF
	for candidate in candidates:
		if not candidate is TacticalStructure3D:
			continue
		var structure := candidate as TacticalStructure3D
		var score := structure.get_defense_score(self, _autonomy_defense_anchor)
		if score <= best_score:
			continue
		best = structure
		best_score = score
	if reserve_candidate and is_instance_valid(best):
		if not best.reserve(self):
			return null
		print("[SOLDIER3D_STATE_CHART_STRUCTURE_SELECT] member=%s structure=%s score=%.1f" % [name, best.name, best_score])
	return best

func set_autonomy_defensive_posture(enabled: bool, defense_anchor := Vector3.ZERO) -> void:
	autonomy_defensive_posture = enabled
	_autonomy_defense_anchor = defense_anchor
	if not enabled and is_instance_valid(_autonomy_structure_candidate) \
			and not is_instance_valid(active_structure):
		_autonomy_structure_candidate.release(self)
		_autonomy_structure_candidate = null

func debug_refresh_autonomy_context() -> void:
	state_chart_refresh_context()

func get_autonomy_debug_snapshot() -> Dictionary:
	var snapshot := _state_chart_controller.get_debug_snapshot() if _state_chart_controller != null else {}
	snapshot.merge({
		"environmental_danger": _environmental_danger,
		"current_risk": _environment_current_risk,
		"route_risk": _environment_route_risk,
		"cover_candidate": _autonomy_cover_candidate.name if is_instance_valid(_autonomy_cover_candidate) else "",
		"escape_available": _autonomy_escape_available,
		"escape_position": _autonomy_escape_position,
		"structure_candidate": _autonomy_structure_candidate.name if is_instance_valid(_autonomy_structure_candidate) else "",
	})
	return snapshot

func _find_emergency_cover() -> TacticalCover3D:
	var registry := BattlefieldRegistry3D.find(get_tree())
	var candidates: Array = registry.get_covers() if registry != null else get_tree().get_nodes_in_group("cover3d")
	var best: TacticalCover3D
	var best_score := -INF
	for candidate in candidates:
		if not candidate is TacticalCover3D:
			continue
		var cover := candidate as TacticalCover3D
		if _movement_constraint_enabled:
			var constraint_offset := cover.global_position - _movement_constraint_center
			constraint_offset.y = 0.0
			if constraint_offset.length() > _movement_constraint_radius:
				continue
		var distance := global_position.distance_to(cover.global_position)
		if distance > emergency_cover_max_distance:
			continue
		var reserved := cover.get_reserved_slot(self)
		if reserved != null and reserved not in cover.get_slots_against(_threat_position):
			continue
		if reserved == null and not _cover_has_reachable_slot(cover):
			continue
		var score := local_threat_field.score_cover(cover, _threat_position, weapon_component.effective_range * 0.72) \
			if local_threat_field != null else cover.score_for_actor(self, _threat_position, weapon_component.effective_range * 0.72)
		if score <= best_score:
			continue
		best = cover
		best_score = score
	return best

func set_movement_constraint(enabled: bool, center: Vector3, radius: float) -> void:
	_movement_constraint_enabled = enabled
	_movement_constraint_center = center
	_movement_constraint_radius = maxf(0.5, radius)

func _cover_has_reachable_slot(cover: TacticalCover3D) -> bool:
	if cover.get_available_slot_count_against(_threat_position) <= 0:
		return false
	var local_actor := cover.to_local(global_position)
	for slot in cover.get_slots_against(_threat_position):
		var local_slot := slot.position
		if absf(local_actor.z) > cover.cover_width * 0.5 and signf(local_actor.z) != signf(local_slot.z):
			continue
		return true
	return false

func _has_confirmed_visible_threat() -> bool:
	return is_instance_valid(_threat_actor) and is_hostile_target(_threat_actor) \
		and is_combat_target_alive(_threat_actor) and perception_component.can_see(_threat_actor)

func _has_known_cover_threat() -> bool:
	return is_instance_valid(active_cover) and is_instance_valid(_threat_actor) and is_hostile_target(_threat_actor) \
		and is_combat_target_alive(_threat_actor)

func _is_target_aiming_at_me() -> bool:
	if not is_instance_valid(_threat_actor) or not _threat_actor is Soldier3D:
		return false
	var hostile := _threat_actor as Soldier3D
	return hostile.current_target == self and (hostile.is_aimed or Time.get_ticks_msec() - hostile.last_weapon_fired_msec < 850)

func _abort_contact_response() -> void:
	_contact_response_complete = true

func _autonomy_operation_label(operation: SoldierStateChart3D.Action) -> String:
	match operation:
		SoldierStateChart3D.Action.SEEK_COVER:
			return "State Chart: emergency cover"
		SoldierStateChart3D.Action.DROP_PRONE:
			return "State Chart: take cover"
		SoldierStateChart3D.Action.RECOVER_MOVEMENT_POSTURE:
			return "State Chart: resume movement posture"
		SoldierStateChart3D.Action.FLINCH_AND_ASSESS:
			return "State Chart: react and assess"
		SoldierStateChart3D.Action.ORIENT_TO_THREAT:
			return "State Chart: orient to threat"
		SoldierStateChart3D.Action.COMMUNICATE_CONTACT:
			return "State Chart: report contact"
		SoldierStateChart3D.Action.ACQUIRE_VISIBLE_TARGET:
			return "State Chart: confirm target"
		SoldierStateChart3D.Action.AIM:
			return "State Chart: aim"
		SoldierStateChart3D.Action.RELOAD_COVERED, SoldierStateChart3D.Action.RELOAD_SAFE:
			return "State Chart: reload"
		SoldierStateChart3D.Action.RETURN_FIRE:
			return "State Chart: return fire"
		SoldierStateChart3D.Action.WAIT_FOR_OPENING:
			return "State Chart: wait under fire"
		SoldierStateChart3D.Action.SCAN_THREAT_SECTOR:
			return "State Chart: scan sector"
		SoldierStateChart3D.Action.GUARD_SECTOR:
			return "State Chart: maintain security"
		SoldierStateChart3D.Action.EVADE_DANGER:
			return "State Chart: leave danger area"
		SoldierStateChart3D.Action.ENTER_DEFENSIVE_STRUCTURE:
			return "State Chart: occupy defensive structure"
	return "State Chart: autonomous"

func _trace_autonomy(message: String) -> void:
	if OS.has_environment("STATE_CHART_TRACE"):
		print("[SOLDIER3D_STATE_CHART_TRACE] member=%s %s" % [name, message])

func _select_tactical_movement() -> void:
	if active_directive == null:
		set_movement_mode(MoveMode.WALK)
		return
	match active_directive.type:
		SquadDirective3D.Type.FLANK:
			set_movement_mode(MoveMode.RUN if stamina_component.can_run() and stamina > 8.0 else MoveMode.WALK)
		SquadDirective3D.Type.RECON:
			var zone := TacticalZone3D.find_at(get_tree(), active_directive.target_position)
			if zone != null and zone.concealment >= 0.5:
				set_movement_mode(MoveMode.QUIET)
			else:
				set_movement_mode(MoveMode.WALK)
		SquadDirective3D.Type.TAKE_COVER:
			if active_directive.reason.contains("伏击"):
				set_movement_mode(MoveMode.QUIET)
			elif _flat_distance_to(active_directive.target_position) > 6.0:
				set_movement_mode(MoveMode.RUN if stamina_component.can_run() and stamina > 8.0 else MoveMode.WALK)
			else:
				set_movement_mode(MoveMode.WALK)
		_:
			set_movement_mode(MoveMode.WALK)

func _select_tactical_stance() -> void:
	if active_directive == null:
		return
	if active_cover != null:
		set_stance(Stance.STAND)
		set_cover_exposed(false)
		return
	if active_directive.type in [SquadDirective3D.Type.FLANK, SquadDirective3D.Type.MOVE, SquadDirective3D.Type.TAKE_COVER]:
		set_stance(Stance.STAND)
	elif active_directive.type == SquadDirective3D.Type.RECON:
		set_stance(Stance.CROUCH)
	elif health <= int(max_health * 0.35) or (combat_role == CombatRole.MARKSMAN and active_directive.type == SquadDirective3D.Type.GUARD):
		set_stance(Stance.PRONE)
	else:
		set_stance(Stance.STAND)

func _update_stamina(delta: float, moving: bool) -> void:
	var running := movement_mode == MoveMode.RUN
	if stamina_component.process(delta, running, moving):
		stamina_changed.emit(self, stamina, stamina_component.maximum)
	if running and not stamina_component.can_run():
		set_movement_mode(MoveMode.WALK)

func _make_stance_shapes_unique() -> void:
	if collision.shape != null:
		collision.shape = collision.shape.duplicate()
	if body_hitbox_shape.shape != null:
		body_hitbox_shape.shape = body_hitbox_shape.shape.duplicate()

func _apply_stance_geometry() -> void:
	var actor_height := 1.8
	var body_height := 1.15
	var center_height := 0.9
	var body_center := 0.92
	var head_height := 1.7
	var visual_height := 1.0
	var visual_scale_y := 1.0
	var weapon_offset_y := 0.0
	match _get_effective_pose_stance():
		Stance.CROUCH:
			actor_height = 1.22
			body_height = 0.82
			center_height = 0.61
			body_center = 0.61
			head_height = 1.05
			visual_height = 0.68
			visual_scale_y = 0.72
			weapon_offset_y = -0.34
		Stance.PRONE:
			actor_height = 0.72
			body_height = 0.66
			center_height = 0.36
			body_center = 0.36
			head_height = 0.55
			visual_height = 0.39
			visual_scale_y = 0.45
			weapon_offset_y = -0.68
	if collision.shape is CapsuleShape3D:
		(collision.shape as CapsuleShape3D).height = actor_height
	if body_hitbox_shape.shape is CapsuleShape3D:
		(body_hitbox_shape.shape as CapsuleShape3D).height = body_height
	collision.position.y = center_height
	body_hitbox.position.y = body_center
	head_hitbox.position.y = head_height
	visual.position.y = visual_height
	visual.scale.y = visual_scale_y
	weapon_pivot.position.y = weapon_offset_y

func _get_aim_height() -> float:
	match _get_effective_pose_stance():
		Stance.CROUCH:
			return 0.98
		Stance.PRONE:
			return 0.5
	return 1.25

func _get_effective_pose_stance() -> Stance:
	if is_instance_valid(active_cover) and not cover_exposed:
		return Stance.CROUCH
	return stance

func _apply_team_visual() -> void:
	match combat_team:
		Team.PLAYER:
			team_display_name = "友军"
		Team.BLUE:
			team_display_name = "蓝队"
		_:
			team_display_name = "红队"
	visual.visible = false
	if voxel_visual != null:
		voxel_visual.configure(VoxelSoldierVisual3D.Faction.JAPANESE if combat_team == Team.RED else VoxelSoldierVisual3D.Faction.RED_ARMY)

func _face_position(position_value: Vector3) -> void:
	var direction := position_value - global_position
	direction.y = 0.0
	if direction == Vector3.ZERO:
		return
	logical_forward = direction.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-logical_forward.x, -logical_forward.z), 0.25)

func _flat_distance_to(position_value: Vector3) -> float:
	var delta := position_value - global_position
	delta.y = 0.0
	return delta.length()

func _flat_distance(first: Vector3, second: Vector3) -> float:
	var delta := first - second
	delta.y = 0.0
	return delta.length()

func _update_visual_animation(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length_squared() > 0.04
	if moving:
		_animation_time += delta
		visual.frame = int(_animation_time * 10.0) % maxi(1, visual.hframes)
	else:
		_animation_time = 0.0
		visual.frame = 0
	var using_fixed_weapon := is_instance_valid(active_structure) and active_structure.has_fixed_weapon()
	if weapon_model_root != null:
		weapon_model_root.visible = not using_fixed_weapon
	if voxel_visual != null:
		var structure_pose := 0
		var structure_entry_progress := 1.0
		if using_fixed_weapon:
			structure_pose = 1 if _structure_enter_animation_remaining > 0.0 else 2
			structure_entry_progress = clampf(1.0 - _structure_enter_animation_remaining / 0.48, 0.0, 1.0)
		voxel_visual.update_pose(
			delta,
			velocity,
			int(movement_mode),
			int(_get_effective_pose_stance()),
			is_aimed,
			Time.get_ticks_msec() - last_weapon_fired_msec < 110,
			dead,
			"bolt_rifle",
			false,
			structure_pose,
			structure_entry_progress
		)
	_structure_enter_animation_remaining = maxf(0.0, _structure_enter_animation_remaining - delta)

func _flash_hit() -> void:
	visual.modulate = Color(1.0, 0.25, 0.18)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.12)
	if voxel_visual != null:
		voxel_visual.play_hit()

func _operation_label(operation: SoldierStateChart3D.Action) -> String:
	if operation == SoldierStateChart3D.Action.ENTER_STRUCTURE:
		return "State Chart: enter defensive structure"
	if operation == SoldierStateChart3D.Action.OPERATE_STRUCTURE:
		return "State Chart: operate defensive structure"
	match operation:
		SoldierStateChart3D.Action.MOVE:
			return "State Chart: 安全移动"
		SoldierStateChart3D.Action.ENTER_COVER:
			return "State Chart: 进入掩体"
		SoldierStateChart3D.Action.ACQUIRE_TARGET:
			return "State Chart: 锁定目标"
		SoldierStateChart3D.Action.APPROACH_TARGET:
			return "State Chart: move to weapon range"
		SoldierStateChart3D.Action.AIM:
			return "State Chart: 稳定瞄准"
		SoldierStateChart3D.Action.RELOAD:
			return "State Chart: reload"
		SoldierStateChart3D.Action.ENGAGE:
			return "State Chart: 执行射击"
		SoldierStateChart3D.Action.GUARD:
			return "State Chart: 警戒扇区"
	return "State Chart: 待命"

func _update_status(action := "") -> void:
	if status_label == null:
		return
	var directive_label := active_directive.get_label() if active_directive != null else "自主警戒"
	var action_label := action if not action.is_empty() else ("完成" if active_directive != null and last_completed_directive_version == active_directive.version else "等待规划")
	status_label.text = "ID:%s\n%s%s｜%s\n%s" % [
		name,
		team_display_name,
		"[队长]" if is_squad_leader else "",
		directive_label,
		action_label,
	]
