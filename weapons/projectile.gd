extends Area2D
class_name Projectile

var velocity := Vector2.ZERO
var damage := 1
var lifetime := 1.0
var shooter: Node = null
var hit_groups: Array[String] = []
var knockback := 0.0
var alive := true

func _ready() -> void:
	add_to_group("projectile")
	add_to_group("bullet")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func launch(config: Dictionary) -> void:
	var direction: Vector2 = config.get("direction", Vector2.RIGHT)

	velocity = direction.normalized() * float(config.get("speed", 1000.0))
	damage = int(config.get("damage", 1))
	lifetime = float(config.get("lifetime", 1.0))
	shooter = config.get("shooter", null)
	hit_groups = config.get("hit_groups", [])
	knockback = float(config.get("knockback", 0.0))
	rotation = direction.angle()

	await get_tree().create_timer(lifetime).timeout
	if alive:
		queue_free()

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_body_entered(body: Node2D) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	if shooter and (area == shooter or area.get_parent() == shooter):
		return

	var target := _get_damage_area_target(area)
	if target is Node2D:
		_try_hit(target)

func _try_hit(target: Node2D) -> void:
	if not alive:
		return

	if target == shooter:
		return

	if not _can_hit(target):
		return

	alive = false
	_apply_damage(target)
	queue_free()

func _can_hit(target: Node) -> bool:
	if hit_groups.is_empty():
		return target.has_method("take_damage")

	for group_name in hit_groups:
		if target.is_in_group(group_name):
			return true

	return false

func _apply_damage(target: Node2D) -> void:
	if target.has_method("take_damage"):
		target.take_damage(damage, global_position)
	elif target.has_method("take_damages"):
		target.take_damages(damage)

func _get_damage_area_target(area: Area2D) -> Node:
	if not _is_damage_area(area):
		return null

	return area.get_parent()

func _is_damage_area(area: Area2D) -> bool:
	var area_name := String(area.name).to_lower()
	return area.is_in_group("hurtbox") \
		or area.is_in_group("hitbox") \
		or area_name == "hurtbox" \
		or area_name == "hitbox"
