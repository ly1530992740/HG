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
	_on_ammo_changed(weapon.magazine_ammo, weapon.reserve_ammo)

func _bind_enemy() -> void:
	if enemy.has_signal("health_changed"):
		enemy.connect("health_changed", _on_enemy_health_changed)
	if enemy.has_signal("died"):
		enemy.connect("died", _on_enemy_died)

	_update_enemy_hud()

func _on_ammo_changed(magazine_ammo: int, reserve_ammo: int) -> void:
	ammo_label.text = "Ammo: %d / %d" % [magazine_ammo, reserve_ammo]

func _on_weapon_attack_failed(reason: String) -> void:
	status_label.text = "Weapon: %s" % reason

func _on_reload_started() -> void:
	status_label.text = "Reloading..."

func _on_reload_finished() -> void:
	status_label.text = "Ready"

func _on_enemy_health_changed(current_health: int, max_health: int) -> void:
	enemy_label.text = "Enemy HP: %d / %d" % [current_health, max_health]

func _on_enemy_died() -> void:
	enemy_label.text = "Enemy defeated"
	status_label.text = "Target down"

func _update_enemy_hud() -> void:
	if not is_instance_valid(enemy):
		enemy_label.text = "Enemy defeated"
		return

	var current_health: Variant = enemy.get("health")
	if current_health == null:
		enemy_label.text = "Enemy: formal AI"
		return

	enemy_label.text = "Goblin HP: %d" % int(current_health)
