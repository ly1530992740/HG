extends TileMapLayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self_modulate.a=0
	if Engine.is_editor_hint():
		clean_invalid_tiles()

func clean_invalid_tiles() -> void:
	if tile_set == null:
		print("TileMapLayer has no TileSet assigned!")
		return

	var cells = get_used_cells() # All tiles in this layer
	for cell in cells:
		var tile_data = get_cell_tile_data(cell)
		if tile_data == null:
			continue # No tile here

		# Check tile identifier via tile_data
		var source_id = tile_data.get_source_id()
		if source_id == -1:
			# Nothing, empty cell
			continue

		# If the source_id is not valid in the TileSet, clear it:
		if not tile_set.has_source(source_id):
			print("Clearing invalid tile at:", cell)
			erase_cell(cell) # Removes tile data entirely

	print("TileMapLayer cleanup done!")
