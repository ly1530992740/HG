extends CharacterBody2D
class_name GoblinBase

signal died(actor: Node)
signal projectile_hit_resolved(victim: Node, shooter: Node, location: int, fatal: bool, damage: int)

enum State { IDLE, CHASE, ATTACK, HIT, DEAD }

static var reserved_targets: Dictionary = {}
static var active_enemies: Array[CharacterBody2D] = []

const MAX_ATTACKERS_PER_TARGET := 2
const STEAL_DISTANCE := 80.0
const SEPARATION_RADIUS := 120.0
const SEPARATION_FORCE := 140.0
const DETOUR_DISTANCE := 60.0

@export var max_health := 6
@export var health := 6
@export var SPEED := 220.0
@export var STOP_DISTANCE := 130.0
@export var ATTACK_DISTANCE := 80.0
@export var KNOCKBACK_FORCE := 300.0
@export var KNOCKBACK_DECAY := 0.85
@export var target_groups: Array[String] = ["player", "castle", "building"]
@export var squad_id: StringName = &"default"
@export var will_profile: WillComponent.Profile = WillComponent.Profile.REGULAR
@export var lock_steady_morale := false
@export var combat_team: StringName = &"hostile"
@export var can_target_players := true
@export var team_display_name := "敌军"
@export var team_color := Color(0.72, 0.16, 0.16, 1.0)
@export var initial_facing_direction := Vector2.RIGHT
@export var death_cleanup_delay := 0.0
@export var death_audio_enabled := true

@onready var anim: AnimatedSprite2D = get_node_or_null("anim")
@onready var nav: NavigationAgent2D = get_node_or_null("NavigationAgent2D")
@onready var hurt_timer: Timer = get_node_or_null("hurt")
@onready var flash_timer: Timer = get_node_or_null("flash")
@onready var predictcast: ShapeCast2D = get_node_or_null("PredictCast")
@onready var hit_audio: AudioStreamPlayer = get_node_or_null("sound fx/hit_sword_audio")
@onready var death_audio: AudioStreamPlayer = get_node_or_null("sound fx/death_audio")

var state: State = State.IDLE
var knockback_velocity := Vector2.ZERO
var is_flashing := false
var targets: Array[Node2D] = []
var current_target: Node2D = null
var last_move_dir := Vector2.DOWN
var stuck_timer := 0.0
var stuck_threshold := 0.3
var last_position := Vector2.ZERO
var cover_user: CoverUser
var squad_member: SquadMember
var will_component: WillComponent
var suppression_component: SuppressionComponent
var injury_component: InjuryComponent
var alert_component: AlertComponent
var perception_component: PerceptionComponent
var aim_component: AimComponent
var concealment_component: ConcealmentComponent
var direct_threat_timer := 0.0

func _ready() -> void:
	z_index = 3
	add_to_group("goblin")
	add_to_group("combatant")
	health = max_health
	active_enemies.append(self)
	last_move_dir = initial_facing_direction.normalized() if initial_facing_direction != Vector2.ZERO else Vector2.RIGHT
	_setup_cover_user()
	_setup_perception_components()
	_setup_squad_member()
	_setup_will_component()
	_setup_suppression_component()
	_setup_injury_component()
	_setup_aim_component()
	_setup_concealment_component()

	if nav:
		nav.path_desired_distance = 6.0
		nav.target_desired_distance = 6.0

	recheck_targets()

func _exit_tree() -> void:
	if cover_user:
		cover_user.exit_cover()
	active_enemies.erase(self)
	release_target()
	rebalance_pack()
	cleanup_reserved_targets()

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	direct_threat_timer = maxf(0.0, direct_threat_timer - delta)
	if concealment_component:
		concealment_component.process(delta)
	if aim_component:
		aim_component.process(delta, velocity.length_squared() > 25.0)

	if knockback_velocity.length() > 1.0:
		velocity = knockback_velocity
		knockback_velocity *= KNOCKBACK_DECAY
	else:
		knockback_velocity = Vector2.ZERO

	if state == State.IDLE or state == State.ATTACK:
		recheck_targets()

	validate_target()

	match state:
		State.IDLE:
			idle_state()
		State.CHASE:
			chase_state()
		State.ATTACK:
			attack_state()
		State.HIT:
			hit_state()

	if cover_user and cover_user.is_in_cover():
		cover_user.maintain_position()
	else:
		if state in [State.IDLE, State.CHASE]:
			velocity += separation_vector() * SEPARATION_FORCE
			detect_stuck(delta)
		avoid_obstacles(delta)
	if velocity.length_squared() > 1.0:
		last_move_dir = velocity.normalized()
	move_and_slide()

func idle_state() -> void:
	velocity = Vector2.ZERO
	if anim:
		anim.play("idle")

func chase_state() -> void:
	if not validate_target():
		return

	var distance_to_target := global_position.distance_to(current_target.global_position)
	if distance_to_target <= STOP_DISTANCE or distance_to_target <= ATTACK_DISTANCE:
		state = State.ATTACK
		return

	var direction := (current_target.global_position - global_position).normalized()
	if nav:
		nav.target_position = current_target.global_position
		var next_point := nav.get_next_path_position()
		direction = (next_point - global_position).normalized()

	last_move_dir = direction
	velocity = direction * SPEED * get_movement_speed_multiplier()

	if anim:
		anim.flip_h = direction.x < 0.0
		anim.play("run")

func attack_state() -> void:
	velocity = Vector2.ZERO
	state = State.CHASE if current_target else State.IDLE

func hit_state() -> void:
	if health <= 0:
		die()
		return

	state = State.CHASE if current_target else State.IDLE

func add_target(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if not targets.has(target):
		targets.append(target)
	choose_best_target()

func remove_target(target: Node2D) -> void:
	targets.erase(target)
	if current_target == target:
		release_target()
		choose_best_target()

func choose_best_target() -> void:
	var best_target: Node2D = null
	var best_dist := INF

	for target in targets:
		if not is_instance_valid(target):
			continue

		var attackers: Array = reserved_targets.get(target, [])
		var distance := global_position.distance_to(target.global_position)

		if attackers.size() < MAX_ATTACKERS_PER_TARGET:
			if distance < best_dist:
				best_dist = distance
				best_target = target
		else:
			for enemy in attackers:
				if is_instance_valid(enemy) and distance + STEAL_DISTANCE < enemy.global_position.distance_to(target.global_position):
					best_dist = distance
					best_target = target
					break

	assign_target(best_target)

func assign_target(target: Node2D) -> void:
	if current_target == target:
		return

	release_target()

	if target == null:
		state = State.IDLE
		return

	if not reserved_targets.has(target):
		reserved_targets[target] = []
	reserved_targets[target].append(self)
	current_target = target
	state = State.CHASE

func release_target() -> void:
	if current_target == null:
		return

	if reserved_targets.has(current_target):
		reserved_targets[current_target].erase(self)
		if reserved_targets[current_target].is_empty():
			reserved_targets.erase(current_target)

	current_target = null

func rebalance_pack() -> void:
	for enemy in active_enemies:
		if enemy == self:
			continue
		if is_instance_valid(enemy) and enemy.has_method("choose_best_target"):
			enemy.choose_best_target()

func cleanup_reserved_targets() -> void:
	for target in reserved_targets.keys():
		reserved_targets[target] = reserved_targets[target].filter(is_instance_valid)
		if reserved_targets[target].is_empty():
			reserved_targets.erase(target)

func validate_target() -> bool:
	if current_target == null:
		state = State.IDLE
		return false

	if not is_instance_valid(current_target):
		release_target()
		state = State.IDLE
		choose_best_target()
		return false

	return true

func recheck_targets() -> void:
	for group_name in target_groups:
		for target in get_tree().get_nodes_in_group(group_name):
			if target is Node2D:
				add_target(target)

func get_combat_team() -> StringName:
	return combat_team

func get_combat_team_label() -> String:
	return team_display_name if not team_display_name.is_empty() else String(combat_team)

func get_combat_team_color() -> Color:
	return team_color

func get_facing_direction() -> Vector2:
	return last_move_dir.normalized() if last_move_dir != Vector2.ZERO else Vector2.RIGHT

func is_combat_alive() -> bool:
	return state != State.DEAD and health > 0 and not is_queued_for_deletion()

func can_damage_target(candidate: Node) -> bool:
	if candidate == null or candidate == self or not is_instance_valid(candidate):
		return false
	if candidate.is_in_group("player"):
		return can_target_players
	if candidate.is_in_group("combatant"):
		if candidate.has_method("get_combat_team"):
			return candidate.get_combat_team() != combat_team
		return true
	return true

func separation_vector() -> Vector2:
	var force := Vector2.ZERO
	for enemy in active_enemies:
		if enemy == self or not is_instance_valid(enemy):
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance > 0.0 and distance < SEPARATION_RADIUS:
			force += (global_position - enemy.global_position).normalized() * (1.0 - distance / SEPARATION_RADIUS)
	return force.normalized() if force.length() > 0.0 else Vector2.ZERO

func take_damage(damage: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEAD:
		return
	if damage <= 0:
		start_flashing()
		return

	health = max(0, health - damage)
	if alert_component:
		alert_component.enter_combat(source_position)
	if suppression_component:
		suppression_component.report_damage(damage)
	if will_component:
		will_component.report_damage(damage)

	if hit_audio and not hit_audio.playing:
		hit_audio.play()

	if source_position != Vector2.ZERO:
		var away := global_position - source_position
		if away != Vector2.ZERO:
			knockback_velocity = away.normalized() * KNOCKBACK_FORCE

	state = State.HIT
	start_flashing()
	if hurt_timer:
		hurt_timer.start(0.3)

	if health <= 0:
		die()

func receive_projectile_hit(base_damage: int, source_position: Vector2, projectile: Node = null) -> void:
	if state == State.DEAD:
		return
	direct_threat_timer = 2.5
	var hit := injury_component.resolve_hit(base_damage, -1, max_health) if injury_component else {
		"location": InjuryComponent.HitLocation.TORSO,
		"damage": base_damage,
		"fatal": false,
	}
	var fatal := bool(hit.get("fatal", false))
	var resolved_damage := max_health * 10 if fatal else int(hit.get("damage", base_damage))
	var shooter: Node = projectile.get("shooter") as Node if is_instance_valid(projectile) else null
	projectile_hit_resolved.emit(self, shooter, int(hit.get("location", InjuryComponent.HitLocation.TORSO)), fatal, resolved_damage)
	take_damage(resolved_damage, source_position)

func start_flashing() -> void:
	if is_flashing or anim == null:
		return

	is_flashing = true
	if flash_timer:
		flash_timer.start(0.1)

	var tween := create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.05)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.05)
	tween.set_loops(3)

func die() -> void:
	if state == State.DEAD:
		return

	state = State.DEAD
	died.emit(self)
	release_target()
	rebalance_pack()
	cleanup_reserved_targets()

	if death_audio_enabled and death_audio and not death_audio.playing:
		death_audio.play()

	_disable_dead_actor()
	if death_cleanup_delay < 0.0:
		return
	if death_cleanup_delay == 0.0:
		queue_free()
		return
	await get_tree().create_timer(death_cleanup_delay).timeout
	if is_instance_valid(self):
		queue_free()

func _disable_dead_actor() -> void:
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	active_enemies.erase(self)
	collision_layer = 0
	collision_mask = 0
	remove_from_group("combatant")
	remove_from_group("goblin")
	set_physics_process(false)
	for node in find_children("*", "CollisionShape2D", true, false):
		var shape := node as CollisionShape2D
		if shape:
			shape.set_deferred("disabled", true)
	if nav:
		nav.avoidance_enabled = false

func avoid_obstacles(_delta: float) -> void:
	if predictcast == null:
		return

	if not predictcast.is_enabled():
		predictcast.enabled = true

	if velocity.length() <= 0.0:
		return

	predictcast.global_rotation = velocity.angle()
	predictcast.force_update_transform()

	if predictcast.is_colliding():
		var normal := predictcast.get_collision_normal(0)
		var slide_dir := velocity - normal * velocity.dot(normal)
		if slide_dir.length() < 0.1:
			slide_dir = Vector2(-normal.y, normal.x) * DETOUR_DISTANCE
		velocity = slide_dir.normalized() * SPEED * get_movement_speed_multiplier()

func detect_stuck(delta: float) -> void:
	if last_position.distance_to(global_position) < 1.0:
		stuck_timer += delta
	else:
		stuck_timer = 0.0

	last_position = global_position

	if stuck_timer > stuck_threshold:
		unstuck()

func unstuck() -> void:
	if velocity != Vector2.ZERO:
		velocity = Vector2(-velocity.y, velocity.x).normalized() * SPEED * get_movement_speed_multiplier()
	stuck_timer = 0.0

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("attackeffect") or area.is_in_group("arrow"):
		take_damage(1, area.global_position)
		area.queue_free()

func _on_hurt_timeout() -> void:
	knockback_velocity = Vector2.ZERO
	if state != State.DEAD:
		state = State.CHASE if current_target else State.IDLE

func _on_flash_timeout() -> void:
	is_flashing = false
	if anim:
		anim.modulate = Color.WHITE

func _on_detect_area_body_entered(body: Node2D) -> void:
	if _is_valid_target_body(body):
		add_target(body)

func _on_detect_area_body_exited(body: Node2D) -> void:
	if _is_valid_target_body(body):
		remove_target(body)

func _on_targeter_area_body_entered(body: Node2D) -> void:
	if _is_valid_target_body(body):
		add_target(body)

func _on_targeter_area_body_exited(body: Node2D) -> void:
	if _is_valid_target_body(body):
		remove_target(body)

func _is_valid_target_body(body: Node2D) -> bool:
	for group_name in target_groups:
		if body.is_in_group(group_name):
			if body.has_method("is_destroyed") and body.is_destroyed():
				return false
			return true
	return false

func _setup_cover_user() -> void:
	cover_user = CoverUser.new()
	cover_user.name = "CoverUser"
	add_child(cover_user)
	cover_user.setup(self)

func _setup_perception_components() -> void:
	alert_component = AlertComponent.new()
	alert_component.name = "AlertComponent"
	add_child(alert_component)
	alert_component.setup(self)

	perception_component = PerceptionComponent.new()
	perception_component.name = "PerceptionComponent"
	add_child(perception_component)
	perception_component.setup(self, alert_component)
	perception_component.contact_confirmed.connect(_on_perception_contact_confirmed)
	perception_component.stimulus_heard.connect(_on_perception_stimulus_heard)

func _setup_squad_member() -> void:
	squad_member = SquadMember.new()
	squad_member.name = "SquadMember"
	add_child(squad_member)
	squad_member.setup(self, squad_id)

func _setup_will_component() -> void:
	will_component = WillComponent.new()
	will_component.name = "WillComponent"
	add_child(will_component)
	will_component.setup(self, will_profile)
	will_component.set_lock_to_steady(lock_steady_morale)

func _setup_suppression_component() -> void:
	suppression_component = SuppressionComponent.new()
	suppression_component.name = "SuppressionComponent"
	add_child(suppression_component)
	suppression_component.setup(self)

func _setup_injury_component() -> void:
	injury_component = InjuryComponent.new()
	injury_component.name = "InjuryComponent"
	add_child(injury_component)

func _setup_aim_component() -> void:
	aim_component = AimComponent.new()
	aim_component.name = "AimComponent"
	add_child(aim_component)

func _setup_concealment_component() -> void:
	concealment_component = ConcealmentComponent.new()
	concealment_component.name = "ConcealmentComponent"
	add_child(concealment_component)

func report_near_miss() -> void:
	direct_threat_timer = maxf(direct_threat_timer, 1.4)
	if alert_component:
		alert_component.enter_combat()
	if suppression_component:
		suppression_component.report_near_miss()
	if will_component:
		will_component.report_near_miss()

func report_ally_death() -> void:
	if suppression_component:
		suppression_component.report_ally_death()
	if will_component:
		will_component.report_ally_death()

func register_cover_candidate(cover: Node) -> void:
	if cover_user:
		cover_user.register_cover(cover)

func unregister_cover_candidate(cover: Node) -> void:
	if cover_user:
		cover_user.unregister_cover(cover)

func enter_cover(cover: Node, precision := false) -> bool:
	return cover_user != null and cover_user.enter_cover(cover, precision)

func enter_cover_against(cover: Node, threat_position: Vector2, precision := false) -> bool:
	return cover_user != null and cover_user.enter_cover_against(cover, threat_position, precision)

func exit_cover() -> void:
	if cover_user:
		cover_user.exit_cover()

func set_cover_precision(enabled: bool) -> void:
	if cover_user:
		cover_user.set_precision(enabled)
	set_weapon_aiming(enabled)

func is_cover_precision() -> bool:
	return cover_user != null and cover_user.is_precision()

func get_active_cover() -> Node:
	return cover_user.get_active_cover() if cover_user else null

func get_weapon_spread_multiplier() -> float:
	var cover_multiplier := cover_user.get_spread_multiplier() if cover_user else 1.0
	var aim_multiplier := 1.0
	var blind_firing := cover_user != null and cover_user.is_in_cover() and not cover_user.is_precision()
	if aim_component and not blind_firing:
		aim_multiplier = aim_component.get_spread_multiplier(velocity.length_squared() > 25.0)
	var injury_multiplier := injury_component.get_accuracy_multiplier() if injury_component else 1.0
	var suppression_multiplier := suppression_component.get_spread_multiplier() if suppression_component else 1.0
	return cover_multiplier * aim_multiplier * injury_multiplier * suppression_multiplier

func get_movement_speed_multiplier() -> float:
	var injury_multiplier := injury_component.get_movement_multiplier() if injury_component else 1.0
	var aim_multiplier := aim_component.get_movement_speed_multiplier() if aim_component else 1.0
	return injury_multiplier * aim_multiplier

func set_weapon_aiming(enabled: bool) -> void:
	if aim_component:
		aim_component.set_aiming(enabled)

func is_weapon_aiming() -> bool:
	return aim_component != null and aim_component.is_aiming()

func get_aim_quality() -> float:
	return aim_component.get_aim_quality() if aim_component else 0.0

func report_weapon_fired() -> void:
	if aim_component:
		aim_component.report_shot()

func register_concealment_source(source: Node) -> void:
	if concealment_component:
		concealment_component.register_source(source)

func unregister_concealment_source(source: Node) -> void:
	if concealment_component:
		concealment_component.unregister_source(source)

func reveal_from_concealment(duration := -1.0) -> void:
	if concealment_component:
		concealment_component.reveal(duration)

func is_visually_concealed() -> bool:
	return concealment_component != null and concealment_component.is_concealed()

func is_under_direct_threat() -> bool:
	return direct_threat_timer > 0.0 or (suppression_component != null and suppression_component.is_under_fire())

func get_suppression() -> float:
	return suppression_component.suppression if suppression_component else 0.0

func is_pinned_by_fire() -> bool:
	return suppression_component != null and suppression_component.should_hunker_down()

func on_cover_blocked_projectile() -> void:
	direct_threat_timer = maxf(direct_threat_timer, 1.0)
	if suppression_component:
		suppression_component.report_cover_impact()
	if cover_user:
		cover_user.show_blocked()

func hear_combat_stimulus(position: Vector2, source: Node2D = null, loudness := 1.0) -> void:
	if perception_component:
		perception_component.hear_stimulus(position, source, loudness)

func _on_perception_contact_confirmed(contact: CombatContact) -> void:
	if squad_member != null and squad_member.coordinator != null and squad_member.coordinator.has_method("report_contact"):
		squad_member.coordinator.report_contact(squad_member, contact)

func _on_perception_stimulus_heard(position: Vector2, source: Node2D) -> void:
	if source == null or not is_instance_valid(source) or not can_damage_target(source):
		return
	if has_method("on_hostile_gunshot_heard"):
		call("on_hostile_gunshot_heard", position, source)
