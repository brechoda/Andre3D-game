extends SceneTree

const TEST_OBJ := "res://assets/maps/liberty_city/godot_tiles/maps_props__part_00.obj"
const MAX_SAFE_SURFACES := 255

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var resource := load(TEST_OBJ)
	if resource == null:
		push_error("OBJ could not be imported: " + TEST_OBJ)
		quit(1)
		return
	if not resource is Mesh:
		push_error("Expected a Mesh resource, got " + resource.get_class())
		quit(1)
		return
	var mesh := resource as Mesh
	var surfaces := mesh.get_surface_count()
	print("[gta3-map-import] type=Mesh surfaces=" + str(surfaces))
	if surfaces < 1 or surfaces > MAX_SAFE_SURFACES:
		push_error("Imported mesh surface count is outside the safe range: " + str(surfaces))
		quit(1)
		return
	quit(0)
