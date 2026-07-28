extends Area2D
class_name AmmoPickup

@export_range(1, 500, 1) var ammo_amount := 12
@export_range(0.0, 60.0, 0.5) var lifetime_seconds := 20.0

func _ready() -> void:
	add_to_group("ammo_pickup")
	body_entered.connect(_on_body_entered)
	if lifetime_seconds > 0.0:
		await get_tree().create_timer(lifetime_seconds).timeout
		if is_instance_valid(self):
			queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.has_method("receive_ammo_pickup"):
		return
	body.receive_ammo_pickup(ammo_amount)
	queue_free()
