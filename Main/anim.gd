extends AnimatedSprite2D

var current_index
func _ready():
	current_index=Global.choosed_colour

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	play(current_index)
