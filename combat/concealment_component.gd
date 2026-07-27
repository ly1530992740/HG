extends Node
class_name ConcealmentComponent

@export var firing_reveal_duration := 1.5

var concealment_sources: Array[Node] = []
var reveal_timer := 0.0

func process(delta: float) -> void:
	reveal_timer = maxf(0.0, reveal_timer - delta)
	concealment_sources = concealment_sources.filter(is_instance_valid)

func register_source(source: Node) -> void:
	if is_instance_valid(source) and not concealment_sources.has(source):
		concealment_sources.append(source)

func unregister_source(source: Node) -> void:
	concealment_sources.erase(source)

func reveal(duration := -1.0) -> void:
	var resolved_duration := firing_reveal_duration if duration < 0.0 else duration
	reveal_timer = maxf(reveal_timer, resolved_duration)

func is_concealed() -> bool:
	return not concealment_sources.is_empty() and reveal_timer <= 0.0

func is_temporarily_revealed() -> bool:
	return reveal_timer > 0.0
