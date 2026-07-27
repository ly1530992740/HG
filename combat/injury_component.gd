extends Node
class_name InjuryComponent

signal injury_received(location: HitLocation, fatal: bool)
signal condition_changed

enum HitLocation {
	HEAD,
	HEART,
	TORSO,
	ARM,
	LEG,
}

var arm_wounds := 0
var leg_wounds := 0
var last_hit_location: HitLocation = HitLocation.TORSO

func resolve_hit(base_damage: int, forced_location := -1, target_max_health := 0) -> Dictionary:
	var location: HitLocation = _roll_location() if forced_location < 0 else forced_location as HitLocation
	var fatal := location in [HitLocation.HEAD, HitLocation.HEART]
	var resolved_damage := base_damage
	match location:
		HitLocation.ARM:
			resolved_damage = maxi(1, int(round(float(base_damage) * 0.75)))
			if target_max_health > 0:
				resolved_damage = maxi(resolved_damage, ceili(float(target_max_health) / 3.0))
			arm_wounds = mini(2, arm_wounds + 1)
		HitLocation.LEG:
			resolved_damage = maxi(1, int(round(float(base_damage) * 0.75)))
			if target_max_health > 0:
				resolved_damage = maxi(resolved_damage, ceili(float(target_max_health) / 3.0))
			leg_wounds = mini(2, leg_wounds + 1)
		HitLocation.TORSO:
			resolved_damage = base_damage
			if target_max_health > 0:
				resolved_damage = maxi(resolved_damage, ceili(float(target_max_health) / 3.0))
		_:
			resolved_damage = base_damage

	last_hit_location = location
	injury_received.emit(location, fatal)
	condition_changed.emit()
	return {
		"location": location,
		"damage": resolved_damage,
		"fatal": fatal,
	}

func get_accuracy_multiplier() -> float:
	return 1.0 + float(arm_wounds) * 0.75

func get_movement_multiplier() -> float:
	match leg_wounds:
		1:
			return 0.72
		2:
			return 0.5
	return 1.0

func get_summary() -> String:
	var conditions: PackedStringArray = []
	if arm_wounds > 0:
		conditions.append("手臂伤%d" % arm_wounds)
	if leg_wounds > 0:
		conditions.append("腿伤%d" % leg_wounds)
	return "无伤" if conditions.is_empty() else "+".join(conditions)

func get_location_name(location: HitLocation) -> String:
	match location:
		HitLocation.HEAD:
			return "头部"
		HitLocation.HEART:
			return "心脏"
		HitLocation.ARM:
			return "手臂"
		HitLocation.LEG:
			return "腿部"
	return "躯干"

func _roll_location() -> HitLocation:
	var roll := randf()
	if roll < 0.08:
		return HitLocation.HEAD
	if roll < 0.13:
		return HitLocation.HEART
	if roll < 0.31:
		return HitLocation.ARM
	if roll < 0.50:
		return HitLocation.LEG
	return HitLocation.TORSO
