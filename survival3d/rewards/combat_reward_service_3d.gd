extends Node
class_name CombatRewardService3D

const AMMO_PICKUP := preload("res://survival3d/pickups/ammo_pickup_3d.tscn")

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for actor in get_tree().get_nodes_in_group("soldier3d"):
		_bind_actor(actor)

func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)

func _on_node_added(node: Node) -> void:
	_bind_actor(node)

func _bind_actor(actor: Node) -> void:
	if not is_instance_valid(actor) or not actor.has_signal("death_reward_requested"):
		return
	if not actor.death_reward_requested.is_connected(_on_death_reward_requested):
		actor.death_reward_requested.connect(_on_death_reward_requested)

func _on_death_reward_requested(actor: Node3D, instigator: Node, score: int, ammo: int) -> void:
	if score > 0 and _is_player_team(instigator):
		SurvivalEconomy.add_points(score, actor)
	if ammo > 0:
		_spawn_ammo(actor.global_position, ammo)

func _is_player_team(actor: Node) -> bool:
	return actor != null and actor.has_method("get_combat_team") \
		and int(actor.get_combat_team()) == int(Soldier3D.Team.PLAYER)

func _spawn_ammo(position: Vector3, amount: int) -> void:
	var battlefield := get_parent() as Node3D
	if battlefield == null:
		return
	var pickup := AMMO_PICKUP.instantiate() as AmmoPickup3D
	if pickup == null:
		return
	pickup.ammo_amount = amount
	battlefield.add_child(pickup)
	pickup.global_position = position + Vector3.UP * 0.15
