extends Node

func _ready() -> void:
	var battle := get_parent()
	var alpha := battle.get_node("EnemySquadCoordinator") as LlmSquadCoordinator
	var bravo := battle.get_node("EnemySquadCoordinatorBravo") as SquadCoordinator
	alpha.allow_silent_ambush = false
	bravo.allow_silent_ambush = false
	alpha.search_direction_override = Vector2.RIGHT
	bravo.search_direction_override = Vector2.LEFT
	alpha.get_blackboard().set_fact(&"scenario_name", "动态战场路线分析包抄")
	bravo.get_blackboard().set_fact(&"scenario_name", "动态战场路线分析防守")
	_configure_facing(alpha, bravo)
	call_deferred("_restart_contact_search")

func _configure_facing(alpha: SquadGroup, bravo: SquadGroup) -> void:
	for actor in alpha.get_configured_member_actors():
		var soldier := actor as GoblinBase
		soldier.global_position.x = maxf(soldier.global_position.x, -820.0)
		soldier.initial_facing_direction = Vector2.RIGHT
		soldier.last_move_dir = Vector2.RIGHT
	for actor in bravo.get_configured_member_actors():
		var soldier := actor as GoblinBase
		soldier.global_position.x = minf(soldier.global_position.x, 820.0)
		soldier.initial_facing_direction = Vector2.LEFT
		soldier.last_move_dir = Vector2.LEFT

func _restart_contact_search() -> void:
	var battle := get_parent()
	for coordinator_name in ["EnemySquadCoordinator", "EnemySquadCoordinatorBravo"]:
		var coordinator := battle.get_node(coordinator_name) as SquadCoordinator
		coordinator._issue_search_sweep()
