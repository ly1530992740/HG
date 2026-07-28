extends AnimatedSprite2D

@export var damage := 15
@export var building_damage := 30

var source_actor: Node = null
var _hit_targets: Dictionary = {}

func _ready() -> void:
	z_index = 5

func configure_attack(attacker: Node, attack_damage: int) -> void:
	source_actor = attacker
	damage = maxi(0, attack_damage)

func _on_animation_finished() -> void:
	queue_free()

func apply_damage(value: int) -> void:
	damage = maxi(0, value)


func _on_attack_effect_body_entered(body: Node2D) -> void:
	if body == source_actor or _hit_targets.has(body):
		return
	if not _is_valid_target(body):
		return
	_hit_targets[body] = true
	if body.has_method("receive_melee_hit"):
		body.receive_melee_hit(damage, global_position, source_actor)
	elif body.is_in_group("goblinbuildings"):
		if body.has_method("take_damage"):
			body.take_damage(building_damage)
		elif body.has_method("take_damages"):
			body.take_damages(building_damage)
	elif body.has_method("take_damage"):
		body.take_damage(damage, global_position)
	elif body.has_method("take_damages"):
		body.take_damages(damage)

func _is_valid_target(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if source_actor != null and is_instance_valid(source_actor) and source_actor.has_method("can_damage_target"):
		return bool(source_actor.can_damage_target(body))
	return body.is_in_group("goblin") or body.is_in_group("goblinbuildings")
