extends Area3D
class_name AmmoPickup3D

@export_range(1, 500, 1) var ammo_amount := 18
@export_range(0.0, 5.0, 0.1) var pickup_delay := 0.2

var _elapsed := 0.0

func _ready() -> void:
	add_to_group("pickup3d")
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_elapsed += delta
	rotation.y += delta * 1.8

func _on_body_entered(body: Node3D) -> void:
	if _elapsed < pickup_delay or not body.has_method("receive_ammo_pickup"):
		return
	body.receive_ammo_pickup(ammo_amount)
	queue_free()
