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
	var static_collision_shapes := 0
	var maximum_floor_offset := 0.0
	for region: Variant in regions:
		if not region is Dictionary:
			continue
		if not expected_region.is_empty() and String((region as Dictionary).get("id", "")) != expected_region:
			continue
		var world := Node3D.new()
		root.add_child(world)
		var tile_values: Variant = (region as Dictionary).get("tiles", [])
		var region_id := String((region as Dictionary).get("id", ""))
		var is_static_region := tile_values is Array and (tile_values as Array).is_empty()
		var map_root: Node3D
		if is_static_region:
			if not ResourceLoader.exists("res://level2_static.tscn"):
				if expected_region == region_id:
					_fail("Static region PCK does not provide res://level2_static.tscn")
					return
				print("[map-region-spawns] skipped external static region without its PCK: " + region_id)
				world.queue_free()
				await process_frame
				continue
			var static_scene := load("res://level2_static.tscn") as PackedScene
			map_root = static_scene.instantiate() as Node3D if static_scene != null else null
			if map_root == null:
				_fail("Could not instantiate static region " + region_id)
				return
			world.add_child(map_root)
			static_collision_shapes = _add_static_region_collisions(map_root)
			if static_collision_shapes == 0:
				_fail("Static region has no usable collision meshes: " + region_id)
				return
		else:
			map_root = Node3D.new()
			map_root.position = MAP_ORIGIN
			map_root.rotation_degrees = MAP_ROTATION
			world.add_child(map_root)
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
					_fail("Could not add collision for %s/%s" % [region_id, tile_name])
					return
			if not _add_collision_tile(map_root, "ground_fix_collision"):
				_fail("Could not add ground-fix collision")
				return
		await physics_frame
		var spawn_points: Array = []
		spawn_points.append({"id": "player", "position": (region as Dictionary).get("spawn", []), "world_space": is_static_region})
		spawn_points.append({"id": "gorece", "position": (region as Dictionary).get("gorece_spawn", []), "world_space": is_static_region})
		var vehicles: Variant = (region as Dictionary).get("vehicle_spawns", {})
		var expected_vehicles := 0 if is_static_region else 4
		if not vehicles is Dictionary or (vehicles as Dictionary).size() != expected_vehicles:
			_fail("Region has an unexpected number of vehicle spawns: " + region_id)
			return
		for vehicle_id: Variant in (vehicles as Dictionary).keys():
			spawn_points.append({"id": String(vehicle_id), "position": (vehicles as Dictionary)[vehicle_id]})
		var local_world_spawns: Dictionary = {}
		var resolved_points: Array[Dictionary] = []
		for point: Variant in spawn_points:
			var raw_position: Variant = (point as Dictionary).get("position", [])
			if not raw_position is Array or (raw_position as Array).size() != 3:
				_fail("Invalid %s spawn in %s" % [String((point as Dictionary).get("id", "")), region_id])
				return
			var position: Vector3
			if bool((point as Dictionary).get("world_space", false)):
				position = Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
			else:
				# O manifesto usa [X, altura, Y]; converter ao espaço mundial.
				var map_position := Vector3(float(raw_position[0]), float(raw_position[2]), float(raw_position[1]))
				position = map_root.to_global(map_position)
			var point_id := String((point as Dictionary).get("id", ""))
			local_world_spawns[point_id] = position
			resolved_points.append({"id": point_id, "position": position})
		if not remote_spawns_by_region.is_empty():
			var remote_region: Variant = remote_spawns_by_region.get(region_id, null)
			if not remote_region is Dictionary:
				_fail("Remote spawn.json has no data for region " + region_id)
				return
			var remote_points: Array[Dictionary] = []
			for actor_id: String in ["player", "gorece"]:
				var actor_data: Variant = (remote_region as Dictionary).get(actor_id, {})
				if not actor_data is Dictionary:
					_fail("Remote spawn.json has no " + actor_id + " position for " + region_id)
					return
				remote_points.append({"id": "remote_" + actor_id, "data": actor_data})
			var remote_vehicles: Variant = (remote_region as Dictionary).get("vehicles", {})
			if not remote_vehicles is Dictionary or (remote_vehicles as Dictionary).size() != expected_vehicles:
				_fail("Remote spawn.json has an unexpected number of region vehicles: " + region_id)
				return
			for vehicle_id: Variant in (remote_vehicles as Dictionary).keys():
				var vehicle_data: Variant = (remote_vehicles as Dictionary)[vehicle_id]
				if not vehicle_data is Dictionary:
					_fail("Remote spawn data is invalid for " + String(vehicle_id))
					return
				remote_points.append({"id": "remote_" + String(vehicle_id), "data": vehicle_data})
			for remote_point: Dictionary in remote_points:
				var remote_id := String(remote_point["id"])
				var remote_data: Dictionary = remote_point["data"]
				var remote_position_data: Variant = remote_data.get("position", [])
				if not remote_position_data is Array or (remote_position_data as Array).size() != 3:
					_fail("Invalid remote position for " + remote_id)
					return
				var remote_position := Vector3(float(remote_position_data[0]), float(remote_position_data[1]), float(remote_position_data[2]))
				var local_id := remote_id.trim_prefix("remote_")
				if not local_world_spawns.has(local_id):
					_fail("Remote spawn has no local counterpart: " + remote_id)
					return
				var local_position: Vector3 = local_world_spawns[local_id]
				if local_position.distance_to(remote_position) > 0.01:
					_fail("Remote spawn %s diverges %.3f m from its local map coordinate" % [remote_id, local_position.distance_to(remote_position)])
					return
				resolved_points.append({"id": remote_id, "position": remote_position})
		for point: Dictionary in resolved_points:
			var position: Vector3 = point["position"]
			var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2.0, position - Vector3.UP * 250.0, 1)
			query.hit_back_faces = true
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				_fail("No COL1 floor directly below %s spawn in %s at %s" % [String(point["id"]), region_id, str(position)])
				return
			var collider := hit.get("collider") as Node
			if collider == null or collider.name != "COL1Collision":
				_fail("Spawn ray did not hit the expected map collision")
				return
			var floor_position: Vector3 = hit.get("position", position)
			var shape_owner_name := "unknown"
			if collider is CollisionObject3D:
				var collision_object := collider as CollisionObject3D
				var owner_id := collision_object.shape_find_owner(int(hit.get("shape", -1)))
				var shape_owner := collision_object.shape_owner_get_owner(owner_id)
				if shape_owner != null:
					shape_owner_name = String(shape_owner.name)
			var floor_offset := absf(position.y - floor_position.y)
			maximum_floor_offset = maxf(maximum_floor_offset, floor_offset)
			if floor_offset > MAX_SPAWN_FLOOR_OFFSET:
				_fail("Spawn %s at %s is %.3f m from collision %s at %s in %s" % [String(point["id"]), str(position), floor_offset, shape_owner_name, str(floor_position), region_id])
				return
			checked_spawns += 1
		world.queue_free()
		await process_frame
	if checked_spawns == 0:
		_fail("No spawn points were checked")
		return
	print("[map-region-spawns] checked %d regional OBJ parts and %d static collision shapes; %d spawns are within %.3f m of COL1 floor%s" % [checked_visual_mesh_parts, static_collision_shapes, checked_spawns, maximum_floor_offset, " including remote config" if not remote_spawns_by_region.is_empty() else ""])
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

func _add_static_region_collisions(static_root: Node3D) -> int:
	var collision_body := StaticBody3D.new()
	collision_body.name = "COL1Collision"
	collision_body.collision_layer = 1
	collision_body.collision_mask = 1
	static_root.add_child(collision_body)
	static_root.force_update_transform()
	var collision_count := 0
	var collision_shapes_by_mesh: Dictionary = {}
	for mesh_node: Node in static_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_name := mesh_instance.name.to_lower()
		if mesh_name.begins_with("tree") or mesh_name.begins_with("arvore") or mesh_name.begins_with("bush") or mesh_name.begins_with("arbusto") or mesh_name.begins_with("grass") or mesh_name.begins_with("gramas"):
			continue
		mesh_instance.force_update_transform()
		var mesh_id := mesh_instance.mesh.get_instance_id()
		var collision_shape := collision_shapes_by_mesh.get(mesh_id) as ConcavePolygonShape3D
		if collision_shape == null:
			collision_shape = mesh_instance.mesh.create_trimesh_shape() as ConcavePolygonShape3D
			if collision_shape == null:
				continue
			collision_shape.backface_collision = true
			collision_shapes_by_mesh[mesh_id] = collision_shape
		var shape_instance := CollisionShape3D.new()
		shape_instance.name = mesh_instance.name + "Collision"
		shape_instance.shape = collision_shape
		shape_instance.transform = static_root.global_transform.affine_inverse() * mesh_instance.global_transform
		collision_body.add_child(shape_instance)
		collision_count += 1
	return collision_count

func _fail(message: String) -> void:
	push_error("[map-region-spawns] " + message)
	quit(1)
