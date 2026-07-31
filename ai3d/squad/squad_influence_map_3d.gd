extends RefCounted
class_name SquadInfluenceMap3D

const LAYER_ENEMY_THREAT := &"enemy_threat"
const LAYER_FRIENDLY_FIRE := &"friendly_fire"
const LAYER_SUPPRESSION := &"suppression"
const LAYER_COVER := &"cover"
const LAYER_CONCEALMENT := &"concealment"
const LAYER_ROUTE_EXPOSURE := &"route_exposure"
const LAYER_OBJECTIVE := &"objective"
const LAYER_INFORMATION := &"information"

var cell_size := 3.0
var radius := 42.0
var origin := Vector3.ZERO
var version := 0
var cells: Dictionary = {}

func configure(new_cell_size := 3.0, new_radius := 42.0) -> void:
	cell_size = maxf(1.0, new_cell_size)
	radius = maxf(cell_size * 2.0, new_radius)

func rebuild(
		belief: SquadBeliefState3D,
		zones: Array[TacticalZone3D],
		member_facts: Array[Dictionary],
		covers: Array,
		center: Vector3,
		objective: Vector3
) -> void:
	origin = _snap_position((center + objective) * 0.5)
	cells.clear()
	var extent := ceili(radius / cell_size)
	var contacts := belief.get_living_contacts() if belief != null else []
	var threat_events := belief.threat_events if belief != null else []
	for x in range(-extent, extent + 1):
		for z in range(-extent, extent + 1):
			var key := Vector2i(x, z)
			var position := origin + Vector3(float(x) * cell_size, 0.0, float(z) * cell_size)
			cells[key] = _build_cell(position, contacts, threat_events, zones, member_facts, covers, objective)
	version += 1

func sample(position: Vector3) -> Dictionary:
	var key := _key_for(position)
	if cells.has(key):
		return (cells[key] as Dictionary).duplicate(true)
	return _empty_cell()

func score_position(position: Vector3, weights := {}) -> float:
	var cell := sample(position)
	var default_weights := {
		LAYER_ENEMY_THREAT: -1.0,
		LAYER_FRIENDLY_FIRE: 0.35,
		LAYER_SUPPRESSION: -0.8,
		LAYER_COVER: 0.8,
		LAYER_CONCEALMENT: 0.55,
		LAYER_ROUTE_EXPOSURE: -0.7,
		LAYER_OBJECTIVE: 0.25,
		LAYER_INFORMATION: 0.2,
	}
	var result := 0.0
	for layer in default_weights:
		result += float(cell.get(layer, 0.0)) * float(weights.get(layer, default_weights[layer]))
	return result

func score_route(route: Array[Vector3], weights := {}) -> float:
	if route.is_empty():
		return -INF
	var total := 0.0
	var worst_threat := 0.0
	for position in route:
		var cell := sample(position)
		total += score_position(position, weights)
		worst_threat = maxf(worst_threat, float(cell.get(LAYER_ENEMY_THREAT, 0.0)))
	return total / float(route.size()) - worst_threat * 0.25

func score_zone(zone: TacticalZone3D, weights := {}) -> float:
	if zone == null:
		return -INF
	var points: Array[Vector3] = [
		zone.global_position,
		zone.to_global(Vector3(zone.size.x * 0.3, 0.0, 0.0)),
		zone.to_global(Vector3(-zone.size.x * 0.3, 0.0, 0.0)),
		zone.to_global(Vector3(0.0, 0.0, zone.size.y * 0.3)),
		zone.to_global(Vector3(0.0, 0.0, -zone.size.y * 0.3)),
	]
	var total := 0.0
	for point in points:
		total += score_position(point, weights)
	return total / float(points.size())

func get_debug_cells() -> Dictionary:
	return cells.duplicate(true)

func _build_cell(
		position: Vector3,
		contacts: Array,
		threat_events: Array,
		zones: Array[TacticalZone3D],
		members: Array[Dictionary],
		covers: Array,
		objective: Vector3
) -> Dictionary:
	var result := _empty_cell()
	for contact_value in contacts:
		var contact := contact_value as CombatContact3D
		if contact == null:
			continue
		var confidence := contact.get_decayed_confidence(24.0)
		var distance := _flat_distance(position, contact.last_known_position)
		var reach := 30.0 if contact.estimated_role == Soldier3D.CombatRole.MARKSMAN else 24.0
		var falloff := clampf(1.0 - distance / reach, 0.0, 1.0)
		result[LAYER_ENEMY_THREAT] += confidence * contact.estimated_firepower * falloff * 30.0
		if contact.currently_visible:
			result[LAYER_ENEMY_THREAT] += falloff * 12.0
	for event in threat_events:
		var distance := _flat_distance(position, event.get("position", Vector3.ZERO) as Vector3)
		result[LAYER_SUPPRESSION] += clampf(1.0 - distance / 14.0, 0.0, 1.0) \
			* float(event.get("confidence", 0.0)) * 45.0
	for member in members:
		var distance := _flat_distance(position, member.get("position", Vector3.ZERO) as Vector3)
		var falloff := clampf(1.0 - distance / 24.0, 0.0, 1.0)
		result[LAYER_FRIENDLY_FIRE] += float(member.get("combat_power", 1.0)) * falloff * 22.0
	for zone in zones:
		if zone.contains_world_position(position):
			result[LAYER_CONCEALMENT] = maxf(float(result[LAYER_CONCEALMENT]), zone.concealment * 100.0)
			result[LAYER_COVER] = maxf(float(result[LAYER_COVER]), zone.cover_value * 60.0)
			result[LAYER_ROUTE_EXPOSURE] = maxf(float(result[LAYER_ROUTE_EXPOSURE]), zone.route_exposure * 100.0)
			result[LAYER_INFORMATION] = zone.information_value * (35.0 if not zone.recon_enabled else 50.0)
	for cover_value in covers:
		if not cover_value is TacticalCover3D:
			continue
		var cover := cover_value as TacticalCover3D
		var distance := _flat_distance(position, cover.global_position)
		result[LAYER_COVER] = maxf(float(result[LAYER_COVER]), clampf(1.0 - distance / 7.0, 0.0, 1.0) * 100.0)
	result[LAYER_OBJECTIVE] = clampf(1.0 - _flat_distance(position, objective) / maxf(1.0, radius), 0.0, 1.0) * 100.0
	for layer in result:
		result[layer] = clampf(float(result[layer]), 0.0, 100.0)
	return result

func _key_for(position: Vector3) -> Vector2i:
	var local := position - origin
	return Vector2i(roundi(local.x / cell_size), roundi(local.z / cell_size))

func _snap_position(position: Vector3) -> Vector3:
	return Vector3(roundf(position.x / cell_size) * cell_size, 0.0, roundf(position.z / cell_size) * cell_size)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()

func _empty_cell() -> Dictionary:
	return {
		LAYER_ENEMY_THREAT: 0.0,
		LAYER_FRIENDLY_FIRE: 0.0,
		LAYER_SUPPRESSION: 0.0,
		LAYER_COVER: 0.0,
		LAYER_CONCEALMENT: 0.0,
		LAYER_ROUTE_EXPOSURE: 0.0,
		LAYER_OBJECTIVE: 0.0,
		LAYER_INFORMATION: 0.0,
	}
