extends RefCounted
class_name SquadCombatRole

enum Type {
	RIFLEMAN,
	MARKSMAN,
	MACHINE_GUNNER,
	SHOTGUNNER,
	PISTOL_SCOUT,
	MELEE,
}

static func get_label(role: Type) -> String:
	match role:
		Type.MARKSMAN:
			return "精确射手"
		Type.MACHINE_GUNNER:
			return "机枪兵"
		Type.SHOTGUNNER:
			return "霰弹突击兵"
		Type.PISTOL_SCOUT:
			return "手枪侦察兵"
		Type.MELEE:
			return "近战兵"
	return "步枪兵"

static func get_short_label(role: Type) -> String:
	match role:
		Type.MARKSMAN:
			return "狙"
		Type.MACHINE_GUNNER:
			return "机"
		Type.SHOTGUNNER:
			return "霰"
		Type.PISTOL_SCOUT:
			return "手"
		Type.MELEE:
			return "刀"
	return "步"
