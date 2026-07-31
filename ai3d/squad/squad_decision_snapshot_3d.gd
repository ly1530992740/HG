extends RefCounted
class_name SquadDecisionSnapshot3D

var belief_version := 0
var mission_type := 0
var mission_state := 0
var mission_target := Vector3.ZERO
var mission_radius := 0.0
var squad_center := Vector3.ZERO
var enemy_count := 0
var enemy_power := 0.0
var members: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var fire_assessment: Dictionary = {}

static func capture(
		belief: SquadBeliefState3D,
		mission: SquadMissionController3D,
		runtime_members: Array[Soldier3D],
		assessment: Dictionary
) -> SquadDecisionSnapshot3D:
	var result := SquadDecisionSnapshot3D.new()
	result.belief_version = belief.version
	result.mission_type = mission.mission_type
	result.mission_state = mission.state
	result.mission_target = mission.target_position
	result.mission_radius = mission.target_radius
	result.fire_assessment = assessment.duplicate(true)
	# Tactical decisions retain low-confidence contacts so a brief loss of sight
	# does not make an engaged squad behave as if the enemy ceased to exist.
	result.enemy_count = belief.get_living_contacts(0.05).size()
	result.enemy_power = belief.get_estimated_enemy_power()
	var center := Vector3.ZERO
	for member in runtime_members:
		if member == null or not member.is_combat_alive():
			continue
		center += member.global_position
		result.members.append(_capture_member(member))
	result.squad_center = center / float(result.members.size()) if not result.members.is_empty() else mission.target_position
	for contact in belief.get_living_contacts(0.05):
		result.contacts.append({
			"id": String(contact.contact_id),
			"position": contact.last_known_position,
			"confidence": contact.get_decayed_confidence(belief.contact_memory_seconds),
			"visible": contact.currently_visible,
			"firepower": contact.estimated_firepower,
			"role": contact.estimated_role,
			"awareness": contact.enemy_awareness_probability,
			"age": contact.age_seconds(),
		})
	return result

static func from_facts(facts: Dictionary) -> SquadDecisionSnapshot3D:
	var result := SquadDecisionSnapshot3D.new()
	result.belief_version = int(facts.get("belief_version", 1))
	result.mission_type = int(facts.get("mission_type", SquadMissionController3D.MissionType.CAPTURE_AND_HOLD))
	result.mission_state = int(facts.get("mission_state", SquadMissionController3D.State.CLEARING))
	result.mission_target = facts.get("mission_target", Vector3.ZERO) as Vector3
	result.mission_radius = float(facts.get("mission_radius", 12.0))
	result.squad_center = facts.get("squad_center", Vector3.ZERO) as Vector3
	result.enemy_count = int(facts.get("enemy_count", 0))
	result.enemy_power = float(facts.get("enemy_power", 0.0))
	result.members.assign(facts.get("members", []))
	result.contacts.assign(facts.get("contacts", []))
	result.fire_assessment = (facts.get("fire_assessment", {}) as Dictionary).duplicate(true)
	return result

func get_member_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for member in members:
		result.append(String(member.get("id", "")))
	return result

func get_member(member_id: String) -> Dictionary:
	for member in members:
		if String(member.get("id", "")) == member_id:
			return member
	return {}

func count_role(role: int) -> int:
	var result := 0
	for member in members:
		result += 1 if int(member.get("role", -1)) == role else 0
	return result

func visible_contact_count() -> int:
	var result := 0
	for contact in contacts:
		result += 1 if bool(contact.get("visible", false)) else 0
	return result

func average_health() -> float:
	if members.is_empty():
		return 0.0
	var total := 0.0
	for member in members:
		total += float(member.get("health", 0.0))
	return total / float(members.size())

static func _capture_member(member: Soldier3D) -> Dictionary:
	var maximum_ammo := maxi(1, member.weapon_component.magazine_size * 4)
	var available_ammo := member.magazine_ammo + member.reserve_ammo
	return {
		"id": String(member.name),
		"position": member.global_position,
		"role": int(member.combat_role),
		"health": float(member.health) / maxf(1.0, float(member.max_health)),
		"mobility": member.get_mobility_ratio(),
		"suppression": member.get_suppression_ratio(),
		"pinned": member.is_pinned(),
		"ammo": clampf(float(available_ammo) / float(maximum_ammo), 0.0, 1.0),
		"loaded": not member.uses_ammunition() or member.magazine_ammo > 0,
		"covered": is_instance_valid(member.active_cover),
		"combat_power": member.get_combat_power(),
		"leader": member.is_squad_leader,
	}
