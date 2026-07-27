extends RefCounted
class_name SquadOrder

enum Type {
	HOLD,
	TAKE_COVER,
	SUPPRESS,
	FOCUS_FIRE,
	ADVANCE,
	RETREAT,
	STAY_HIDDEN,
	OVERWATCH,
	FLANK_LEFT,
	FLANK_RIGHT,
	AMBUSH_POSITION,
	SEARCH_AREA,
}

var type: Type = Type.HOLD
var issuer: Node = null
var target: Node2D = null
var target_position := Vector2.ZERO
var assigned_cover: Node = null
var recipients: Array[Node] = []
var priority := 0
var expires_at_msec := -1
var version := 0

func configure(
		new_type: Type,
		new_issuer: Node = null,
		new_target: Node2D = null,
		new_target_position := Vector2.ZERO,
		new_assigned_cover: Node = null,
		new_priority := 0,
		duration_seconds := -1.0,
		new_recipients: Array = []
) -> SquadOrder:
	type = new_type
	issuer = new_issuer
	target = new_target
	target_position = new_target_position
	assigned_cover = new_assigned_cover
	recipients.clear()
	for recipient in new_recipients:
		if recipient is Node and is_instance_valid(recipient):
			recipients.append(recipient)
	priority = new_priority
	expires_at_msec = -1
	if duration_seconds > 0.0:
		expires_at_msec = Time.get_ticks_msec() + int(duration_seconds * 1000.0)
	return self

func is_expired() -> bool:
	return expires_at_msec >= 0 and Time.get_ticks_msec() >= expires_at_msec

func get_type_name() -> String:
	return Type.keys()[type]

func applies_to(member: Node) -> bool:
	return recipients.is_empty() or recipients.has(member)
