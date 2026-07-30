extends Node
class_name ShoulderSpriteAnimator3D

const FRAME_COUNTS := {
	"ready": 4,
	"aim": 4,
	"fire": 4,
	"reload": 8,
}

var current_state := "ready"
var animation_set: Dictionary = {}
var _sprite: Sprite3D
var _active := false
var _elapsed := 0.0
var _fire_remaining := 0.0
var _fire_duration := 0.22

func setup(sprite: Sprite3D) -> void:
	_sprite = sprite

func set_animation_set(new_animation_set: Dictionary) -> void:
	animation_set = new_animation_set
	_elapsed = 0.0
	if _active:
		_apply_state(current_state, true)

func set_active(enabled: bool, aiming := false) -> void:
	_active = enabled
	if not _active or _sprite == null:
		return
	_fire_remaining = 0.0
	_apply_state("aim" if aiming else "ready", true)

func notify_fire(weapon_family: String) -> void:
	_fire_duration = 0.16 if weapon_family in ["pistol", "smg"] else (0.26 if weapon_family in ["bolt_rifle", "sniper_rifle", "shotgun"] else 0.2)
	_fire_remaining = _fire_duration
	if _active:
		_apply_state("fire", true)

func notify_reload_started() -> void:
	_fire_remaining = 0.0
	if _active:
		_apply_state("reload", true)

func update_animation(delta: float, aiming: bool, reloading: bool, reload_progress: float, moving: bool) -> void:
	if not _active or _sprite == null or animation_set.is_empty():
		return
	_fire_remaining = maxf(0.0, _fire_remaining - delta)
	var target_state := "reload" if reloading else ("fire" if _fire_remaining > 0.0 else ("aim" if aiming else "ready"))
	_apply_state(target_state)
	_elapsed += delta
	var frame_count := get_frame_count(current_state)
	if current_state == "reload":
		_sprite.frame = clampi(int(floor(clampf(reload_progress, 0.0, 0.999) * float(frame_count))), 0, frame_count - 1)
	elif current_state == "fire":
		var progress := 1.0 - _fire_remaining / maxf(0.01, _fire_duration)
		_sprite.frame = clampi(int(floor(progress * float(frame_count))), 0, frame_count - 1)
	else:
		var fps := 7.0 if current_state == "aim" else (6.0 if moving else 3.5)
		_sprite.frame = int(floor(_elapsed * fps)) % frame_count

func get_frame_count(state: String) -> int:
	return int(FRAME_COUNTS.get(state, 1))

func _apply_state(state: String, force := false) -> void:
	if not force and current_state == state:
		return
	current_state = state
	_elapsed = 0.0
	if _sprite == null:
		return
	var texture := animation_set.get(current_state) as Texture2D
	if texture == null:
		texture = animation_set.get("ready") as Texture2D
	_sprite.texture = texture
	_sprite.hframes = get_frame_count(current_state)
	_sprite.vframes = 1
	_sprite.frame = 0
