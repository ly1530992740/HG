extends Area3D
class_name WeaponPickup3D

@export var weapon_id := "rifle"
@export var display_name := "步枪"
@export_range(0, 500, 1) var ammo_amount := 30
@export_range(0.0, 5.0, 0.1) var pickup_delay := 0.25

var _elapsed := 0.0

func _ready() -> void:
	add_to_group("pickup3d")
	body_entered.connect(_on_body_entered)
	var definition := WeaponCatalog3D.get_definition(weapon_id)
	display_name = String(definition.get("display_name", display_name))
	$Label.text = display_name
	WeaponModelFactory3D.rebuild($ModelRoot, definition, 0.72)

func _process(delta: float) -> void:
	_elapsed += delta
	$ModelRoot.rotation.y += delta * 1.4

func _on_body_entered(body: Node3D) -> void:
	if _elapsed < pickup_delay or not body.has_method("receive_weapon_pickup"):
		return
	if bool(body.receive_weapon_pickup(weapon_id, ammo_amount)):
		queue_free()
