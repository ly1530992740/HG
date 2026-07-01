extends Node2D
class_name Weapon

@warning_ignore("unused_signal")
signal attack_started
@warning_ignore("unused_signal")
signal attack_finished
@warning_ignore("unused_signal")
signal attack_failed(reason: String)

@export var weapon_data: WeaponData
@export var muzzle_path: NodePath

var wielder: Node = null
var is_equipped := false

@onready var muzzle: Node2D = get_node_or_null(muzzle_path)

func equip(new_wielder: Node) -> void:
	wielder = new_wielder
	is_equipped = true
	show()

func unequip() -> void:
	is_equipped = false
	hide()

func can_attack() -> bool:
	return is_equipped and weapon_data != null

func try_attack(_target_position: Vector2) -> bool:
	push_warning("try_attack() should be implemented by a child weapon class.")
	return false

func stop_attack() -> void:
	pass

func reload() -> bool:
	return false

func get_attack_origin() -> Vector2:
	if muzzle:
		return muzzle.global_position
	return global_position
