extends Node3D
class_name LimitedIntelCaseStudy3D

@export var show_debug_hud := true

var elapsed := 0.0
var event_log: Array[Dictionary] = []
var blue_first_contact_count := -1
var blue_max_known_contacts_before_left_recon := 0
var blue_recon_started := false
var blue_left_contact_discovered := false
var blue_left_observed := false
var blue_right_observed := false
var blue_flank_started := false
var blue_flank_zone := ""
var red_hold_reached := false
var red_defend_started := false
var red_max_mission_distance := 0.0
var shots_blue := 0
var shots_red := 0
var deaths_blue := 0
var deaths_red := 0
var _last_blue_candidate_id := ""

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
		"blue_flank_started": blue_flank_started,
		"blue_flank_zone": blue_flank_zone,
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
		"events": event_log.duplicate(true),
	}

func _on_blue_report(report: SquadContactReport3D) -> void:
	var advanced := blue.get_advanced_tactics()
	if advanced == null:
		return
	var count := advanced.belief.get_estimated_enemy_count()
	if blue_first_contact_count < 0 and report.stimulus != SquadContactReport3D.Stimulus.ZONE_OBSERVED and count > 0:
		blue_first_contact_count = count
	if report.stimulus == SquadContactReport3D.Stimulus.ZONE_OBSERVED:
		if report.zone_id == &"left_route":
			blue_left_observed = true
		elif report.zone_id == &"right_grass":
			blue_right_observed = true
	elif report.stimulus == SquadContactReport3D.Stimulus.VISUAL:
		var left_zone := advanced.get_zone_by_id(&"left_route")
		if left_zone != null and left_zone.contains_world_position(report.position):
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
	elif selected_id.begins_with("FLANK_"):
		blue_flank_started = true
		blue_flank_zone = selected_id.trim_prefix("FLANK_").to_lower()
	if selected_id == _last_blue_candidate_id:
		return
	_last_blue_candidate_id = selected_id
	_record("BLUE_CANDIDATE", {"selected": selected_id, "count": candidates.size()})

func _on_blue_command(plan: String, summary: String, source: String) -> void:
	_record("BLUE_COMMAND", {"plan": plan, "summary": summary, "source": source})

func _on_red_command(plan: String, summary: String, source: String) -> void:
	red_defend_started = red_defend_started or plan == "DEFEND_CONTACT"
	_record("RED_COMMAND", {"plan": plan, "summary": summary, "source": source})

func _on_blue_mission_state(state_name: String) -> void:
	_record("BLUE_MISSION", {"state": state_name})

func _on_red_mission_state(state_name: String) -> void:
	red_hold_reached = red_hold_reached or state_name == "HOLDING"
	_record("RED_MISSION", {"state": state_name})

func _on_weapon_fired(actor: Soldier3D, _target: Node3D) -> void:
	if actor.combat_team == Soldier3D.Team.BLUE:
		shots_blue += 1
	elif actor.combat_team == Soldier3D.Team.RED:
		shots_red += 1

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
	debug_label.text = "LIMITED INTEL CASE STUDY\nTime %.1fs\n\nBLUE attack/capture\n%s\nKnown enemies: %d\nRecon L/R: %s / %s\nFlank: %s\n\nRED capture/hold\n%s\nMax mission distance: %.1f / %.1f\n\nShots B/R: %d / %d\nDeaths B/R: %d / %d" % [
		elapsed,
		String(blue_debug.get("active_intent", "WAITING")),
		int((blue_debug.get("belief", {}) as Dictionary).get("estimated_enemy_count", 0)),
		str(blue_left_observed), str(blue_right_observed), blue_flank_zone,
		String(red_debug.get("active_intent", "WAITING")),
		red_max_mission_distance, red.mission_radius,
		shots_blue, shots_red, deaths_blue, deaths_red,
	]
