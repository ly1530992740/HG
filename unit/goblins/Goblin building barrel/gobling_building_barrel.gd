extends StaticBody2D

# ------------------------
# NODES
# ------------------------
@onready var anim: AnimatedSprite2D = $anim
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $hitbox

@onready var marker_barrel1: Marker2D = $"Marker barrel1"

@onready var hit_swordfx: AudioStreamPlayer = $hit_swordfx
@onready var hit_attackfx: AudioStreamPlayer = $hit_attackfx
@onready var destroyed_fx: AudioStreamPlayer = $destroyed_fx

# ------------------------
# PRELOADS (EXPORTED)
# ------------------------
@export var GOBLIN_SCENE_BARREL: PackedScene
@export var FIRE_SCENE: PackedScene

# ------------------------
# LIFE
# ------------------------
@export var max_life: int = 300
var life: int = 0
var destroyed: bool = false

# ------------------------
# SPAWN SETTINGS
# ------------------------
@export var spawn_duration: float = 2
@export var wave_interval: float = 1
@export var spawn_radius: float = 10.0
@export var base_wave_size: int = 2
@export var max_wave_size: int = 4


var elapsed_time: float = 0.0
var spawning: bool = false

# ------------------------
# READY
# ------------------------
func _ready() -> void:
	z_index = 3
	life = max_life
	Global.connect("wave_started_signal", _on_wave_started)

# ------------------------
# DAMAGE HANDLING
# ------------------------
func _on_hitbox_area_entered(area: Area2D) -> void:
	if destroyed:
		return
	if not area.is_in_group("attackeffect") and not area.is_in_group("arrow"):
		return

	if area.is_in_group("attackeffect"):
		hit_swordfx.play()
	else:
		hit_attackfx.play()

func _hit_flash() -> void:
	anim.play("hit")
	anim.modulate = Color(1, 0.2, 0.2)
	var tween: Tween = create_tween()
	tween.tween_property(anim, "modulate", Color.WHITE, 0.15)

# ------------------------
# GLOBAL WAVE
# ------------------------
func _on_wave_started(_wave_number: int) -> void:
	if destroyed:
		return

	spawning = true
	Global.wave_start = true
	elapsed_time = 0.0

	Global.register_spawner()
	_spawn_waves_async()

# ------------------------
# SPAWN LOOP
# ------------------------
func _spawn_waves_async() -> void:
	while elapsed_time < spawn_duration and spawning and not destroyed:
		_spawn_wave()
		await get_tree().create_timer(wave_interval).timeout
		elapsed_time += wave_interval

	spawning = false
	Global.wave_start = false
	Global.unregister_spawner()

# ------------------------
# SPAWN LOGIC
# ------------------------
func _spawn_wave() -> void:
	var progress: float = clamp(elapsed_time / spawn_duration, 0.0, 1.0)
	var wave_size: int = int(lerp(base_wave_size, max_wave_size, progress))

	for i in range(wave_size):
		_spawn_goblin(marker_barrel1)

func _spawn_goblin(marker: Marker2D) -> void:
	var goblin: Node2D = GOBLIN_SCENE_BARREL.instantiate()

	var offset: Vector2 = Vector2(
		randf_range(-spawn_radius, spawn_radius),
		randf_range(-spawn_radius, spawn_radius)
	)

	goblin.global_position = marker.global_position + offset

	# disable processing immediately
	goblin.set_process(false)
	goblin.set_physics_process(false)

	get_parent().call_deferred("add_child", goblin)

	_activate_goblin_later(goblin)

func _activate_goblin_later(goblin: Node) -> void:
	await get_tree().create_timer(6.5).timeout

	if is_instance_valid(goblin):
		goblin.set_process(true)
		goblin.set_physics_process(true)

# ------------------------
# DESTROY
# ------------------------
func destroy_house() -> void:
	if destroyed:
		return

	destroyed = true
	spawning = false

	anim.play("destroy")
	destroyed_fx.play()
	collision_shape.disabled = true
	hitbox.monitoring = false

	Global.unregister_spawner()

	await anim.animation_finished

	for i in range(5):
		var fire: Node2D = FIRE_SCENE.instantiate()
		fire.global_position = global_position + Vector2(
			randf_range(-32, 32),
			randf_range(-32, 32)
		)
		get_parent().add_child(fire)

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.5)
	await tween.finished
	Global.Goblin_house += 1
	queue_free()

func take_damage(damage: int) -> void:
	life -= damage
	hit_attackfx.play()
	if destroyed:
		return
	_hit_flash()

	if life <= 0:
		destroy_house()

func take_damages(damage: int) -> void:
	life -= damage
	hit_attackfx.play()
	if destroyed:
		return
	_hit_flash()
	if life <= 0:
		destroy_house()
