extends Node

const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")
const COVER_SCENE := preload("res://ai3d/tactical_cover_3d.tscn")
const ENEMY_SQUADS := [
	preload("res://Prefab/Enemy3D/rifle_fireteam_3d.tscn"),
	preload("res://Prefab/Enemy3D/heavy_support_squad_3d.tscn"),
	preload("res://Prefab/Enemy3D/scout_raider_squad_3d.tscn"),
	preload("res://Prefab/Enemy3D/assault_raider_squad_3d.tscn"),
	preload("res://Prefab/Enemy3D/east_reinforcement_squad_3d.tscn"),
]

func _ready() -> void:
	_test_fire_cycles()
	await _test_suppression_and_cover()
	await _test_cover_posture_and_fire()
	await _test_enemy_prefabs()
	print("COH-style combat rhythm test passed: bursts, setup arcs, suppression, cover impacts, and 3D enemy AI configuration verified.")
	get_tree().quit()

func _test_fire_cycles() -> void:
	var target := Node.new()
	add_child(target)
	var smg := WeaponFireCycle3D.new()
	add_child(smg)
	smg.configure({
		"id": "test_smg",
		"family": "smg",
		"fire_interval": 0.1,
		"aim_settle_time": 0.4,
		"reload_duration": 1.8,
	}, Soldier3D.CombatRole.SMG, 17)
	assert(not smg.can_fire(target), "A new target must require acquisition time.")
	smg.process(1.0)
	var burst_shots := 0
	while smg.phase != WeaponFireCycle3D.Phase.RECOVERING and burst_shots < 20:
		if smg.can_fire(target):
			smg.record_shot()
			burst_shots += 1
		smg.process(0.11)
	assert(burst_shots >= 3 and burst_shots <= 7, "SMG must fire a bounded burst before recovery.")

	var lmg := WeaponFireCycle3D.new()
	add_child(lmg)
	lmg.configure({
		"id": "test_lmg",
		"family": "lmg",
		"fire_interval": 0.1,
		"aim_settle_time": 0.7,
		"reload_duration": 3.0,
	}, Soldier3D.CombatRole.MACHINE_GUNNER, 23)
	assert(lmg.get_required_aim_duration() >= 1.4, "LMG setup time must extend initial aim.")
	lmg.complete_aim(Vector3.FORWARD)
	assert(not lmg.requires_reaim(Vector3.FORWARD), "LMG must retain a target inside its fire arc.")
	assert(lmg.requires_reaim(Vector3.BACK), "LMG must re-aim and set up outside its fire arc.")
	lmg.notify_movement_started()
	assert(lmg.get_required_aim_duration() >= 1.4, "Moving must tear down the LMG setup.")
	target.queue_free()
	smg.queue_free()
	lmg.queue_free()

func _test_suppression_and_cover() -> void:
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	soldier.set_physics_process(false)
	add_child(soldier)
	await get_tree().process_frame
	for _index in 4:
		soldier.suppression_component.report_near_miss(Vector3.FORWARD * 10.0)
	assert(soldier.is_pinned(), "Four close rounds must be able to pin an exposed soldier.")
	assert(is_zero_approx(soldier.get_current_move_speed()), "Pinned soldiers must not move.")
	assert(not soldier._try_attack_target(null), "Pinned soldiers must not fire.")

	var protected_soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	protected_soldier.set_physics_process(false)
	var cover := COVER_SCENE.instantiate() as TacticalCover3D
	add_child(cover)
	add_child(protected_soldier)
	await get_tree().process_frame
	var threat := Vector3(0.0, 0.0, 10.0)
	var slot := cover.reserve_slot(protected_soldier, threat)
	assert(slot != null, "Cover must provide a directional protected slot.")
	var departure := cover.get_departure_route(slot, Vector3(12.0, 0.0, 10.0))
	assert(not departure.is_empty() and absf(cover.to_local(departure[0]).x) > cover.cover_length * 0.5,
		"Cover departure must route a soldier around an end of the wall.")
	assert(signf(cover.to_local(departure[0]).z) == signf(slot.position.z),
		"Cover departure must remain on the occupied safe side.")
	protected_soldier.global_position = slot.global_position
	protected_soldier.active_cover = cover
	protected_soldier.active_cover_slot = slot
	cover.report_projectile_impact(threat, 1.0)
	assert(protected_soldier.get_suppression_ratio() > 0.0, "Rounds striking cover must suppress its protected occupants.")
	assert(protected_soldier.is_protected_from_position(threat), "Cover protection must depend on threat direction.")
	var released_occupant := SOLDIER_SCENE.instantiate() as Soldier3D
	released_occupant.set_physics_process(false)
	add_child(released_occupant)
	await get_tree().process_frame
	var released_slot := cover.reserve_slot(released_occupant, -threat)
	assert(released_slot != null, "A disposable occupant must be able to reserve cover.")
	released_occupant.free()
	assert(cover.score_for_actor(protected_soldier, -threat) > -INF,
		"Freed cover occupants must be purged before cover scoring.")
	assert(cover.reserve_specific_slot(soldier, released_slot),
		"A slot held by a freed occupant must become reservable again.")
	var assessment := FireSuperiorityAssessment3D.new().assess([soldier, protected_soldier], 2)
	assert(String(assessment.get("state_name", "")) in ["LOSING", "PINNED"], "Pinned members must reduce squad fire superiority.")
	soldier.queue_free()
	protected_soldier.queue_free()
	cover.queue_free()
	await get_tree().process_frame

func _test_cover_posture_and_fire() -> void:
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	var target := SOLDIER_SCENE.instantiate() as Soldier3D
	var cover := COVER_SCENE.instantiate() as TacticalCover3D
	soldier.set_physics_process(false)
	target.set_physics_process(false)
	soldier.combat_team = Soldier3D.Team.BLUE
	target.combat_team = Soldier3D.Team.RED
	add_child(cover)
	add_child(soldier)
	add_child(target)
	target.global_position = Vector3(0.0, 0.0, -8.0)
	await get_tree().physics_frame
	var slot := cover.reserve_slot(soldier, target.global_position)
	assert(slot != null, "Cover posture test requires a reserved slot.")
	soldier.global_position = slot.global_position
	soldier.active_cover = cover
	soldier.active_cover_slot = slot
	soldier.set_cover_exposed(false)
	soldier.set_stance(Soldier3D.Stance.CROUCH)
	soldier.set_stance(Soldier3D.Stance.PRONE)
	assert(soldier.stance == Soldier3D.Stance.STAND, "Cover hiding must remain separate from crouch and prone stance.")
	soldier.current_target = target
	soldier.set("_operation_elapsed", 10.0)
	assert(not soldier._try_attack_target(target), "A soldier hidden behind cover must not fire.")
	assert(soldier._perform_aim(), "A covered soldier must be able to aim after standing up.")
	assert(soldier.is_cover_exposed() and soldier.stance == Soldier3D.Stance.STAND,
		"A covered soldier must use the exposed standing cover pose before aiming or firing.")
	assert(not soldier.is_autonomy_action_valid(SoldierAutonomyAction3D.Operation.BLIND_FIRE_FROM_COVER),
		"Blind fire must remain unavailable until its later integration.")
	soldier.end_goap_operation(SoldierDirectiveAction3D.Operation.ENGAGE)
	assert(not soldier.is_cover_exposed() and soldier.stance == Soldier3D.Stance.STAND,
		"A covered soldier must return to the hidden cover pose after an engage action.")
	soldier.queue_free()
	target.queue_free()
	cover.queue_free()
	await get_tree().process_frame

func _test_enemy_prefabs() -> void:
	for scene in ENEMY_SQUADS:
		var squad := scene.instantiate() as SquadCoordinator3D
		assert(squad != null, "Enemy prefab root must be SquadCoordinator3D.")
		assert(squad.use_advanced_tactics, "Every formal 3D enemy prefab must enable advanced tactics.")
		assert(not squad.use_qwen, "Formal enemies must use deterministic combat planning without Qwen.")
		add_child(squad)
		await get_tree().process_frame
		assert(not squad.get_configured_member_actors().is_empty(), "Enemy prefab must contain configured soldiers.")
		for member in squad.get_configured_member_actors():
			assert(member.fire_cycle_component != null, "Every enemy soldier must use the shared weapon fire cycle.")
			assert(member.perception_component != null and member.suppression_component != null, "Every enemy soldier must have perception and suppression components.")
			assert(member.working_memory != null and member.get("_goap_agent") is GoapAgent,
				"Every formal enemy must use F.E.A.R.-style memory and GOAP arbitration.")
		squad.queue_free()
		await get_tree().process_frame
