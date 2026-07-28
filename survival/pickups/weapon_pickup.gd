extends Area2D

@export var weapon_id := "pistol"
@export var display_name := "武器"
@export_range(0, 500, 1) var ammo_amount := 0
@export_range(0.0, 300.0, 1.0) var lifetime_seconds := 0.0

@onready var name_label: Label = $Name

func _ready() -> void:
	add_to_group("weapon_pickup")
	name_label.text = display_name
	body_entered.connect(_on_body_entered)
	if lifetime_seconds > 0.0:
		await get_tree().create_timer(lifetime_seconds).timeout
		if is_instance_valid(self):
			queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.has_method("receive_weapon_pickup"):
		return
	if bool(body.receive_weapon_pickup(weapon_id, ammo_amount)):
		queue_free()
