extends Node2D

@onready var player: Node2D = $Player
@onready var enemy: Node = $Enemy
@onready var ammo_label: Label = $CanvasLayer/Hud/VBoxContainer/AmmoLabel
@onready var enemy_label: Label = $CanvasLayer/Hud/VBoxContainer/EnemyLabel
@onready var status_label: Label = $CanvasLayer/Hud/VBoxContainer/StatusLabel

func _ready() -> void:
	GlobalPlayer.set_active_pawn(player)
	call_deferred("_bind_player_weapon")
	_bind_enemy()
	status_label.text = "WASD/Arrow move | Mouse aims | F/Q fires | R reloads"

func _process(_delta: float) -> void:
	_update_enemy_hud()

func _bind_player_weapon() -> void:
	var weapon := player.get("firearm_weapon") as FirearmWeapon
	if weapon == null:
		ammo_label.text = "Weapon: not ready"
		return

	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.attack_failed.connect(_on_weapon_attack_failed)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.cycle_started.connect(_on_weapon_cycle_started)
	weapon.cycle_finished.connect(_on_weapon_cycle_finished)
	weapon.weapon_changed.connect(_on_weapon_changed)
	_on_ammo_changed(weapon.magazine_ammo, weapon.reserve_ammo)
	_on_weapon_changed(weapon.weapon_data)

func _bind_enemy() -> void:
	_update_enemy_hud()

	if player.has_signal("died"):
		player.connect("died", _on_player_died)

func _on_ammo_changed(magazine_ammo: int, reserve_ammo: int) -> void:
	var weapon := player.get("firearm_weapon") as FirearmWeapon
	var weapon_name: String = weapon.weapon_data.weapon_name if weapon and weapon.weapon_data else "Weapon"
	ammo_label.text = "%s Ammo: %d / %d" % [weapon_name, magazine_ammo, reserve_ammo]

func _on_weapon_changed(data: WeaponData) -> void:
	if data == null:
		status_label.text = "Weapon: none"
		return

	status_label.text = "Selected: %s | T weapons | F/Q fires | R reloads" % data.weapon_name
	var weapon := player.get("firearm_weapon") as FirearmWeapon
	if weapon:
		_on_ammo_changed(weapon.magazine_ammo, weapon.reserve_ammo)

func _on_weapon_attack_failed(reason: String) -> void:
	status_label.text = "Weapon: %s" % reason

func _on_reload_started() -> void:
	status_label.text = "Reloading..."

func _on_reload_finished() -> void:
	status_label.text = "Ready"

func _on_weapon_cycle_started(_duration: float) -> void:
	status_label.text = "Cycling..."

func _on_weapon_cycle_finished() -> void:
	status_label.text = "Ready"

func _on_enemy_health_changed(current_health: int, max_health: int) -> void:
	enemy_label.text = "Enemy HP: %d / %d" % [current_health, max_health]

func _on_enemy_died() -> void:
	enemy_label.text = "Enemy defeated"
	status_label.text = "Target down"

func _on_player_died(_pawn) -> void:
	status_label.text = "Player defeated!"
	enemy_label.text = "Player down"

func _update_enemy_hud() -> void:
	if not is_instance_valid(enemy):
		enemy_label.text = "Enemy defeated"
		return

	var current_health: Variant = enemy.get("health")
	if current_health == null:
		enemy_label.text = "Enemy: no health"
		return

	enemy_label.text = "Shooter HP: %d" % int(current_health)
