extends RefCounted
class_name SoldierLocalThreatField3D

const DEFAULT_LOOKAHEAD := 4.0
const LOCAL_THREAT_RADIUS := 18.0
const SWITCH_IMPROVEMENT := 4.0

var actor: Soldier3D
var working_memory: SoldierWorkingMemory3D
var shared_influence: SquadInfluenceMap3D

func configure(owner_actor: Soldier3D, memory: SoldierWorkingMemory3D) -> void:
	actor = owner_actor
	working_memory = memory

func set_shared_influence(value: SquadInfluenceMap3D) -> void:
	shared_influence = value

func score_position(position: Vector3) -> float:
	var risk := 0.0
	if shared_influence != null:
		var cell := shared_influence.sample(position)
		risk += float(cell.get(SquadInfluenceMap3D.LAYER_ENEMY_THREAT, 0.0))
		risk += float(cell.get(SquadInfluenceMap3D.LAYER_SUPPRESSION, 0.0)) * 1.25
		risk += float(cell.get(SquadInfluenceMap3D.LAYER_ROUTE_EXPOSURE, 0.0)) * 0.55
		risk -= float(cell.get(SquadInfluenceMap3D.LAYER_COVER, 0.0)) * 0.65
		risk -= float(cell.get(SquadInfluenceMap3D.LAYER_CONCEALMENT, 0.0)) * 0.35
	if working_memory != null:
		for fact in working_memory.get_spatial_threat_facts():
			var threat_position := fact.get("position", Vector3.ZERO) as Vector3
			var distance := _flat_distance(position, threat_position)
			var falloff := clampf(1.0 - distance / LOCAL_THREAT_RADIUS, 0.0, 1.0)
			if falloff <= 0.0:
				continue
			var confidence := float(fact.get("confidence", 0.0))
			var intensity := 62.0 if bool(fact.get("immediate", false)) else 34.0
			var exposure := 1.0 if _terrain_line_is_clear(threat_position, position) else 0.22
			risk += confidence * falloff * intensity * exposure
	return maxf(0.0, risk)

func score_segment(from_position: Vector3, to_position: Vector3, sample_count := 5) -> float:
	var count := maxi(2, sample_count)
	var total := 0.0
	var worst := 0.0
	for index in count:
		var weight := float(index + 1) / float(count)
		var risk := score_position(from_position.lerp(to_position, weight))
		total += risk
		worst = maxf(worst, risk)
	return total / float(count) + worst * 0.35

func score_cover(cover: TacticalCover3D, threat_position: Vector3, preferred_range: float) -> float:
	if cover == null or actor == null:
		return -INF
	var tactical_value := cover.score_for_actor(actor, threat_position, preferred_range)
	var travel_risk := score_segment(actor.global_position, cover.global_position)
	var destination_risk := score_position(cover.global_position)
	return tactical_value - travel_risk * 0.32 - destination_risk * 0.18

func choose_local_detour(
		origin: Vector3,
		destination: Vector3,
		max_detour := 3.0,
		lookahead := DEFAULT_LOOKAHEAD
) -> Dictionary:
	var offset := destination - origin
	offset.y = 0.0
	var distance := offset.length()
	if distance <= 0.05:
		return _choice(destination, 0.0, 0.0, 0.0)
	var forward := offset / distance
	var lateral := Vector3(-forward.z, 0.0, forward.x)
	var step := minf(maxf(1.2, lookahead), distance)
	var direct := origin + forward * step
	var lateral_near := minf(max_detour, step * 0.48)
	var lateral_far := minf(max_detour, step * 0.78)
	var candidates: Array[Vector3] = [
		direct,
		origin + forward * step * 0.92 + lateral * lateral_near,
		origin + forward * step * 0.92 - lateral * lateral_near,
		origin + forward * step * 0.74 + lateral * lateral_far,
		origin + forward * step * 0.74 - lateral * lateral_far,
	]
	var direct_choice := _evaluate_candidate(origin, destination, direct, max_detour)
	var best := direct_choice
	for point in candidates:
		var candidate := _evaluate_candidate(origin, destination, point, max_detour)
		if not bool(candidate.get("valid", false)):
			continue
		if not bool(best.get("valid", false)) or float(candidate.get("cost", INF)) < float(best.get("cost", INF)):
			best = candidate
	if not bool(best.get("valid", false)):
		return _choice(direct, score_segment(origin, direct), score_segment(origin, direct), INF)
	if bool(direct_choice.get("valid", false)) and best.get("point", direct) != direct:
		var improvement := float(direct_choice.get("cost", INF)) - float(best.get("cost", INF))
		if improvement < SWITCH_IMPROVEMENT:
			best = direct_choice
	best["direct_risk"] = float(direct_choice.get("selected_risk", score_segment(origin, direct)))
	return best

func _evaluate_candidate(origin: Vector3, destination: Vector3, point: Vector3, max_detour: float) -> Dictionary:
	var total_distance := _flat_distance(origin, destination)
	var remaining := _flat_distance(point, destination)
	var progress := total_distance - remaining
	var corridor_offset := _distance_to_segment(point, origin, destination)
	if progress < 0.3 or corridor_offset > max_detour + 0.05 or not _segment_is_clear(origin, point):
		return {"valid": false, "point": point, "cost": INF}
	var risk := score_segment(origin, point)
	var path_cost := _flat_distance(origin, point) + remaining
	var crowding := _friendly_crowding_risk(point)
	var cost := path_cost * 1.2 + corridor_offset * 2.2 + risk * 0.18 + crowding
	var result := _choice(point, risk, risk, cost)
	result["valid"] = true
	result["progress"] = progress
	result["corridor_offset"] = corridor_offset
	return result

func _friendly_crowding_risk(position: Vector3) -> float:
	if actor == null or not actor.is_inside_tree():
		return 0.0
	var risk := 0.0
	for value in actor.get_tree().get_nodes_in_group("soldier3d"):
		if value == actor or not value is Soldier3D:
			continue
		var soldier := value as Soldier3D
		if soldier.combat_team != actor.combat_team or not soldier.is_combat_alive():
			continue
		var distance := _flat_distance(position, soldier.global_position)
		if distance < 1.0:
			risk += 18.0
		elif distance < 1.8:
			risk += 7.0
	return risk

func _segment_is_clear(origin: Vector3, destination: Vector3) -> bool:
	if actor == null or not actor.is_inside_tree() or actor.get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		origin + Vector3.UP * 0.55,
		destination + Vector3.UP * 0.55,
		1
	)
	query.exclude = [actor.get_rid()]
	query.collide_with_areas = false
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _terrain_line_is_clear(origin: Vector3, destination: Vector3) -> bool:
	if actor == null or not actor.is_inside_tree() or actor.get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		origin + Vector3.UP * 1.1,
		destination + Vector3.UP * 1.1,
		1
	)
	query.exclude = [actor.get_rid()]
	query.collide_with_areas = false
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _choice(point: Vector3, selected_risk: float, direct_risk: float, cost: float) -> Dictionary:
	return {
		"valid": true,
		"point": point,
		"selected_risk": selected_risk,
		"direct_risk": direct_risk,
		"cost": cost,
	}

func _distance_to_segment(point: Vector3, start: Vector3, finish: Vector3) -> float:
	var segment := finish - start
	segment.y = 0.0
	var relative := point - start
	relative.y = 0.0
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return relative.length()
	var amount := clampf(relative.dot(segment) / length_squared, 0.0, 1.0)
	return (relative - segment * amount).length()

func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
