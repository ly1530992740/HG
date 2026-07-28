extends Node

signal points_changed(points: int, delta: int)
signal enemy_defeated(actor: Node, reward: int)
signal purchase_failed(reason: String)

var points := 0

func add_points(amount: int, source: Node = null) -> void:
	if amount <= 0:
		return
	points += amount
	points_changed.emit(points, amount)
	if source != null:
		enemy_defeated.emit(source, amount)

func can_afford(cost: int) -> bool:
	return cost >= 0 and points >= cost

func try_spend(cost: int) -> bool:
	if cost < 0:
		purchase_failed.emit("商品价格无效")
		return false
	if points < cost:
		purchase_failed.emit("积分不足")
		return false
	points -= cost
	points_changed.emit(points, -cost)
	return true

func reset(new_points := 0) -> void:
	var delta := new_points - points
	points = maxi(0, new_points)
	points_changed.emit(points, delta)
