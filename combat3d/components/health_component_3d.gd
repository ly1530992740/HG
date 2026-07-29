extends Node
class_name HealthComponent3D

signal changed(current: int, maximum: int)
signal depleted

var maximum := 100
var current := 100

func configure(maximum_health: int) -> void:
	maximum = maxi(1, maximum_health)
	current = maximum
	changed.emit(current, maximum)

func apply_damage(amount: int) -> bool:
	if amount <= 0 or current <= 0:
		return false
	current = maxi(0, current - amount)
	changed.emit(current, maximum)
	if current == 0:
		depleted.emit()
	return true

func is_alive() -> bool:
	return current > 0
