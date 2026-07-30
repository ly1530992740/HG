@tool
extends Node3D
class_name TacticalZone3D

@export_category("Zone Identity")
@export var zone_id: StringName = &"zone"
@export var display_name := "Tactical Zone"
@export var size := Vector2(8.0, 12.0):
	set(value):
		size = Vector2(maxf(0.5, value.x), maxf(0.5, value.y))
		_schedule_rebuild()
@export var recon_enabled := true
@export var recon_waypoints: Array[Vector3] = []
@export_node_path("Node3D") var observation_point_path: NodePath

@export_category("Known Terrain")
@export_range(0.0, 1.0, 0.05) var concealment := 0.0
@export_range(0.0, 1.0, 0.05) var cover_value := 0.0
@export_range(0.0, 1.0, 0.05) var route_exposure := 0.5
@export_range(0.0, 2.0, 0.1) var information_value := 1.0

@export_category("Debug Display")
@export var show_zone := true:
	set(value):
		show_zone = value
		_schedule_rebuild()
@export var zone_color := Color(0.2, 0.65, 0.85, 0.16):
	set(value):
		zone_color = value
		_schedule_rebuild()

var _rebuild_queued := false

func _ready() -> void:
	add_to_group("tactical_zone3d")
	_rebuild()

func contains_world_position(value: Vector3) -> bool:
	var local := to_local(value)
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.y * 0.5

func get_observation_point(from_position: Vector3) -> Vector3:
	var marker := get_node_or_null(observation_point_path) as Node3D
	if marker != null:
		return marker.global_position
	var local_from := to_local(from_position)
	var local_point := Vector3(
		clampf(local_from.x, -size.x * 0.32, size.x * 0.32),
		0.0,
		clampf(local_from.z, -size.y * 0.32, size.y * 0.32)
	)
	return to_global(local_point)

func get_recon_route(from_position: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for local_point in recon_waypoints:
		result.append(to_global(local_point))
	var observation := get_observation_point(from_position)
	if result.is_empty() or result[-1].distance_to(observation) > 0.2:
		result.append(observation)
	return result

func get_utility(known_enemy_count: int, observation: Dictionary) -> float:
	var observed_bonus := 1.4 if not observation.is_empty() else 0.0
	var unseen_enemy_bonus := 2.0 if int(observation.get("visible_contact_ids", []).size()) == 0 else 0.0
	var threat_evidence_penalty := float(observation.get("threat_evidence_count", 0)) * 2.5
	return concealment * 4.0 + cover_value * 2.2 + information_value + observed_bonus + unseen_enemy_bonus \
		- route_exposure * 3.0 - float(known_enemy_count) * 3.5 - threat_evidence_penalty

func _schedule_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")

func _rebuild() -> void:
	_rebuild_queued = false
	var mesh_instance := get_node_or_null("DebugZone") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "DebugZone"
		add_child(mesh_instance)
	mesh_instance.visible = show_zone
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.025, size.y)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = zone_color
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.025

static func find_at(tree: SceneTree, position: Vector3) -> TacticalZone3D:
	for node in tree.get_nodes_in_group("tactical_zone3d"):
		if node is TacticalZone3D and (node as TacticalZone3D).contains_world_position(position):
			return node as TacticalZone3D
	return null
