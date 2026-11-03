extends SceneTree

const SESSION_PATH := "user://andre3d_session.json"

var _session_existed := false
var _saved_session := PackedByteArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_session_existed = FileAccess.file_exists(SESSION_PATH)
	if _session_existed:
		_saved_session = FileAccess.get_file_as_bytes(SESSION_PATH)
	var session_file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if session_file == null:
		_fail("Could not create a temporary map selection session")
		return
	session_file.store_string(JSON.stringify({"map_region": "center"}))
	session_file.close()

	var world := Node3D.new()
	root.add_child(world)
	var streamer_script := load("res://scripts/gta3_map_streamer.gd") as GDScript
	if streamer_script == null:
		_fail("Could not load the map streamer script")
		return
	var streamer := streamer_script.new() as Node3D
	streamer.position = Vector3(-130.6, -15.2, 30.4)
	streamer.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	world.add_child(streamer)

	var selected_region := String(streamer.call("get_selected_region_id"))
	if selected_region != "center":
		_fail("Expected center to be selected, got: " + selected_region)
		return
	var catalog_file := FileAccess.open("res://assets/maps/liberty_city/gta3_tile_catalog.json", FileAccess.READ)
	if catalog_file == null:
		_fail("Could not read the spatial tile catalog")
		return
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text())
	if not catalog is Dictionary:
		_fail("The spatial tile catalog is invalid")
		return
	var industrial_center: Array = []
	for row: Variant in (catalog as Dictionary).get("tiles", []):
		if row is Dictionary and String((row as Dictionary).get("name", "")) == "industnw/industnw":
			industrial_center = (row as Dictionary).get("center", [])
			break
	if industrial_center.size() < 2:
		_fail("Could not find the Industrial tile center")
		return

	var player := Node3D.new()
	player.name = "Player"
	world.add_child(player)
	# Simula o jogador chegando exatamente sobre um tile da região não selecionada.
	player.global_position = streamer.to_global(Vector3(float(industrial_center[0]), float(industrial_center[1]), 0.0))
	streamer.call("_refresh_active_tiles")

	var selected_tiles: Dictionary = streamer.get("_selected_region_tiles")
	var allowed_tiles := {
		"comnbtm/comnbtm": true,
		"comntop/comntop": true,
		"comse/comse": true,
		"comsw/comsw": true,
	}
	for tile_name: String in selected_tiles.keys():
		if not allowed_tiles.has(tile_name):
			_fail("Selected region contains an unexpected tile: " + tile_name)
			return
	var paths_by_tile: Dictionary = streamer.get("_part_paths_by_tile")
	for tile_name in ["industne/industne", "industnw/industnw", "industse/industse", "industsw/industsw"]:
		if paths_by_tile.has(tile_name):
			_fail("An unselected Industrial tile remains requestable: " + tile_name)
			return
	var wanted: Dictionary = streamer.get("_wanted_tiles")
	for tile_name: String in wanted.keys():
		if tile_name != "ground_fix" and not allowed_tiles.has(tile_name):
			_fail("The streamer requested an unselected tile: " + tile_name)
			return
	print("[map-region-isolation] center selected; no Industrial tile requested at its own coordinates")
	_restore_session()
	world.queue_free()
	await process_frame
	quit(0)

func _fail(message: String) -> void:
	push_error("[map-region-isolation] " + message)
	_restore_session()
	quit(1)

func _restore_session() -> void:
	if _session_existed:
		var restore_file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
		if restore_file != null:
			restore_file.store_buffer(_saved_session)
			restore_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
