extends Node
class_name LimbDamageComponent3D

@export var gore_enabled := true
@export var arm_sever_threshold := 65
@export var leg_sever_threshold := 72
@export var head_sever_threshold := 90

var actor: Node3D
var visual: VoxelSoldierVisual3D
var accumulated_damage: Dictionary = {}

func configure(owner_actor: Node3D, actor_visual: VoxelSoldierVisual3D) -> void:
	actor = owner_actor
	visual = actor_visual

func report_damage(amount: int, location: String, hit_position: Vector3, instigator: Node, lethal: bool, force_sever := false) -> bool:
	if not gore_enabled or visual == null or location == "body":
		return false
	accumulated_damage[location] = int(accumulated_damage.get(location, 0)) + amount
	var threshold := head_sever_threshold if location == "head" else (arm_sever_threshold if location.ends_with("arm") else leg_sever_threshold)
	if int(accumulated_damage[location]) < threshold and not force_sever and not (lethal and location == "head"):
		return false
	var direction := Vector3.UP
	if instigator is Node3D:
		direction = (hit_position - (instigator as Node3D).global_position).normalized()
	return visual.detach_limb(location, direction)
