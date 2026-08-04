extends RefCounted
class_name SquadDecisionTrace3D

const SCHEMA_VERSION := 1

var max_events := 512
var events: Array[Dictionary] = []
var trace_path := ""
var _sequence := 0
var _file: FileAccess
var _started_msec := 0

func configure(squad_id: StringName, write_jsonl := true, new_max_events := 512) -> void:
	max_events = maxi(32, new_max_events)
	events.clear()
	_sequence = 0
	_started_msec = Time.get_ticks_msec()
	trace_path = ""
	_file = null
	if write_jsonl:
		var directory := ProjectSettings.globalize_path("user://squad_ai_traces")
		DirAccess.make_dir_recursive_absolute(directory)
		var timestamp_msec := int(Time.get_unix_time_from_system() * 1000.0)
		var filename := "%s_%d.jsonl" % [_safe_filename(String(squad_id)), timestamp_msec]
		trace_path = directory.path_join(filename)
		_file = FileAccess.open(trace_path, FileAccess.WRITE)
	record("header", {
		"schema_version": SCHEMA_VERSION,
		"squad_id": String(squad_id),
		"scene": "",
		"project_version": ProjectSettings.get_setting("application/config/version", "development"),
		"started_unix": Time.get_unix_time_from_system(),
	})

func record(event_type: String, payload := {}) -> Dictionary:
	_sequence += 1
	var event := {
		"sequence": _sequence,
		"event": event_type,
		"elapsed_msec": Time.get_ticks_msec() - _started_msec,
		"physics_frame": Engine.get_physics_frames(),
		"payload": _sanitize(payload),
	}
	events.append(event)
	while events.size() > max_events:
		events.pop_front()
	if _file != null:
		_file.store_line(JSON.stringify(event))
		_file.flush()
	return event

func get_timeline(limit := 24) -> Array[Dictionary]:
	var count := mini(maxi(0, limit), events.size())
	var result: Array[Dictionary] = []
	for index in range(events.size() - count, events.size()):
		result.append(events[index].duplicate(true))
	return result

func clear() -> void:
	events.clear()
	record("trace_cleared")

func close() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null

func _sanitize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var result := {}
			for key in (value as Dictionary).keys():
				result[String(key)] = _sanitize((value as Dictionary)[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item in value as Array:
				result.append(_sanitize(item))
			return result
		TYPE_PACKED_STRING_ARRAY:
			return Array(value as PackedStringArray)
		TYPE_PACKED_VECTOR3_ARRAY:
			var result: Array = []
			for item in value as PackedVector3Array:
				result.append(_sanitize(item))
			return result
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_RECT2:
			return {"position": _sanitize(value.position), "size": _sanitize(value.size)}
		TYPE_RECT2I:
			return {"position": _sanitize(value.position), "size": _sanitize(value.size)}
		TYPE_STRING_NAME:
			return String(value)
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Node:
				return {"node": String((value as Node).name), "class": value.get_class()}
			return str(value)
	return value

func _safe_filename(value: String) -> String:
	var result := value.to_lower()
	for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "squad"
