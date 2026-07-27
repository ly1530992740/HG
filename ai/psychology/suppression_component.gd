extends Node
class_name SuppressionComponent

signal suppression_changed(value: float)
signal level_changed(level: Level)

enum Level {
	CALM,
	ALERT,
	PINNED,
	OVERWHELMED,
}

@export var decay_delay := 0.9
@export var exposed_decay_per_second := 5.0
@export var covered_decay_per_second := 10.0

var actor: Node2D = null
var suppression := 0.0
var level: Level = Level.CALM
var time_since_event := 999.0

func setup(new_actor: Node2D) -> void:
	actor = new_actor

func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	time_since_event += delta
	if time_since_event <= decay_delay or suppression <= 0.0:
		return
	var covered := actor.has_method("get_active_cover") and actor.get_active_cover() != null
	var decay_rate := covered_decay_per_second if covered else exposed_decay_per_second
	_set_suppression(suppression - decay_rate * delta)

func report_near_miss() -> void:
	_add_suppression(22.0)

func report_cover_impact() -> void:
	_add_suppression(14.0)

func report_damage(amount: int) -> void:
	_add_suppression(30.0 + minf(24.0, float(amount) * 4.0))

func report_ally_death() -> void:
	_add_suppression(12.0)

func is_under_fire() -> bool:
	return suppression >= 18.0 or time_since_event <= 1.5

func should_hunker_down() -> bool:
	return level == Level.PINNED or level == Level.OVERWHELMED

func get_spread_multiplier() -> float:
	return 1.0 + suppression / 100.0 * 1.6

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
	_update_level()

func _update_level() -> void:
	var new_level := level
	match level:
		Level.CALM:
			if suppression >= 18.0:
				new_level = Level.ALERT
		Level.ALERT:
			if suppression >= 55.0:
				new_level = Level.PINNED
			elif suppression < 8.0:
				new_level = Level.CALM
		Level.PINNED:
			if suppression >= 85.0:
				new_level = Level.OVERWHELMED
			elif suppression < 38.0:
				new_level = Level.ALERT
		Level.OVERWHELMED:
			if suppression < 70.0:
				new_level = Level.PINNED
	if new_level != level:
		level = new_level
		level_changed.emit(level)
