extends StaticBody3D
class_name TacticalStructure3D

enum Kind {
	MACHINE_GUN,
	WATCHTOWER,
}

@export var structure_kind: Kind = Kind.WATCHTOWER
@export var operator_anchor_path: NodePath = ^"OperatorAnchor"
@export var muzzle_path: NodePath = ^"Muzzle"
@export_range(1.0, 40.0, 0.5) var assignment_max_distance := 18.0
@export_range(0.0, 200.0, 1.0) var defense_priority := 50.0
@export_range(1.0, 360.0, 1.0) var firing_arc_degrees := 360.0
@export_range(0.5, 3.0, 0.05) var vision_multiplier := 1.0
@export var assigned_team := -1

var _reserved_actor: WeakRef
var _occupied := false

func _ready() -> void:
	add_to_group("tactical_structure3d")

func reserve(actor: Node3D) -> bool:
	_prune_user()
	if not is_instance_valid(actor) or not is_team_allowed(actor):
		return false
	var current: Node3D = get_user()
	if current != null:
		return current == actor
	_reserved_actor = weakref(actor)
	_occupied = false
	return true

func occupy(actor: Node3D) -> bool:
	if not reserve(actor):
		return false
	_occupied = true
	return true

func release(actor: Node3D = null) -> void:
	var current: Node3D = get_user()
	if actor != null and current != actor:
		return
	_reserved_actor = null
	_occupied = false

func evacuate() -> void:
	var current: Node3D = get_user()
	release()
	if current != null and current.has_method("notify_structure_released"):
		current.notify_structure_released(self)

func get_user() -> Node3D:
	_prune_user()
	return _reserved_actor.get_ref() as Node3D if _reserved_actor != null else null

func is_reserved_by(actor: Node3D) -> bool:
	return get_user() == actor

func is_occupied_by(actor: Node3D) -> bool:
	return _occupied and get_user() == actor

func is_available_to(actor: Node3D) -> bool:
	var current: Node3D = get_user()
	return is_team_allowed(actor) and (current == null or current == actor)

func is_team_allowed(actor: Node3D) -> bool:
	if actor == null or assigned_team < 0:
		return true
	return actor is Soldier3D and (actor as Soldier3D).combat_team == assigned_team

func get_operator_anchor() -> Marker3D:
	return get_node_or_null(operator_anchor_path) as Marker3D

func get_operator_position() -> Vector3:
	var anchor: Marker3D = get_operator_anchor()
	return anchor.global_position if anchor != null else global_position

func get_muzzle_position() -> Vector3:
	var marker := get_node_or_null(muzzle_path) as Marker3D
	return marker.global_position if marker != null else get_operator_position() + Vector3.UP * 1.25

func align_operator(actor: Node3D) -> void:
	if actor == null or not is_occupied_by(actor):
		return
	actor.global_position = get_operator_position()
	if actor is CharacterBody3D:
		(actor as CharacterBody3D).velocity = Vector3.ZERO

func can_engage_target(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return true
	return is_position_in_firing_arc(target.global_position)

func is_position_in_firing_arc(position_value: Vector3) -> bool:
	if firing_arc_degrees >= 359.0:
		return true
	var local_target: Vector3 = to_local(position_value)
	var flat_direction := Vector2(local_target.x, local_target.z)
	if flat_direction.length_squared() <= 0.001:
		return true
	var forward := Vector2(0.0, -1.0)
	return absf(rad_to_deg(forward.angle_to(flat_direction.normalized()))) <= firing_arc_degrees * 0.5

func get_effective_fire_range() -> float:
	var user := get_user() as Soldier3D
	return user.weapon_component.effective_range if user != null and user.weapon_component != null else 0.0

func get_firepower_score() -> float:
	var user := get_user() as Soldier3D
	return user.get_combat_power() if user != null else 0.0

func get_fire_threat_at_position(position_value: Vector3) -> float:
	var fire_range := get_effective_fire_range()
	if fire_range <= 0.0 or not is_position_in_firing_arc(position_value):
		return 0.0
	var offset := position_value - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > fire_range:
		return 0.0
	return clampf(1.0 - distance / fire_range, 0.0, 1.0) * 100.0

func has_fixed_weapon() -> bool:
	return false

func try_fixed_weapon_fire(_actor: Soldier3D, _target: Node3D) -> bool:
	return false

func aim_at(_target_position: Vector3) -> void:
	pass

func get_defense_score(actor: Soldier3D, objective_position: Vector3) -> float:
	if actor == null or not is_available_to(actor):
		return -INF
	var distance := actor.global_position.distance_to(get_operator_position())
	if distance > assignment_max_distance:
		return -INF
	var objective_distance := Vector2(global_position.x - objective_position.x, global_position.z - objective_position.z).length()
	var score := defense_priority - distance * 2.2 - objective_distance * 0.35
	if actor.is_squad_leader:
		score -= 24.0
	match structure_kind:
		Kind.MACHINE_GUN:
			match actor.combat_role:
				Soldier3D.CombatRole.RIFLEMAN:
					score += 16.0
				Soldier3D.CombatRole.SMG:
					score += 8.0
				Soldier3D.CombatRole.MACHINE_GUNNER:
					score -= 10.0
				Soldier3D.CombatRole.MARKSMAN:
					score -= 18.0
		Kind.WATCHTOWER:
			match actor.combat_role:
				Soldier3D.CombatRole.MARKSMAN:
					score += 30.0
				Soldier3D.CombatRole.RIFLEMAN:
					score += 10.0
				Soldier3D.CombatRole.MACHINE_GUNNER:
					score -= 16.0
	if is_occupied_by(actor):
		score += 40.0
	return score

func get_structure_label() -> String:
	return "machine-gun emplacement" if structure_kind == Kind.MACHINE_GUN else "watchtower"

func _exit_tree() -> void:
	evacuate()

func _prune_user() -> void:
	if _reserved_actor == null:
		return
	var actor: Node3D = _reserved_actor.get_ref() as Node3D
	if not is_instance_valid(actor) or (actor.has_method("is_combat_alive") and not bool(actor.is_combat_alive())):
		_reserved_actor = null
		_occupied = false
