extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/gta3_map_streamer.gd") as GDScript
	if script == null:
		push_error("Could not parse the GTA III map streamer script")
		quit(1)
		return
	var instance: Node = script.new()
	if not instance is Node3D:
		push_error("GTA III map streamer must extend Node3D")
		quit(1)
		return
	print("[gta3-map-streamer] script parsed and instance created")
	instance.free()
	quit(0)
