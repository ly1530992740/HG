extends CharacterBody3D
class_name TargetDummy3D

signal health_changed(current: int, maximum: int, hit_location: String)
signal died

@export var max_health := 100
@export var respawn_delay := 2.0

@onready var visual: Sprite3D = $Visual
@onready var health_label: Label3D = $HealthLabel

var health := 0
var logical_forward := Vector3.BACK
var _spawn_transform := Transform3D.IDENTITY

func _ready() -> void:
	health = max_health
	_spawn_transform = global_transform
	_update_health_label("")

func receive_hit(damage: int, hit_location: String, _hit_position: Vector3, _instigator: Node, _weapon_metadata := {}) -> void:
	if health <= 0:
		return
	health = maxi(0, health - damage)
	_update_health_label(hit_location)
	_flash_hit()
	health_changed.emit(health, max_health, hit_location)
	if health <= 0:
		_die()

func is_alive() -> bool:
	return health > 0

func _die() -> void:
	died.emit()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(respawn_delay).timeout
	if not is_inside_tree():
		return
	health = max_health
	global_transform = _spawn_transform
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_update_health_label("")
	health_changed.emit(health, max_health, "respawn")

func _update_health_label(hit_location: String) -> void:
	if health_label == null:
		return
	var suffix := "  头部" if hit_location == "head" else ""
	health_label.text = "目标 %d/%d%s" % [health, max_health, suffix]

func _flash_hit() -> void:
	if visual == null:
		return
	visual.modulate = Color(1.0, 0.25, 0.18)
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color.WHITE, 0.12)
