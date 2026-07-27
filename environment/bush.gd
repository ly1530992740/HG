extends Area2D
class_name Bush

func _ready() -> void:
	add_to_group("concealment_area")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _exit_tree() -> void:
	for body in get_overlapping_bodies():
		_unregister_body(body)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("register_concealment_source"):
		body.register_concealment_source(self)

func _on_body_exited(body: Node2D) -> void:
	_unregister_body(body)

func _unregister_body(body: Node) -> void:
	if is_instance_valid(body) and body.has_method("unregister_concealment_source"):
		body.unregister_concealment_source(self)
