extends Node
class_name SurvivalPurchaseService3D

const WEAPON_PICKUP := preload("res://survival3d/pickups/weapon_pickup_3d.tscn")

var _purchase_serial := 0

func purchase_weapon(item: Dictionary, player: Node3D, world_parent: Node) -> Dictionary:
	if player == null:
		return {"success": false, "message": "找不到玩家"}
	if world_parent == null:
		return {"success": false, "message": "找不到武器投放场景"}
	if not SurvivalEconomy.try_spend(int(item.get("cost", 0))):
		return {"success": false, "message": "积分不足"}
	var pickup := WEAPON_PICKUP.instantiate() as WeaponPickup3D
	pickup.weapon_id = String(item.get("weapon_id", "rifle"))
	pickup.display_name = String(item.get("name", "武器"))
	pickup.ammo_amount = int(item.get("ammo_amount", 0))
	world_parent.add_child(pickup)
	_purchase_serial += 1
	var angle := float(_purchase_serial % 8) * TAU / 8.0
	pickup.global_position = player.global_position + Vector3(cos(angle), 0.15, sin(angle)) * 1.8
	return {"success": true, "message": "%s 已投放到附近地面，关闭商城后靠近拾取" % pickup.display_name, "category": "weapon"}

func purchase_ally(item: Dictionary, player: Node3D, world_parent: Node) -> Dictionary:
	var scene := load(String(item.get("scene", ""))) as PackedScene
	if scene == null:
		return {"success": false, "message": "队友预制体无法加载"}
	if not SurvivalEconomy.try_spend(int(item.get("cost", 0))):
		return {"success": false, "message": "积分不足"}
	var squad := scene.instantiate() as SquadCoordinator3D
	if squad == null:
		SurvivalEconomy.add_points(int(item.get("cost", 0)))
		return {"success": false, "message": "队友预制体根节点不是 SquadCoordinator3D"}
	world_parent.add_child(squad)
	squad.global_position = player.global_position + Vector3.RIGHT * 3.0 if player != null else Vector3.ZERO
	squad.squad_id = StringName("player_allies_%d" % squad.get_instance_id())
	return {"success": true, "message": "守备小队已抵达，按 G 指挥集结", "category": "ally"}
