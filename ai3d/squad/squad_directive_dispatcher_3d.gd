extends Node
class_name SquadDirectiveDispatcher3D

const OBJECTIVE_CLEARANCE := preload("res://ai3d/squad/squad_objective_clearance_3d.gd")

signal directive_bound(task_id: StringName, member_id: StringName, directive_version: int)
signal task_member_ready(task_id: StringName, member_id: StringName)
signal task_member_succeeded(task_id: StringName, member_id: StringName)
signal task_member_failed(task_id: StringName, member_id: StringName, reason: String)

var coordinator: SquadCoordinator3D
var belief: SquadBeliefState3D

func configure(owner_coordinator: SquadCoordinator3D, shared_belief: SquadBeliefState3D) -> void:
	coordinator = owner_coordinator
	belief = shared_belief

func dispatch(task: SquadTask3D) -> void:
	if coordinator == null or task == null:
		return
	var recipients: Array[Soldier3D] = []
	for member_id in task.recipient_ids:
		var member := coordinator.get_member_by_id(String(member_id))
		if member != null:
			recipients.append(member)
		else:
			task_member_failed.emit(task.task_id, StringName(member_id), "member unavailable")
	var contact := _find_contact(task.contact_id)
	var target := contact.get_target() if contact != null else null
	match task.type:
		SquadTask3D.Type.MOVE_TO_OBJECTIVE, SquadTask3D.Type.RETURN_TO_ORIGIN:
			_dispatch_formation_move(task, recipients)
		SquadTask3D.Type.TAKE_COVER:
			_dispatch_cover(task, recipients, target)
		SquadTask3D.Type.RECON_ZONE, SquadTask3D.Type.FLANK_ZONE:
			_dispatch_recon(task, recipients)
		SquadTask3D.Type.SUPPRESS_CONTACT:
			_dispatch_fire_task(task, recipients, target, SquadDirective3D.Type.SUPPRESS)
		SquadTask3D.Type.ATTACK_CONTACT:
			_dispatch_fire_task(task, recipients, target, SquadDirective3D.Type.ATTACK)
		SquadTask3D.Type.AIM_CONTACT:
			_dispatch_fire_task(task, recipients, target, SquadDirective3D.Type.AIM)
		SquadTask3D.Type.HOLD_OBJECTIVE:
			_dispatch_hold(task, recipients)
		SquadTask3D.Type.RECOVER_IN_COVER:
			_dispatch_recover(task, recipients)

func redispatch_persistent_member(task: SquadTask3D, member: Soldier3D) -> void:
	if coordinator == null or task == null or member == null or not task.persistent:
		return
	var recipients: Array[Soldier3D] = [member]
	var contact := _find_contact(task.contact_id)
	var target := contact.get_target() if contact != null else null
	match task.type:
		SquadTask3D.Type.SUPPRESS_CONTACT:
			_dispatch_fire_task(task, recipients, target, SquadDirective3D.Type.SUPPRESS)
		SquadTask3D.Type.ATTACK_CONTACT:
			_dispatch_fire_task(task, recipients, target, SquadDirective3D.Type.ATTACK)
		SquadTask3D.Type.HOLD_OBJECTIVE:
			_dispatch_hold(task, recipients)

func _dispatch_formation_move(task: SquadTask3D, recipients: Array[Soldier3D]) -> void:
	for index in recipients.size():
		var destination := _formation_position(task.target_position, index, recipients.size(), 1.6)
		var type := SquadDirective3D.Type.WITHDRAW if task.type == SquadTask3D.Type.RETURN_TO_ORIGIN else SquadDirective3D.Type.MOVE
		_bind(task, recipients[index], coordinator.issue_tactical_directive(
			recipients[index], type, null, destination, task.route, null, 0.0, task.reason, task.zone_id, task.rules_of_engagement
		))

func _dispatch_cover(task: SquadTask3D, recipients: Array[Soldier3D], target: Node3D) -> void:
	if task.prefer_defensive_structures:
		_ensure_defensive_structure_reservations(task, recipients, coordinator.get_mission_target_position(), target)
	for member in recipients:
		var structure := _reserved_structure_for(member)
		if structure != null and (target == null or structure.can_engage_target(target)):
			_bind(task, member, coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.USE_STRUCTURE, target, structure.get_operator_position(), [], null, 0.8,
				"Take defensive position in %s" % structure.get_structure_label(), task.zone_id,
				task.rules_of_engagement, structure
			))
			continue
		elif structure != null:
			structure.release(member)
		if member.is_pinned() and not task.advance_toward_objective:
			var pinned_directive := coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.HOLD_SECTOR, target, member.global_position, [], null, 1.4,
				"Pinned: stay prone and survive the fire", task.zone_id, SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
			)
			_bind(task, member, pinned_directive)
			if pinned_directive != null:
				task_member_succeeded.emit(task.task_id, StringName(member.name))
			continue
		var assignment := _reserve_best_cover(member, task.target_position, task.advance_toward_objective, task)
		var cover := assignment.get("cover") as TacticalCover3D
		var slot := assignment.get("slot") as Marker3D
		if cover != null and slot != null:
			print("[TACTICAL3D_COVER_CHOICE] squad=%s member=%s cover=%s score=%.1f route_risk=%.1f destination_risk=%.1f advance=%s" % [
				coordinator.squad_display_name, member.name, cover.name,
				float(assignment.get("score", 0.0)), float(assignment.get("route_risk", 0.0)),
				float(assignment.get("destination_risk", 0.0)), task.advance_toward_objective,
			])
			_bind(task, member, coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.TAKE_COVER, target, slot.global_position, [], cover, 0.0, task.reason, task.zone_id, task.rules_of_engagement
			))
		elif task.advance_toward_objective:
			var staging := _safest_objective_staging_position(member, task.target_position)
			print("[TACTICAL3D_OBJECTIVE_STAGING] squad=%s member=%s distance=%.1f destination=(%.1f, %.1f)" % [
				coordinator.squad_display_name, member.name, _flat_distance(member.global_position, staging), staging.x, staging.z,
			])
			_bind(task, member, coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.MOVE, null, staging, [], null, 0.0,
				"Advance to a protected observation point before entering the objective", task.zone_id,
				SquadDirective3D.RulesOfEngagement.RETURN_FIRE
			))
		else:
			_bind(task, member, coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.HOLD_SECTOR, target, member.global_position, [], null, 0.0, "No cover available; hold low", task.zone_id, task.rules_of_engagement
			))

func _dispatch_recon(task: SquadTask3D, recipients: Array[Soldier3D]) -> void:
	for index in recipients.size():
		var destination := _formation_position(task.target_position, index, recipients.size(), 1.0)
		var directive := coordinator.issue_tactical_directive(
			recipients[index], SquadDirective3D.Type.RECON, null, destination, task.route, null, task.duration, task.reason, task.zone_id, task.rules_of_engagement
		)
		if directive != null:
			directive.observation_seconds = 1.2 if task.type == SquadTask3D.Type.RECON_ZONE else 0.45
		_bind(task, recipients[index], directive)

func _dispatch_fire_task(task: SquadTask3D, recipients: Array[Soldier3D], target: Node3D, type: SquadDirective3D.Type) -> void:
	if task.prefer_defensive_structures:
		_ensure_defensive_structure_reservations(task, recipients, coordinator.get_mission_target_position(), target)
	for member in recipients:
		var member_contact_id := StringName(task.member_contact_ids.get(StringName(member.name), task.contact_id))
		var member_contact := _find_contact(member_contact_id)
		if type in [SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.AIM]:
			member_contact = _best_visible_contact_for(member, member_contact)
		var member_target := member_contact.get_target() if member_contact != null else target
		var member_target_position := member_contact.last_known_position if member_contact != null else task.target_position
		var structure := _reserved_structure_for(member)
		if structure != null and (member_target == null or structure.can_engage_target(member_target)):
			var operation_duration := 0.0 if task.persistent else maxf(0.8, task.duration)
			var structure_directive := coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.USE_STRUCTURE, member_target, structure.get_operator_position(), [], null,
				operation_duration, "Defend from %s" % structure.get_structure_label(), task.zone_id,
				task.rules_of_engagement, structure
			)
			_bind(task, member, structure_directive)
			if task.persistent and structure_directive != null:
				task_member_ready.emit(task.task_id, StringName(member.name))
			continue
		elif structure != null:
			structure.release(member)
		if member_target == null or (type in [SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.AIM] \
				and not member.perception_component.has_line_of_sight(member_target)):
			var hold := coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.HOLD_SECTOR, null, member.global_position, [], null, 0.8 if task.persistent else 0.0,
				"No visible assigned target; observe sector", task.zone_id, SquadDirective3D.RulesOfEngagement.RETURN_FIRE
			)
			_bind(task, member, hold)
			if task.persistent and hold != null:
				task_member_ready.emit(task.task_id, StringName(member.name))
			continue
		var directive := coordinator.issue_tactical_directive(
			member, type, member_target, member_target_position, [], null, task.duration, task.reason, task.zone_id, task.rules_of_engagement
		)
		_bind(task, member, directive)
		if task.persistent and directive != null:
			task_member_ready.emit(task.task_id, StringName(member.name))

func _best_visible_contact_for(member: Soldier3D, preferred: CombatContact3D) -> CombatContact3D:
	if preferred != null and is_instance_valid(preferred.get_target()) \
			and member.perception_component.has_line_of_sight(preferred.get_target()):
		return preferred
	for candidate in belief.get_living_contacts():
		var target := candidate.get_target()
		if is_instance_valid(target) and member.perception_component.has_line_of_sight(target):
			return candidate
	return null

func _dispatch_hold(task: SquadTask3D, recipients: Array[Soldier3D]) -> void:
	var unassigned := recipients.duplicate()
	if task.prefer_defensive_structures:
		var structures: Array = coordinator.get_registered_structures()
		structures.sort_custom(func(a: TacticalStructure3D, b: TacticalStructure3D):
			return a.defense_priority > b.defense_priority
		)
		for node in structures:
			if not node is TacticalStructure3D:
				continue
			var structure := node as TacticalStructure3D
			if not coordinator.is_position_allowed_by_mission(structure.global_position):
				continue
			var selected: Soldier3D
			var selected_score := 0.0
			for member in unassigned:
				var score := structure.get_defense_score(member, task.target_position)
				if score > selected_score:
					selected = member
					selected_score = score
			if selected == null or not structure.reserve(selected):
				continue
			_release_other_structure_reservations(selected, structure)
			print("[TACTICAL3D_STRUCTURE_ASSIGN] squad=%s task=%s structure=%s member=%s" % [
				coordinator.squad_display_name, task.task_id, structure.name, selected.name,
			])
			var directive := coordinator.issue_tactical_directive(
				selected, SquadDirective3D.Type.USE_STRUCTURE, null, structure.get_operator_position(), [], null,
				0.0, "Occupy %s for defense" % structure.get_structure_label(), task.zone_id,
				task.rules_of_engagement, structure
			)
			_bind(task, selected, directive)
			if directive != null:
				task_member_ready.emit(task.task_id, StringName(selected.name))
			unassigned.erase(selected)
	for index in unassigned.size():
		var destination := _formation_position(task.target_position, index, recipients.size(), minf(2.5, coordinator.mission_radius * 0.3))
		var directive := coordinator.issue_tactical_directive(
			unassigned[index], SquadDirective3D.Type.HOLD_SECTOR, null, destination, [], null, 0.0, task.reason, task.zone_id, task.rules_of_engagement
		)
		_bind(task, unassigned[index], directive)
		if directive != null:
			task_member_ready.emit(task.task_id, StringName(unassigned[index].name))

func _dispatch_recover(task: SquadTask3D, recipients: Array[Soldier3D]) -> void:
	if task.prefer_defensive_structures:
		_ensure_defensive_structure_reservations(task, recipients, coordinator.get_mission_target_position(), null)
	for member in recipients:
		var structure := _reserved_structure_for(member)
		if structure != null:
			_bind(task, member, coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.USE_STRUCTURE, null, structure.get_operator_position(), [], null,
				maxf(1.0, task.duration), "Recover while holding %s" % structure.get_structure_label(), task.zone_id,
				SquadDirective3D.RulesOfEngagement.RETURN_FIRE, structure
			))
			continue
		_bind(task, member, coordinator.issue_tactical_directive(
			member, SquadDirective3D.Type.HOLD_SECTOR, null, member.global_position, [], null,
			maxf(1.0, task.duration), "Recover under cover before re-engaging", task.zone_id,
			SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
		))

func _reserve_best_cover(
		member: Soldier3D,
		threat_position: Vector3,
		advancing := false,
		task: SquadTask3D = null
) -> Dictionary:
	var covers: Array = coordinator.get_registered_covers()
	var candidates: Array[Dictionary] = []
	for node in covers:
		if not node is TacticalCover3D:
			continue
		var cover := node as TacticalCover3D
		if task != null and StringName(cover.name) in task.excluded_cover_ids:
			continue
		var max_distance := maxf(10.0, member.emergency_cover_max_distance * (2.0 if advancing else 1.5))
		if member.global_position.distance_to(cover.global_position) > max_distance:
			continue
		if not coordinator.is_position_allowed_by_mission(cover.global_position):
			continue
		var objective_distance := _flat_distance(cover.global_position, threat_position)
		var progress := _flat_distance(member.global_position, threat_position) - objective_distance
		if advancing:
			if objective_distance < coordinator.mission_radius * 0.82 or progress < 0.75:
				continue
		var tactical_score := cover.score_for_actor(member, threat_position, member.weapon_component.effective_range * 0.72)
		var route_risk := 0.0
		var destination_risk := 0.0
		if member.local_threat_field != null:
			tactical_score = member.local_threat_field.score_cover(
				cover, threat_position, member.weapon_component.effective_range * 0.72
			)
			route_risk = member.local_threat_field.score_segment(member.global_position, cover.global_position)
			destination_risk = member.local_threat_field.score_position(cover.global_position)
		if advancing and (route_risk >= 85.0 or destination_risk >= 70.0):
			continue
		var score := tactical_score + (progress * 2.4 if advancing else 0.0)
		candidates.append({
			"cover": cover,
			"score": score,
			"route_risk": route_risk,
			"destination_risk": destination_risk,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		return float(a.get("score", -INF)) > float(b.get("score", -INF))
	)
	for candidate in candidates:
		var cover := candidate.get("cover") as TacticalCover3D
		var slot := cover.reserve_reachable_slot(member, threat_position)
		if slot != null:
			candidate["slot"] = slot
			return candidate
	return {}

func _safest_objective_staging_position(member: Soldier3D, objective: Vector3) -> Vector3:
	var from_objective := member.global_position - objective
	from_objective.y = 0.0
	if from_objective.length_squared() <= 0.01:
		from_objective = Vector3.BACK
	var base_direction := from_objective.normalized()
	var staging_radius := maxf(3.0, coordinator.mission_radius * 1.08)
	var minimum_reposition_distance := maxf(2.5, coordinator.mission_radius * 0.35)
	var best := objective + base_direction * staging_radius
	var best_cost := INF
	for index in 8:
		var direction := base_direction.rotated(Vector3.UP, float(index - 3) * PI / 4.0)
		var candidate := objective + direction * staging_radius
		if _flat_distance(member.global_position, candidate) < minimum_reposition_distance:
			continue
		var route_risk := member.local_threat_field.score_segment(member.global_position, candidate) \
			if member.local_threat_field != null else 0.0
		var destination_risk := member.local_threat_field.score_position(candidate) \
			if member.local_threat_field != null else 0.0
		var visibility := OBJECTIVE_CLEARANCE.visible_sample_count(
			member.get_world_3d(), candidate, member.get_rid(), objective, coordinator.mission_radius
		)
		var cost := _flat_distance(member.global_position, candidate) + route_risk * 0.85 \
			+ destination_risk * 0.35 - float(visibility) * 7.0
		if cost < best_cost:
			best = candidate
			best_cost = cost
	return best

func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()

func _reserved_structure_for(member: Soldier3D) -> TacticalStructure3D:
	if is_instance_valid(member.active_structure) and member.active_structure.is_reserved_by(member):
		return member.active_structure
	for node in coordinator.get_registered_structures():
		if node is TacticalStructure3D and (node as TacticalStructure3D).is_reserved_by(member):
			return node as TacticalStructure3D
	return null

func _release_other_structure_reservations(member: Soldier3D, selected: TacticalStructure3D) -> void:
	for node in coordinator.get_registered_structures():
		if node is TacticalStructure3D and node != selected:
			(node as TacticalStructure3D).release(member)

func _ensure_defensive_structure_reservations(task: SquadTask3D, recipients: Array[Soldier3D], objective_position: Vector3, target: Node3D) -> void:
	var available_members := recipients.filter(func(member: Soldier3D): return _reserved_structure_for(member) == null)
	var structures: Array = coordinator.get_registered_structures()
	structures.sort_custom(func(a: TacticalStructure3D, b: TacticalStructure3D): return a.defense_priority > b.defense_priority)
	for node in structures:
		if not node is TacticalStructure3D:
			continue
		var structure := node as TacticalStructure3D
		if not structure.is_available_to(null) or not coordinator.is_position_allowed_by_mission(structure.global_position):
			continue
		if is_instance_valid(target) and not structure.can_engage_target(target):
			continue
		var selected: Soldier3D
		var selected_score := 0.0
		for member in available_members:
			var score := structure.get_defense_score(member, objective_position)
			if score > selected_score:
				selected = member
				selected_score = score
		if selected != null and structure.reserve(selected):
			available_members.erase(selected)
			print("[TACTICAL3D_STRUCTURE_ASSIGN] squad=%s task=%s structure=%s member=%s" % [
				coordinator.squad_display_name, task.task_id, structure.name, selected.name,
			])

func _find_contact(contact_id: StringName) -> CombatContact3D:
	return belief.contacts.get(contact_id) as CombatContact3D if belief != null else null

func _bind(task: SquadTask3D, member: Soldier3D, directive: SquadDirective3D) -> void:
	if directive == null:
		task_member_failed.emit(task.task_id, StringName(member.name), "directive could not be created")
		return
	if directive.type == SquadDirective3D.Type.USE_STRUCTURE:
		print("[TACTICAL3D_STRUCTURE_DIRECTIVE] squad=%s task=%s member=%s structure=%s version=%d" % [
			coordinator.squad_display_name, task.task_id, member.name,
			directive.assigned_structure.name if is_instance_valid(directive.assigned_structure) else "NONE",
			directive.version,
		])
	directive_bound.emit(task.task_id, StringName(member.name), directive.version)

func _formation_position(center: Vector3, index: int, count: int, radius: float) -> Vector3:
	if count <= 1:
		return center
	var angle := TAU * float(index) / float(count)
	return center + Vector3(cos(angle), 0.0, sin(angle)) * radius
