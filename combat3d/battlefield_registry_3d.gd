extends Node
class_name BattlefieldRegistry3D

var _combatants: Array[Node3D] = []
var _soldiers: Array[Soldier3D] = []
var _squads: Array[SquadCoordinator3D] = []
var _covers: Array[TacticalCover3D] = []

func _ready() -> void:
	add_to_group("battlefield_registry3d")
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	for group_name in [&"combatant3d", &"soldier3d", &"squad3d", &"cover3d"]:
		for node in get_tree().get_nodes_in_group(group_name):
			register_node(node)

func _exit_tree() -> void:
	if get_tree() == null:
		return
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if get_tree().node_removed.is_connected(_on_node_removed):
		get_tree().node_removed.disconnect(_on_node_removed)

func register_node(node: Node) -> void:
	if node is Soldier3D and not _soldiers.has(node):
		_soldiers.append(node)
	if node is SquadCoordinator3D and not _squads.has(node):
		_squads.append(node)
	if node is TacticalCover3D and not _covers.has(node):
		_covers.append(node)
	if node is Node3D and node.is_in_group("combatant3d") and not _combatants.has(node):
		_combatants.append(node)

func get_combatants() -> Array[Node3D]:
	_prune()
	return _combatants.duplicate()

func get_soldiers() -> Array[Soldier3D]:
	_prune()
	return _soldiers.duplicate()

func get_squads() -> Array[SquadCoordinator3D]:
	_prune()
	return _squads.duplicate()

func get_covers() -> Array[TacticalCover3D]:
	_prune()
	return _covers.duplicate()

static func find(tree: SceneTree) -> BattlefieldRegistry3D:
	return tree.get_first_node_in_group("battlefield_registry3d") as BattlefieldRegistry3D

func _on_node_added(node: Node) -> void:
	register_node.call_deferred(node)

func _on_node_removed(node: Node) -> void:
	if node is Node3D:
		_combatants.erase(node)
	if node is Soldier3D:
		_soldiers.erase(node)
	if node is SquadCoordinator3D:
		_squads.erase(node)
	if node is TacticalCover3D:
		_covers.erase(node)

func _prune() -> void:
	for index in range(_combatants.size() - 1, -1, -1):
		if not is_instance_valid(_combatants[index]) or not _combatants[index].is_in_group("combatant3d"):
			_combatants.remove_at(index)
	for index in range(_soldiers.size() - 1, -1, -1):
		if not is_instance_valid(_soldiers[index]) or not _soldiers[index].is_in_group("soldier3d"):
			_soldiers.remove_at(index)
	for index in range(_squads.size() - 1, -1, -1):
		if not is_instance_valid(_squads[index]) or not _squads[index].is_in_group("squad3d"):
			_squads.remove_at(index)
	for index in range(_covers.size() - 1, -1, -1):
		if not is_instance_valid(_covers[index]) or not _covers[index].is_in_group("cover3d"):
			_covers.remove_at(index)
