extends Node
class_name SoldierWorkingMemory3D

signal fact_changed(fact_key: StringName)

enum FactType { CONTACT, DANGER, DAMAGE, DISTURBANCE, KNOWLEDGE, TASK, DESIRE }

var actor: Soldier3D
var _clock := 0.0
var _facts: Dictionary = {}

func configure(owner_actor: Soldier3D) -> void:
	actor = owner_actor

func tick(delta: float) -> void:
	_clock += maxf(0.0, delta)
	for key in _facts.keys():
		var fact: Dictionary = _facts[key]
		if float(fact.get("expires_at", INF)) <= _clock or not _fact_target_is_valid(fact):
			_facts.erase(key)
			fact_changed.emit(key)

func remember_threat(
		source: Node3D,
		position: Vector3,
		confidence: float,
		ttl: float,
		direct_observation: bool,
		immediate: bool,
		stimulus: StringName = &"threat"
) -> void:
	var source_id := int(source.get_instance_id()) if is_instance_valid(source) else 0
	var key := StringName("threat:%d:%s" % [source_id, stimulus])
	_remember(key, FactType.DANGER if immediate else FactType.CONTACT, position, source, confidence, ttl, {
		"direct": direct_observation,
		"immediate": immediate,
		"stimulus": stimulus,
	})

func remember_task(task_id: StringName, position: Vector3, ttl: float, metadata := {}) -> void:
	_remember(StringName("task:%s" % task_id), FactType.TASK, position, null, 1.0, ttl, metadata)

func remember_desire(desire_id: StringName, position: Vector3, confidence: float, ttl: float) -> void:
	_remember(StringName("desire:%s" % desire_id), FactType.DESIRE, position, null, confidence, ttl, {})

func get_best_threat() -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for fact_value in _facts.values():
		var fact: Dictionary = fact_value
		if int(fact.get("type", -1)) not in [FactType.CONTACT, FactType.DANGER, FactType.DAMAGE, FactType.DISTURBANCE]:
			continue
		var remaining := maxf(0.0, float(fact.get("expires_at", _clock)) - _clock)
		var score := float(fact.get("confidence", 0.0)) * 100.0 + minf(20.0, remaining)
		if bool(fact.get("direct", false)):
			score += 25.0
		if bool(fact.get("immediate", false)):
			score += 35.0
		if score > best_score:
			best_score = score
			best = fact
	return best.duplicate(true)

func has_recent_type(type: FactType, minimum_confidence := 0.0) -> bool:
	for fact_value in _facts.values():
		var fact: Dictionary = fact_value
		if int(fact.get("type", -1)) == type and float(fact.get("confidence", 0.0)) >= minimum_confidence:
			return true
	return false

func get_fact_count() -> int:
	return _facts.size()

func get_spatial_threat_facts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact_value in _facts.values():
		var fact: Dictionary = fact_value
		if int(fact.get("type", -1)) not in [FactType.CONTACT, FactType.DANGER, FactType.DAMAGE, FactType.DISTURBANCE]:
			continue
		result.append({
			"position": fact.get("position", Vector3.ZERO),
			"confidence": fact.get("confidence", 0.0),
			"direct": fact.get("direct", false),
			"immediate": fact.get("immediate", false),
			"stimulus": fact.get("stimulus", &"threat"),
		})
	return result

func get_debug_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact_value in _facts.values():
		var fact: Dictionary = fact_value
		var copy := fact.duplicate(true)
		copy["remaining"] = maxf(0.0, float(copy.get("expires_at", _clock)) - _clock)
		result.append(copy)
	return result

func _remember(
		key: StringName,
		type: FactType,
		position: Vector3,
		source: Node3D,
		confidence: float,
		ttl: float,
		metadata: Dictionary
) -> void:
	var previous: Dictionary = _facts.get(key, {})
	var fact := metadata.duplicate(true)
	fact["key"] = key
	fact["type"] = type
	fact["position"] = position
	fact["source"] = weakref(source) if is_instance_valid(source) else null
	fact["confidence"] = maxf(float(previous.get("confidence", 0.0)), clampf(confidence, 0.0, 1.0))
	fact["created_at"] = float(previous.get("created_at", _clock))
	fact["updated_at"] = _clock
	fact["expires_at"] = _clock + maxf(0.05, ttl)
	_facts[key] = fact
	fact_changed.emit(key)

func _fact_target_is_valid(fact: Dictionary) -> bool:
	var reference := fact.get("source") as WeakRef
	if reference == null:
		return true
	var source := reference.get_ref() as Node
	return source == null or not source.has_method("is_combat_alive") or bool(source.is_combat_alive())
