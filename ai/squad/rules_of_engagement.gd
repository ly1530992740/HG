extends RefCounted
class_name RulesOfEngagement

enum Type {
	WEAPONS_HOLD,
	WEAPONS_TIGHT,
	WEAPONS_FREE,
}

static func get_label(value: Type) -> String:
	match value:
		Type.WEAPONS_HOLD:
			return "HOLD"
		Type.WEAPONS_TIGHT:
			return "TIGHT"
	return "FREE"
