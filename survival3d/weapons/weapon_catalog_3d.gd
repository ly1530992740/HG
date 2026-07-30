extends RefCounted
class_name WeaponCatalog3D

const CATALOG_PATH := "res://survival3d/data/weapon_catalog_3d.json"

static var _catalog: Dictionary = {}

static func get_definition(weapon_id: String) -> Dictionary:
	_ensure_loaded()
	var canonical_id := resolve_id(weapon_id)
	var weapons: Dictionary = _catalog.get("weapons", {})
	if not weapons.has(canonical_id):
		canonical_id = "zhongzheng"
	var definition := _resolve_definition(canonical_id, weapons)
	definition["id"] = canonical_id
	definition["requested_id"] = weapon_id
	return definition

static func _resolve_definition(weapon_id: String, weapons: Dictionary, visited := {}) -> Dictionary:
	if visited.has(weapon_id):
		push_error("Weapon catalog inheritance cycle at %s" % weapon_id)
		return {}
	var next_visited: Dictionary = visited.duplicate()
	next_visited[weapon_id] = true
	var raw: Dictionary = (weapons.get(weapon_id, {}) as Dictionary).duplicate(true)
	var base_id := String(raw.get("base", ""))
	if base_id.is_empty():
		return raw
	var result := _resolve_definition(base_id, weapons, next_visited)
	raw.erase("base")
	result.merge(raw, true)
	return result

static func resolve_id(weapon_id: String) -> String:
	_ensure_loaded()
	var aliases: Dictionary = _catalog.get("aliases", {})
	return String(aliases.get(weapon_id, weapon_id))

static func get_display_name(weapon_id: String) -> String:
	return String(get_definition(weapon_id).get("display_name", weapon_id))

static func get_all_ids() -> PackedStringArray:
	_ensure_loaded()
	var result := PackedStringArray()
	for weapon_id in (_catalog.get("weapons", {}) as Dictionary).keys():
		result.append(String(weapon_id))
	result.sort()
	return result

static func _ensure_loaded() -> void:
	if not _catalog.is_empty():
		return
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("Weapon catalog is missing: %s" % CATALOG_PATH)
		_catalog = {"weapons": {}}
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_catalog = parsed
	else:
		push_error("Weapon catalog is not valid JSON: %s" % CATALOG_PATH)
		_catalog = {"weapons": {}}
