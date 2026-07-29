extends Node3D

@onready var player: ThirdPersonPlayer3D = $Player
@onready var camera_director: CameraDirector3D = $CameraDirector
@onready var mode_label: Label = $CanvasLayer/Hud/Margin/VBox/Mode
@onready var ammo_label: Label = $CanvasLayer/Hud/Margin/VBox/Ammo
@onready var hit_label: Label = $CanvasLayer/Hud/Margin/VBox/Hit
@onready var crosshair: WeaponSpreadCrosshair3D = $CanvasLayer/Crosshair

func _ready() -> void:
	player.ammo_changed.connect(_on_ammo_changed)
	player.shot_resolved.connect(_on_shot_resolved)
	camera_director.aim_mode_changed.connect(_on_aim_mode_changed)
	camera_director.view_mode_changed.connect(_on_view_mode_changed)
	crosshair.bind_player(player)
	_on_ammo_changed(player.current_ammo, player.reserve_ammo)
	_refresh_mode_label()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_aim_mode_changed(_enabled: bool) -> void:
	_refresh_mode_label()

func _on_view_mode_changed(_shoulder_view: bool) -> void:
	_refresh_mode_label()

func _refresh_mode_label() -> void:
	var view_label := "越肩视角" if camera_director.is_shoulder_view() else "45度战术视角"
	mode_label.text = "%s / %s" % [view_label, "举枪瞄准" if camera_director.is_aiming() else "腰射"]

func _on_ammo_changed(current: int, reserve: int) -> void:
	ammo_label.text = "弹药  %d / %d" % [current, reserve]

func _on_shot_resolved(result: Dictionary) -> void:
	var collider := result.get("collider") as Node
	if collider is CombatHitbox3D:
		var hitbox := collider as CombatHitbox3D
		hit_label.text = "命中：%s" % ("头部" if hitbox.hit_location == "head" else "身体")
	elif collider != null:
		hit_label.text = "命中：掩体"
	else:
		hit_label.text = "未命中"
