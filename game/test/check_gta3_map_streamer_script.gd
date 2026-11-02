extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/gta3_map_streamer.gd") as GDScript
	if script == null:
		push_error("Could not parse the GTA III map streamer script")
		quit(1)
		return
	if not script.can_instantiate():
		push_error("The GTA III map streamer script has a parse error")
		quit(1)
		return
	var instance: Node = script.new()
	if not instance is Node3D:
		push_error("GTA III map streamer must extend Node3D")
		quit(1)
		return
	instance.call("_load_parts_manifest")
	var part_paths: Variant = instance.get("_part_paths_by_tile")
	if not part_paths is Dictionary or not (part_paths as Dictionary).has("ground_fix"):
		push_error("The ground-fix visual is not registered as a streamed tile")
		instance.free()
		quit(1)
		return
	var registered_ground_fix: PackedStringArray = (part_paths as Dictionary)["ground_fix"]
	if registered_ground_fix != PackedStringArray(["res://assets/maps/liberty_city/ground_fix/ground_fix_visual.obj"]):
		push_error("The registered ground-fix mesh path is incorrect")
		instance.free()
		quit(1)
		return
	var visual_mesh := load("res://assets/maps/liberty_city/ground_fix/ground_fix_visual.obj") as Mesh
	var collision_mesh := load("res://assets/maps/liberty_city/collisions/ground_fix_collision.obj") as Mesh
	if visual_mesh == null or collision_mesh == null:
		push_error("The ground-fix visual or collision OBJ did not import as a Mesh")
		instance.free()
		quit(1)
		return
	print("[gta3-map-streamer] script parsed and instance created")
	print("[gta3-map-streamer] ground-fix visual and collision assets loaded")
	instance.free()
	quit(0)
