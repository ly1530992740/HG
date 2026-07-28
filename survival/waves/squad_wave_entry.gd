extends Resource
class_name SquadWaveEntry

@export_category("小队生成项")
@export var squad_scene: PackedScene
@export_range(1, 50, 1) var count := 1
@export_range(-1.0, 5000.0, 10.0) var spawn_radius_override := -1.0
