extends Weapon
class_name MeleeWeapon

signal hitbox_spawned(hitbox: Area2D)

var cooldown_timer := 0.0
var attacking := false

func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer = max(0.0, cooldown_timer - delta)

func try_attack(target_position: Vector2) -> bool:
	if not can_attack():
		emit_signal("attack_failed", "not_ready")
		return false

	if attacking:
		emit_signal("attack_failed", "attacking")
		return false

	if cooldown_timer > 0.0:
		emit_signal("attack_failed", "cooldown")
		return false

	attacking = true
	cooldown_timer = weapon_data.fire_cooldown

	var origin := get_attack_origin()
	var direction := (target_position - origin).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	_spawn_hitbox(origin, direction)
	emit_signal("attack_started")
	_finish_attack_async()
	return true

func _spawn_hitbox(origin: Vector2, direction: Vector2) -> void:
	var hitbox := Area2D.new()
	hitbox.name = "MeleeHitbox"
	hitbox.add_to_group("attackeffect")
	hitbox.global_position = origin + direction * weapon_data.melee_range
	hitbox.rotation = direction.angle()
	hitbox.monitoring = true
	hitbox.monitorable = false

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = weapon_data.melee_radius
	shape.shape = circle
	hitbox.add_child(shape)

	get_tree().current_scene.add_child(hitbox)
	hitbox.area_entered.connect(_on_hitbox_area_entered.bind(hitbox))
	emit_signal("hitbox_spawned", hitbox)

	await get_tree().create_timer(weapon_data.melee_active_time).timeout
	if is_instance_valid(hitbox):
		hitbox.queue_free()

func _on_hitbox_area_entered(area: Area2D, hitbox: Area2D) -> void:
	var target := area.get_parent()
	if target == wielder:
		return

	if not _can_hit(target):
		return

	if target.has_method("take_damage"):
		target.take_damage(weapon_data.damage, hitbox.global_position)
	elif target.has_method("take_damages"):
		target.take_damages(weapon_data.damage)

func _can_hit(target: Node) -> bool:
	if target == null:
		return false

	if weapon_data.hit_groups.is_empty():
		return target.has_method("take_damage") or target.has_method("take_damages")

	for group_name in weapon_data.hit_groups:
		if target.is_in_group(group_name):
			return true

	return false

func _finish_attack_async() -> void:
	await get_tree().create_timer(weapon_data.melee_recover_time).timeout
	attacking = false
	emit_signal("attack_finished")
