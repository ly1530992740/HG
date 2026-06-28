extends StaticBody2D

# ==================================================
# NODES
# ==================================================
@onready var anim: AnimatedSprite2D = $anim
@onready var marker: Marker2D = $Marker2D
@onready var hitbox: Area2D = $hitbox
@onready var hit_swordfx: AudioStreamPlayer = $hit_swordfx
@onready var hit_attackfx: AudioStreamPlayer = $hit_attackfx
@onready var destroyed_fx: AudioStreamPlayer = $destroyed_fx

# ==================================================
# CONSTANTS
# ==================================================
const MAX_LIFE := 10
const HIT_FLASH_TIME := 0.15
const ARCHER_SCALE := Vector2(0.8, 0.8)

const GOBLIN_ARCHER_SCENE := preload(
	"res://unit/goblins/tower goblin/Goblin archer.tscn"
)

# ==================================================
# STATE
# ==================================================
var life: int = MAX_LIFE
var is_hit := false
var hit_flash_timer := 0.0
var is_destroyed := false

var spawned_archer: Node2D = null

# ==================================================
# READY
# ==================================================
func _ready() -> void:
	z_index = 3
	spawn_archer()

# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
	if anim.animation == "destroyed":
		$CollisionShape2D.disabled = true
	else:
		$CollisionShape2D.disabled = false

	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0:
			is_hit = false
			anim.modulate = Color.WHITE

# ==================================================
# HIT / DAMAGE
# ==================================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	if is_destroyed:
		return

	if area.is_in_group("arrow"):
		take_damage(2)
		hit_swordfx.play()
	if area.is_in_group("attackeffect"):
		take_damage(2)
		hit_attackfx.play()


func flash_red() -> void:
	is_hit = true
	hit_flash_timer = HIT_FLASH_TIME
	anim.modulate = Color.RED

func die() -> void:
	is_destroyed = true
	anim.play("destroyed")
	destroyed_fx.play()
	await get_tree().create_timer(0.3).timeout
	_fade_and_remove()

	if is_instance_valid(spawned_archer):
		spawned_archer.queue_free()
		spawned_archer = null

# ==================================================
# SPAWN ARCHER
# ==================================================
func spawn_archer() -> void:
	if is_instance_valid(spawned_archer):
		return

	spawned_archer = GOBLIN_ARCHER_SCENE.instantiate()
	add_child(spawned_archer)

	spawned_archer.global_position = marker.global_position
	spawned_archer.scale = ARCHER_SCALE
	spawned_archer.z_index = 3

func _fade_and_remove() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.5)
	await tween.finished
	queue_free()

func take_damage(damage: int) -> void:
	if damage:
		pass
	life -= 1
	hit_attackfx.play()
	if is_destroyed:
		return
	flash_red()
	if life <= 0:
		die()

# =================================================
# DAMAGE
# =================================================

func take_damages(damage: int) -> void:
	if damage:
		pass
	life -= 1
	hit_attackfx.play()
	if is_destroyed:
		return
	flash_red()
	if life <= 0:
		die()
