extends MultiMeshInstance3D
class_name TacticalSandboxHeatmap3D

enum Layer {
	COMPOSITE_RISK,
	ENEMY_THREAT,
	SUPPRESSION,
	COVER,
	CONCEALMENT,
	INFORMATION,
	TACTICAL_TOPOLOGY,
}

const BENEFIT_LAYERS := [Layer.COVER, Layer.CONCEALMENT, Layer.INFORMATION]

var opacity := 0.58
var render_version := 0

func show_squad_map(influence: SquadInfluenceMap3D, layer: Layer) -> void:
	if influence == null:
		clear_map()
		return
	var samples: Array[Dictionary] = []
	for key_value in influence.cells.keys():
		var key := key_value as Vector2i
		var position := influence.origin + Vector3(float(key.x) * influence.cell_size, 0.0, float(key.y) * influence.cell_size)
		var cell := influence.cells.get(key, {}) as Dictionary
		samples.append({"position": position, "value": _squad_value(cell, layer)})
	_render(samples, influence.cell_size, layer in BENEFIT_LAYERS)

func show_soldier_map(soldier: Soldier3D, radius := 36.0, cell_size := 3.0) -> void:
	if soldier == null or soldier.local_threat_field == null:
		clear_map()
		return
	var samples: Array[Dictionary] = []
	var extent := ceili(radius / cell_size)
	var origin := Vector3(
		roundf(soldier.global_position.x / cell_size) * cell_size,
		0.0,
		roundf(soldier.global_position.z / cell_size) * cell_size
	)
	for x in range(-extent, extent + 1):
		for z in range(-extent, extent + 1):
			var position := origin + Vector3(float(x) * cell_size, 0.0, float(z) * cell_size)
			samples.append({"position": position, "value": soldier.local_threat_field.score_position(position)})
	_render(samples, cell_size, false)

func show_topology(topology: SquadTacticalTopology3D) -> void:
	if topology == null or topology.version <= 0:
		clear_map()
		return
	var samples: Array[Dictionary] = []
	for key_value in topology.cell_kinds.keys():
		var key := key_value as Vector2i
		samples.append({
			"position": topology.world_position_for(key),
			"kind": int(topology.cell_kinds.get(key, SquadTacticalTopology3D.CellKind.BLOCKED)),
		})
	_render_topology(samples, topology.cell_size)

func clear_map() -> void:
	multimesh = null
	render_version += 1

func get_visible_cell_count() -> int:
	return multimesh.instance_count if multimesh != null else 0

func get_render_version() -> int:
	return render_version

func _render(samples: Array[Dictionary], cell_size: float, beneficial: bool) -> void:
	if samples.is_empty():
		clear_map()
		return
	var tile := BoxMesh.new()
	tile.size = Vector3(cell_size * 0.92, 0.025, cell_size * 0.92)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = false
	material.render_priority = -10
	tile.material = material
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.use_colors = true
	data.mesh = tile
	data.instance_count = samples.size()
	for index in samples.size():
		var sample := samples[index]
		var position := sample.get("position", Vector3.ZERO) as Vector3
		position.y = 0.045
		data.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
		data.set_instance_color(index, _heat_color(float(sample.get("value", 0.0)), beneficial))
	multimesh = data
	render_version += 1

func _squad_value(cell: Dictionary, layer: Layer) -> float:
	match layer:
		Layer.ENEMY_THREAT:
			return float(cell.get(SquadInfluenceMap3D.LAYER_ENEMY_THREAT, 0.0))
		Layer.SUPPRESSION:
			return float(cell.get(SquadInfluenceMap3D.LAYER_SUPPRESSION, 0.0))
		Layer.COVER:
			return float(cell.get(SquadInfluenceMap3D.LAYER_COVER, 0.0))
		Layer.CONCEALMENT:
			return float(cell.get(SquadInfluenceMap3D.LAYER_CONCEALMENT, 0.0))
		Layer.INFORMATION:
			return float(cell.get(SquadInfluenceMap3D.LAYER_INFORMATION, 0.0))
		_:
			return maxf(0.0,
				float(cell.get(SquadInfluenceMap3D.LAYER_ENEMY_THREAT, 0.0))
				+ float(cell.get(SquadInfluenceMap3D.LAYER_SUPPRESSION, 0.0)) * 1.25
				+ float(cell.get(SquadInfluenceMap3D.LAYER_ROUTE_EXPOSURE, 0.0)) * 0.55
				- float(cell.get(SquadInfluenceMap3D.LAYER_COVER, 0.0)) * 0.65
				- float(cell.get(SquadInfluenceMap3D.LAYER_CONCEALMENT, 0.0)) * 0.35)

func _heat_color(value: float, beneficial: bool) -> Color:
	var amount := clampf(value / 100.0, 0.0, 1.0)
	if beneficial:
		return Color(0.08, lerpf(0.28, 0.88, amount), lerpf(0.38, 0.92, amount), lerpf(0.08, opacity, amount))
	var low := Color(0.12, 0.72, 0.26, opacity * 0.48)
	var middle := Color(0.96, 0.78, 0.12, opacity * 0.8)
	var high := Color(0.94, 0.12, 0.08, opacity)
	return low.lerp(middle, amount * 2.0) if amount < 0.5 else middle.lerp(high, (amount - 0.5) * 2.0)

func _render_topology(samples: Array[Dictionary], topology_cell_size: float) -> void:
	if samples.is_empty():
		clear_map()
		return
	var tile := BoxMesh.new()
	tile.size = Vector3(topology_cell_size * 0.9, 0.035, topology_cell_size * 0.9)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	tile.material = material
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.use_colors = true
	data.mesh = tile
	data.instance_count = samples.size()
	for index in samples.size():
		var sample := samples[index]
		var position := sample.get("position", Vector3.ZERO) as Vector3
		position.y = 0.06
		data.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
		var color := Color(0.16, 0.48, 0.92, 0.18)
		match int(sample.get("kind", SquadTacticalTopology3D.CellKind.BLOCKED)):
			SquadTacticalTopology3D.CellKind.BLOCKED:
				color = Color(0.18, 0.2, 0.22, 0.5)
			SquadTacticalTopology3D.CellKind.CHOKE:
				color = Color(0.96, 0.2, 0.1, 0.78)
			SquadTacticalTopology3D.CellKind.DEAD_END:
				color = Color(0.65, 0.22, 0.84, 0.58)
		data.set_instance_color(index, color)
	multimesh = data
	render_version += 1
