extends Node
class_name PerceptionComponent

signal contact_confirmed(contact: CombatContact)
signal contact_updated(contact: CombatContact)
signal stimulus_heard(position: Vector2, source: Node2D)

@export var sight_range := 1800.0
@export_range(10.0, 360.0) var field_of_view_degrees := 110.0
@export var hearing_range := 1500.0
@export var scan_interval_min := 0.22
@export var scan_interval_max := 0.35
@export var detection_threshold := 1.0
@export var detection_gain_per_second := 3.2
@export var detection_decay_per_second := 1.1
@export var contact_memory_seconds := 7.0

var actor: Node2D = null
var alert: AlertComponent = null
var contacts: Dictionary = {}
var _detection_progress: Dictionary = {}
var _scan_timer := 0.0

func _ready() -> void:
	add_to_group("perception_listener")
	_scan_timer = randf_range(0.0, scan_interval_max)

func setup(new_actor: Node2D, new_alert: AlertComponent, new_sight_range := -1.0) -> void:
	actor = new_actor
	alert = new_alert
	if new_sight_range > 0.0:
		sight_range = new_sight_range

func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	var scan_delta := maxf(scan_interval_min, scan_interval_max - _scan_timer)
	_scan_timer = randf_range(scan_interval_min, scan_interval_max)
	_scan_world(scan_delta)

func _scan_world(delta: float) -> void:
	for contact_value in contacts.values():
		var known_contact := contact_value as CombatContact
		if known_contact != null:
			known_contact.currently_visible = false

	var candidates: Dictionary = {}
	for group_name in ["player", "combatant"]:
		for node in get_tree().get_nodes_in_group(group_name):
			candidates[node] = true
	for candidate in candidates.keys():
		if candidate is Node2D:
			evaluate_candidate(candidate, delta)
	_decay_and_forget(delta, candidates)

func evaluate_candidate(candidate: Node2D, delta: float) -> bool:
	if not _is_hostile_candidate(candidate):
		return false
	var distance := actor.global_position.distance_to(candidate.global_position)
	var concealed := candidate.has_method("is_visually_concealed") and bool(candidate.is_visually_concealed())
	var visible := not concealed and distance <= sight_range and _is_inside_fov(candidate.global_position) and _has_line_of_sight(candidate)
	var progress := float(_detection_progress.get(candidate, 0.0))
	if not visible:
		_detection_progress[candidate] = maxf(0.0, progress - detection_decay_per_second * delta)
		return false

	var distance_factor := lerpf(1.0, 0.35, clampf(distance / maxf(1.0, sight_range), 0.0, 1.0))
	progress = minf(detection_threshold, progress + detection_gain_per_second * distance_factor * delta)
	_detection_progress[candidate] = progress
	if alert != null:
		alert.register_observation(candidate.global_position)
	if progress < detection_threshold:
		return false

	var is_new := not contacts.has(candidate)
	var contact := _get_or_create_contact(candidate)
	contact.update_visual(candidate.global_position, 1.0, _estimate_target_awareness(candidate))
	if alert != null:
		alert.register_contact(candidate.global_position)
	if is_new:
		contact_confirmed.emit(contact)
	else:
		contact_updated.emit(contact)
	return true

func hear_stimulus(position: Vector2, source: Node2D = null, loudness := 1.0) -> void:
	if actor == null or actor.global_position.distance_to(position) > hearing_range * maxf(0.1, loudness):
		return
	if source == actor:
		return
	if alert != null:
		alert.register_suspicion(position)
	stimulus_heard.emit(position, source)
	if source == null or not _is_hostile_candidate(source):
		return
	var is_new := not contacts.has(source)
	var contact := _get_or_create_contact(source)
	contact.update_hearing(position, 0.45)
	if is_new:
		contact_confirmed.emit(contact)
	else:
		contact_updated.emit(contact)

func get_best_contact(require_visible := false) -> CombatContact:
	var best: CombatContact = null
	var best_score := -INF
	for value in contacts.values():
		var contact := value as CombatContact
		if contact == null or not contact.is_valid():
			continue
		if require_visible and not contact.currently_visible:
			continue
		var distance := actor.global_position.distance_to(contact.last_known_position)
		var score := contact.confidence * 1000.0 - distance
		if contact.currently_visible:
			score += 1000.0
		if score > best_score:
			best = contact
			best_score = score
	return best

func get_contact(candidate: Node2D) -> CombatContact:
	return contacts.get(candidate) as CombatContact

func is_currently_visible(candidate: Node2D) -> bool:
	var contact := get_contact(candidate)
	return contact != null and contact.currently_visible

func forget_contact(candidate) -> void:
	contacts.erase(candidate)
	_detection_progress.erase(candidate)

func _get_or_create_contact(candidate: Node2D) -> CombatContact:
	var contact := contacts.get(candidate) as CombatContact
	if contact == null:
		contact = CombatContact.new()
		contact.target = candidate
		contact.observer = actor
		contacts[candidate] = contact
	return contact

func _decay_and_forget(delta: float, scanned_candidates: Dictionary) -> void:
	for candidate in _detection_progress.keys().duplicate():
		if not is_instance_valid(candidate) or not scanned_candidates.has(candidate):
			_detection_progress.erase(candidate)
			continue
		var contact := contacts.get(candidate) as CombatContact
		if contact == null or not contact.currently_visible:
			_detection_progress[candidate] = maxf(0.0, float(_detection_progress[candidate]) - detection_decay_per_second * delta)
	for candidate in contacts.keys().duplicate():
		var contact := contacts.get(candidate) as CombatContact
		if contact == null or not contact.is_valid() or (not contact.currently_visible and contact.age_seconds() > contact_memory_seconds):
			forget_contact(candidate)

func _is_inside_fov(target_position: Vector2) -> bool:
	var to_target := (target_position - actor.global_position).normalized()
	if to_target == Vector2.ZERO or field_of_view_degrees >= 359.0:
		return true
	var facing := Vector2.RIGHT
	if actor.has_method("get_facing_direction"):
		facing = actor.get_facing_direction()
	return facing.normalized().dot(to_target) >= cos(deg_to_rad(field_of_view_degrees * 0.5))

func _has_line_of_sight(candidate: Node2D) -> bool:
	if actor.get_world_2d() == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(actor.global_position, candidate.global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if actor is CollisionObject2D:
		query.exclude = [actor.get_rid()]
	var hit := actor.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider == candidate or (collider != null and collider.get_parent() == candidate)

func _is_hostile_candidate(candidate: Node2D) -> bool:
	if candidate == null or candidate == actor or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return false
	if candidate.has_method("is_combat_alive") and not candidate.is_combat_alive():
		return false
	return actor.has_method("can_damage_target") and bool(actor.can_damage_target(candidate))

func _estimate_target_awareness(candidate: Node2D) -> bool:
	var target_alert := candidate.get("alert_component") as AlertComponent
	return target_alert != null and target_alert.is_aware_of_combat()
