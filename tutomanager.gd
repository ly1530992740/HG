extends Node
class_name TutorialManager

# ==============================
# FILE CONFIG
# ==============================
const SAVE_PATH := "user://savegame.save"

# ==============================
# TUTORIAL CONFIG
# ==============================
var tutorial_scenes: Array[String] = [
	"res://Tutorials/pawn tutorials/pawntutorial1.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial2.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial3.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial4.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial5.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial6.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial7.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial8.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial9.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial10.tscn",
	"res://Tutorials/pawn tutorials/pawntutorial11.tscn",
]

# ==============================
# SCENES
# ==============================
@export var tutorial_end_menu := "res://Levels/level1/level1.tscn"
@export var skip_menu :="res://Main/Menu_select.tscn"

# ==============================
# STATE
# ==============================
var current_index: int = 0
var tutorial_done: bool = false
var forced_replay: bool = false

# ==============================
# GODOT LIFECYCLE
# ==============================
func _ready():
	load_save()

# ==============================
# SAVE SYSTEM
# ==============================
func load_save():
	if not FileAccess.file_exists(SAVE_PATH):
		tutorial_done = false
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = file.get_var()
	file.close()

	tutorial_done = data.get("tutorial_done", false)



func save_game():
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var({
		"tutorial_done": tutorial_done
	})
	file.close()

# ==============================
# GAME ENTRY POINT
# ==============================
func start_game():
	# First launch → tutorial
	if not tutorial_done:
		start_tutorial()
		return

	# Tutorial done → skip
	get_tree().change_scene_to_file(skip_menu)

# ==============================
# TUTORIAL CONTROL
# ==============================
func start_tutorial(force := false):
	forced_replay = force
	current_index = 0
	load_current()


func next_step():
	current_index += 1
	load_current()


func load_current():
	if current_index >= tutorial_scenes.size():
		finish_tutorial()
		return

	get_tree().change_scene_to_file(tutorial_scenes[current_index])


func finish_tutorial():
	# Save only if first completion
	if not tutorial_done:
		tutorial_done = true
		save_game()

	# Always go back to menu select
	get_tree().change_scene_to_file(tutorial_end_menu)
