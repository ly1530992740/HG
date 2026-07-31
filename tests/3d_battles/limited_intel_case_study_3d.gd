extends Node3D
class_name LimitedIntelCaseStudy3D

@export var show_debug_hud := true
@export var case_title := "LIMITED INTEL CASE STUDY"
@export var defended_route_zone_id: StringName = &"left_route"
@export var flank_route_zone_id: StringName = &"right_grass"

var elapsed := 0.0
var event_log: Array[Dictionary] = []
var blue_first_contact_count := -1
var blue_max_known_contacts_before_left_recon := 0
var blue_recon_started := false
var blue_left_contact_discovered := false
var blue_left_observed := false
var blue_right_observed := false
var blue_defended_route_observed := false
var blue_flank_route_observed := false
var blue_defended_route_contacts := -1
var blue_flank_route_contacts := -1
var blue_flank_started := false
var blue_flank_zone := ""
var blue_flank_task_succeeded := false
var blue_synchronized_attack_started := false
var blue_synchronized_attack_shots := 0
var red_hold_reached := false
var red_defend_started := false
var red_max_mission_distance := 0.0
var shots_blue := 0
var shots_red := 0
var deaths_blue := 0
var deaths_red := 0
var _last_blue_candidate_id := ""
var _blue_flanker_ids: Dictionary = {}

@onready var blue: SquadCoordinator3D = $BlueSquad
@onready var red: SquadCoordinator3D = $RedSquad
@onready var debug_label: Label = $DebugLayer/Panel/DebugLabel

func _ready() -> void:
	$Camera3D.look_at(Vector3(0.0, 0.0, -1.5), Vector3.UP)
	debug_label.visible = show_debug_hud
	call_deferred("_bind_runtime")

func _process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(blue) or not is_instance_valid(red):
		return
	var target := red.get_mission_target_position()
	for member in red.get_living_members():
		var offset := member.global_position - target
		offset.y = 0.0
		red_max_mission_distance = maxf(red_max_mission_distance, offset.length())
	var advanced := blue.get_advanced_tactics()
	if advanced != null and not blue_left_contact_discovered:
		blue_max_known_contacts_before_left_recon = maxi(
			blue_max_known_contacts_before_left_recon,
			advanced.belief.get_estimated_enemy_count()
		)
	_observe_tactical_execution(advanced)
	_update_hud()

func _bind_runtime() -> void:
	var blue_advanced := blue.get_advanced_tactics()
	var red_advanced := red.get_advanced_tactics()
	if blue_advanced != null:
		blue_advanced.belief_report_accepted.connect(_on_blue_report)
		blue_advanced.tactical_candidates_evaluated.connect(_on_blue_candidates)
		blue_advanced.mission_state_changed.connect(_on_blue_mission_state)
	if red_advanced != null:
		red_advanced.mission_state_changed.connect(_on_red_mission_state)
	blue.command_changed.connect(_on_blue_command)
	red.command_changed.connect(_on_red_command)
	for soldier in blue.get_configured_member_actors() + red.get_configured_member_actors():
		if not soldier.weapon_fired.is_connected(_on_weapon_fired):
			soldier.weapon_fired.connect(_on_weapon_fired)
		if not soldier.died.is_connected(_on_soldier_died):
			soldier.died.connect(_on_soldier_died)
	_record("SCENARIO_READY", {"blue": blue.members.size(), "red": red.members.size()})

func get_case_metrics() -> Dictionary:
	var blue_advanced := blue.get_advanced_tactics() if is_instance_valid(blue) else null
	var red_advanced := red.get_advanced_tactics() if is_instance_valid(red) else null
	return {
		"elapsed": elapsed,
		"blue_first_contact_count": blue_first_contact_count,
		"blue_max_known_before_left": blue_max_known_contacts_before_left_recon,
		"blue_recon_started": blue_recon_started,
		"blue_left_observed": blue_left_observed,
		"blue_right_observed": blue_right_observed,
		"blue_defended_route_observed": blue_defended_route_observed,
		"blue_flank_route_observed": blue_flank_route_observed,
		"blue_defended_route_contacts": blue_defended_route_contacts,
		"blue_flank_route_contacts": blue_flank_route_contacts,
		"blue_flank_started": blue_flank_started,
		"blue_flank_zone": blue_flank_zone,
		"blue_flank_task_succeeded": blue_flank_task_succeeded,
		"blue_synchronized_attack_started": blue_synchronized_attack_started,
		"blue_synchronized_attack_shots": blue_synchronized_attack_shots,
		"red_hold_reached": red_hold_reached,
		"red_defend_started": red_defend_started,
		"red_max_mission_distance": red_max_mission_distance,
		"shots_blue": shots_blue,
		"shots_red": shots_red,
		"deaths_blue": deaths_blue,
		"deaths_red": deaths_red,
		"blue_alive": blue.get_living_members().size() if is_instance_valid(blue) else 0,
		"red_alive": red.get_living_members().size() if is_instance_valid(red) else 0,
		"blue_mission": blue_advanced.mission.get_state_name() if blue_advanced != null else "NONE",
		"red_mission": red_advanced.mission.get_state_name() if red_advanced != null else "NONE",
		"red_task_debug": _task_debug(red_advanced),
		"red_member_debug": _member_debug(red),
		"blue_task_debug": _task_debug(blue_advanced),
		"blue_member_debug": _member_debug(blue),
		"events": event_log.duplicate(true),
	}

func _task_debug(advanced: SquadAdvancedTactics3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if advanced == null or advanced.scheduler == null or advanced.scheduler.active_plan == null:
		return result
	for task in advanced.scheduler.active_plan.tasks:
		result.append({
			"id": String(task.task_id),
			"type": task.get_type_name(),
			"state": task.get_state_name(),
			"members": task.member_states.duplicate(true),
		})
	return result

func _member_debug(squad: SquadCoordinator3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member in squad.get_living_members():
		var agent := member.get("_goap_agent") as GoapAgent
		var action := agent.get_current_action() if agent != null else null
		result.append({
			"id": String(member.name),
			"position": [snappedf(member.global_position.x, 0.1), snappedf(member.global_position.z, 0.1)],
			"stance": int(member.stance),
			"cover": is_instance_valid(member.active_cover),
			"directive": member.active_directive.get_label() if member.active_directive != null else "NONE",
			"directive_version": member.get_directive_version(),
			"completed_version": member.last_completed_directive_version,
			"target_position": [
				snappedf(member.active_directive.target_position.x, 0.1),
				snappedf(member.active_directive.target_position.z, 0.1),
			] if member.active_directive != null else [],
			"route_index": int(member.get("_route_index")),
			"action": String(action.name) if action != null else "NONE",
			"local_navigation": member.get_local_navigation_debug(),
			"pinned": member.is_pinned(),
			"suppression": snappedf(member.get_suppression_ratio(), 0.05),
		})
	return result

func _on_blue_report(report: SquadContactReport3D) -> void:
	var advanced := blue.get_advanced_tactics()
	if advanced == null:
		return
	var count := advanced.belief.get_estimated_enemy_count()
	if blue_first_contact_count < 0 and report.stimulus != SquadContactReport3D.Stimulus.ZONE_OBSERVED and count > 0:
		blue_first_contact_count = count
	if report.stimulus == SquadContactReport3D.Stimulus.ZONE_OBSERVED:
		if report.zone_id == defended_route_zone_id:
			blue_defended_route_observed = true
			blue_defended_route_contacts = report.zone_visible_contact_ids.size()
		elif report.zone_id == flank_route_zone_id:
			blue_flank_route_observed = true
			blue_flank_route_contacts = report.zone_visible_contact_ids.size()
		if report.zone_id == &"left_route":
			blue_left_observed = true
		elif report.zone_id == &"right_grass":
			blue_right_observed = true
	elif report.stimulus == SquadContactReport3D.Stimulus.VISUAL:
		var defended_zone := advanced.get_zone_by_id(defended_route_zone_id)
		if defended_zone != null and defended_zone.contains_world_position(report.position):
			blue_left_contact_discovered = true
	if report.stimulus in [SquadContactReport3D.Stimulus.VISUAL, SquadContactReport3D.Stimulus.DAMAGE, SquadContactReport3D.Stimulus.ZONE_OBSERVED]:
		_record("BLUE_REPORT", {
			"stimulus": SquadContactReport3D.Stimulus.keys()[report.stimulus],
			"target": String(report.get_target().name) if report.get_target() != null else "",
			"zone": String(report.zone_id),
			"known_contacts": count,
			"visible_in_zone": report.zone_visible_contact_ids.size(),
			"threat_evidence": report.zone_threat_evidence_count,
		})

func _on_blue_candidates(candidates: Array[Dictionary], selected_id: String) -> void:
	if selected_id == "RECON_SPLIT":
		blue_recon_started = true
	if selected_id == _last_blue_candidate_id:
		return
	_last_blue_candidate_id = selected_id
	_record("BLUE_CANDIDATE", {"selected": selected_id, "count": candidates.size()})

func _on_blue_command(plan: String, summary: String, source: String) -> void:
	if plan == "SUPPRESS_AND_FLANK":
		blue_flank_started = true
		var candidate_id := summary.split(" | ")[0]
		blue_flank_zone = candidate_id.trim_prefix("FLANK_").to_lower()
		_capture_flank_members()
	_record("BLUE_COMMAND", {"plan": plan, "summary": summary, "source": source})

func _on_red_command(plan: String, summary: String, source: String) -> void:
	red_defend_started = red_defend_started or plan in ["DEFEND_CONTACT", "RECOVER_IN_COVER", "FALLBACK_DEFENSE"]
	_record("RED_COMMAND", {"plan": plan, "summary": summary, "source": source})

func _on_blue_mission_state(state_name: String) -> void:
	_record("BLUE_MISSION", {"state": state_name})

func _on_red_mission_state(state_name: String) -> void:
	red_hold_reached = red_hold_reached or state_name == "HOLDING"
	_record("RED_MISSION", {"state": state_name})

func _on_weapon_fired(actor: Soldier3D, _target: Node3D) -> void:
	if actor.combat_team == Soldier3D.Team.BLUE:
		shots_blue += 1
		if _is_active_synchronized_shooter(actor):
			blue_synchronized_attack_shots += 1
			if blue_synchronized_attack_shots == 1:
				_record("BLUE_FLANK_OPENED_FIRE", {"member": String(actor.name)})
	elif actor.combat_team == Soldier3D.Team.RED:
		shots_red += 1

func _is_active_synchronized_shooter(actor: Soldier3D) -> bool:
	if actor == null or not _blue_flanker_ids.has(String(actor.name)):
		return false
	var advanced := blue.get_advanced_tactics()
	if advanced == null or advanced.scheduler.active_plan == null:
		return false
	for task in advanced.scheduler.active_plan.tasks:
		if task.task_id == &"synchronized_attack" and task.state in [SquadTask3D.State.ACTIVE, SquadTask3D.State.READY] \
				and String(actor.name) in task.recipient_ids:
			return true
	return false

func _capture_flank_members() -> void:
	var advanced := blue.get_advanced_tactics()
	if advanced == null or advanced.scheduler.active_plan == null:
		return
	for task in advanced.scheduler.active_plan.tasks:
		if task.task_id != &"flank_move":
			continue
		for member_id in task.recipient_ids:
			_blue_flanker_ids[String(member_id)] = true

func _observe_tactical_execution(advanced: SquadAdvancedTactics3D) -> void:
	if advanced == null or advanced.scheduler.active_plan == null:
		return
	for task in advanced.scheduler.active_plan.tasks:
		if task.task_id == &"flank_move" and task.state == SquadTask3D.State.SUCCEEDED \
				and not blue_flank_task_succeeded:
			blue_flank_task_succeeded = true
			_record("BLUE_FLANK_ARRIVED", {"members": Array(task.recipient_ids), "zone": String(task.zone_id)})
		elif task.task_id == &"synchronized_attack" \
				and task.state in [SquadTask3D.State.ACTIVE, SquadTask3D.State.READY, SquadTask3D.State.SUCCEEDED] \
				and not blue_synchronized_attack_started:
			blue_synchronized_attack_started = true
			_record("BLUE_SYNCHRONIZED_ATTACK", {"members": Array(task.recipient_ids)})

func _on_soldier_died(actor: Soldier3D) -> void:
	if actor.combat_team == Soldier3D.Team.BLUE:
		deaths_blue += 1
	elif actor.combat_team == Soldier3D.Team.RED:
		deaths_red += 1
	_record("CASUALTY", {"team": int(actor.combat_team), "name": String(actor.name)})

func _record(kind: String, data: Dictionary) -> void:
	var event := data.duplicate(true)
	event["time"] = snappedf(elapsed, 0.1)
	event["kind"] = kind
	event_log.append(event)
	print("[CASE3D] %s" % JSON.stringify(event))

func _update_hud() -> void:
	if not show_debug_hud or debug_label == null:
		return
	var blue_debug := blue.get_advanced_tactics().get_debug_snapshot() if blue.get_advanced_tactics() != null else {}
	var red_debug := red.get_advanced_tactics().get_debug_snapshot() if red.get_advanced_tactics() != null else {}
	debug_label.text = "%s\nTime %.1fs\n\nBLUE attack/capture\n%s\nKnown enemies: %d\nRecon defended/flank: %s / %s\nFlank: %s\n\nRED capture/hold\n%s\nMax mission distance: %.1f / %.1f\n\nShots B/R: %d / %d\nDeaths B/R: %d / %d" % [
		case_title,
		elapsed,
		String(blue_debug.get("active_intent", "WAITING")),
		int((blue_debug.get("belief", {}) as Dictionary).get("estimated_enemy_count", 0)),
		str(blue_defended_route_observed), str(blue_flank_route_observed), blue_flank_zone,
		String(red_debug.get("active_intent", "WAITING")),
		red_max_mission_distance, red.mission_radius,
		shots_blue, shots_red, deaths_blue, deaths_red,
	]
