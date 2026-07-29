extends RefCounted
class_name ShopCatalogRepository3D

static func load_items(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法打开3D商城配置：%s" % path)
		return result
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("3D商城JSON根节点必须是字典")
		return result
	for value in parsed.get("items", []):
		if value is Dictionary:
			result.append(value)
	return result
