extends Node

const SOLDIER_SCENE := preload("res://ai3d/soldier_3d.tscn")
const MACHINE_GUN_SCENE := preload("res://ai3d/structures/machine_gun_emplacement_3d.tscn")
var _failed := false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var emplacement := MACHINE_GUN_SCENE.instantiate() as MachineGunEmplacement3D
	emplacement.name = "StateChart_Test_Emplacement"
	emplacement.assigned_team = Soldier3D.Team.RED
	add_child(emplacement)
	var soldier := SOLDIER_SCENE.instantiate() as Soldier3D
	soldier.name = "StateChart_Test_Operator"
	soldier.combat_team = Soldier3D.Team.RED
	add_child(soldier)
	await get_tree().physics_frame
	soldier.relocate_for_scenario_setup(emplacement.get_operator_position())

	var timed := SquadDirective3D.new().configure(
		SquadDirective3D.Type.USE_STRUCTURE,
		71,
		null,
		emplacement.get_operator_position(),
		[],
		null,
		0.25,
		"timed structure operation",
		&"",
		SquadDirective3D.RulesOfEngagement.WEAPONS_FREE,
		emplacement
	)
	soldier.receive_directive(timed)
	await _wait_physics_frames(70)
	print("[TACTICAL_STRUCTURE_SMOKE_STATE] version=%d completed=%d operation_elapsed=%.3f snapshot=%s" % [
		soldier.get_directive_version(), soldier.last_completed_directive_version, soldier._operation_elapsed,
		str(soldier.get_autonomy_debug_snapshot()),
	])
	_assert(emplacement.is_occupied_by(soldier), "State Chart must enter the assigned emplacement")
	_assert(soldier.last_completed_directive_version == 71, "timed structure operation must complete explicitly")

	var danger := SquadInfluenceMap3D.new()
	danger.configure(2.0, 20.0)
	danger.origin = emplacement.get_operator_position()
	for x in range(-6, 7):
		for z in range(-6, 7):
			danger.cells[Vector2i(x, z)] = _danger_cell(100.0)
	danger.version = 11
	soldier.relocate_for_scenario_setup(emplacement.get_operator_position() + Vector3(0.0, 0.0, 8.0))
	soldier.set_squad_influence_map(danger)
	var initial_distance := soldier.global_position.distance_to(emplacement.get_operator_position())

	var persistent := SquadDirective3D.new().configure(
		SquadDirective3D.Type.USE_STRUCTURE,
		72,
		null,
		emplacement.get_operator_position(),
		[],
		null,
		0.0,
		"persistent structure operation",
		&"",
		SquadDirective3D.RulesOfEngagement.WEAPONS_FREE,
		emplacement
	)
	soldier.receive_directive(persistent)
	await _wait_physics_frames(20)
	_assert(soldier.global_position.distance_to(emplacement.get_operator_position()) <= initial_distance + 0.5,
		"a committed structure order must not retreat merely because its only route is dangerous")
	await _wait_physics_frames(180)
	_assert(emplacement.is_occupied_by(soldier), "persistent operation must retain occupancy")
	_assert(soldier.last_completed_directive_version < 72, "duration zero must keep operating instead of completing accidentally")
	var snapshot := soldier.get_autonomy_debug_snapshot()
	_assert(soldier.get_directive_version() == 72, "survival reactions must not replace the committed directive")
	_assert(snapshot.get("root_state", "") == "EXECUTE_ORDER", "high route danger must not trap a committed order in survival override")
	_assert(snapshot.get("action", "") == "OPERATE_STRUCTURE", "State Chart must remain in the structure operation state")
	print("[TACTICAL_STRUCTURE_SMOKE_PASS] occupant=%s action=%s" % [soldier.name, snapshot.get("action", "")])
	get_tree().quit(1 if _failed else 0)

func _danger_cell(enemy_threat: float) -> Dictionary:
	return {
		SquadInfluenceMap3D.LAYER_ENEMY_THREAT: enemy_threat,
		SquadInfluenceMap3D.LAYER_FRIENDLY_SUPPORT: 0.0,
		SquadInfluenceMap3D.LAYER_SUPPRESSION: 0.0,
		SquadInfluenceMap3D.LAYER_COVER: 0.0,
		SquadInfluenceMap3D.LAYER_CONCEALMENT: 0.0,
		SquadInfluenceMap3D.LAYER_ROUTE_EXPOSURE: 0.0,
		SquadInfluenceMap3D.LAYER_OBJECTIVE: 0.0,
		SquadInfluenceMap3D.LAYER_INFORMATION: 0.0,
	}

func _wait_physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[TACTICAL_STRUCTURE_SMOKE_FAIL] %s" % message)
