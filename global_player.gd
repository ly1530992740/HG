extends Node

var pawns: Array = []
var active_player: Node = null
var active_player_position: Vector2
var pawn_all_dead: bool = true

var castle_position
var camera_shake_func: Callable = Callable()

# --------------------------------------------------
# REGISTER
# --------------------------------------------------
func register_pawn(pawn: Node) -> void:
	if pawn == null or pawn in pawns:
		return

	pawns.append(pawn)

	# IMPORTANT: deactivate by default
	if pawn.has_method("deactivate"):
		pawn.deactivate()

	# connect death signal safely
	if pawn.has_signal("died"):
		pawn.died.connect(_on_pawn_died.bind(pawn))

	_update_pawn_state()

	# first pawn becomes active
	if active_player == null:
		set_active_pawn(pawn)


# --------------------------------------------------
# SIGNAL CALLBACK
# --------------------------------------------------
func _on_pawn_died(pawn: Node) -> void:
	unregister_pawn(pawn)


func unregister_pawn(pawn: Node) -> void:
	if pawn not in pawns:
		return

	var was_active := pawn == active_player

	pawns.erase(pawn)

	_update_pawn_state()

	if was_active:
		activate_next_pawn()


# --------------------------------------------------
# ACTIVE PAWN
# --------------------------------------------------
func set_active_pawn(pawn: Node) -> void:
	if pawn == null:
		return

	# deactivate ALL pawns first (very important)
	for p in pawns:
		if is_instance_valid(p):
			if p.has_method("deactivate"):
				p.deactivate()
		else:
			pass

	active_player = pawn

	if active_player.has_method("activate_from_global"):
		active_player.activate_from_global()


func activate_next_pawn() -> void:
	# remove invalid references
	pawns = pawns.filter(func(p): return is_instance_valid(p))

	if pawns.is_empty():
		active_player = null
		return

	set_active_pawn(pawns[0])


# --------------------------------------------------
# STATE
# --------------------------------------------------
func _update_pawn_state() -> void:
	pawn_all_dead = pawns.is_empty()


func get_pawn_count() -> int:
	return pawns.size()
