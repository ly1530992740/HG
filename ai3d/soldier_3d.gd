extends CharacterBody3D
class_name Soldier3D

const DAMAGE_RULES_3D := preload("res://combat3d/combat_damage_rules_3d.gd")

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
@export var emergency_cover_max_distance := 8.0
@export var autonomy_return_fire_seconds := 0.9
@export var autonomy_scan_seconds := 1.2
@export var security_cycle_interval := 1.5
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
var active_directive: SquadDirective3D
var last_completed_directive_version := 0
var aware_of_enemy := false
var is_aimed := false
var fire_cooldown := 0.0
var dead := false
var is_squad_leader := false
var last_weapon_fired_msec := -100000
var stance: Stance = Stance.STAND
var movement_mode: MoveMode = MoveMode.WALK
var stamina: float:
	get: return stamina_component.current if is_instance_valid(stamina_component) else 0.0

var _goap_agent: GoapAgent
var _operation_elapsed := 0.0
var _route_index := 0
var _scan_timer := 0.0
var _reaction_timer := 0.0
var _desired_velocity := Vector3.ZERO
var _animation_time := 0.0
var _last_instigator: Node
var weapon_feedback_component: WeaponFeedback3D
var _threat_position := Vector3.ZERO
var _threat_memory_timer := 0.0
var _immediate_threat_timer := 0.0
var _threat_confidence := 0.0
var _threat_actor: Node3D
var _contact_response_complete := true
var _security_cycle_timer := 0.0
var _autonomy_cover_candidate: TacticalCover3D
var _autonomy_cover_slot: Marker3D
var _autonomy_operation_completed := false
var _movement_constraint_enabled := false
var _movement_constraint_center := Vector3.ZERO
var _movement_constraint_radius := 0.0

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
	weapon_feedback_component = WeaponFeedback3D.new()
	weapon_feedback_component.name = "WeaponFeedback"
	$Components.add_child(weapon_feedback_component)
	weapon_feedback_component.setup(self, weapon_model_root, muzzle, true)
	weapon_feedback_component.configure(weapon_component.definition)
	limb_damage_component.configure(self, voxel_visual)
	perception_component.configure(self)
	suppression_component.configure(self)
	_apply_team_visual()
	status_label.visible = show_status_label
	_setup_goap()
	_update_status()
	stamina_changed.emit(self, stamina, max_stamina)

func _physics_process(delta: float) -> void:
	if dead:
		return
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	_reaction_timer = maxf(0.0, _reaction_timer - delta)
	_threat_memory_timer = maxf(0.0, _threat_memory_timer - delta)
	_immediate_threat_timer = maxf(0.0, _immediate_threat_timer - delta)
	_security_cycle_timer = maxf(0.0, _security_cycle_timer - delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.22
		_scan_for_hostiles()
	_desired_velocity = Vector3.ZERO
	_select_tactical_movement()
	_sync_dynamic_goap_state()
	if _goap_agent != null:
		_goap_agent.process(delta)
	_update_stamina(delta, _desired_velocity.length_squared() > 0.01)
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = move_toward(velocity.x, _desired_velocity.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, _desired_velocity.z, 14.0 * delta)
	move_and_slide()
	_update_visual_animation(delta)

func receive_directive(directive: SquadDirective3D) -> void:
	if directive == null or directive.version <= get_directive_version():
		return
	var preserves_aim := is_aimed and active_directive != null \
		and active_directive.type == SquadDirective3D.Type.AIM \
		and directive.type in [SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.SUPPRESS] \
		and is_instance_valid(current_target) and current_target == directive.target
	var keeps_cover := directive.type in [SquadDirective3D.Type.TAKE_COVER, SquadDirective3D.Type.AIM, SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.SUPPRESS]
	if directive.type == SquadDirective3D.Type.TAKE_COVER and active_cover != directive.assigned_cover:
		if active_cover != null:
			active_cover.release_slot(self)
		active_cover = null
		active_cover_slot = null
	if active_cover != null and not keeps_cover:
		active_cover.release_slot(self)
		active_cover = null
		active_cover_slot = null
	active_directive = directive
	is_aimed = preserves_aim
	_route_index = 0
	_select_tactical_movement()
	_select_tactical_stance()
	if is_instance_valid(directive.target):
		current_target = directive.target
	elif not is_instance_valid(current_target):
		current_target = null
	var world := _goap_agent.get_world_state()
	world.set_state(&"directive_complete", 0)
	world.set_state(&"at_destination", false)
	world.set_state(&"in_cover", active_cover != null)
	world.set_state(&"target_acquired", false)
	world.set_state(&"in_weapon_range", _is_target_in_weapon_range(current_target) if is_instance_valid(current_target) else false)
	world.set_state(&"weapon_loaded", not uses_ammunition() or magazine_ammo > 0)
	world.set_state(&"aimed", preserves_aim)
	_goap_agent.request_replan()
	directive_changed.emit(self, directive)
	_update_status()

func has_active_directive() -> bool:
	return active_directive != null and active_directive.version > last_completed_directive_version

func get_active_directive() -> SquadDirective3D:
	return active_directive

func get_directive_version() -> int:
	return active_directive.version if active_directive != null else 0

func on_directive_plan_completed() -> void:
	if active_directive == null or last_completed_directive_version >= active_directive.version:
		return
	last_completed_directive_version = active_directive.version
	directive_completed.emit(self, active_directive)
	_update_status()

func begin_goap_operation(operation: SoldierDirectiveAction3D.Operation) -> void:
	_operation_elapsed = 0.0
	if operation == SoldierDirectiveAction3D.Operation.APPROACH_TARGET and active_cover != null:
		active_cover.release_slot(self)
		active_cover = null
		active_cover_slot = null
		set_stance(Stance.STAND)
	if operation in [SoldierDirectiveAction3D.Operation.MOVE, SoldierDirectiveAction3D.Operation.ENTER_COVER, SoldierDirectiveAction3D.Operation.APPROACH_TARGET]:
		is_aimed = false
	_update_status(_operation_label(operation))

func perform_goap_operation(operation: SoldierDirectiveAction3D.Operation, delta: float) -> bool:
	_operation_elapsed += delta
	match operation:
		SoldierDirectiveAction3D.Operation.MOVE:
			return _perform_move()
		SoldierDirectiveAction3D.Operation.ENTER_COVER:
			return _perform_enter_cover()
		SoldierDirectiveAction3D.Operation.ACQUIRE_TARGET:
			return _perform_acquire_target()
		SoldierDirectiveAction3D.Operation.APPROACH_TARGET:
			return _perform_approach_target()
		SoldierDirectiveAction3D.Operation.AIM:
			return _perform_aim()
		SoldierDirectiveAction3D.Operation.RELOAD:
			return _perform_reload()
		SoldierDirectiveAction3D.Operation.ENGAGE:
			return _perform_engage()
		SoldierDirectiveAction3D.Operation.GUARD:
			return _perform_guard()
		SoldierDirectiveAction3D.Operation.OBSERVE:
			return _perform_observe()
	return false

func end_goap_operation(_operation: SoldierDirectiveAction3D.Operation) -> void:
	_desired_velocity = Vector3.ZERO

func _perform_move() -> bool:
	if active_directive == null:
		return false
	var destination := active_directive.target_position
	if not active_directive.route.is_empty() and _route_index < active_directive.route.size():
		destination = active_directive.route[_route_index]
		if _flat_distance_to(destination) <= 0.55:
			_route_index += 1
			if _route_index < active_directive.route.size():
				destination = active_directive.route[_route_index]
	if _flat_distance_to(destination) <= 0.5:
		_desired_velocity = Vector3.ZERO
		return active_directive.route.is_empty() or _route_index >= active_directive.route.size()
	_move_toward(destination)
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
	active_cover = cover
	set_stance(Stance.CROUCH if cover.cover_height <= 1.45 else Stance.STAND)
	set_movement_mode(MoveMode.WALK)
	_desired_velocity = Vector3.ZERO
	return true

func _perform_acquire_target() -> bool:
	if active_directive != null and is_instance_valid(active_directive.target) and is_hostile_target(active_directive.target) \
		and (active_directive.type == SquadDirective3D.Type.SUPPRESS or perception_component.can_see(active_directive.target)):
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
	_move_toward(current_target.global_position)
	return false

func _perform_aim() -> bool:
	if not is_instance_valid(current_target):
		return false
	_face_position(current_target.global_position)
	var settle_time := 0.65 if combat_role == CombatRole.MARKSMAN else 0.38
	is_aimed = _operation_elapsed >= settle_time
	return is_aimed

func _perform_reload() -> bool:
	_desired_velocity = Vector3.ZERO
	if magazine_ammo > 0:
		return true
	if reserve_ammo <= 0:
		return false
	if _operation_elapsed < 1.4:
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
		_set_goap_state(&"target_acquired", false, true)
		_set_goap_state(&"aimed", false)
		return false
	_face_position(current_target.global_position)
	if _reaction_timer <= 0.0:
		_try_attack_target(current_target)
	if active_directive != null and active_directive.type == SquadDirective3D.Type.SUPPRESS:
		return _operation_elapsed >= maxf(1.5, active_directive.duration)
	return not is_instance_valid(current_target) or not is_combat_target_alive(current_target)

func _perform_guard() -> bool:
	_desired_velocity = Vector3.ZERO
	return _operation_elapsed >= 0.35

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
	direction = direction.normalized()
	logical_forward = direction
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 0.18)
	_desired_velocity = direction * get_current_move_speed()

func _try_attack_target(target: Node3D) -> bool:
	if fire_cooldown > 0.0 or target == null:
		return false
	if active_directive != null:
		if active_directive.rules_of_engagement == SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD and _immediate_threat_timer <= 0.0:
			return false
		if active_directive.rules_of_engagement == SquadDirective3D.RulesOfEngagement.RETURN_FIRE \
			and _immediate_threat_timer <= 0.0 and not perception_component.can_see(target):
			return false
	if not weapon_component.is_target_in_range(self, target):
		return false
	if weapon_component.uses_ammunition() and weapon_component.magazine_ammo <= 0:
		_set_goap_state(&"weapon_loaded", false, true)
		return false
	if not weapon_component.try_attack(self, target, _get_fire_origin()):
		return false
	if weapon_feedback_component != null:
		var direction := (weapon_component.get_target_point(target) - _get_fire_origin()).normalized()
		weapon_feedback_component.play_fire(direction, weapon_component.last_hit_result)
	last_weapon_fired_msec = Time.get_ticks_msec()
	if weapon_component.uses_ammunition() and weapon_component.magazine_ammo <= 0:
		_set_goap_state(&"weapon_loaded", false, true)
	fire_cooldown = weapon_component.shot_cooldown
	aware_of_enemy = true
	get_tree().call_group("soldier3d", "hear_combat_sound", global_position, self, 1.0)
	weapon_fired.emit(self, target)
	return true

func _get_fire_origin() -> Vector3:
	if active_cover != null:
		return global_position + Vector3.UP * (active_cover.cover_height + 0.18)
	return muzzle.global_position

func _scan_for_hostiles() -> void:
	var hostile := perception_component.find_best_hostile(true)
	if hostile == null:
		return
	_register_autonomy_threat(hostile.global_position, hostile, 1.0, true)
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
		current_target = instigator
		_register_autonomy_threat((instigator as Node3D).global_position, instigator, 1.0, true)
		contact_spotted.emit(self, instigator)
		perception_report_ready.emit(self, instigator, (instigator as Node3D).global_position, 1.0, &"damage")
	else:
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
	_register_autonomy_threat(source_position, instigator if instigator is Node3D else null, 0.95, true)
	if suppression_component != null:
		suppression_component.report_near_miss(source_position, intensity)
	perception_report_ready.emit(self, instigator as Node3D if instigator is Node3D else null, source_position, 0.9, &"near_miss")

func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * _get_aim_height()

func set_stance(new_stance: Stance) -> void:
	if stance == new_stance:
		return
	stance = new_stance
	if stance != Stance.STAND and movement_mode == MoveMode.RUN:
		set_movement_mode(MoveMode.WALK)
	_apply_stance_geometry()
	stance_changed.emit(self, stance)
	_update_status()

func set_movement_mode(new_mode: MoveMode) -> void:
	if new_mode == MoveMode.RUN and (stance != Stance.STAND or not stamina_component.can_run()):
		new_mode = MoveMode.WALK
	if movement_mode == new_mode:
		return
	movement_mode = new_mode
	movement_mode_changed.emit(self, movement_mode)
	_update_status()

func get_current_move_speed() -> float:
	match stance:
		Stance.CROUCH:
			return crouch_speed
		Stance.PRONE:
			return prone_speed
	match movement_mode:
		MoveMode.RUN:
			return run_speed
		MoveMode.QUIET:
			return quiet_speed
	return move_speed

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

func get_stance_label() -> String:
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
	velocity = Vector3.ZERO
	if active_cover != null:
		active_cover.release_slot(self)
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

func _setup_goap() -> void:
	var goals := Node.new()
	goals.name = "Goals"
	add_child(goals)
	for kind in SoldierAutonomyGoal3D.Kind.values():
		var autonomy_goal := SoldierAutonomyGoal3D.new()
		autonomy_goal.kind = kind
		autonomy_goal.name = SoldierAutonomyGoal3D.Kind.keys()[kind]
		goals.add_child(autonomy_goal)
	var directive_goal := SoldierDirectiveGoal3D.new()
	directive_goal.name = "执行小队指令"
	goals.add_child(directive_goal)
	var actions := Node.new()
	actions.name = "Actions"
	add_child(actions)
	for operation in SoldierDirectiveAction3D.Operation.values():
		var action := SoldierDirectiveAction3D.new()
		action.operation = operation
		action.name = SoldierDirectiveAction3D.Operation.keys()[operation]
		actions.add_child(action)
	for operation in SoldierAutonomyAction3D.Operation.values():
		var autonomy_action := SoldierAutonomyAction3D.new()
		autonomy_action.operation = operation
		autonomy_action.name = "AUTONOMY_%s" % SoldierAutonomyAction3D.Operation.keys()[operation]
		actions.add_child(autonomy_action)
	_goap_agent = GoapAgent.new()
	_goap_agent.name = "GoapAgent"
	_goap_agent.goals_node = goals
	_goap_agent.actions_node = actions
	_goap_agent.debug_enabled = false
	_goap_agent.replan_on_world_state_change = false
	add_child(_goap_agent)
	_goap_agent.init(self)
	var world := _goap_agent.get_world_state()
	world.set_state(&"directive_complete", 0)
	world.set_state(&"at_destination", false)
	world.set_state(&"in_cover", false)
	world.set_state(&"target_acquired", false)
	world.set_state(&"in_weapon_range", false)
	world.set_state(&"weapon_loaded", not uses_ammunition() or magazine_ammo > 0)
	world.set_state(&"aimed", false)
	world.set_state(&"immediate_threat", false)
	world.set_state(&"protected_from_threat", false)
	world.set_state(&"safe_posture", false)
	world.set_state(&"oriented_to_threat", false)
	world.set_state(&"contact_response_complete", true)
	world.set_state(&"security_cycle_complete", false)

func uses_ammunition() -> bool:
	return weapon_component.uses_ammunition()

func can_reload_weapon() -> bool:
	return weapon_component.can_reload()

func _is_target_in_weapon_range(target: Node3D) -> bool:
	if not is_instance_valid(target) or not is_combat_target_alive(target):
		return false
	return weapon_component.is_target_in_range(self, target)

func _sync_dynamic_goap_state() -> void:
	if _goap_agent == null:
		return
	if _threat_memory_timer <= 0.0 and _threat_confidence > 0.0:
		_threat_confidence = 0.0
		_threat_actor = null
		_contact_response_complete = true
		_set_goap_state(&"oriented_to_threat", false)
		_set_goap_state(&"target_acquired", false)
		_set_goap_state(&"contact_response_complete", true)
	if _security_cycle_timer <= 0.0 \
		and bool(_goap_agent.get_world_state().get_state(&"security_cycle_complete", false)):
		_set_goap_state(&"security_cycle_complete", false, true)
	_set_goap_state(&"weapon_loaded", not uses_ammunition() or magazine_ammo > 0)
	if is_instance_valid(current_target) and is_combat_target_alive(current_target):
		_set_goap_state(&"in_weapon_range", _is_target_in_weapon_range(current_target), true)
	_set_goap_state(&"immediate_threat", _immediate_threat_timer > 0.0)
	_set_goap_state(&"protected_from_threat", _is_protected_from_threat())
	_set_goap_state(&"safe_posture", active_cover != null or stance == Stance.PRONE)
	_set_goap_state(&"contact_response_complete", _contact_response_complete)

func _set_goap_state(key: StringName, value: Variant, request_replan := false) -> void:
	if _goap_agent == null:
		return
	var world := _goap_agent.get_world_state()
	if world.get_state(key) == value:
		return
	world.set_state(key, value)
	if request_replan:
		_goap_agent.request_replan()

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
	_set_goap_state(&"immediate_threat", _immediate_threat_timer > 0.0)
	_set_goap_state(&"protected_from_threat", _is_protected_from_threat())
	if not starts_new_response:
		return
	if immediate:
		_reaction_timer = maxf(_reaction_timer, reaction_delay)
	_contact_response_complete = false
	_set_goap_state(&"oriented_to_threat", false)
	_set_goap_state(&"target_acquired", false)
	_set_goap_state(&"aimed", false)
	_set_goap_state(&"contact_response_complete", false)
	_set_goap_state(&"security_cycle_complete", false)
	if _goap_agent != null:
		_goap_agent.request_replan()

func _is_protected_from_threat() -> bool:
	if stance == Stance.PRONE:
		return true
	if not is_instance_valid(active_cover) or not is_instance_valid(active_cover_slot):
		return false
	if _flat_distance_to(active_cover_slot.global_position) > 0.9:
		return false
	return active_cover_slot in active_cover.get_slots_against(_threat_position)

func is_autonomy_goal_valid(kind: SoldierAutonomyGoal3D.Kind) -> bool:
	match kind:
		SoldierAutonomyGoal3D.Kind.SURVIVE_THREAT:
			return _immediate_threat_timer > 0.0 and not _is_protected_from_threat()
		SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT:
			return not has_active_directive() and _threat_memory_timer > 0.0 and not _contact_response_complete
		SoldierAutonomyGoal3D.Kind.RESTORE_WEAPON:
			return uses_ammunition() and magazine_ammo <= 0 and reserve_ammo > 0 \
				and (_immediate_threat_timer <= 0.0 or _is_protected_from_threat())
		SoldierAutonomyGoal3D.Kind.MAINTAIN_SECURITY:
			return not has_active_directive() and _threat_memory_timer <= 0.0 \
				and _security_cycle_timer <= 0.0 \
				and not bool(_goap_agent.get_world_state().get_state(&"security_cycle_complete", false))
	return false

func get_autonomy_goal_priority(kind: SoldierAutonomyGoal3D.Kind) -> int:
	match kind:
		SoldierAutonomyGoal3D.Kind.SURVIVE_THREAT:
			return 300
		SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT:
			return 180
		SoldierAutonomyGoal3D.Kind.RESTORE_WEAPON:
			return 130
		SoldierAutonomyGoal3D.Kind.MAINTAIN_SECURITY:
			return 10
	return 0

func prepare_autonomy_goal(kind: SoldierAutonomyGoal3D.Kind) -> void:
	if kind in [SoldierAutonomyGoal3D.Kind.SURVIVE_THREAT, SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT] \
		and _immediate_threat_timer > 0.0 and not _is_protected_from_threat():
		_autonomy_cover_candidate = _find_emergency_cover()
	else:
		_autonomy_cover_candidate = null

func on_autonomy_goal_achieved(kind: SoldierAutonomyGoal3D.Kind) -> void:
	match kind:
		SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT:
			_contact_response_complete = true
			is_aimed = false
		SoldierAutonomyGoal3D.Kind.MAINTAIN_SECURITY:
			_security_cycle_timer = security_cycle_interval
	_update_status()

func is_autonomy_action_valid(operation: SoldierAutonomyAction3D.Operation) -> bool:
	if _goap_agent == null or not _goap_agent.get_current_goal() is SoldierAutonomyGoal3D:
		return false
	var goal := _goap_agent.get_current_goal() as SoldierAutonomyGoal3D
	match operation:
		SoldierAutonomyAction3D.Operation.SEEK_COVER:
			return goal.kind in [SoldierAutonomyGoal3D.Kind.SURVIVE_THREAT, SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT] \
				and _immediate_threat_timer > 0.0 and not _is_protected_from_threat() \
				and is_instance_valid(_autonomy_cover_candidate)
		SoldierAutonomyAction3D.Operation.DROP_PRONE:
			return goal.kind in [SoldierAutonomyGoal3D.Kind.SURVIVE_THREAT, SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT] \
				and _immediate_threat_timer > 0.0 and not _is_protected_from_threat()
		SoldierAutonomyAction3D.Operation.ORIENT_TO_THREAT:
			return _threat_memory_timer > 0.0
		SoldierAutonomyAction3D.Operation.ACQUIRE_VISIBLE_TARGET, SoldierAutonomyAction3D.Operation.AIM:
			return goal.kind == SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT and _has_confirmed_visible_threat()
		SoldierAutonomyAction3D.Operation.RELOAD_COVERED:
			return goal.kind == SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT and uses_ammunition() \
				and magazine_ammo <= 0 and reserve_ammo > 0
		SoldierAutonomyAction3D.Operation.RELOAD_SAFE:
			return goal.kind == SoldierAutonomyGoal3D.Kind.RESTORE_WEAPON and can_reload_weapon()
		SoldierAutonomyAction3D.Operation.RETURN_FIRE:
			return goal.kind == SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT \
				and _has_confirmed_visible_threat() and _is_target_in_weapon_range(_threat_actor)
		SoldierAutonomyAction3D.Operation.SCAN_THREAT_SECTOR:
			return goal.kind == SoldierAutonomyGoal3D.Kind.RESPOND_TO_CONTACT and _threat_memory_timer > 0.0
		SoldierAutonomyAction3D.Operation.GUARD_SECTOR:
			return goal.kind == SoldierAutonomyGoal3D.Kind.MAINTAIN_SECURITY
	return false

func get_autonomy_action_cost(operation: SoldierAutonomyAction3D.Operation) -> int:
	match operation:
		SoldierAutonomyAction3D.Operation.SEEK_COVER:
			return 2 + ceili(global_position.distance_to(_autonomy_cover_candidate.global_position)) \
				if is_instance_valid(_autonomy_cover_candidate) else 100
		SoldierAutonomyAction3D.Operation.DROP_PRONE:
			return 18 if is_instance_valid(_autonomy_cover_candidate) else 3
		SoldierAutonomyAction3D.Operation.ORIENT_TO_THREAT, SoldierAutonomyAction3D.Operation.ACQUIRE_VISIBLE_TARGET:
			return 1
		SoldierAutonomyAction3D.Operation.AIM:
			return 2
		SoldierAutonomyAction3D.Operation.RELOAD_COVERED, SoldierAutonomyAction3D.Operation.RELOAD_SAFE:
			return 5
		SoldierAutonomyAction3D.Operation.RETURN_FIRE:
			return 3
		SoldierAutonomyAction3D.Operation.SCAN_THREAT_SECTOR:
			return 24 if _has_confirmed_visible_threat() and _is_target_in_weapon_range(_threat_actor) else 3
		SoldierAutonomyAction3D.Operation.GUARD_SECTOR:
			return 1
	return 10

func begin_autonomy_operation(operation: SoldierAutonomyAction3D.Operation) -> void:
	_operation_elapsed = 0.0
	_autonomy_operation_completed = false
	_desired_velocity = Vector3.ZERO
	if operation == SoldierAutonomyAction3D.Operation.SEEK_COVER:
		is_aimed = false
		if is_instance_valid(active_cover) and not _is_protected_from_threat():
			active_cover.release_slot(self)
			active_cover = null
			active_cover_slot = null
		if is_instance_valid(_autonomy_cover_candidate):
			_autonomy_cover_slot = _autonomy_cover_candidate.reserve_reachable_slot(self, _threat_position)
	else:
		_autonomy_cover_slot = null
	_update_status(_autonomy_operation_label(operation))

func perform_autonomy_operation(operation: SoldierAutonomyAction3D.Operation, delta: float) -> bool:
	_operation_elapsed += delta
	match operation:
		SoldierAutonomyAction3D.Operation.SEEK_COVER:
			if not is_instance_valid(_autonomy_cover_candidate) or not is_instance_valid(_autonomy_cover_slot):
				set_stance(Stance.PRONE)
				_autonomy_operation_completed = true
				return true
			set_stance(Stance.STAND)
			set_movement_mode(MoveMode.RUN if stamina_component.can_run() else MoveMode.WALK)
			if _flat_distance_to(_autonomy_cover_slot.global_position) > 0.45:
				_move_toward(_autonomy_cover_slot.global_position)
				return false
			global_position = _autonomy_cover_slot.global_position
			active_cover = _autonomy_cover_candidate
			active_cover_slot = _autonomy_cover_slot
			set_stance(Stance.CROUCH if active_cover.cover_height <= 1.45 else Stance.STAND)
			set_movement_mode(MoveMode.WALK)
			_desired_velocity = Vector3.ZERO
			_autonomy_operation_completed = true
			return true
		SoldierAutonomyAction3D.Operation.DROP_PRONE:
			_desired_velocity = Vector3.ZERO
			set_stance(Stance.PRONE)
			_autonomy_operation_completed = true
			return true
		SoldierAutonomyAction3D.Operation.ORIENT_TO_THREAT:
			_desired_velocity = Vector3.ZERO
			_face_position(_threat_position)
			_autonomy_operation_completed = _operation_elapsed >= 0.2
			return _autonomy_operation_completed
		SoldierAutonomyAction3D.Operation.ACQUIRE_VISIBLE_TARGET:
			if _has_confirmed_visible_threat():
				current_target = _threat_actor
				aware_of_enemy = true
				_autonomy_operation_completed = true
				return true
			_abort_contact_response()
			return false
		SoldierAutonomyAction3D.Operation.AIM:
			if not _has_confirmed_visible_threat():
				_abort_contact_response()
				return false
			_autonomy_operation_completed = _perform_aim()
			return _autonomy_operation_completed
		SoldierAutonomyAction3D.Operation.RELOAD_COVERED, SoldierAutonomyAction3D.Operation.RELOAD_SAFE:
			_autonomy_operation_completed = _perform_reload()
			return _autonomy_operation_completed
		SoldierAutonomyAction3D.Operation.RETURN_FIRE:
			_desired_velocity = Vector3.ZERO
			if not _has_confirmed_visible_threat() or not _is_target_in_weapon_range(_threat_actor):
				_autonomy_operation_completed = true
				return true
			current_target = _threat_actor
			_face_position(current_target.global_position)
			if _reaction_timer <= 0.0:
				_try_attack_target(current_target)
			_autonomy_operation_completed = _operation_elapsed >= autonomy_return_fire_seconds \
				or not is_combat_target_alive(current_target)
			return _autonomy_operation_completed
		SoldierAutonomyAction3D.Operation.SCAN_THREAT_SECTOR:
			_desired_velocity = Vector3.ZERO
			_face_position(_threat_position)
			_autonomy_operation_completed = _operation_elapsed >= autonomy_scan_seconds
			return _autonomy_operation_completed
		SoldierAutonomyAction3D.Operation.GUARD_SECTOR:
			_desired_velocity = Vector3.ZERO
			_autonomy_operation_completed = _operation_elapsed >= 0.45
			return _autonomy_operation_completed
	return false

func end_autonomy_operation(operation: SoldierAutonomyAction3D.Operation) -> void:
	_desired_velocity = Vector3.ZERO
	if operation == SoldierAutonomyAction3D.Operation.SEEK_COVER \
		and not _autonomy_operation_completed and is_instance_valid(_autonomy_cover_candidate):
		_autonomy_cover_candidate.release_slot(self)
		_autonomy_cover_slot = null

func _find_emergency_cover() -> TacticalCover3D:
	var registry := BattlefieldRegistry3D.find(get_tree())
	var candidates: Array = registry.get_covers() if registry != null else get_tree().get_nodes_in_group("cover3d")
	var best: TacticalCover3D
	var best_distance := INF
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
		if distance > emergency_cover_max_distance or distance >= best_distance:
			continue
		var reserved := cover.get_reserved_slot(self)
		if reserved != null and reserved not in cover.get_slots_against(_threat_position):
			continue
		if reserved == null and not _cover_has_reachable_slot(cover):
			continue
		best = cover
		best_distance = distance
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

func _abort_contact_response() -> void:
	_contact_response_complete = true
	_set_goap_state(&"contact_response_complete", true)
	if _goap_agent != null:
		_goap_agent.request_replan()

func _autonomy_operation_label(operation: SoldierAutonomyAction3D.Operation) -> String:
	match operation:
		SoldierAutonomyAction3D.Operation.SEEK_COVER:
			return "GOAP: emergency cover"
		SoldierAutonomyAction3D.Operation.DROP_PRONE:
			return "GOAP: take cover"
		SoldierAutonomyAction3D.Operation.ORIENT_TO_THREAT:
			return "GOAP: orient to threat"
		SoldierAutonomyAction3D.Operation.ACQUIRE_VISIBLE_TARGET:
			return "GOAP: confirm target"
		SoldierAutonomyAction3D.Operation.AIM:
			return "GOAP: aim"
		SoldierAutonomyAction3D.Operation.RELOAD_COVERED, SoldierAutonomyAction3D.Operation.RELOAD_SAFE:
			return "GOAP: reload"
		SoldierAutonomyAction3D.Operation.RETURN_FIRE:
			return "GOAP: return fire"
		SoldierAutonomyAction3D.Operation.SCAN_THREAT_SECTOR:
			return "GOAP: scan sector"
		SoldierAutonomyAction3D.Operation.GUARD_SECTOR:
			return "GOAP: maintain security"
	return "GOAP: autonomous"

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
		set_stance(Stance.CROUCH if active_cover.cover_height <= 1.45 else Stance.STAND)
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
	match stance:
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
	match stance:
		Stance.CROUCH:
			return 0.98
		Stance.PRONE:
			return 0.5
	return 1.25

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

func _update_visual_animation(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length_squared() > 0.04
	if moving:
		_animation_time += delta
		visual.frame = int(_animation_time * 10.0) % maxi(1, visual.hframes)
	else:
		_animation_time = 0.0
		visual.frame = 0
	if voxel_visual != null:
		voxel_visual.update_pose(delta, velocity, int(movement_mode), int(stance), is_aimed, Time.get_ticks_msec() - last_weapon_fired_msec < 110, dead)

func _flash_hit() -> void:
	visual.modulate = Color(1.0, 0.25, 0.18)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.12)
	if voxel_visual != null:
		voxel_visual.play_hit()

func _operation_label(operation: SoldierDirectiveAction3D.Operation) -> String:
	match operation:
		SoldierDirectiveAction3D.Operation.MOVE:
			return "GOAP：安全移动"
		SoldierDirectiveAction3D.Operation.ENTER_COVER:
			return "GOAP：进入掩体"
		SoldierDirectiveAction3D.Operation.ACQUIRE_TARGET:
			return "GOAP：锁定目标"
		SoldierDirectiveAction3D.Operation.APPROACH_TARGET:
			return "GOAP: move to weapon range"
		SoldierDirectiveAction3D.Operation.AIM:
			return "GOAP：稳定瞄准"
		SoldierDirectiveAction3D.Operation.RELOAD:
			return "GOAP: reload"
		SoldierDirectiveAction3D.Operation.ENGAGE:
			return "GOAP：执行射击"
		SoldierDirectiveAction3D.Operation.GUARD:
			return "GOAP：警戒扇区"
	return "GOAP：待命"

func _update_status(action := "") -> void:
	if status_label == null:
		return
	var directive_label := active_directive.get_label() if active_directive != null else "自主警戒"
	var action_label := action if not action.is_empty() else ("完成" if active_directive != null and last_completed_directive_version == active_directive.version else "等待规划")
	status_label.text = "%s%s｜%s\n%s" % [team_display_name, "[队长]" if is_squad_leader else "", directive_label, action_label]
