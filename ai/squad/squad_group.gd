extends Node
class_name SquadGroup

signal group_member_added(actor: Node2D)
signal group_member_removed(actor: Node2D)
signal analysis_refreshed(snapshot: Dictionary, routes: Array[Dictionary])

@export_group("小队身份")
@export var squad_id: StringName = &"default"
@export var combat_team: StringName = &"hostile"
@export var squad_display_name := ""
@export var can_target_players := true
@export var team_color := Color(0.72, 0.16, 0.16, 1.0)

@export_group("场景成员")
@export var member_root_path: NodePath
@export var member_actor_paths: Array[NodePath] = []
@export var propagate_group_identity := false

@export_group("编辑器添加士兵")
@export var editor_spawn_center := Vector2.ZERO
@export var editor_spawn_area := Vector2(500.0, 400.0)

@export_group("分析模块")
@export var battlefield_analyzer_path := NodePath("BattlefieldAnalyzer")
@export var route_analyzer_path := NodePath("RouteAnalyzer")

var battlefield_analyzer: SquadBattlefieldAnalyzer = null
var route_analyzer: SquadRouteAnalyzer = null
var last_analysis_snapshot: Dictionary = {}
var last_route_candidates: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("squad_group")
	_resolve_analysis_modules()
	call_deferred("_configure_roster")

func _resolve_analysis_modules() -> void:
	battlefield_analyzer = get_node_or_null(battlefield_analyzer_path) as SquadBattlefieldAnalyzer
	route_analyzer = get_node_or_null(route_analyzer_path) as SquadRouteAnalyzer
	if battlefield_analyzer != null:
		battlefield_analyzer.bind_group(self)
	if route_analyzer != null:
		route_analyzer.bind_group(self)

func refresh_group_analysis(target: Node2D = null) -> Dictionary:
	if battlefield_analyzer == null or route_analyzer == null:
		_resolve_analysis_modules()
	last_analysis_snapshot = battlefield_analyzer.analyze(target) if battlefield_analyzer != null else {}
	last_route_candidates.clear()
	if route_analyzer != null and is_instance_valid(target):
		last_route_candidates.assign(route_analyzer.analyze_routes(target))
	analysis_refreshed.emit(last_analysis_snapshot, last_route_candidates)
	return {
		"snapshot": last_analysis_snapshot,
		"routes": last_route_candidates,
	}

func get_route_candidate(route_id: StringName) -> Dictionary:
	for route in last_route_candidates:
		if StringName(route.get("id", &"")) == route_id:
			return route
	return {}

func get_best_route_candidate() -> Dictionary:
	for route in last_route_candidates:
		if bool(route.get("available", false)):
			return route
	return {}

func get_configured_member_actors() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for member_path in member_actor_paths:
		var actor := get_node_or_null(member_path) as Node2D
		if actor != null and not result.has(actor):
			result.append(actor)
	var root := get_node_or_null(member_root_path)
	if root != null:
		_collect_member_actors(root, result)
	return result

func get_member_actor(member_id: StringName) -> Node2D:
	for actor in get_configured_member_actors():
		if actor.name == String(member_id):
			return actor
	return null

func get_member_count() -> int:
	return get_configured_member_actors().size()

func spawn_member(spawn: SquadMemberSpawn, scene: PackedScene) -> Node2D:
	if spawn == null or spawn.member_id == &"":
		return null
	if scene == null:
		push_error("SquadGroup %s cannot dynamically spawn a member without a scene." % name)
		return null
	var root := get_node_or_null(member_root_path)
	if root == null:
		push_error("SquadGroup %s cannot generate members: member_root_path is invalid." % name)
		return null
	var existing := root.get_node_or_null(String(spawn.member_id)) as Node2D
	if existing != null:
		return existing
	var actor := scene.instantiate() as Node2D
	if actor == null:
		push_error("SquadGroup %s dynamic member scene must instantiate a Node2D." % name)
		return null
	spawn.apply_to(actor)
	_configure_member_identity(actor)
	root.add_child(actor)
	call_deferred("add_member_actor", actor)
	return actor

func add_member_actor(actor: Node2D) -> void:
	if actor == null:
		return
	_configure_member_identity(actor)
	var member := actor.get("squad_member") as SquadMember
	if member != null and has_method("register_member"):
		call("register_member", member)
	group_member_added.emit(actor)

func remove_member_actor(actor: Node2D) -> void:
	if actor == null:
		return
	var member := actor.get("squad_member") as SquadMember
	if member != null and has_method("unregister_member"):
		call("unregister_member", member)
	group_member_removed.emit(actor)

func _configure_roster() -> void:
	for actor in get_configured_member_actors():
		add_member_actor(actor)

func _collect_member_actors(root: Node, result: Array[Node2D]) -> void:
	for child in root.get_children():
		if child is GoblinBase and not result.has(child):
			result.append(child)
		_collect_member_actors(child, result)

func _configure_member_identity(actor: Node2D) -> void:
	actor.set("squad_id", squad_id)
	var member := actor.get("squad_member") as SquadMember
	if member != null:
		member.squad_id = squad_id
	if not propagate_group_identity:
		return
	actor.set("combat_team", combat_team)
	actor.set("can_target_players", can_target_players)
	actor.set("team_display_name", squad_display_name)
	actor.set("team_color", team_color)
