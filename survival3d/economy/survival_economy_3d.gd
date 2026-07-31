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
		purchase_failed.emit("Invalid item cost")
		return false
	if points < cost:
		purchase_failed.emit("Not enough points")
		return false
	points -= cost
	points_changed.emit(points, -cost)
	return true

func reset(new_points := 0) -> void:
	var previous := points
	points = maxi(0, new_points)
	points_changed.emit(points, points - previous)
