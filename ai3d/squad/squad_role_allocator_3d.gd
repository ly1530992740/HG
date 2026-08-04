extends RefCounted
class_name SquadRoleAllocator3D

const BASE_OF_FIRE: StringName = &"BASE_OF_FIRE"
const MANEUVER_LEAD: StringName = &"MANEUVER_LEAD"
const MANEUVER_WING: StringName = &"MANEUVER_WING"
const SECURITY: StringName = &"SECURITY"
const BREACHER: StringName = &"BREACHER"
const RESERVE: StringName = &"RESERVE"

const MAX_SEARCH_NODES := 50000

var previous_roles: Dictionary = {}
var last_result: Dictionary = {}

var _members: Array[Dictionary] = []
var _slots: Array[Dictionary] = []
var _best_assignments: Array[Dictionary] = []
var _best_score := -INF
var _search_nodes := 0

func allocate(members: Array[Dictionary], slot_requests: Array[Dictionary]) -> Dictionary:
	_members = members.duplicate(true)
	_members.sort_custom(func(a: Dictionary, b: Dictionary):
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	_slots = _expand_slots(slot_requests)
	_best_assignments.clear()
	_best_score = -INF
	_search_nodes = 0
	_search(0, {}, [], 0.0)
	var required_count := _slots.filter(func(slot: Dictionary): return bool(slot.get("required", true))).size()
	var required_filled := _best_assignments.filter(func(item: Dictionary): return bool(item.get("required", true))).size()
	last_result = {
		"complete": required_filled == required_count,
		"score": _best_score if _best_score > -INF else 0.0,
		"assignments": _best_assignments.duplicate(true),
		"unfilled_required": maxi(0, required_count - required_filled),
		"search_nodes": _search_nodes,
	}
	if bool(last_result.get("complete", false)):
		for assignment in _best_assignments:
			previous_roles[String(assignment.get("member_id", ""))] = StringName(assignment.get("role", ""))
	return last_result

func ids_for(result: Dictionary, roles: Array[StringName]) -> PackedStringArray:
	var ids := PackedStringArray()
	for assignment_value in result.get("assignments", []):
		var assignment := assignment_value as Dictionary
		if StringName(assignment.get("role", "")) in roles:
			ids.append(String(assignment.get("member_id", "")))
	return ids

func _expand_slots(requests: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var role_counts: Dictionary = {}
	for request in requests:
		var count := maxi(0, int(request.get("count", 1)))
		for index in count:
			var slot := request.duplicate(true)
			var role_name := String(request.get("role", RESERVE))
			role_counts[role_name] = int(role_counts.get(role_name, 0)) + 1
			slot["slot_id"] = "%s_%02d" % [role_name, int(role_counts[role_name])]
			result.append(slot)
	# Allocate the most constrained jobs first so the bounded search finds a valid plan quickly.
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		return _eligible_count(a) < _eligible_count(b)
	)
	return result

func _search(slot_index: int, used: Dictionary, assignments: Array[Dictionary], score: float) -> void:
	_search_nodes += 1
	if _search_nodes > MAX_SEARCH_NODES:
		return
	if slot_index >= _slots.size():
		if score > _best_score:
			_best_score = score
			_best_assignments = assignments.duplicate(true)
		return
	var slot := _slots[slot_index]
	var found := false
	for member in _members:
		var member_id := String(member.get("id", ""))
		if member_id.is_empty() or used.has(member_id) or not _is_eligible(member, slot):
			continue
		found = true
		var assignment_score := _score_member(member, slot)
		var assignment := {
			"slot_id": String(slot.get("slot_id", "")),
			"role": StringName(slot.get("role", RESERVE)),
			"member_id": member_id,
			"score": assignment_score,
			"required": bool(slot.get("required", true)),
			"tag": String(slot.get("tag", "")),
			"target_position": slot.get("target_position", Vector3.ZERO),
			"reason": _score_reason(member, slot),
		}
		used[member_id] = true
		assignments.append(assignment)
		_search(slot_index + 1, used, assignments, score + assignment_score)
		assignments.pop_back()
		used.erase(member_id)
	if not bool(slot.get("required", true)):
		_search(slot_index + 1, used, assignments, score)
	elif not found:
		# Keep the best partial result for diagnostics when a required slot cannot be filled.
		if assignments.size() > _best_assignments.size():
			_best_assignments = assignments.duplicate(true)
			_best_score = score

func _eligible_count(slot: Dictionary) -> int:
	var count := 0
	for member in _members:
		count += 1 if _is_eligible(member, slot) else 0
	return count

func _is_eligible(member: Dictionary, slot: Dictionary) -> bool:
	var role := StringName(slot.get("role", RESERVE))
	var health := float(member.get("health", 0.0))
	var mobility := float(member.get("mobility", 0.0))
	var ammo := float(member.get("ammo", 0.0))
	var pinned := bool(member.get("pinned", false))
	match role:
		BASE_OF_FIRE:
			return not pinned and health > 0.2 and ammo > 0.08 and bool(member.get("loaded", true))
		MANEUVER_LEAD, MANEUVER_WING, BREACHER:
			return not pinned and health >= 0.52 and mobility >= 0.42
		SECURITY:
			return not pinned and health >= 0.3 and ammo > 0.05
		_:
			return health > 0.0

func _score_member(member: Dictionary, slot: Dictionary) -> float:
	var role := StringName(slot.get("role", RESERVE))
	var combat_role := int(member.get("role", -1))
	var health := float(member.get("health", 0.0))
	var mobility := float(member.get("mobility", 0.0))
	var ammo := float(member.get("ammo", 0.0))
	var suppression := float(member.get("suppression", 0.0))
	var role_fit := 0.0
	match role:
		BASE_OF_FIRE:
			role_fit = {
				Soldier3D.CombatRole.MACHINE_GUNNER: 120.0,
				Soldier3D.CombatRole.MARKSMAN: 92.0,
				Soldier3D.CombatRole.RIFLEMAN: 72.0,
				Soldier3D.CombatRole.SMG: 48.0,
			}.get(combat_role, 30.0)
		MANEUVER_LEAD:
			role_fit = {
				Soldier3D.CombatRole.SMG: 112.0,
				Soldier3D.CombatRole.SHOTGUNNER: 104.0,
				Soldier3D.CombatRole.RIFLEMAN: 82.0,
			}.get(combat_role, 48.0)
		MANEUVER_WING:
			role_fit = {
				Soldier3D.CombatRole.RIFLEMAN: 94.0,
				Soldier3D.CombatRole.SMG: 88.0,
				Soldier3D.CombatRole.SHOTGUNNER: 82.0,
			}.get(combat_role, 52.0)
		SECURITY:
			role_fit = {
				Soldier3D.CombatRole.MARKSMAN: 105.0,
				Soldier3D.CombatRole.RIFLEMAN: 88.0,
				Soldier3D.CombatRole.MACHINE_GUNNER: 70.0,
			}.get(combat_role, 50.0)
		BREACHER:
			role_fit = 112.0 if combat_role in [Soldier3D.CombatRole.SMG, Soldier3D.CombatRole.SHOTGUNNER] else 62.0
		_:
			role_fit = 55.0 + (20.0 if bool(member.get("leader", false)) else 0.0)
	var continuity := 22.0 if previous_roles.get(String(member.get("id", ""))) == role else 0.0
	var target := slot.get("target_position", Vector3.ZERO) as Vector3
	var position := member.get("position", Vector3.ZERO) as Vector3
	var distance_penalty := minf(35.0, _flat_distance(position, target) * float(slot.get("distance_weight", 0.0)))
	return role_fit + health * 34.0 + mobility * 22.0 + ammo * 24.0 \
		- suppression * 62.0 + continuity - distance_penalty

func _score_reason(member: Dictionary, slot: Dictionary) -> String:
	return "%s fit; health %.2f, mobility %.2f, ammo %.2f%s" % [
		String(slot.get("role", RESERVE)),
		float(member.get("health", 0.0)),
		float(member.get("mobility", 0.0)),
		float(member.get("ammo", 0.0)),
		", role continuity" if previous_roles.get(String(member.get("id", ""))) == StringName(slot.get("role", RESERVE)) else "",
	]

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
