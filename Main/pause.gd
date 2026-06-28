extends Panel
@onready var resume: Label = $resume
func _ready():
	resume.text=" Press the resume key "
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event):
	# Pause game
	if event.is_action_pressed("pause") and !get_tree().paused:
		get_tree().paused = true
		show()

	# Resume game
	elif event.is_action_pressed("resume") and get_tree().paused:
		get_tree().paused = false
		hide()
