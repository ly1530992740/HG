extends AnimatedSprite2D

@onready var skull: AnimatedSprite2D = $"."

func _ready() -> void:
	z_index = 4
	skull.animation="sp"


@warning_ignore("unused_parameter")
func _physics_process(delta: float) -> void:
	var time=get_tree().create_timer(2.5)
	time.timeout.connect(self.fade)


func fade():
	skull.animation="fade"
	@warning_ignore("standalone_expression")
	skull.animation_finished
	die()

func die():
	queue_free()
