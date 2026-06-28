extends Node
#==========================================
# LEVEL VARIABLE

var level=1
var current_level_id: int=2
var Goblin_house =0


# =========================
# GOBLIN MANAGER
# =========================
var goblins: Array = []

#============================================
# PLAYER STATE / RESOURCES
#============================================
var pawn_tool:String="hand"
var choosed_colour: String="black"
const SAVE_COLOR: String="user://levels.save"

# variables
var gold:int=5
var wood:int=5
var meat:int=5

var max_gold:int=1000
var max_wood:int=1000
var max_meat:int=1000


#==========================================
# VARIABLE
#==========================================
var level_exit_unlocked: bool = false   # ⭐ ADD THIS

# use this block to implement my levels paths
const LEVEL_SCENES:={
	1: "res://Levels/level1/level1.tscn",
	2: "res://Levels/level2/level2.tscn",
	3: "res://Levels/level3/level3.tscn",
	4: "res://Levels/level4/level4.tscn",
	5: "res://Levels/level5/level5.tscn",
	}

# =========================
# GLOBAL WAVE SYSTEM
# =========================
var wave_timer: float = 0.0
var wave_interval: float = 190.0   #minutes
var current_wave: int = 0
var max_waves: int = 3

var wave_active: bool = false
var wave_started: bool = false
var wave_start: bool = false    # USED BY MUSIC / BUILDINGS

# Number of buildings still spawning
var active_spawners: int = 0

signal wave_started_signal(wave_number: int)
signal wave_ended(wave_number: int)


# Game over system var
var game_over: bool = false

var wave_system_enabled := true

# =========================
# READY
# =========================
func _ready() -> void:
	Global.Goblin_house=0
	load_colour()
	clamp_resources()
	game_over = false


# =========================
# SAVE / LOAD COLOR
# =========================
func save_colour() -> void:
	var file: FileAccess = FileAccess.open(SAVE_COLOR, FileAccess.WRITE)
	file.store_string(choosed_colour)
	file.close()

func load_colour() -> void:
	if FileAccess.file_exists(SAVE_COLOR):
		var file: FileAccess = FileAccess.open(SAVE_COLOR, FileAccess.READ)
		choosed_colour = file.get_as_text()
		file.close()


# =========================
# RESOURCE CLAMPING
# =========================
func clamp_resources() -> void:
	gold = clamp(gold, 0, max_gold)
	wood = clamp(wood, 0, max_wood)
	meat = clamp(meat, 0, max_meat)

func add_gold(amount: int) -> void:
	gold = min(gold + amount, max_gold)

func add_wood(amount: int) -> void:
	wood = min(wood + amount, max_wood)

func add_meat(amount: int = 1) -> void:
	meat = min(meat + amount, max_meat)

func consume_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true

func consume_wood(amount: int) -> bool:
	if wood < amount:
		return false
	wood -= amount
	return true

func consume_meat(amount: int = 1) -> bool:
	if meat < amount:
		return false
	meat -= amount
	return true

func can_spawn_pawn() -> bool:
	return meat > 0


# =========================
# PROCESS
# =========================
func _process(delta: float) -> void:
	if !wave_system_enabled:
		return

	if wave_active:
		return

	if current_wave >= max_waves:
		return

	wave_timer += delta
	if wave_timer >= wave_interval:
		wave_timer = 0.0
		start_wave()


# =========================
# WAVE CONTROL
# =========================
func start_wave() -> void:
	current_wave += 1
	wave_active = true
	wave_started = true
	wave_start = true
	active_spawners = 0

	emit_signal("wave_started_signal", current_wave)

	# NEW — wake all goblins
	for g in goblins:
		if is_instance_valid(g):
			g.set_active(true)




func register_spawner() -> void:
	active_spawners += 1


func unregister_spawner() -> void:
	active_spawners -= 1
	if active_spawners <= 0:
		end_wave()

func end_wave() -> void:
	wave_active = false
	wave_started = false
	wave_start = false

	# NEW — put goblins to sleep
	for g in goblins:
		if is_instance_valid(g):
			g.set_active(false)

	emit_signal("wave_ended", current_wave)


# =========================
# RESET GAME (NEW)
# =========================
func reset_game() -> void:
	# Wave system
	wave_timer = 0.0
	current_wave = 0
	wave_active = false
	wave_started = false
	wave_start = false
	active_spawners = 0

	# Game state
	game_over = false


const SAVE_FILE: String = "user://save_game.json"

# =========================
# SAVE / LOAD GAME
# =========================
func save_game() -> void:
	var save_data := {
		"level_id": current_level_id,
		"gold": gold,
		"wood": wood,
		"meat": meat
	}

	var file := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_FILE):
		return

	var file: FileAccess = FileAccess.open(SAVE_FILE, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file")
		return

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save file is corrupted")
		return

	var data: Dictionary = parsed

	# LOAD EXACT SAVED VALUES (NO DEFAULTS)
	current_level_id = int(data["level_id"])
	gold = int(data["gold"])
	wood = int(data["wood"])
	meat = int(data["meat"])

	clamp_resources()

	# VALIDATE LEVEL
	if not LEVEL_SCENES.has(current_level_id):
		push_error("Invalid level ID in save: %s" % current_level_id)
		return

	get_tree().change_scene_to_file(LEVEL_SCENES[current_level_id])


func set_current_level(level_id: int) -> void:
	current_level_id = level_id

func init_level_state() -> void:
	# Wave system
	wave_timer = 0.0
	current_wave = 0
	wave_active = false
	wave_started = false
	wave_start = false
	active_spawners = 0

	# Level-specific state
	Goblin_house = 0
	game_over = false
	level_exit_unlocked = false   # ⭐ reset exit


func register_goblin(goblin: Node) -> void:
	if not goblins.has(goblin):
		goblins.append(goblin)


func unregister_goblin(goblin: Node) -> void:
	goblins.erase(goblin)
