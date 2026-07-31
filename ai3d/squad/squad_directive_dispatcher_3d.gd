extends Node
class_name SquadDirectiveDispatcher3D

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
			_bind(task, member, coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.HOLD_SECTOR, null, member.global_position, [], null,
				1.2, task.reason, task.zone_id, task.rules_of_engagement
			))

func _dispatch_formation_move(task: SquadTask3D, recipients: Array[Soldier3D]) -> void:
	for index in recipients.size():
		var destination := _formation_position(task.target_position, index, recipients.size(), 1.6)
		var type := SquadDirective3D.Type.WITHDRAW if task.type == SquadTask3D.Type.RETURN_TO_ORIGIN else SquadDirective3D.Type.MOVE
		_bind(task, recipients[index], coordinator.issue_tactical_directive(
			recipients[index], type, null, destination, [], null, 0.0, task.reason, task.zone_id, task.rules_of_engagement
		))

func _dispatch_cover(task: SquadTask3D, recipients: Array[Soldier3D], target: Node3D) -> void:
	for member in recipients:
		if member.is_pinned():
			var pinned_directive := coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.HOLD_SECTOR, target, member.global_position, [], null, 1.4,
				"Pinned: stay prone and survive the fire", task.zone_id, SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
			)
			_bind(task, member, pinned_directive)
			if pinned_directive != null:
				task_member_succeeded.emit(task.task_id, StringName(member.name))
			continue
		var assignment := _reserve_nearest_cover(member, task.target_position)
		var cover := assignment.get("cover") as TacticalCover3D
		var slot := assignment.get("slot") as Marker3D
		if cover != null and slot != null:
			_bind(task, member, coordinator.issue_tactical_directive(
				member, SquadDirective3D.Type.TAKE_COVER, target, slot.global_position, [], cover, 0.0, task.reason, task.zone_id, task.rules_of_engagement
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
	for member in recipients:
		var member_contact_id := StringName(task.member_contact_ids.get(StringName(member.name), task.contact_id))
		var member_contact := _find_contact(member_contact_id)
		if type in [SquadDirective3D.Type.ATTACK, SquadDirective3D.Type.AIM]:
			member_contact = _best_visible_contact_for(member, member_contact)
		var member_target := member_contact.get_target() if member_contact != null else target
		var member_target_position := member_contact.last_known_position if member_contact != null else task.target_position
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
	for index in recipients.size():
		var destination := _formation_position(task.target_position, index, recipients.size(), minf(2.5, coordinator.mission_radius * 0.3))
		var directive := coordinator.issue_tactical_directive(
			recipients[index], SquadDirective3D.Type.HOLD_SECTOR, null, destination, [], null, 0.0, task.reason, task.zone_id, task.rules_of_engagement
		)
		_bind(task, recipients[index], directive)
		if directive != null:
			task_member_ready.emit(task.task_id, StringName(recipients[index].name))

func _dispatch_recover(task: SquadTask3D, recipients: Array[Soldier3D]) -> void:
	for member in recipients:
		_bind(task, member, coordinator.issue_tactical_directive(
			member, SquadDirective3D.Type.HOLD_SECTOR, null, member.global_position, [], null,
			maxf(1.0, task.duration), "Recover under cover before re-engaging", task.zone_id,
			SquadDirective3D.RulesOfEngagement.WEAPONS_HOLD
		))

func _reserve_nearest_cover(member: Soldier3D, threat_position: Vector3) -> Dictionary:
	var covers: Array = coordinator.get_registered_covers()
	covers.sort_custom(func(a: TacticalCover3D, b: TacticalCover3D):
		return a.score_for_actor(member, threat_position, member.weapon_component.effective_range * 0.72) \
			> b.score_for_actor(member, threat_position, member.weapon_component.effective_range * 0.72)
	)
	for node in covers:
		if not node is TacticalCover3D:
			continue
		var cover := node as TacticalCover3D
		if member.global_position.distance_to(cover.global_position) > maxf(10.0, member.emergency_cover_max_distance * 1.5):
			continue
		if not coordinator.is_position_allowed_by_mission(cover.global_position):
			continue
		var slot := cover.reserve_reachable_slot(member, threat_position)
		if slot != null:
			return {"cover": cover, "slot": slot}
	return {}

func _find_contact(contact_id: StringName) -> CombatContact3D:
	return belief.contacts.get(contact_id) as CombatContact3D if belief != null else null

func _bind(task: SquadTask3D, member: Soldier3D, directive: SquadDirective3D) -> void:
	if directive == null:
		task_member_failed.emit(task.task_id, StringName(member.name), "directive could not be created")
		return
	directive_bound.emit(task.task_id, StringName(member.name), directive.version)

func _formation_position(center: Vector3, index: int, count: int, radius: float) -> Vector3:
	if count <= 1:
		return center
	var angle := TAU * float(index) / float(count)
	return center + Vector3(cos(angle), 0.0, sin(angle)) * radius
