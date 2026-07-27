extends Node

class SweepTarget:
	extends CharacterBody2D
	var hit_count := 0

	func _ready() -> void:
		add_to_group("combatant")
		collision_layer = 1
		collision_mask = 0
		var collision := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 15.0
		collision.shape = circle
		add_child(collision)

	func get_combat_team() -> StringName:
		return &"sweep_target"

	func is_combat_alive() -> bool:
		return true

	func receive_projectile_hit(_damage: int, _source_position: Vector2, _projectile: Node = null) -> void:
		hit_count += 1

class SweepShooter:
	extends Node2D

	func can_damage_target(_candidate: Node) -> bool:
		return true

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var shooter_scene := load("res://unit/goblins/goblin shooter.tscn") as PackedScene
	var actor := shooter_scene.instantiate() as GoblinBase
	actor.name = "InjuryVisualProbe"
	actor.squad_id = &"injury_visual_probe"
	actor.combat_team = &"injury_visual_probe"
	actor.can_target_players = false
	actor.global_position = Vector2(-10000.0, -10000.0)
	add_child(actor)
	await get_tree().process_frame

	assert(actor.death_cleanup_delay < 0.0, "Shooter corpses are not configured to persist.")
	assert(not actor.death_audio_enabled, "Shooter death audio is enabled.")
	assert(actor.has_node("VisualAnatomy/Head") and actor.has_node("VisualAnatomy/VisualBody"), "Shooter anatomy visuals were not created.")
	var gun_sprite := actor.get_node("VisualGunSprite") as Sprite2D
	assert(gun_sprite.texture != null, "Shooter firearm texture was not assigned.")
	var resting_leg_endpoint := (actor.get_node("VisualAnatomy/LeftLeg") as Line2D).points[2]
	actor.velocity = Vector2(120.0, 0.0)
	actor.call("_update_visual", 0.12)
	assert(not (actor.get_node("VisualAnatomy/LeftLeg") as Line2D).points[2].is_equal_approx(resting_leg_endpoint), "Movement did not animate the shooter legs.")
	actor.call("_on_firearm_fired")
	actor.call("_update_visual", 0.01)
	assert((actor.get_node("MuzzleFlash") as CanvasItem).visible, "Firing did not show the muzzle flash animation.")
	actor.velocity = Vector2.ZERO
	await _assert_continuous_projectile_hit()
	var injury := actor.injury_component
	injury.resolve_hit(1, InjuryComponent.HitLocation.TORSO, actor.max_health)
	injury.resolve_hit(1, InjuryComponent.HitLocation.ARM, actor.max_health)
	injury.resolve_hit(1, InjuryComponent.HitLocation.LEG, actor.max_health)
	injury.resolve_hit(1, InjuryComponent.HitLocation.HEART, actor.max_health)
	injury.resolve_hit(1, InjuryComponent.HitLocation.HEAD, actor.max_health)
	assert((actor.get_node("VisualAnatomy/Wounds/HeadWound") as CanvasItem).visible, "Head trauma has no visible wound.")
	assert((actor.get_node("VisualAnatomy/Wounds/HeartWound") as CanvasItem).visible, "Heart trauma has no visible wound.")
	assert((actor.get_node("VisualAnatomy/Wounds/ArmWound") as CanvasItem).visible, "Arm trauma has no visible wound.")
	assert((actor.get_node("VisualAnatomy/Wounds/LegWound") as CanvasItem).visible, "Leg trauma has no visible wound.")
	assert(actor.get_node_or_null("VisualAnatomy/Wounds/TorsoWound1") != null, "Torso trauma has no visible wound.")

	actor.die()
	await get_tree().process_frame
	assert(not (actor.get_node("sound fx/death_audio") as AudioStreamPlayer).playing, "Shooter death audio played while disabled.")
	await get_tree().physics_frame
	assert(is_instance_valid(actor) and actor.is_inside_tree(), "Persistent shooter corpse was freed.")
	assert(actor.state == GoblinBase.State.DEAD, "Persistent corpse did not remain in the DEAD state.")
	assert(actor.collision_layer == 0 and actor.collision_mask == 0, "Persistent corpse still participates in body collisions.")
	assert(not actor.is_in_group("combatant") and not actor.is_in_group("goblin"), "Persistent corpse remained targetable.")
	assert(not GoblinBase.active_enemies.has(actor), "Persistent corpse remained in AI separation calculations.")
	for node in actor.find_children("*", "CollisionShape2D", true, false):
		assert((node as CollisionShape2D).disabled, "Persistent corpse retained an active hit shape.")
	assert(not (actor.get_node("EnemyHPBar") as CanvasItem).visible, "Persistent corpse kept its health bar visible.")

	print("Injury visual smoke test passed: five wound locations and persistent non-blocking corpse verified.")
	get_tree().quit(0)

func _assert_continuous_projectile_hit() -> void:
	var shooter := SweepShooter.new()
	shooter.name = "SweepShooter"
	shooter.global_position = Vector2(10000.0, 10000.0)
	add_child(shooter)
	var target := SweepTarget.new()
	target.name = "SweepTarget"
	target.global_position = shooter.global_position + Vector2(120.0, 0.0)
	add_child(target)
	await get_tree().physics_frame
	await get_tree().process_frame
	var projectile := (load("res://weapons/enemy_bullet.tscn") as PackedScene).instantiate() as Projectile
	projectile.set_physics_process(false)
	projectile.global_position = shooter.global_position + Vector2(30.0, 0.0)
	add_child(projectile)
	projectile.launch({
		"direction": Vector2.RIGHT,
		"speed": 2600.0,
		"damage": 2,
		"lifetime": 1.0,
		"shooter": shooter,
		"hit_groups": ["combatant"],
	})
	var ray := PhysicsRayQueryParameters2D.create(projectile.global_position, projectile.global_position + Vector2(156.0, 0.0))
	ray.collide_with_bodies = true
	ray.collide_with_areas = true
	ray.collision_mask = projectile.collision_mask
	ray.exclude = [projectile.get_rid()]
	var baseline_hit := projectile.get_world_2d().direct_space_state.intersect_ray(ray)
	assert(baseline_hit.get("collider") == target, "The physics baseline ray did not see the sweep target: %s" % baseline_hit)
	assert(projectile._can_hit(target), "The projectile rejected a valid hostile sweep target.")
	assert(is_equal_approx(projectile.velocity.length(), 2600.0), "Projectile launch did not apply its configured speed.")
	assert(target.hit_count == 0, "The sweep target was hit before the manual high-speed motion.")
	projectile._sweep_motion(projectile.global_position + projectile.velocity * 0.06)
	assert(target.hit_count == 1, "A high-speed projectile tunneled through its target.")
	target.queue_free()
	shooter.queue_free()
