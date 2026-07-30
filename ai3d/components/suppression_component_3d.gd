extends Node
class_name SuppressionComponent3D

signal suppression_changed(value: float)
signal level_changed(level: Level)

enum Level { NORMAL, SUPPRESSED, PINNED }

@export var decay_delay := 0.9
@export var exposed_decay_per_second := 6.0
@export var covered_decay_per_second := 12.0

var actor: Soldier3D
var suppression := 0.0
var level: Level = Level.NORMAL
var time_since_event := 999.0
var last_source_position := Vector3.ZERO

func configure(owner_actor: Soldier3D) -> void:
	actor = owner_actor

func _process(delta: float) -> void:
	time_since_event += delta
	if actor == null or suppression <= 0.0 or time_since_event <= decay_delay:
		return
	var decay := covered_decay_per_second if is_instance_valid(actor.active_cover) else exposed_decay_per_second
	_set_suppression(suppression - decay * delta)

func report_near_miss(source_position: Vector3, intensity := 1.0) -> void:
	last_source_position = source_position
	_add_suppression(18.0 * clampf(intensity, 0.25, 3.0))

func report_cover_impact(source_position: Vector3, intensity := 1.0) -> void:
	last_source_position = source_position
	_add_suppression(12.0 * clampf(intensity, 0.25, 3.0))

func report_damage(amount: int, source_position: Vector3) -> void:
	last_source_position = source_position
	_add_suppression(28.0 + minf(28.0, float(amount) * 0.5))

func is_under_fire() -> bool:
	return suppression >= 16.0 or time_since_event <= 1.5

func is_pinned() -> bool:
	return level == Level.PINNED

func get_accuracy_multiplier() -> float:
	return 1.0 + suppression / 100.0 * 1.8

func get_level_name() -> String:
	return Level.keys()[level]

func _add_suppression(amount: float) -> void:
	time_since_event = 0.0
	_set_suppression(suppression + amount)

func _set_suppression(value: float) -> void:
	var previous := suppression
	suppression = clampf(value, 0.0, 100.0)
	if not is_equal_approx(previous, suppression):
		suppression_changed.emit(suppression)
	var next := level
	match level:
		Level.NORMAL:
			if suppression >= 30.0:
				next = Level.SUPPRESSED
		Level.SUPPRESSED:
			if suppression >= 68.0:
				next = Level.PINNED
			elif suppression < 16.0:
				next = Level.NORMAL
		Level.PINNED:
			if suppression < 48.0:
				next = Level.SUPPRESSED
	if next != level:
		level = next
		level_changed.emit(level)
