extends Node
class_name CoverUser

enum Mode { NONE, BLIND, PRECISION }

var actor: CharacterBody2D
var active_cover: Node = null
var active_slot: Marker2D = null
var mode: Mode = Mode.NONE
var nearby_covers: Array[Node] = []
var status_label: Label
var lateral_offset := 0.0
var cover_move_speed := 72.0

func setup(owner_actor: CharacterBody2D) -> void:
	actor = owner_actor
	_setup_status_label()

func register_cover(cover: Node) -> void:
	if is_instance_valid(cover) and not nearby_covers.has(cover):
		nearby_covers.append(cover)

func unregister_cover(cover: Node) -> void:
	nearby_covers.erase(cover)

func toggle_nearest_cover() -> bool:
	if is_in_cover():
		exit_cover()
		return true

	var cover := get_nearest_cover()
	if cover == null:
		return false
	return enter_cover(cover)

func get_nearest_cover() -> Node:
	return _get_nearest_cover_internal(null)

func get_nearest_cover_against(threat_position: Vector2) -> Node:
	return _get_nearest_cover_internal(threat_position)

func _get_nearest_cover_internal(threat_position: Variant) -> Node:
	nearby_covers = nearby_covers.filter(is_instance_valid)
	var nearest: Node = null
	var nearest_distance := INF
	for cover in nearby_covers:
		if not cover.has_method("request_cover"):
			continue
		if threat_position != null and cover.has_method("has_available_cover_against") and not cover.has_available_cover_against(threat_position as Vector2):
			continue
		var distance := actor.global_position.distance_to(cover.global_position)
		if distance < nearest_distance:
			nearest = cover
			nearest_distance = distance
	return nearest

func enter_cover(cover: Node, precision := false) -> bool:
	return _enter_cover_internal(cover, precision, null)

func enter_cover_against(cover: Node, threat_position: Vector2, precision := false) -> bool:
	return _enter_cover_internal(cover, precision, threat_position)

func _enter_cover_internal(cover: Node, precision: bool, threat_position: Variant) -> bool:
	if actor == null or not is_instance_valid(cover) or not cover.has_method("request_cover"):
		return false

	if is_in_cover():
		exit_cover()

	var slot: Marker2D
	if threat_position != null and cover.has_method("request_cover_against"):
		slot = cover.request_cover_against(actor, threat_position as Vector2) as Marker2D
	else:
		slot = cover.request_cover(actor) as Marker2D
	if slot == null:
		return false

	active_cover = cover
	active_slot = slot
	lateral_offset = 0.0
	mode = Mode.PRECISION if precision else Mode.BLIND
	actor.global_position = _get_cover_position()
	actor.velocity = Vector2.ZERO
	_update_status_label()
	return true

func exit_cover() -> void:
	if is_instance_valid(active_cover) and active_cover.has_method("release_cover"):
		active_cover.release_cover(actor)
	active_cover = null
	active_slot = null
	lateral_offset = 0.0
	mode = Mode.NONE
	_update_status_label()

func set_precision(enabled: bool) -> void:
	if not is_in_cover():
		return
	mode = Mode.PRECISION if enabled else Mode.BLIND
	_update_status_label()

func is_in_cover() -> bool:
	return active_cover != null and is_instance_valid(active_cover) and active_slot != null and is_instance_valid(active_slot)

func is_precision() -> bool:
	return is_in_cover() and mode == Mode.PRECISION

func maintain_position() -> void:
	if is_in_cover():
		actor.global_position = _get_cover_position()
		actor.velocity = Vector2.ZERO

func move_along_cover(input_strength: float, delta: float) -> void:
	if not is_in_cover() or is_zero_approx(input_strength):
		maintain_position()
		return
	lateral_offset += input_strength * cover_move_speed * delta
	if active_cover.has_method("clamp_lateral_offset"):
		lateral_offset = active_cover.clamp_lateral_offset(actor, active_slot, lateral_offset)
	actor.global_position = _get_cover_position()
	actor.velocity = Vector2.ZERO

func move_toward_lateral_offset(target_offset: float, delta: float) -> bool:
	if not is_in_cover():
		return true
	lateral_offset = move_toward(lateral_offset, target_offset, cover_move_speed * 0.55 * delta)
	if active_cover.has_method("clamp_lateral_offset"):
		lateral_offset = active_cover.clamp_lateral_offset(actor, active_slot, lateral_offset)
	actor.global_position = _get_cover_position()
	actor.velocity = Vector2.ZERO
	return absf(lateral_offset - target_offset) <= 1.0

func get_cover_axis() -> Vector2:
	if is_in_cover() and active_cover.has_method("get_cover_axis"):
		return active_cover.get_cover_axis()
	return Vector2.RIGHT

func _get_cover_position() -> Vector2:
	if not is_in_cover():
		return actor.global_position if actor else Vector2.ZERO
	if active_cover.has_method("get_cover_position"):
		return active_cover.get_cover_position(actor, active_slot, lateral_offset)
	return active_slot.global_position

func get_spread_multiplier() -> float:
	if not is_in_cover():
		return 1.0
	return 1.0 if is_precision() else 5.0

func get_active_cover() -> Node:
	return active_cover if is_in_cover() else null

func show_blocked() -> void:
	if not is_in_cover() or status_label == null:
		return
	status_label.text = "COVER: BLOCKED"
	status_label.modulate = Color(0.35, 1.0, 0.55)
	_restore_status_async()

func _restore_status_async() -> void:
	await get_tree().create_timer(0.22).timeout
	_update_status_label()

func _setup_status_label() -> void:
	if actor == null:
		return
	status_label = Label.new()
	status_label.name = "CoverStatus"
	status_label.position = Vector2(-52, -70)
	status_label.size = Vector2(104, 20)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.z_index = 20
	actor.add_child(status_label)
	_update_status_label()

func _update_status_label() -> void:
	if status_label == null:
		return
	match mode:
		Mode.BLIND:
			status_label.text = "COVER: BLIND"
			status_label.modulate = Color(0.45, 0.9, 1.0)
		Mode.PRECISION:
			status_label.text = "COVER: PRECISE"
			status_label.modulate = Color(1.0, 0.85, 0.3)
		_:
			status_label.text = ""
