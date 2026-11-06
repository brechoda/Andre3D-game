extends SceneTree

const REGIONS_PATH := "res://assets/maps/liberty_city/map_regions.json"
const COLLISION_DIRECTORY := "res://assets/maps/liberty_city/collisions/"
const PARTS_MANIFEST_PATH := "res://assets/maps/liberty_city/godot_tiles/tile_parts.json"
const MAP_ORIGIN := Vector3(-130.6, -15.2, 30.4)
const MAP_ROTATION := Vector3(-90.0, 0.0, 0.0)
const MAX_SPAWN_FLOOR_OFFSET := 0.75

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var expected_region := ""
	var remote_spawns_by_region: Dictionary = {}
	if not args.is_empty():
		if args.size() not in [1, 2, 3] or not ProjectSettings.load_resource_pack(args[0], true):
			_fail("Usage: -- [<region-pck> [region-id [spawn-json]]]")
			return
		if args.size() == 2:
			expected_region = args[1]
		elif args.size() == 3:
			expected_region = args[1]
			var remote_file := FileAccess.open(args[2], FileAccess.READ)
			if remote_file == null:
				_fail("Could not open optional remote spawn.json")
				return
			var remote_data: Variant = JSON.parse_string(remote_file.get_as_text())
			if not remote_data is Dictionary or not (remote_data as Dictionary).get("regional_spawns", {}) is Dictionary:
				_fail("Optional remote spawn.json has an invalid structure")
				return
			remote_spawns_by_region = (remote_data as Dictionary)["regional_spawns"]
	var file := FileAccess.open(REGIONS_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open map region manifest")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("Map region manifest is invalid")
		return
	var regions: Variant = (parsed as Dictionary).get("regions", [])
	if not regions is Array:
		_fail("Map region manifest has no regions")
		return
	var parts_file := FileAccess.open(PARTS_MANIFEST_PATH, FileAccess.READ)
	if parts_file == null:
		_fail("Could not open split-tile manifest")
		return
	var parts_data: Variant = JSON.parse_string(parts_file.get_as_text())
	if not parts_data is Dictionary or not (parts_data as Dictionary).get("tiles", []) is Array:
		_fail("Split-tile manifest is invalid")
		return
	var part_rows: Array = (parts_data as Dictionary).get("tiles", [])
	var checked_spawns := 0
	var checked_visual_mesh_parts := 0
	var maximum_floor_offset := 0.0
	for region: Variant in regions:
		if not region is Dictionary:
			continue
		if not expected_region.is_empty() and String((region as Dictionary).get("id", "")) != expected_region:
			continue
		var world := Node3D.new()
		root.add_child(world)
		var map_root := Node3D.new()
		map_root.position = MAP_ORIGIN
		map_root.rotation_degrees = MAP_ROTATION
		world.add_child(map_root)
		var tile_values: Variant = (region as Dictionary).get("tiles", [])
		for tile_value: Variant in tile_values:
			var tile_name := String(tile_value).replace("/", "_")
			var visual_found := false
			for part_row: Variant in part_rows:
				if not part_row is Dictionary or String((part_row as Dictionary).get("tile", "")).replace("/", "_") != tile_name:
					continue
				var part_names: Variant = (part_row as Dictionary).get("parts", [])
				if not part_names is Array or (part_names as Array).is_empty():
					break
				for part_name: Variant in part_names:
					var visual_path := "res://assets/maps/liberty_city/godot_tiles/" + String(part_name)
					var visual_mesh := ResourceLoader.load(visual_path, "Mesh") as Mesh
					if visual_mesh == null or visual_mesh.get_surface_count() == 0:
						_fail("Could not load visual mesh " + visual_path)
						return
					checked_visual_mesh_parts += 1
				visual_found = true
				break
			if not visual_found:
				_fail("No visual mesh registered for tile " + tile_name)
				return
			if not _add_collision_tile(map_root, tile_name):
				_fail("Could not add collision for %s/%s" % [String((region as Dictionary).get("id", "")), tile_name])
				return
		if not _add_collision_tile(map_root, "ground_fix_collision"):
			_fail("Could not add ground-fix collision")
			return
		await physics_frame
		var spawn_points: Array = []
		spawn_points.append({"id": "player", "position": (region as Dictionary).get("spawn", [])})
		spawn_points.append({"id": "gorece", "position": (region as Dictionary).get("gorece_spawn", [])})
		var vehicles: Variant = (region as Dictionary).get("vehicle_spawns", {})
		if not vehicles is Dictionary or (vehicles as Dictionary).size() != 4:
			_fail("Region is missing one or more vehicle spawn points: " + String((region as Dictionary).get("id", "")))
			return
		for vehicle_id: Variant in (vehicles as Dictionary).keys():
			spawn_points.append({"id": String(vehicle_id), "position": (vehicles as Dictionary)[vehicle_id]})
		if not remote_spawns_by_region.is_empty():
			var region_id := String((region as Dictionary).get("id", ""))
			var remote_region: Variant = remote_spawns_by_region.get(region_id, null)
			if not remote_region is Dictionary:
				_fail("Remote spawn.json has no data for region " + region_id)
				return
			for actor_id: String in ["player", "gorece"]:
				var actor_data: Variant = (remote_region as Dictionary).get(actor_id, {})
				if not actor_data is Dictionary:
					_fail("Remote spawn.json has no " + actor_id + " position for " + region_id)
					return
				spawn_points.append({"id": "remote_" + actor_id, "position": (actor_data as Dictionary).get("position", []), "world_space": true})
			var remote_vehicles: Variant = (remote_region as Dictionary).get("vehicles", {})
			if not remote_vehicles is Dictionary or (remote_vehicles as Dictionary).size() != 4:
				_fail("Remote spawn.json is missing region vehicles: " + region_id)
				return
			for vehicle_id: Variant in (remote_vehicles as Dictionary).keys():
				var vehicle_data: Variant = (remote_vehicles as Dictionary)[vehicle_id]
				if not vehicle_data is Dictionary:
					_fail("Remote spawn data is invalid for " + String(vehicle_id))
					return
				spawn_points.append({"id": "remote_" + String(vehicle_id), "position": (vehicle_data as Dictionary).get("position", []), "world_space": true})
			var local_world_spawns: Dictionary = {}
			for point: Variant in spawn_points:
				var raw_position: Variant = (point as Dictionary).get("position", [])
				if not raw_position is Array or (raw_position as Array).size() != 3:
					_fail("Invalid %s spawn in %s" % [String((point as Dictionary).get("id", "")), String((region as Dictionary).get("id", ""))])
					return
				var position: Vector3
				if bool((point as Dictionary).get("world_space", false)):
					position = Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
				else:
					# O manifesto usa [X, altura, Y]; converter ao espaço mundial.
					var map_position := Vector3(float(raw_position[0]), float(raw_position[2]), float(raw_position[1]))
					position = map_root.to_global(map_position)
				var point_id := String((point as Dictionary).get("id", ""))
				if bool((point as Dictionary).get("world_space", false)):
					var local_id := point_id.trim_prefix("remote_")
					if not local_world_spawns.has(local_id):
						_fail("Remote spawn has no local counterpart: " + point_id)
						return
					var local_position: Vector3 = local_world_spawns[local_id]
					if local_position.distance_to(position) > 0.01:
						_fail("Remote spawn %s diverges %.3f m from its local map coordinate" % [point_id, local_position.distance_to(position)])
						return
				else:
					local_world_spawns[point_id] = position
				var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2.0, position - Vector3.UP * 250.0, 1)
				query.hit_back_faces = true
				var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty():
					_fail("No COL1 floor directly below %s spawn in %s at %s" % [String((point as Dictionary).get("id", "")), String((region as Dictionary).get("id", "")), str(position)])
					return
				var collider := hit.get("collider") as Node
				if collider == null or collider.name != "COL1Collision":
					_fail("Spawn ray did not hit the expected map collision")
					return
				var floor_position: Vector3 = hit.get("position", position)
				var floor_offset := absf(position.y - floor_position.y)
				maximum_floor_offset = maxf(maximum_floor_offset, floor_offset)
				if floor_offset > MAX_SPAWN_FLOOR_OFFSET:
					_fail("Spawn %s is %.3f m from the COL1 floor in %s" % [String((point as Dictionary).get("id", "")), floor_offset, String((region as Dictionary).get("id", ""))])
					return
				checked_spawns += 1
		world.queue_free()
		await process_frame
	if checked_spawns == 0:
		_fail("No spawn points were checked")
		return
	print("[map-region-spawns] loaded %d visual mesh parts; %d spawns are within %.3f m of COL1 floor%s" % [checked_visual_mesh_parts, checked_spawns, maximum_floor_offset, " including remote config" if not remote_spawns_by_region.is_empty() else ""])
	quit(0)

func _add_collision_tile(map_root: Node3D, tile_name: String) -> bool:
	var filename := "ground_fix_collision.obj" if tile_name == "ground_fix_collision" else tile_name + ".obj"
	var path := COLLISION_DIRECTORY + filename
	var mesh := ResourceLoader.load(path, "Mesh") as Mesh
	if mesh == null:
		return false
	var shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	if shape == null:
		return false
	shape.backface_collision = true
	var tile_root := Node3D.new()
	tile_root.name = tile_name
	map_root.add_child(tile_root)
	var body := StaticBody3D.new()
	body.name = "COL1Collision"
	body.collision_layer = 1
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	tile_root.add_child(body)
	return true

func _fail(message: String) -> void:
	push_error("[map-region-spawns] " + message)
	quit(1)
