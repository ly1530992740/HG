extends Node

@export var auto_pause_after_opening_volley := true
@export_range(0.1, 1.0, 0.05) var pause_delay_seconds := 0.3

var _pause_scheduled := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var battle := get_parent()
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	alpha.allow_silent_ambush = true
	alpha.ambush_ready_ratio_required = 1.0
	alpha.ambush_aim_quality_required = 0.9
	alpha.search_direction_override = Vector2.RIGHT
	bravo.allow_silent_ambush = true
	bravo.hold_search_until_first_contact = true
	bravo.search_direction_override = Vector2.ZERO
	for child in battle.get_children():
		if child is GoblinBase:
			child.initial_facing_direction = Vector2.RIGHT
			child.last_move_dir = Vector2.RIGHT
	if not alpha.ambush_opened.is_connected(_on_alpha_ambush_opened):
		alpha.ambush_opened.connect(_on_alpha_ambush_opened)
	call_deferred("_restart_search_orders")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		_set_demo_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func _on_alpha_ambush_opened(_target: Node2D, _reason: StringName) -> void:
	if not auto_pause_after_opening_volley or _pause_scheduled:
		return
	_pause_scheduled = true
	await get_tree().create_timer(pause_delay_seconds, true, false, true).timeout
	_set_demo_paused(true)

func _set_demo_paused(paused: bool) -> void:
	var battle := get_parent()
	for node_name in ["EnemySquadCoordinator", "EnemySquadCoordinatorBravo"]:
		var commander := battle.get_node_or_null(node_name) as LlmSquadCoordinator
		if commander == null:
			continue
		commander.get_blackboard().set_fact(&"demo_paused", paused)
		commander._update_decision_label()
	get_tree().paused = paused

func _restart_search_orders() -> void:
	var battle := get_parent()
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as LlmSquadCoordinator
	if not alpha.members.is_empty():
		alpha._issue_search_sweep()
	if not bravo.members.is_empty():
		bravo._issue_search_sweep()
