extends Resource
class_name WeaponData

enum FireMode {
	SEMI_AUTO,
	AUTO,
	BURST
}

enum ReloadType {
	MAGAZINE,
	ROUND_BY_ROUND
}

@export var weapon_name := "Rifle"

@export_category("Damage")
@export var damage := 10
@export var knockback := 0.0

@export_category("Fire")
@export var fire_mode: FireMode = FireMode.SEMI_AUTO
@export var fire_cooldown := 0.25
@export var burst_count := 3
@export var burst_delay := 0.08
@export var spread_degrees := 2.0
@export var projectile_count := 1
@export var projectile_spread_degrees := 0.0
@export var ammo_per_shot := 1
@export var cycle_time := 0.0

@export_category("Ammo")
@export var reload_type: ReloadType = ReloadType.MAGAZINE
@export var magazine_size := 8
@export var reserve_ammo := 32
@export var reload_time := 1.4

@export_category("Projectile")
@export var projectile_scene: PackedScene
@export var projectile_speed := 1200.0
@export var projectile_lifetime := 0.6
@export var hit_groups: Array[String] = ["goblin"]

@export_category("Melee")
@export var melee_range := 34.0
@export var melee_radius := 28.0
@export var melee_active_time := 0.08
@export var melee_recover_time := 0.12

@export_category("Feedback")
@export var shoot_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream
@export var muzzle_flash_scene: PackedScene
