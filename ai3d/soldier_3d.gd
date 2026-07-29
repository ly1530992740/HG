extends CharacterBody3D
class_name Soldier3D

signal died(actor: Soldier3D)
signal health_changed(current: int, maximum: int)
signal contact_spotted(actor: Soldier3D, hostile: Node3D)
signal directive_changed(actor: Soldier3D, directive: SquadDirective3D)
signal directive_completed(actor: Soldier3D, directive: SquadDirective3D)
signal weapon_fired(actor: Soldier3D, target: Node3D)
signal stamina_changed(actor: Soldier3D, current: float, maximum: float)
signal stance_changed(actor: Soldier3D, stance: Stance)
signal movement_mode_changed(actor: Soldier3D, mode: MoveMode)
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
@export var initially_aware := false
@export var awards_player_score := true
@export var score_reward := 1
@export var drops_ammo_on_death := true
@export_range(0, 200, 1) var dropped_ammo_amount := 18

@onready var visual: Sprite3D = $Visual
@onready var collision: CollisionShape3D = $Collision
@onready var muzzle: Marker3D = $WeaponPivot/Muzzle
@onready var body_hitbox: Area3D = $BodyHitbox
@onready var body_hitbox_shape: CollisionShape3D = $BodyHitbox/Shape
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var status_label: Label3D = $StatusLabel
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var weapon_component: SoldierWeaponComponent3D = $Components/Weapon
@onready var perception_component: SoldierPerceptionComponent3D = $Components/Perception
@onready var health_component: HealthComponent3D = $Components/Health
@onready var stamina_component: StaminaComponent3D = $Components/Stamina

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
	weapon_component.configure(combat_role)
	perception_component.configure(self)
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
	if active_directive != null and is_instance_valid(active_directive.target) and is_hostile_target(active_directive.target):
		current_target = active_directive.target
	elif not is_instance_valid(current_target):
		current_target = perception_component.find_best_hostile(false)
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
	return weapon_component.reload()

func _perform_engage() -> bool:
	if not is_instance_valid(current_target) or not is_combat_target_alive(current_target):
		return true
	_face_position(current_target.global_position)
	if _reaction_timer <= 0.0:
		_try_attack_target(current_target)
	if active_directive != null and active_directive.type == SquadDirective3D.Type.SUPPRESS:
		return _operation_elapsed >= maxf(1.5, active_directive.duration)
	return not is_instance_valid(current_target) or not is_combat_target_alive(current_target)

func _perform_guard() -> bool:
	_desired_velocity = Vector3.ZERO
	return _operation_elapsed >= 0.35

func _move_toward(destination: Vector3) -> void:
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
	if not weapon_component.is_target_in_range(self, target):
		return false
	if weapon_component.uses_ammunition() and weapon_component.magazine_ammo <= 0:
		_set_goap_state(&"weapon_loaded", false, true)
		return false
	if not weapon_component.try_attack(self, target, _get_fire_origin()):
		return false
	if weapon_component.uses_ammunition() and weapon_component.magazine_ammo <= 0:
		_set_goap_state(&"weapon_loaded", false, true)
	fire_cooldown = weapon_component.shot_cooldown
	aware_of_enemy = true
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
	current_target = hostile
	aware_of_enemy = true
	contact_spotted.emit(self, hostile)

func receive_hit(damage: int, _hit_location: String, _hit_position: Vector3, instigator: Node) -> void:
	if dead or damage <= 0:
		return
	if not health_component.apply_damage(damage):
		return
	_last_instigator = instigator
	aware_of_enemy = true
	_reaction_timer = reaction_delay
	if instigator is Node3D and is_hostile_target(instigator):
		current_target = instigator
		contact_spotted.emit(self, instigator)
	health_changed.emit(health, health_component.maximum)
	if health <= 0:
		_die()
	else:
		_flash_hit()

func apply_reaction_delay(seconds: float) -> void:
	_reaction_timer = maxf(_reaction_timer, maxf(0.0, seconds))

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
	return multiplier

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
	visible = false
	collision.disabled = true
	set_physics_process(false)
	await get_tree().create_timer(0.35).timeout
	queue_free()

func _setup_goap() -> void:
	var goals := Node.new()
	goals.name = "Goals"
	add_child(goals)
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

func uses_ammunition() -> bool:
	return weapon_component.uses_ammunition()

func can_reload_weapon() -> bool:
	return weapon_component.can_reload()

func _is_target_in_weapon_range(target: Node3D) -> bool:
	if not is_instance_valid(target) or not is_combat_target_alive(target):
		return false
	return weapon_component.is_target_in_range(self, target)

func _sync_dynamic_goap_state() -> void:
	if _goap_agent == null or active_directive == null:
		return
	_set_goap_state(&"weapon_loaded", not uses_ammunition() or magazine_ammo > 0)
	if is_instance_valid(current_target) and is_combat_target_alive(current_target):
		_set_goap_state(&"in_weapon_range", _is_target_in_weapon_range(current_target), true)

func _set_goap_state(key: StringName, value: Variant, request_replan := false) -> void:
	if _goap_agent == null:
		return
	var world := _goap_agent.get_world_state()
	if world.get_state(key) == value:
		return
	world.set_state(key, value)
	if request_replan:
		_goap_agent.request_replan()

func _select_tactical_movement() -> void:
	if active_directive == null:
		set_movement_mode(MoveMode.WALK)
		return
	match active_directive.type:
		SquadDirective3D.Type.FLANK:
			set_movement_mode(MoveMode.RUN if stamina_component.can_run() and stamina > 8.0 else MoveMode.WALK)
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
	var color_name := "Red"
	match combat_team:
		Team.PLAYER:
			color_name = "Blue"
			team_display_name = "友军"
		Team.BLUE:
			color_name = "Blue"
			team_display_name = "蓝队"
		_:
			color_name = "Red"
			team_display_name = "红队"
	var path := "res://Textures/new/Units/%s Units/Pawn/Pawn_Idle.png" % color_name
	var texture := load(path) as Texture2D
	if texture != null:
		visual.texture = texture

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

func _flash_hit() -> void:
	visual.modulate = Color(1.0, 0.25, 0.18)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.12)

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
	status_label.text = "%s｜%s\n%s" % [team_display_name, directive_label, action_label]
