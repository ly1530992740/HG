extends "res://unit/goblins/goblin_base.gd"

signal surprise_reaction_started(duration: float)

enum ThreatResponse { WAIT, BLIND_FIRE, PRECISE_FIRE }
enum FirearmLoadout { ROLE_DEFAULT, SMG }

@export var combat_role: SquadCombatRole.Type = SquadCombatRole.Type.RIFLEMAN
@export var firearm_loadout: FirearmLoadout = FirearmLoadout.ROLE_DEFAULT
@export var detect_range := 420.0
@export var attack_range := 330.0
@export var keep_distance := 230.0
@export var fire_cooldown := 0.85
@export var projectile_damage := 3
@export var projectile_speed := 2000.0
@export var projectile_lifetime := 0.7
@export var spread_degrees := 4.0
@export var magazine_size := 12
@export var reserve_ammo := 96
@export var reload_time := 1.6
@export var hit_groups: Array[String] = ["player", "pawn", "combatant"]
@export var melee_trigger_distance := 92.0
@export var melee_attack_distance := 58.0
@export var melee_damage := 4
@export var ai_decision_interval := 0.12
@export var target_refresh_interval := 0.18
@export var surprise_reaction_min := 0.5
@export var surprise_reaction_max := 0.8
@export var standard_sight_range := 1800.0
@export var standard_field_of_view := 110.0
@export var marksman_aim_sight_range := 3000.0
@export var marksman_aim_field_of_view := 35.0

const PROJECTILE_SCENE := preload("res://weapons/enemy_bullet.tscn")
const RIFLE_TEXTURE := preload("res://weapons/visuals/rifle_simple.svg")
const SMG_TEXTURE := preload("res://weapons/visuals/smg_simple.svg")
const MARKSMAN_TEXTURE := preload("res://weapons/visuals/marksman_simple.svg")
const LMG_TEXTURE := preload("res://weapons/visuals/lmg_simple.svg")
const SHOTGUN_TEXTURE := preload("res://weapons/visuals/shotgun_simple.svg")
const PISTOL_TEXTURE := preload("res://weapons/visuals/pistol_simple.svg")

var target: Node2D = null
var firearm_weapon: FirearmWeapon
var melee_weapon: MeleeWeapon
var current_combat_weapon: Weapon
var hp_bar: ProgressBar
var anatomy_root: Node2D
var body_visual: Polygon2D
var head_visual: Polygon2D
var back_arm_visual: Line2D
var weapon_arm_visual: Line2D
var left_leg_visual: Line2D
var right_leg_visual: Line2D
var wound_layer: Node2D
var head_wound_visual: Polygon2D
var heart_wound_visual: Polygon2D
var arm_wound_visual: Polygon2D
var leg_wound_visual: Polygon2D
var gun_visual: Polygon2D
var gun_sprite: Sprite2D
var muzzle_flash_visual: Polygon2D
var melee_visual: Polygon2D
var muzzle: Marker2D
var goap_agent: GoapAgent

var _goap_controls_actor := false
var _active_squad_action := -1
var _action_elapsed := 0.0
var _selected_cover: Node = null
var _threat_response: ThreatResponse = ThreatResponse.WAIT
var _threat_response_timer := 0.0
var _peek_window_remaining := 0.0
var _concealment_remaining := 0.0
var _cover_strafe_target := 0.0
var _cover_reposition_wait := 0.0
var _gun_length_scale := 1.0
var melee_goal_version := 0
var _melee_attack_started := false
var _ai_decision_timer := 0.0
var _target_refresh_timer := 0.0
var _movement_detour_waypoint := Vector2.ZERO
var _movement_detour_destination := Vector2.ZERO
var _movement_detour_cover: Node = null
var _completed_detour_covers: Array[Node] = []
var _surprise_reaction_timer := 0.0
var _prepared_ambush_target: Node2D = null
var _ambush_followup_active := false
var _ambush_followup_shots_fired := 0
var _torso_wound_count := 0
var _walk_phase := 0.0
var _visual_recoil := 0.0
var _muzzle_flash_remaining := 0.0

func _ready() -> void:
	_apply_combat_role_profile()
	STOP_DISTANCE = keep_distance
	ATTACK_DISTANCE = attack_range
	target_groups = []
	super._ready()
	if perception_component:
		perception_component.sight_range = standard_sight_range
		perception_component.field_of_view_degrees = standard_field_of_view

	if anim:
		anim.visible = false

	_setup_visual()
	_setup_injury_visuals()
	_apply_combat_role_visual()
	_setup_firearm()
	_setup_melee_weapon()
	_setup_hp_bar()
	_find_combat_target()
	_setup_squad_goap()

func _physics_process(delta: float) -> void:
	if _surprise_reaction_timer > 0.0:
		_surprise_reaction_timer = maxf(0.0, _surprise_reaction_timer - delta)
		velocity = Vector2.ZERO
		state = State.IDLE
		super._physics_process(delta)
		_update_visual(delta)
		_update_hp_bar()
		return
	_process_ambush_followup()
	_target_refresh_timer -= delta
	if _target_refresh_timer <= 0.0:
		_target_refresh_timer = target_refresh_interval
		_find_combat_target()
	if not _goap_controls_actor and current_combat_weapon == melee_weapon and not is_melee_engagement_needed():
		_equip_combat_weapon(firearm_weapon)
	_ai_decision_timer -= delta
	if _ai_decision_timer <= 0.0:
		var decision_delta := ai_decision_interval - _ai_decision_timer
		_ai_decision_timer = ai_decision_interval
		_update_goap_world_state()
		if goap_agent:
			goap_agent.process(decision_delta)
	if _goap_controls_actor:
		state = State.IDLE
	else:
		_update_ai_state()
	super._physics_process(delta)
	_update_visual(delta)
	_update_hp_bar()

func idle_state() -> void:
	if _goap_controls_actor:
		return
	super.idle_state()

func separation_vector() -> Vector2:
	if squad_member != null:
		var order := squad_member.get_current_order()
		if (order == null and target == null) or (order != null and order.type == SquadOrder.Type.HOLD):
			return Vector2.ZERO
	return super.separation_vector()

func _find_combat_target() -> void:
	var best: Node2D = null
	if perception_component:
		var own_contact := perception_component.get_best_contact()
		if own_contact != null:
			best = own_contact.target
	if best == null and squad_member != null and squad_member.blackboard != null:
		var shared_target := squad_member.blackboard.shared_target
		if is_instance_valid(shared_target) and can_damage_target(shared_target):
			best = shared_target
	if best != null and best.has_method("is_combat_alive") and not best.is_combat_alive():
		best = null
	target = best
	current_target = target

func has_combat_contact() -> bool:
	return target != null and is_instance_valid(target) and perception_component != null and perception_component.get_contact(target) != null

func _update_ai_state() -> void:
	if state == State.DEAD or state == State.HIT:
		return

	if target == null:
		state = State.IDLE
		return

	var distance := global_position.distance_to(target.global_position)
	if distance <= attack_range:
		state = State.ATTACK
	elif distance <= detect_range:
		state = State.CHASE
	else:
		state = State.IDLE

func chase_state() -> void:
	if target == null:
		velocity = Vector2.ZERO
		return

	var to_target := target.global_position - global_position
	var distance := to_target.length()
	if distance <= keep_distance:
		velocity = Vector2.ZERO
		return

	if nav:
		nav.target_position = target.global_position
		var next_point := nav.get_next_path_position()
		velocity = (next_point - global_position).normalized() * SPEED * get_movement_speed_multiplier()
	else:
		velocity = to_target.normalized() * SPEED * get_movement_speed_multiplier()

func attack_state() -> void:
	if target == null:
		velocity = Vector2.ZERO
		return

	velocity = Vector2.ZERO
	if _is_player_threatening_me():
		if get_active_cover() == null:
			set_weapon_aiming(false)
			return
		set_cover_precision(false)
	elif get_active_cover() != null:
		set_cover_precision(true)
	else:
		set_weapon_aiming(true)
	_try_fire_at(target.global_position)

func _try_fire_at(target_position: Vector2) -> void:
	if _surprise_reaction_timer > 0.0 or firearm_weapon == null or current_combat_weapon != firearm_weapon or firearm_weapon.reloading:
		return
	var fire_target := _get_order_target() if _get_order_target() != null else target
	if not _is_fire_authorized(fire_target):
		return
	if firearm_weapon.magazine_ammo <= 0:
		firearm_weapon.reload()
		return
	firearm_weapon.try_attack(target_position)

func _setup_visual() -> void:
	anatomy_root = Node2D.new()
	anatomy_root.name = "VisualAnatomy"
	anatomy_root.z_index = 4
	add_child(anatomy_root)

	var limb_color := team_color.darkened(0.18)
	back_arm_visual = _make_limb("BackArm", PackedVector2Array([
		Vector2(-9, -7), Vector2(-21, 2), Vector2(-15, 15)
	]), 6.0, limb_color, 1)
	weapon_arm_visual = _make_limb("WeaponArm", PackedVector2Array([
		Vector2(-7, -6), Vector2(7, -1), Vector2(20, 0)
	]), 6.0, team_color.lightened(0.05), 5)
	left_leg_visual = _make_limb("LeftLeg", PackedVector2Array([
		Vector2(-7, 13), Vector2(-10, 27), Vector2(-16, 38)
	]), 7.0, limb_color, 2)
	right_leg_visual = _make_limb("RightLeg", PackedVector2Array([
		Vector2(7, 13), Vector2(10, 27), Vector2(17, 37)
	]), 7.0, limb_color, 2)

	body_visual = Polygon2D.new()
	body_visual.name = "VisualBody"
	body_visual.color = team_color
	body_visual.polygon = PackedVector2Array([
		Vector2(-12, -13), Vector2(12, -13), Vector2(16, 10),
		Vector2(8, 20), Vector2(-8, 20), Vector2(-16, 10)
	])
	body_visual.z_index = 3
	anatomy_root.add_child(body_visual)

	head_visual = Polygon2D.new()
	head_visual.name = "Head"
	head_visual.color = team_color.lightened(0.12)
	head_visual.polygon = _make_circle_polygon(Vector2(0, -27), 12.0, 14)
	head_visual.z_index = 4
	anatomy_root.add_child(head_visual)

	wound_layer = Node2D.new()
	wound_layer.name = "Wounds"
	wound_layer.z_index = 8
	anatomy_root.add_child(wound_layer)

	gun_visual = Polygon2D.new()
	gun_visual.name = "VisualGun"
	gun_visual.color = Color(0.25, 0.25, 0.25, 1.0)
	gun_visual.polygon = PackedVector2Array([
		Vector2(0, -3), Vector2(32, -3), Vector2(32, 3), Vector2(0, 3)
	])
	gun_visual.z_index = 5
	add_child(gun_visual)
	gun_visual.visible = false

	gun_sprite = Sprite2D.new()
	gun_sprite.name = "VisualGunSprite"
	gun_sprite.texture = RIFLE_TEXTURE
	gun_sprite.position = Vector2(20, 0)
	gun_sprite.z_index = 6
	add_child(gun_sprite)

	muzzle_flash_visual = Polygon2D.new()
	muzzle_flash_visual.name = "MuzzleFlash"
	muzzle_flash_visual.color = Color(1.0, 0.82, 0.2, 0.95)
	muzzle_flash_visual.polygon = PackedVector2Array([
		Vector2(0, -3), Vector2(10, -7), Vector2(7, 0),
		Vector2(13, 4), Vector2(0, 3),
	])
	muzzle_flash_visual.z_index = 8
	muzzle_flash_visual.visible = false
	add_child(muzzle_flash_visual)

	melee_visual = Polygon2D.new()
	melee_visual.name = "VisualMeleeWeapon"
	melee_visual.color = Color(0.82, 0.86, 0.9, 1.0)
	melee_visual.polygon = PackedVector2Array([
		Vector2(4, -3), Vector2(28, -2), Vector2(36, 0),
		Vector2(28, 2), Vector2(4, 3), Vector2(0, 0)
	])
	melee_visual.z_index = 5
	melee_visual.visible = false
	add_child(melee_visual)

	muzzle = Marker2D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector2(44, 0)
	add_child(muzzle)

func _make_limb(node_name: String, limb_points: PackedVector2Array, width: float, color: Color, layer: int) -> Line2D:
	var limb := Line2D.new()
	limb.name = node_name
	limb.points = limb_points
	limb.width = width
	limb.default_color = color
	limb.begin_cap_mode = Line2D.LINE_CAP_ROUND
	limb.end_cap_mode = Line2D.LINE_CAP_ROUND
	limb.joint_mode = Line2D.LINE_JOINT_ROUND
	limb.antialiased = true
	limb.z_index = layer
	anatomy_root.add_child(limb)
	return limb

func _make_circle_polygon(center: Vector2, radius: float, point_count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in point_count:
		var angle := TAU * float(index) / float(point_count)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result

func _setup_injury_visuals() -> void:
	head_wound_visual = _make_wound("HeadWound", Vector2(7, -31), 5.0)
	heart_wound_visual = _make_wound("HeartWound", Vector2(-5, -6), 4.5)
	arm_wound_visual = _make_wound("ArmWound", Vector2(10, 0), 3.5)
	leg_wound_visual = _make_wound("LegWound", Vector2(10, 25), 4.0)
	if injury_component != null and not injury_component.injury_received.is_connected(_on_injury_received):
		injury_component.injury_received.connect(_on_injury_received)
	if not died.is_connected(_on_visual_death):
		died.connect(_on_visual_death)

func _make_wound(node_name: String, center: Vector2, radius: float) -> Polygon2D:
	var wound := Polygon2D.new()
	wound.name = node_name
	wound.color = Color(0.42, 0.015, 0.01, 1.0)
	wound.polygon = _make_circle_polygon(center, radius, 9)
	wound.visible = false
	wound_layer.add_child(wound)
	return wound

func _on_injury_received(location: InjuryComponent.HitLocation, _fatal: bool) -> void:
	match location:
		InjuryComponent.HitLocation.HEAD:
			_apply_head_wound()
		InjuryComponent.HitLocation.HEART:
			heart_wound_visual.visible = true
		InjuryComponent.HitLocation.TORSO:
			_add_torso_wound()
		InjuryComponent.HitLocation.ARM:
			_apply_arm_wound()
		InjuryComponent.HitLocation.LEG:
			_apply_leg_wound()
	_emit_blood_droplets(location)

func _apply_head_wound() -> void:
	# The concave right edge reads as a missing section even at overview zoom.
	head_visual.polygon = PackedVector2Array([
		Vector2(-11, -32), Vector2(-6, -38), Vector2(1, -40),
		Vector2(7, -37), Vector2(4, -32), Vector2(10, -28),
		Vector2(4, -24), Vector2(10, -20), Vector2(3, -16),
		Vector2(-5, -16), Vector2(-11, -21), Vector2(-13, -27),
	])
	head_wound_visual.visible = true

func _add_torso_wound() -> void:
	var wound_positions := [
		Vector2(4, -6), Vector2(-7, 2), Vector2(7, 8),
		Vector2(-3, 13), Vector2(0, -10), Vector2(10, 2),
	]
	var wound := _make_wound("TorsoWound%d" % (_torso_wound_count + 1), wound_positions[_torso_wound_count % wound_positions.size()], 2.8)
	wound.visible = true
	_torso_wound_count += 1

func _apply_arm_wound() -> void:
	arm_wound_visual.visible = true
	if injury_component != null and injury_component.arm_wounds > 1:
		back_arm_visual.default_color = Color(0.42, 0.06, 0.05, 1.0)
		back_arm_visual.points = PackedVector2Array([
			Vector2(-9, -7), Vector2(-20, 3), Vector2(-12, 20),
		])
	else:
		weapon_arm_visual.default_color = Color(0.48, 0.07, 0.05, 1.0)
		weapon_arm_visual.points = PackedVector2Array([
			Vector2(-7, -6), Vector2(6, 0), Vector2(14, 15),
		])

func _apply_leg_wound() -> void:
	leg_wound_visual.visible = true
	if injury_component != null and injury_component.leg_wounds > 1:
		left_leg_visual.default_color = Color(0.42, 0.06, 0.05, 1.0)
		left_leg_visual.points = PackedVector2Array([
			Vector2(-7, 13), Vector2(-13, 27), Vector2(-9, 39),
		])
	else:
		right_leg_visual.default_color = Color(0.48, 0.07, 0.05, 1.0)
		right_leg_visual.points = PackedVector2Array([
			Vector2(7, 13), Vector2(15, 25), Vector2(10, 37),
		])

func _emit_blood_droplets(location: InjuryComponent.HitLocation) -> void:
	var origin := Vector2.ZERO
	match location:
		InjuryComponent.HitLocation.HEAD:
			origin = Vector2(6, -30)
		InjuryComponent.HitLocation.HEART:
			origin = Vector2(-5, -6)
		InjuryComponent.HitLocation.ARM:
			origin = Vector2(10, 0)
		InjuryComponent.HitLocation.LEG:
			origin = Vector2(10, 25)
		_:
			origin = Vector2(0, 2)
	for index in 3:
		var droplet := Polygon2D.new()
		droplet.name = "BloodDroplet"
		droplet.color = Color(0.5, 0.01, 0.01, 0.95)
		droplet.polygon = _make_circle_polygon(Vector2.ZERO, 1.8 + float(index) * 0.4, 7)
		droplet.position = origin
		wound_layer.add_child(droplet)
		var travel := Vector2(randf_range(-18.0, 18.0), randf_range(-20.0, 10.0))
		var tween := droplet.create_tween()
		tween.set_parallel(true)
		tween.tween_property(droplet, "position", origin + travel, 0.3)
		tween.tween_property(droplet, "modulate:a", 0.0, 0.3)
		tween.chain().tween_callback(droplet.queue_free)

func _on_visual_death(_actor: Node) -> void:
	if hp_bar:
		hp_bar.visible = false
	for control in find_children("*", "Control", true, false):
		if control is CanvasItem:
			(control as CanvasItem).visible = false
	var facing := -1.0 if anatomy_root.scale.x < 0.0 else 1.0
	anatomy_root.rotation = facing * PI * 0.5
	anatomy_root.position = Vector2(0, 16)
	anatomy_root.modulate = Color(0.58, 0.52, 0.52, 1.0)
	gun_visual.position = Vector2(5.0 * facing, 22.0)
	gun_visual.rotation = facing * 0.65
	gun_visual.modulate = Color(0.65, 0.65, 0.65, 1.0)
	gun_sprite.position = Vector2(6.0 * facing, 23.0)
	gun_sprite.rotation = facing * 0.7
	gun_sprite.modulate = Color(0.62, 0.62, 0.62, 1.0)
	muzzle_flash_visual.visible = false
	melee_visual.position = Vector2(-4.0 * facing, 20.0)
	melee_visual.rotation = facing * -0.8
	z_index = 1

func _setup_firearm() -> void:
	var data := WeaponData.new()
	data.knockback = 0.0
	data.projectile_scene = PROJECTILE_SCENE
	data.hit_groups = hit_groups
	if firearm_loadout == FirearmLoadout.SMG:
		_configure_smg_weapon_data(data)
		firearm_weapon = SmgWeapon.new()
	else:
		_configure_role_weapon_data(data)
		match combat_role:
			SquadCombatRole.Type.MARKSMAN:
				firearm_weapon = BoltActionRifleWeapon.new()
			SquadCombatRole.Type.MACHINE_GUNNER:
				firearm_weapon = LmgWeapon.new()
			SquadCombatRole.Type.SHOTGUNNER:
				firearm_weapon = ShotgunWeapon.new()
			SquadCombatRole.Type.PISTOL_SCOUT:
				firearm_weapon = PistolWeapon.new()
			_:
				firearm_weapon = RifleWeapon.new()
	firearm_weapon.name = "FirearmWeapon"
	firearm_weapon.weapon_data = data
	firearm_weapon.muzzle_path = NodePath("../Muzzle")
	add_child(firearm_weapon)
	attack_range = data.effective_range
	ATTACK_DISTANCE = attack_range
	firearm_weapon.equip(self)
	if not firearm_weapon.fired.is_connected(_on_firearm_fired):
		firearm_weapon.fired.connect(_on_firearm_fired)
	current_combat_weapon = firearm_weapon

func _apply_combat_role_profile() -> void:
	match combat_role:
		SquadCombatRole.Type.MARKSMAN:
			max_health = 7
			SPEED = 180.0
			detect_range = 1800.0
			keep_distance = 1200.0
		SquadCombatRole.Type.MACHINE_GUNNER:
			max_health = 10
			SPEED = 175.0
			detect_range = 1800.0
			keep_distance = 950.0
		SquadCombatRole.Type.SHOTGUNNER:
			max_health = 9
			SPEED = 235.0
			detect_range = 1800.0
			keep_distance = 500.0
		SquadCombatRole.Type.PISTOL_SCOUT:
			max_health = 7
			SPEED = 245.0
			detect_range = 1800.0
			keep_distance = 650.0
		_:
			max_health = 8
			SPEED = 210.0
			detect_range = 1800.0
			keep_distance = 900.0
	if firearm_loadout == FirearmLoadout.SMG:
		keep_distance = 800.0

func _configure_smg_weapon_data(data: WeaponData) -> void:
	data.weapon_name = "Tactical SMG"
	data.damage = 2
	data.fire_mode = WeaponData.FireMode.AUTO
	data.fire_cooldown = 0.1
	data.spread_degrees = 0.8
	data.magazine_size = 32
	data.reserve_ammo = 160
	data.reload_time = 1.55
	data.effective_range = 1600.0
	data.projectile_speed = 2600.0
	data.projectile_lifetime = 0.85

func _configure_role_weapon_data(data: WeaponData) -> void:
	match combat_role:
		SquadCombatRole.Type.MARKSMAN:
			data.weapon_name = "Marksman Rifle"
			data.damage = 4
			data.fire_mode = WeaponData.FireMode.SEMI_AUTO
			data.fire_cooldown = 1.8
			data.cycle_time = 1.1
			data.spread_degrees = 0.35
			data.magazine_size = 5
			data.reserve_ammo = 35
			data.reload_time = 2.6
			data.effective_range = 2400.0
			data.projectile_speed = 3100.0
			data.projectile_lifetime = 1.35
		SquadCombatRole.Type.MACHINE_GUNNER:
			data.weapon_name = "Light Machine Gun"
			data.damage = 1
			data.fire_mode = WeaponData.FireMode.AUTO
			data.fire_cooldown = 0.18
			data.spread_degrees = 1.8
			data.magazine_size = 50
			data.reserve_ammo = 200
			data.reload_time = 3.4
			data.effective_range = 1900.0
			data.projectile_speed = 2500.0
			data.projectile_lifetime = 1.2
		SquadCombatRole.Type.SHOTGUNNER:
			data.weapon_name = "Combat Shotgun"
			data.damage = 1
			data.fire_mode = WeaponData.FireMode.SEMI_AUTO
			data.fire_cooldown = 1.05
			data.spread_degrees = 1.5
			data.projectile_count = 6
			data.projectile_spread_degrees = 16.0
			data.magazine_size = 6
			data.reserve_ammo = 36
			data.reload_time = 2.4
			data.effective_range = 850.0
			data.projectile_speed = 1900.0
			data.projectile_lifetime = 0.48
		SquadCombatRole.Type.PISTOL_SCOUT:
			data.weapon_name = "Service Pistol"
			data.damage = 2
			data.fire_mode = WeaponData.FireMode.SEMI_AUTO
			data.fire_cooldown = 0.48
			data.spread_degrees = 2.2
			data.magazine_size = 12
			data.reserve_ammo = 72
			data.reload_time = 1.35
			data.effective_range = 1200.0
			data.projectile_speed = 2100.0
			data.projectile_lifetime = 0.7
		_:
			data.weapon_name = "Service Rifle"
			data.damage = 2
			data.fire_mode = WeaponData.FireMode.SEMI_AUTO
			data.fire_cooldown = 0.62
			data.spread_degrees = 0.9
			data.magazine_size = 20
			data.reserve_ammo = 120
			data.reload_time = 1.9
			data.effective_range = 1800.0
			data.projectile_speed = 2600.0
			data.projectile_lifetime = 1.15

func _apply_combat_role_visual() -> void:
	if gun_visual == null or gun_sprite == null:
		return
	gun_sprite.texture = SMG_TEXTURE if firearm_loadout == FirearmLoadout.SMG else RIFLE_TEXTURE
	gun_sprite.scale = Vector2(0.9, 0.9)
	if firearm_loadout == FirearmLoadout.SMG:
		gun_visual.color = Color(0.2, 0.22, 0.24, 1.0)
		_gun_length_scale = 0.9
		return
	match combat_role:
		SquadCombatRole.Type.MARKSMAN:
			gun_sprite.texture = MARKSMAN_TEXTURE
			gun_visual.color = Color(0.22, 0.32, 0.2, 1.0)
			_gun_length_scale = 1.35
		SquadCombatRole.Type.MACHINE_GUNNER:
			gun_sprite.texture = LMG_TEXTURE
			gun_visual.color = Color(0.16, 0.18, 0.2, 1.0)
			gun_visual.scale.y = 1.65
		SquadCombatRole.Type.SHOTGUNNER:
			gun_sprite.texture = SHOTGUN_TEXTURE
			gun_visual.color = Color(0.42, 0.27, 0.12, 1.0)
			_gun_length_scale = 0.9
		SquadCombatRole.Type.PISTOL_SCOUT:
			gun_sprite.texture = PISTOL_TEXTURE
			gun_visual.color = Color(0.35, 0.35, 0.38, 1.0)
			_gun_length_scale = 0.55

func get_combat_role() -> SquadCombatRole.Type:
	return combat_role

func get_combat_role_label() -> String:
	return SquadCombatRole.get_label(combat_role)

func _setup_melee_weapon() -> void:
	var data := WeaponData.new()
	data.weapon_name = "Goblin Combat Knife"
	data.damage = melee_damage
	data.fire_cooldown = 0.65
	data.melee_range = 34.0
	data.melee_radius = 28.0
	data.melee_active_time = 0.12
	data.melee_recover_time = 0.32
	data.hit_groups = hit_groups

	melee_weapon = MeleeWeapon.new()
	melee_weapon.name = "MeleeWeapon"
	melee_weapon.weapon_data = data
	add_child(melee_weapon)
	melee_weapon.equip(self)
	melee_weapon.unequip()

func _equip_combat_weapon(weapon: Weapon) -> void:
	if weapon == null or current_combat_weapon == weapon:
		return
	if current_combat_weapon:
		current_combat_weapon.unequip()
	current_combat_weapon = weapon
	current_combat_weapon.equip(self)
	if gun_visual:
		gun_visual.visible = false
	if gun_sprite:
		gun_sprite.visible = current_combat_weapon == firearm_weapon
	if melee_visual:
		melee_visual.visible = current_combat_weapon == melee_weapon

func _setup_squad_goap() -> void:
	var actions := Node.new()
	actions.name = "Actions"
	add_child(actions)

	var action_types := [
		SquadOrder.Type.HOLD,
		SquadOrder.Type.TAKE_COVER,
		SquadOrder.Type.SUPPRESS,
		SquadOrder.Type.FOCUS_FIRE,
		SquadOrder.Type.ADVANCE,
		SquadOrder.Type.RETREAT,
		SquadOrder.Type.STAY_HIDDEN,
		SquadOrder.Type.OVERWATCH,
		SquadOrder.Type.FLANK_LEFT,
		SquadOrder.Type.FLANK_RIGHT,
		SquadOrder.Type.AMBUSH_POSITION,
		SquadOrder.Type.SEARCH_AREA,
	]
	for order_type in action_types:
		var action := SquadCommandAction.new()
		action.name = "%sAction" % SquadOrder.Type.keys()[order_type].to_pascal_case()
		action.supported_order_type = order_type
		action.cost = _get_base_action_cost(order_type)
		actions.add_child(action)

	var seek_safety := SeekSafetyAction.new()
	seek_safety.name = "SeekSafetyAction"
	seek_safety.cost = 3
	actions.add_child(seek_safety)
	var melee_action := MeleeEngageAction.new()
	melee_action.name = "MeleeEngageAction"
	melee_action.cost = 2
	actions.add_child(melee_action)

	var goals := Node.new()
	goals.name = "Goals"
	add_child(goals)
	var order_goal := SquadOrderGoal.new()
	order_goal.name = "ObeySquadOrderGoal"
	goals.add_child(order_goal)
	var survival_goal := PreserveLifeGoal.new()
	survival_goal.name = "PreserveLifeGoal"
	goals.add_child(survival_goal)
	var close_combat_goal := CloseCombatGoal.new()
	close_combat_goal.name = "CloseCombatGoal"
	goals.add_child(close_combat_goal)

	goap_agent = GoapAgent.new()
	goap_agent.name = "GoapAgent"
	goap_agent.actions_node = actions
	goap_agent.goals_node = goals
	goap_agent.debug_enabled = false
	add_child(goap_agent)
	goap_agent.init(self)
	goap_agent.plan_changed.connect(_on_goap_plan_changed)
	goap_agent.goal_changed.connect(_on_goap_goal_changed)
	goap_agent.action_changed.connect(_on_goap_action_changed)
	if squad_member:
		squad_member.sync_goap_state()
	_update_goap_world_state()

func _update_goap_world_state() -> void:
	if goap_agent == null or goap_agent.get_world_state() == null:
		return
	var world_state := goap_agent.get_world_state()
	var in_cover := get_active_cover() != null
	world_state.set_state(&"in_cover", in_cover)
	world_state.set_state(&"is_safe", in_cover and not is_cover_precision())
	world_state.set_state(&"has_target", target != null)
	world_state.set_state(&"under_direct_threat", _is_player_threatening_me())
	world_state.set_state(&"suppressed", get_suppression() >= 18.0)
	world_state.set_state(&"pinned", is_pinned_by_fire())
	world_state.set_state(&"target_in_melee_range", is_melee_engagement_needed())
	world_state.set_state(&"roe", _get_rules_of_engagement())
	world_state.set_state(&"contact_visible", target != null and perception_component != null and perception_component.is_currently_visible(target))

func get_squad_action_cost(order_type: SquadOrder.Type, base_cost: int) -> int:
	var adjusted_cost := base_cost
	if order_type == SquadOrder.Type.TAKE_COVER and get_active_cover() != null:
		adjusted_cost = 1
	match combat_role:
		SquadCombatRole.Type.MARKSMAN:
			if order_type == SquadOrder.Type.OVERWATCH:
				adjusted_cost = 1
			elif order_type in [SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT, SquadOrder.Type.ADVANCE]:
				adjusted_cost += 20
		SquadCombatRole.Type.MACHINE_GUNNER:
			if order_type == SquadOrder.Type.SUPPRESS:
				adjusted_cost = 1
			elif order_type in [SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT]:
				adjusted_cost += 24
		SquadCombatRole.Type.SHOTGUNNER:
			if order_type in [SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT, SquadOrder.Type.ADVANCE]:
				adjusted_cost = 1
			elif order_type == SquadOrder.Type.OVERWATCH:
				adjusted_cost += 18
		SquadCombatRole.Type.PISTOL_SCOUT:
			if order_type in [SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT]:
				adjusted_cost = 1
	if will_component:
		return will_component.get_command_cost(adjusted_cost)
	return adjusted_cost

func begin_squad_action(order_type: SquadOrder.Type) -> void:
	_equip_combat_weapon(firearm_weapon)
	_goap_controls_actor = true
	_active_squad_action = order_type
	_action_elapsed = 0.0
	_selected_cover = null
	_threat_response = _choose_threat_response()
	_threat_response_timer = 0.0
	_peek_window_remaining = 0.0
	_concealment_remaining = 0.0 if order_type == SquadOrder.Type.FOCUS_FIRE and _ambush_followup_active else randf_range(0.25, 0.75)
	_cover_strafe_target = randf_range(-70.0, 70.0)
	_cover_reposition_wait = randf_range(0.15, 0.55)
	if not (order_type == SquadOrder.Type.FOCUS_FIRE and _ambush_followup_active):
		set_weapon_aiming(false)
	var details := _get_action_plan_text(order_type)
	if squad_member:
		squad_member.set_ai_status("执行队长命令", _get_action_name(order_type), details)
	if order_type in [SquadOrder.Type.ADVANCE, SquadOrder.Type.RETREAT, SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT, SquadOrder.Type.SEARCH_AREA]:
		exit_cover()

func perform_squad_action(order_type: SquadOrder.Type, delta: float) -> bool:
	_action_elapsed += delta
	match order_type:
		SquadOrder.Type.HOLD:
			velocity = Vector2.ZERO
			return _action_elapsed >= 0.5
		SquadOrder.Type.TAKE_COVER:
			return _move_into_cover()
		SquadOrder.Type.STAY_HIDDEN:
			if not _move_into_cover():
				return false
			set_cover_precision(false)
			velocity = Vector2.ZERO
			return _action_elapsed >= 1.2
		SquadOrder.Type.FOCUS_FIRE:
			if not _move_into_cover():
				return false
			_fire_for_command(true, delta)
			return _action_elapsed >= 1.6
		SquadOrder.Type.SUPPRESS:
			if not _move_into_cover():
				return false
			_fire_for_command(false, delta)
			return _action_elapsed >= 2.0
		SquadOrder.Type.OVERWATCH:
			if not _move_into_cover():
				return false
			_fire_for_command(true, delta)
			return _action_elapsed >= 2.4
		SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT:
			return _perform_flank_action()
		SquadOrder.Type.AMBUSH_POSITION:
			var ambush_order := squad_member.get_current_order() if squad_member else null
			if ambush_order == null or ambush_order.target_position == Vector2.ZERO:
				velocity = Vector2.ZERO
				return true
			if is_instance_valid(ambush_order.assigned_cover):
				var active_cover := get_active_cover()
				if active_cover == ambush_order.assigned_cover:
					prepare_ambush_shot(_get_assigned_ambush_target(ambush_order.target))
					velocity = Vector2.ZERO
					return true
				if active_cover != null:
					exit_cover()
				_selected_cover = ambush_order.assigned_cover
				if not _move_into_cover():
					return false
				set_cover_precision(false)
				velocity = Vector2.ZERO
				return true
			if global_position.distance_to(ambush_order.target_position) > 55.0:
				exit_cover()
				_move_toward_position(ambush_order.target_position, SPEED * 0.82 * get_movement_speed_multiplier())
				return _action_elapsed >= 6.0
			velocity = Vector2.ZERO
			return true
		SquadOrder.Type.SEARCH_AREA:
			set_weapon_aiming(false)
			var search_order := squad_member.get_current_order() if squad_member else null
			if search_order == null or search_order.target_position == Vector2.ZERO:
				velocity = Vector2.ZERO
				return true
			if global_position.distance_to(search_order.target_position) > 55.0:
				exit_cover()
				_move_toward_position(search_order.target_position, SPEED * 0.72 * get_movement_speed_multiplier())
				return false
			velocity = Vector2.ZERO
			return _action_elapsed >= 2.0
		SquadOrder.Type.ADVANCE:
			var advance_target := _get_order_target()
			if advance_target:
				_move_toward_position(advance_target.global_position, SPEED * 1.05 * get_movement_speed_multiplier())
				_try_fire_at(advance_target.global_position)
				return _action_elapsed >= 2.0 or global_position.distance_to(advance_target.global_position) <= 175.0
			return true
		SquadOrder.Type.RETREAT:
			var retreat_target := _get_order_target()
			var retreat_order := squad_member.get_current_order() if squad_member else null
			if retreat_order and retreat_order.target_position != Vector2.ZERO:
				_move_toward_position(retreat_order.target_position, SPEED * get_movement_speed_multiplier())
				return global_position.distance_to(retreat_order.target_position) <= 55.0 or _action_elapsed >= 3.2
			if retreat_target:
				var away := (global_position - retreat_target.global_position).normalized()
				velocity = away * SPEED * get_movement_speed_multiplier()
			return _action_elapsed >= 2.0
	return true

func _perform_flank_action() -> bool:
	var order := squad_member.get_current_order() if squad_member else null
	var order_target := _get_order_target()
	if order == null or order.target_position == Vector2.ZERO or order_target == null:
		velocity = Vector2.ZERO
		return true
	var distance_to_destination := global_position.distance_to(order.target_position)
	if distance_to_destination > 55.0:
		set_weapon_aiming(false)
		_move_toward_position(order.target_position, SPEED * 1.08 * get_movement_speed_multiplier())
		if _action_elapsed >= 1.0 and global_position.distance_to(order_target.global_position) <= attack_range:
			_try_fire_at(order_target.global_position)
		return _action_elapsed >= 4.2
	velocity = Vector2.ZERO
	set_weapon_aiming(true)
	_try_fire_at(order_target.global_position)
	return _action_elapsed >= 3.2

func end_squad_action(order_type: SquadOrder.Type) -> void:
	if _active_squad_action != order_type:
		return
	_goap_controls_actor = false
	_active_squad_action = -1
	velocity = Vector2.ZERO
	if order_type == SquadOrder.Type.FOCUS_FIRE:
		_ambush_followup_active = false

func begin_safety_action() -> void:
	_equip_combat_weapon(firearm_weapon)
	_goap_controls_actor = true
	_active_squad_action = SquadOrder.Type.TAKE_COVER
	_action_elapsed = 0.0
	_selected_cover = null
	if squad_member:
		squad_member.set_ai_status("恐惧超过服从", "优先寻找掩体", "到达掩体 -> 盲射姿态")

func perform_safety_action(_delta: float) -> bool:
	if not _move_into_cover():
		return false
	set_cover_precision(false)
	return true

func end_safety_action() -> void:
	_goap_controls_actor = false
	_active_squad_action = -1
	velocity = Vector2.ZERO

func on_squad_goal_completed() -> void:
	if squad_member and squad_member.current_order:
		squad_member.set_ai_status("命令已完成", "恢复自主接敌", "已完成 v%d" % squad_member.current_order.version)

func is_melee_engagement_needed() -> bool:
	return target != null \
		and is_instance_valid(target) \
		and can_damage_target(target) \
		and global_position.distance_to(target.global_position) <= melee_trigger_distance

func get_melee_goal_priority() -> int:
	var result := 132
	if will_component:
		if will_component.profile == WillComponent.Profile.TIMID:
			result -= 22
		if will_component.mental_state == WillComponent.MentalState.AFRAID:
			result -= 18
		elif will_component.mental_state == WillComponent.MentalState.BROKEN:
			result -= 35
	return result

func prepare_melee_goal() -> int:
	melee_goal_version += 1
	return melee_goal_version

func begin_melee_engagement() -> void:
	_goap_controls_actor = true
	_melee_attack_started = false
	exit_cover()
	_equip_combat_weapon(melee_weapon)
	if squad_member:
		squad_member.set_ai_status("敌人距离过近", "拔出近战武器", "接近目标 -> 近战攻击")

func perform_melee_engagement(_delta: float) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	var distance := global_position.distance_to(target.global_position)
	if distance > melee_attack_distance:
		_move_toward_position(target.global_position, SPEED * get_movement_speed_multiplier())
		return false
	velocity = Vector2.ZERO
	if not _melee_attack_started:
		_melee_attack_started = melee_weapon.try_attack(target.global_position)
		return false
	return not melee_weapon.attacking

func end_melee_engagement() -> void:
	_goap_controls_actor = false
	velocity = Vector2.ZERO
	if not is_melee_engagement_needed():
		_equip_combat_weapon(firearm_weapon)

func _move_into_cover() -> bool:
	if get_active_cover() != null:
		velocity = Vector2.ZERO
		return true
	if _selected_cover == null or not is_instance_valid(_selected_cover):
		var order := squad_member.get_current_order() if squad_member else null
		var cover_target := _get_order_target()
		_selected_cover = order.assigned_cover if order and is_instance_valid(order.assigned_cover) else null
		if _selected_cover == null and cover_target:
			_selected_cover = cover_user.get_nearest_cover_against(cover_target.global_position)
		if _selected_cover == null:
			_selected_cover = _find_nearest_world_cover(cover_target.global_position if cover_target else global_position)
	if _selected_cover == null:
		velocity = Vector2.ZERO
		return false
	var approach_position: Vector2 = _selected_cover.global_position
	var active_order := squad_member.get_current_order() if squad_member else null
	if active_order and active_order.assigned_cover == _selected_cover and active_order.target_position != Vector2.ZERO:
		approach_position = active_order.target_position
	if global_position.distance_to(approach_position) <= 150.0:
		var cover_target := _get_order_target()
		var entered := enter_cover_against(_selected_cover, cover_target.global_position, false) if cover_target else enter_cover(_selected_cover, false)
		if not entered:
			_selected_cover = null
		return entered
	_move_toward_position(approach_position, SPEED * get_movement_speed_multiplier())
	return false

func _find_nearest_world_cover(threat_position: Vector2) -> Node:
	var nearest: Node = null
	var nearest_distance := INF
	for cover in get_tree().get_nodes_in_group("cover"):
		if not cover is Node2D or not cover.has_method("request_cover"):
			continue
		if cover.has_method("has_available_cover_against") and not cover.has_available_cover_against(threat_position):
			continue
		var distance := global_position.distance_to(cover.global_position)
		if distance < nearest_distance:
			nearest = cover
			nearest_distance = distance
	return nearest

func _move_toward_position(destination: Vector2, move_speed: float) -> void:
	if _movement_detour_destination.distance_to(destination) > 60.0:
		_movement_detour_waypoint = Vector2.ZERO
		_movement_detour_cover = null
		_completed_detour_covers.clear()
	_movement_detour_destination = destination
	if _movement_detour_waypoint != Vector2.ZERO and global_position.distance_to(_movement_detour_waypoint) <= 90.0:
		if is_instance_valid(_movement_detour_cover) and not _completed_detour_covers.has(_movement_detour_cover):
			_completed_detour_covers.append(_movement_detour_cover)
		_movement_detour_waypoint = Vector2.ZERO
		_movement_detour_cover = null
	if _movement_detour_waypoint == Vector2.ZERO:
		_movement_detour_waypoint = _find_cover_detour(destination)
	var movement_target := _movement_detour_waypoint if _movement_detour_waypoint != Vector2.ZERO else destination
	var direction := (movement_target - global_position).normalized()
	if nav:
		nav.target_position = movement_target
		var next_point := nav.get_next_path_position()
		if next_point != global_position:
			direction = (next_point - global_position).normalized()
	velocity = direction * move_speed

func _find_cover_detour(destination: Vector2) -> Vector2:
	var best_waypoint := Vector2.ZERO
	var nearest_distance := INF
	for cover in get_tree().get_nodes_in_group("cover"):
		if not is_instance_valid(cover) or _completed_detour_covers.has(cover) or not cover.has_method("get_navigation_detour_waypoint"):
			continue
		var waypoint_value: Variant = cover.get_navigation_detour_waypoint(global_position, destination)
		if not waypoint_value is Vector2:
			continue
		var waypoint := waypoint_value as Vector2
		var distance := global_position.distance_to(waypoint)
		if distance < nearest_distance:
			best_waypoint = waypoint
			nearest_distance = distance
			_movement_detour_cover = cover
	return best_waypoint

func _fire_for_command(precise: bool, delta: float) -> void:
	var order_target := _get_order_target()
	if order_target == null:
		velocity = Vector2.ZERO
		return
	if _ambush_followup_active and _ambush_followup_shots_fired >= _get_ambush_opening_shot_limit():
		velocity = Vector2.ZERO
		return
	var threatened := _is_player_threatening_me()
	if threatened:
		_threat_response_timer -= delta
		if _threat_response_timer <= 0.0:
			_threat_response = _choose_threat_response()
			_threat_response_timer = randf_range(0.8, 1.5)
		match _threat_response:
			ThreatResponse.WAIT:
				set_cover_precision(false)
				velocity = Vector2.ZERO
				if squad_member:
					squad_member.set_ai_status("等待火力间隙", "保持隐蔽", "确认压制 -> 等待 -> 重新判断")
				return
			ThreatResponse.BLIND_FIRE:
				set_cover_precision(false)
				if squad_member:
					squad_member.set_ai_status("受压制继续还击", "掩体后盲射", "保持隐蔽 -> 短暂盲射 -> 再评估")
			ThreatResponse.PRECISE_FIRE:
				if squad_member:
					squad_member.set_ai_status("冒险还击", "短暂探头射击", "观察火力 -> 探头 -> 短点射 -> 隐蔽")
	else:
		_threat_response = ThreatResponse.PRECISE_FIRE if precise else ThreatResponse.BLIND_FIRE

	if _threat_response == ThreatResponse.PRECISE_FIRE:
		set_weapon_aiming(true)
		if _concealment_remaining > 0.0:
			_concealment_remaining = maxf(0.0, _concealment_remaining - delta)
			set_cover_precision(false)
			velocity = Vector2.ZERO
			return
		if _peek_window_remaining <= 0.0:
			_peek_window_remaining = randf_range(0.55, 0.95)
		set_cover_precision(true)
		_peek_window_remaining = maxf(0.0, _peek_window_remaining - delta)
		if _peek_window_remaining <= 0.0:
			_concealment_remaining = randf_range(0.65, 1.25)
	else:
		set_weapon_aiming(false)
		set_cover_precision(false)
		_peek_window_remaining = 0.0
	_cover_reposition_wait = maxf(0.0, _cover_reposition_wait - delta)
	if _cover_reposition_wait <= 0.0 and cover_user.move_toward_lateral_offset(_cover_strafe_target, delta):
		_cover_strafe_target = randf_range(-70.0, 70.0)
		_cover_reposition_wait = randf_range(0.8, 1.6)
	velocity = Vector2.ZERO
	if _ambush_followup_active and firearm_weapon != null and can_damage_target(order_target):
		firearm_weapon.try_attack(order_target.global_position)
	else:
		_try_fire_at(order_target.global_position)

func _is_player_threatening_me() -> bool:
	if is_under_direct_threat():
		return true
	if target and target.has_method("is_aiming_at"):
		return bool(target.is_aiming_at(self))
	return false

func _choose_threat_response() -> ThreatResponse:
	var roll := randf()
	var suppression := get_suppression()
	if will_component and will_component.mental_state in [WillComponent.MentalState.AFRAID, WillComponent.MentalState.RECOVERING, WillComponent.MentalState.BROKEN]:
		if roll < 0.72:
			return ThreatResponse.WAIT
		return ThreatResponse.BLIND_FIRE
	if suppression >= 55.0:
		if will_component and will_component.profile == WillComponent.Profile.INDOCTRINATED:
			if roll < 0.12:
				return ThreatResponse.PRECISE_FIRE
			return ThreatResponse.BLIND_FIRE if roll < 0.78 else ThreatResponse.WAIT
		if will_component and will_component.profile == WillComponent.Profile.TIMID:
			return ThreatResponse.BLIND_FIRE if roll < 0.12 else ThreatResponse.WAIT
		return ThreatResponse.BLIND_FIRE if roll < 0.42 else ThreatResponse.WAIT
	if will_component == null:
		return ThreatResponse.BLIND_FIRE if roll < 0.6 else ThreatResponse.WAIT
	match will_component.profile:
		WillComponent.Profile.INDOCTRINATED:
			if roll < 0.28:
				return ThreatResponse.PRECISE_FIRE
			return ThreatResponse.BLIND_FIRE if roll < 0.88 else ThreatResponse.WAIT
		WillComponent.Profile.TIMID:
			if roll < 0.02:
				return ThreatResponse.PRECISE_FIRE
			return ThreatResponse.BLIND_FIRE if roll < 0.32 else ThreatResponse.WAIT
		_:
			if roll < 0.10:
				return ThreatResponse.PRECISE_FIRE
			return ThreatResponse.BLIND_FIRE if roll < 0.62 else ThreatResponse.WAIT

func _get_order_target() -> Node2D:
	var order := squad_member.get_current_order() if squad_member else null
	if order and _is_live_combat_target(order.target):
		return order.target
	if _is_live_combat_target(target):
		return target
	if squad_member != null and squad_member.blackboard != null:
		var shared_target := squad_member.blackboard.shared_target
		if _is_live_combat_target(shared_target) and can_damage_target(shared_target):
			return shared_target
	return null

func _is_live_combat_target(candidate: Node) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return false
	return not candidate.has_method("is_combat_alive") or bool(candidate.is_combat_alive())

func _process_ambush_followup() -> void:
	if not _ambush_followup_active:
		return
	if _ambush_followup_shots_fired >= _get_ambush_opening_shot_limit():
		_ambush_followup_active = false
		return
	var order := squad_member.get_current_order() if squad_member else null
	if order == null or order.type != SquadOrder.Type.FOCUS_FIRE or firearm_weapon == null or firearm_weapon.reloading:
		_ambush_followup_active = false
		return
	var followup_target := _get_order_target()
	if followup_target == null or not can_damage_target(followup_target):
		return
	firearm_weapon.try_attack(followup_target.global_position)

func _get_base_action_cost(order_type: SquadOrder.Type) -> int:
	match order_type:
		SquadOrder.Type.SEARCH_AREA:
			return 5
		SquadOrder.Type.AMBUSH_POSITION:
			return 3
		SquadOrder.Type.ADVANCE:
			return 24
		SquadOrder.Type.RETREAT:
			return 5
		SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT:
			return 10
		SquadOrder.Type.OVERWATCH:
			return 4
		SquadOrder.Type.TAKE_COVER:
			return 4
		SquadOrder.Type.STAY_HIDDEN:
			return 2
		SquadOrder.Type.FOCUS_FIRE, SquadOrder.Type.SUPPRESS:
			return 3
	return 1

func _get_action_name(order_type: SquadOrder.Type) -> String:
	match order_type:
		SquadOrder.Type.SEARCH_AREA:
			return "搜索区域"
		SquadOrder.Type.AMBUSH_POSITION:
			return "Silent approach"
		SquadOrder.Type.TAKE_COVER:
			return "移动到最近掩体"
		SquadOrder.Type.STAY_HIDDEN:
			return "保持隐蔽"
		SquadOrder.Type.FOCUS_FIRE:
			return "精准集中射击"
		SquadOrder.Type.SUPPRESS:
			return "盲射压制"
		SquadOrder.Type.ADVANCE:
			return "离开掩体推进"
		SquadOrder.Type.RETREAT:
			return "脱离接触撤退"
		SquadOrder.Type.OVERWATCH:
			return "后排精确警戒"
		SquadOrder.Type.FLANK_LEFT:
			return "向左侧翼机动"
		SquadOrder.Type.FLANK_RIGHT:
			return "向右侧翼机动"
	return "原地待命"

func _get_action_plan_text(order_type: SquadOrder.Type) -> String:
	match order_type:
		SquadOrder.Type.SEARCH_AREA:
			return "离开旧掩体 -> 保持队形 -> 搜索前方区域"
		SquadOrder.Type.AMBUSH_POSITION:
			return "Hold fire -> move to ambush position -> await command"
		SquadOrder.Type.TAKE_COVER:
			return "选择最近矮墙 -> 移动 -> 进入掩体"
		SquadOrder.Type.STAY_HIDDEN:
			return "进入掩体 -> 降低暴露 -> 停止射击"
		SquadOrder.Type.FOCUS_FIRE:
			return "确认目标 -> 精确姿态 -> 连续射击"
		SquadOrder.Type.SUPPRESS:
			return "确认目标 -> 盲射姿态 -> 持续压制"
		SquadOrder.Type.ADVANCE:
			return "离开掩体 -> 接近目标 -> 移动射击"
		SquadOrder.Type.RETREAT:
			return "脱离掩体 -> 远离目标 -> 保存生命"
		SquadOrder.Type.OVERWATCH:
			return "占据后排掩体 -> 观察暴露目标 -> 精确射击"
		SquadOrder.Type.FLANK_LEFT, SquadOrder.Type.FLANK_RIGHT:
			return "确认压制火力 -> 沿侧翼移动 -> 近距离攻击"
	return "停止移动 -> 观察战场"

func _on_goap_plan_changed(plan: Array) -> void:
	if squad_member == null or plan.is_empty():
		return
	var steps: PackedStringArray = []
	for item in plan:
		if item is GoapAction:
			steps.append(item.get_action_name())
	if not steps.is_empty():
		squad_member.set_ai_status(squad_member.intent_text, squad_member.action_text, " -> ".join(steps))

func _on_goap_goal_changed(goal: GoapGoal) -> void:
	if squad_member == null or goal == null:
		return
	var intent := "优先保全生命" if goal is PreserveLifeGoal else "服从队长命令"
	squad_member.set_ai_status(intent, "GOAP 正在规划", squad_member.plan_text)

func _on_goap_action_changed(action: GoapAction) -> void:
	if squad_member == null:
		return
	var action_name: String = str(action.get_action_name()) if action else "行动完成"
	squad_member.set_ai_status(squad_member.intent_text, action_name, squad_member.plan_text)

func _get_rules_of_engagement() -> RulesOfEngagement.Type:
	if squad_member == null or squad_member.blackboard == null:
		return RulesOfEngagement.Type.WEAPONS_FREE
	return int(squad_member.blackboard.get_fact(&"roe", RulesOfEngagement.Type.WEAPONS_HOLD)) as RulesOfEngagement.Type

func _is_fire_authorized(candidate: Node2D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if global_position.distance_to(candidate.global_position) > attack_range:
		return false
	var roe := _get_rules_of_engagement()
	if roe == RulesOfEngagement.Type.WEAPONS_HOLD:
		return false
	var visible := perception_component != null and perception_component.is_currently_visible(candidate)
	if roe == RulesOfEngagement.Type.WEAPONS_TIGHT:
		return visible
	if visible:
		return true
	var order := squad_member.get_current_order() if squad_member else null
	return order != null and order.type == SquadOrder.Type.SUPPRESS

func on_hostile_gunshot_heard(_position: Vector2, _source: Node2D) -> void:
	if state == State.DEAD or alert_component == null or alert_component.state >= AlertComponent.State.CONTACT:
		return
	if _surprise_reaction_timer > 0.0:
		return
	_surprise_reaction_timer = randf_range(surprise_reaction_min, surprise_reaction_max)
	velocity = Vector2.ZERO
	if squad_member:
		squad_member.set_ai_status("遭到突然袭击", "受惊反应", "听到敌方枪声 -> 停顿 -> 恢复判断")
	surprise_reaction_started.emit(_surprise_reaction_timer)

func get_surprise_reaction_remaining() -> float:
	return _surprise_reaction_timer

func _on_firearm_fired() -> void:
	if _ambush_followup_active:
		_ambush_followup_shots_fired += 1
	_visual_recoil = 1.0
	_muzzle_flash_remaining = 0.075
	if muzzle_flash_visual:
		muzzle_flash_visual.visible = true
	report_weapon_fired()
	reveal_from_concealment()
	if alert_component:
		alert_component.enter_combat(global_position)
	for listener in get_tree().get_nodes_in_group("perception_listener"):
		if listener != perception_component and listener.has_method("hear_stimulus"):
			listener.hear_stimulus(global_position, self, 1.0)

func set_weapon_aiming(enabled: bool) -> void:
	super.set_weapon_aiming(enabled)
	if perception_component == null:
		return
	if combat_role == SquadCombatRole.Type.MARKSMAN and enabled:
		perception_component.sight_range = marksman_aim_sight_range
		perception_component.field_of_view_degrees = marksman_aim_field_of_view
	else:
		perception_component.sight_range = standard_sight_range
		perception_component.field_of_view_degrees = standard_field_of_view

func prepare_ambush_shot(assigned_target: Node2D) -> void:
	if not is_instance_valid(assigned_target):
		return
	if _prepared_ambush_target != assigned_target:
		_prepared_ambush_target = assigned_target
		if aim_component:
			aim_component.reset_aim()
	target = assigned_target
	current_target = assigned_target
	velocity = Vector2.ZERO
	if get_active_cover() != null:
		set_cover_precision(true)
	else:
		set_weapon_aiming(true)
	if squad_member:
		squad_member.set_ai_status("伏击准备", "瞄准分配目标", "隐蔽就位 -> 稳定瞄准 -> 等待齐射")

func is_ambush_shot_ready(required_quality := 0.9) -> bool:
	return is_instance_valid(_prepared_ambush_target) \
		and aim_component != null \
		and aim_component.is_settled(required_quality) \
		and velocity.length_squared() <= 25.0

func release_ambush_shot(assigned_target: Node2D) -> bool:
	if not is_instance_valid(assigned_target) or not is_ambush_shot_ready():
		return false
	if firearm_weapon == null or firearm_weapon.reloading or not can_damage_target(assigned_target):
		return false
	prepare_ambush_shot(assigned_target)
	# A coordinated volley uses the squad's confirmed target assignment instead of
	# re-running the normal personal-visibility gate at the instant of release.
	_ambush_followup_active = true
	_ambush_followup_shots_fired = 0
	var fired := firearm_weapon.try_attack(assigned_target.global_position)
	if fired:
		_prepared_ambush_target = null
		if squad_member:
			squad_member.set_ai_status("队长下令开火", "执行同步齐射", "目标锁定 -> FIRE NOW -> 继续交战")
	else:
		_ambush_followup_active = false
	return fired

func _get_ambush_opening_shot_limit() -> int:
	if firearm_weapon is SmgWeapon:
		return 4
	match combat_role:
		SquadCombatRole.Type.MACHINE_GUNNER:
			return 4
		SquadCombatRole.Type.PISTOL_SCOUT:
			return 2
	return 1

func _get_assigned_ambush_target(fallback: Node2D) -> Node2D:
	if squad_member != null and squad_member.coordinator != null and squad_member.coordinator.has_method("get_ambush_target_for"):
		var assigned := squad_member.coordinator.get_ambush_target_for(squad_member) as Node2D
		if is_instance_valid(assigned):
			return assigned
	return fallback

func _update_visual(delta: float) -> void:
	if state == State.DEAD or anatomy_root == null or gun_sprite == null or muzzle == null:
		return

	_update_movement_animation(delta)
	var dir := get_facing_direction()
	if target != null and perception_component != null and perception_component.is_currently_visible(target):
		dir = target.global_position - global_position
		if dir != Vector2.ZERO:
			last_move_dir = dir.normalized()
	var facing := -1.0 if dir.x < 0.0 else 1.0
	anatomy_root.scale.x = facing
	melee_visual.scale.x = facing
	_visual_recoil = move_toward(_visual_recoil, 0.0, delta * 12.0)
	_muzzle_flash_remaining = maxf(0.0, _muzzle_flash_remaining - delta)
	var visual_y := anatomy_root.position.y
	gun_sprite.flip_h = facing < 0.0
	gun_sprite.position = Vector2((20.0 - _visual_recoil * 6.0) * facing, visual_y)
	gun_sprite.rotation = -0.04 * _visual_recoil * facing
	melee_visual.position.x = 0.0 if facing > 0.0 else -34.0
	muzzle.position = Vector2(44.0 * facing, visual_y)
	muzzle_flash_visual.position = muzzle.position
	muzzle_flash_visual.rotation = 0.0 if facing > 0.0 else PI
	muzzle_flash_visual.visible = _muzzle_flash_remaining > 0.0 and current_combat_weapon == firearm_weapon
	muzzle_flash_visual.scale = Vector2.ONE * (0.85 + _visual_recoil * 0.35)
	if injury_component == null or injury_component.arm_wounds == 0:
		weapon_arm_visual.points = PackedVector2Array([
			Vector2(-7, -6), Vector2(7, -1), Vector2(20.0 - _visual_recoil * 4.0, -_visual_recoil * 2.0),
		])

func _update_movement_animation(delta: float) -> void:
	var moving := velocity.length_squared() > 100.0
	if moving:
		_walk_phase += delta * 10.0
		var stride := sin(_walk_phase) * 6.0
		anatomy_root.position.y = sin(_walk_phase * 2.0) * 1.6
		anatomy_root.rotation = sin(_walk_phase) * 0.025
		if injury_component == null or injury_component.leg_wounds == 0:
			left_leg_visual.points = PackedVector2Array([
				Vector2(-7, 13), Vector2(-10, 27), Vector2(-16 + stride, 38),
			])
			right_leg_visual.points = PackedVector2Array([
				Vector2(7, 13), Vector2(10, 27), Vector2(17 - stride, 37),
			])
	else:
		anatomy_root.position.y = move_toward(anatomy_root.position.y, 0.0, delta * 18.0)
		anatomy_root.rotation = move_toward(anatomy_root.rotation, 0.0, delta * 8.0)
		if injury_component == null or injury_component.leg_wounds == 0:
			left_leg_visual.points = PackedVector2Array([
				Vector2(-7, 13), Vector2(-10, 27), Vector2(-16, 38),
			])
			right_leg_visual.points = PackedVector2Array([
				Vector2(7, 13), Vector2(10, 27), Vector2(17, 37),
			])

func _setup_hp_bar() -> void:
	hp_bar = ProgressBar.new()
	hp_bar.name = "EnemyHPBar"
	hp_bar.max_value = max_health
	hp_bar.value = health
	hp_bar.show_percentage = false
	hp_bar.position = Vector2(-28, -48)
	hp_bar.size = Vector2(56, 8)
	hp_bar.z_index = 10
	add_child(hp_bar)

func _update_hp_bar() -> void:
	if hp_bar == null or not is_instance_valid(hp_bar):
		return
	hp_bar.max_value = max_health
	hp_bar.value = health
	hp_bar.visible = health > 0

func start_flashing() -> void:
	if anatomy_root == null:
		super.start_flashing()
		return
	anatomy_root.modulate = Color(1.0, 0.3, 0.24, 1.0)
	var tween := create_tween()
	tween.tween_property(anatomy_root, "modulate", Color.WHITE, 0.12)
