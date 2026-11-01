extends Node3D
class_name Gta3MapStreamer

## Streams split IPL tiles around the player. Source GTA coordinates are mapped
## into Godot Y-up by the transform on this node in third_person.tscn.

@export_file("*.json") var parts_manifest_path := "res://assets/maps/liberty_city/godot_tiles/tile_parts.json"
@export var max_active_tiles := 3
@export var load_radius := 900.0
@export var refresh_interval := 0.75
@export var build_mesh_collisions := true
@export var max_meshes_per_frame := 4

const TILE_DIRECTORY := "res://assets/maps/liberty_city/godot_tiles/"
const COLLISION_DIRECTORY := "res://assets/maps/liberty_city/collisions/"
const OVERVIEW_TILE := "maps/overview"
const INITIAL_SPAWN_TILE := "comntop/comntop"

var _tile_records: Array[Dictionary] = []
var _part_paths_by_tile: Dictionary = {}
var _part_bounds: Dictionary = {}
var _loaded_tiles: Dictionary = {}
var _pending_paths: Dictionary = {}
var _wanted_tiles: Dictionary = {}
var _alpha_texture_cache: Dictionary = {}
var _refresh_elapsed := 0.0
var _manifest_ready := false
var _ultra_low_mode := false
var _low_material_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("graphics_map")
	GraphicsSettings.apply()
	_load_parts_manifest()
	if _manifest_ready:
		_refresh_active_tiles()
	set_process(true)

func apply_graphics_settings(distance_level: int, texture_quality_level: int) -> void:
    _ultra_low_mode = distance_level == 0
    max_active_tiles = [1, 1, 2, 3][clampi(distance_level, 0, 3)]
    load_radius = [220.0, 520.0, 780.0, 1100.0][clampi(distance_level, 0, 3)]
    refresh_interval = 0.35 if _ultra_low_mode else 0.75
    max_meshes_per_frame = [1, 2, 4, 7][clampi(texture_quality_level, 0, 3)]
	_refresh_active_tiles()

func _process(delta: float) -> void:
	_process_pending_meshes()
	_refresh_elapsed += delta
	if _refresh_elapsed >= refresh_interval:
		_refresh_elapsed = 0.0
		_refresh_active_tiles()

func _load_parts_manifest() -> void:
	if not FileAccess.file_exists(parts_manifest_path):
		push_error("GTA III split-tile manifest is missing: " + parts_manifest_path)
		return
	var file := FileAccess.open(parts_manifest_path, FileAccess.READ)
	if file == null:
		push_error("Could not open GTA III split-tile manifest: " + parts_manifest_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("GTA III split-tile manifest has an invalid structure")
		return
	var root := parsed as Dictionary
	var tile_rows: Variant = root.get("tiles", [])
	if not tile_rows is Array:
		push_error("GTA III split-tile manifest has no tile array")
		return
	for row: Variant in tile_rows:
		if not row is Dictionary:
			continue
		var record := row as Dictionary
		var tile_name := String(record.get("tile", ""))
		var part_names: Variant = record.get("parts", [])
		if tile_name.is_empty() or not part_names is Array:
			continue
		var part_paths := PackedStringArray()
		for part_name: Variant in part_names:
			part_paths.append(TILE_DIRECTORY + String(part_name))
		_part_paths_by_tile[tile_name] = part_paths
	var bounds_path := parts_manifest_path.get_base_dir() + "/tile_part_bounds.json"
	if FileAccess.file_exists(bounds_path):
		var bounds_file := FileAccess.open(bounds_path, FileAccess.READ)
		if bounds_file != null:
			var bounds_data: Variant = JSON.parse_string(bounds_file.get_as_text())
			if bounds_data is Dictionary:
				_part_bounds = (bounds_data as Dictionary).get("parts", {})

	var catalog_path := parts_manifest_path.get_base_dir().get_base_dir() + "/gta3_tile_catalog.json"
	if not FileAccess.file_exists(catalog_path):
		push_error("GTA III spatial catalog is missing: " + catalog_path)
		return
	var catalog_file := FileAccess.open(catalog_path, FileAccess.READ)
	if catalog_file == null:
		push_error("Could not open GTA III spatial catalog: " + catalog_path)
		return
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text())
	if not catalog is Dictionary:
		push_error("GTA III spatial catalog has an invalid structure")
		return
	var catalog_rows: Variant = (catalog as Dictionary).get("tiles", [])
	if not catalog_rows is Array:
		push_error("GTA III spatial catalog has no tile array")
		return
	for row: Variant in catalog_rows:
		if row is Dictionary and (row as Dictionary).has("name"):
			_tile_records.append(row as Dictionary)
	_manifest_ready = not _tile_records.is_empty() and not _part_paths_by_tile.is_empty()
	if not _manifest_ready:
		push_error("GTA III map manifests contain no usable tiles")

func _refresh_active_tiles() -> void:
	if not _manifest_ready:
		return
	var world_root := get_parent()
	if world_root == null:
		return
	var player := world_root.get_node_or_null("Player") as Node3D
	if player == null:
		return
	var source_position := to_local(player.global_position)
	var candidates: Array[Dictionary] = []
	for record: Dictionary in _tile_records:
        var tile_name := String(record.get("name", ""))
        if tile_name == OVERVIEW_TILE or not _part_paths_by_tile.has(tile_name):
            continue
        if _ultra_low_mode and tile_name == "maps/props":
            continue
		var distance := _distance_to_tile_center(source_position, record)
		if distance <= load_radius:
			candidates.append({"name": tile_name, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	var desired: Dictionary = {}
        if not _ultra_low_mode and _part_paths_by_tile.has(OVERVIEW_TILE):
            desired[OVERVIEW_TILE] = true
	# O tile inicial contém o chão/colisão do spawn. Ele precisa permanecer
	# carregado também no preset BAIXA, mesmo quando o raio foi reduzido.
        if not _ultra_low_mode and _part_paths_by_tile.has(INITIAL_SPAWN_TILE):
            desired[INITIAL_SPAWN_TILE] = true
        if _ultra_low_mode and candidates.is_empty():
            var nearest: Dictionary = {}
            var nearest_distance := INF
            for record: Dictionary in _tile_records:
                var tile_name := String(record.get("name", ""))
                if tile_name == OVERVIEW_TILE or tile_name == "maps/props" or not _part_paths_by_tile.has(tile_name):
                    continue
                var distance := _distance_to_tile_center(source_position, record)
                if distance < nearest_distance:
                    nearest_distance = distance
                    nearest = {"name": tile_name, "distance": distance}
            if not nearest.is_empty():
                candidates.append(nearest)
	var limit := mini(max_active_tiles, candidates.size())
	for index: int in range(limit):
		desired[String(candidates[index]["name"])] = true
	_wanted_tiles = desired
	for tile_name: String in desired.keys():
		if not _loaded_tiles.has(tile_name):
			_start_tile_load(tile_name, source_position)
	for tile_name: String in _loaded_tiles.keys():
		if not desired.has(tile_name):
			(_loaded_tiles[tile_name] as Node).queue_free()
			_loaded_tiles.erase(tile_name)

func _distance_to_tile_center(source_position: Vector3, record: Dictionary) -> float:
	var center: Array = record["center"]
	return Vector2(float(center[0]) - source_position.x, float(center[1]) - source_position.y).length()

func _start_tile_load(tile_name: String, source_position: Vector3) -> void:
	var tile_root := Node3D.new()
	tile_root.name = tile_name.replace("/", "_")
	add_child(tile_root)
	_loaded_tiles[tile_name] = tile_root
	var nearest_path := ""
	var nearest_distance := INF
	var requested_parts := 0
	for path: String in _part_paths_by_tile[tile_name]:
		var part_distance := _part_distance_to_player(path, source_position)
		if part_distance < nearest_distance:
			nearest_distance = part_distance
			nearest_path = path
		if _ultra_low_mode and part_distance > load_radius:
			continue
		# Do not check FileAccess/ResourceLoader.exists here: exported Android
		# packages keep the imported mesh and remap, not the source OBJ itself.
		var error := ResourceLoader.load_threaded_request(path, "Mesh", false)
		if error != OK and error != ERR_BUSY:
			push_error("Could not start loading GTA III mesh %s (error %d)" % [path, error])
			continue
		_pending_paths[path] = {"tile": tile_name, "collision": false}
		requested_parts += 1
	if _ultra_low_mode and requested_parts == 0 and not nearest_path.is_empty():
		var nearest_error := ResourceLoader.load_threaded_request(nearest_path, "Mesh", false)
		if nearest_error == OK or nearest_error == ERR_BUSY:
			_pending_paths[nearest_path] = {"tile": tile_name, "collision": false}
	var collision_path := COLLISION_DIRECTORY + tile_name.replace("/", "_") + ".obj"
	if tile_name != OVERVIEW_TILE:
		var collision_error := ResourceLoader.load_threaded_request(collision_path, "Mesh", false)
		if collision_error != OK and collision_error != ERR_BUSY:
			push_error("Could not start COL1 collision load %s (error %d)" % [collision_path, collision_error])
		else:
			_pending_paths[collision_path] = {"tile": tile_name, "collision": true}

func _process_pending_meshes() -> void:
	var processed_count := 0
	for path: String in _pending_paths.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if processed_count >= max_meshes_per_frame:
			return
		processed_count += 1
		var pending: Dictionary = _pending_paths[path]
		var tile_name: String = String(pending["tile"])
		var is_collision: bool = bool(pending["collision"])
		_pending_paths.erase(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_error("Failed to import split GTA III mesh: " + path)
			continue
		var mesh := ResourceLoader.load_threaded_get(path) as Mesh
		if mesh == null:
			push_error("Split GTA III OBJ did not import as a Mesh: " + path)
			continue
		if not _wanted_tiles.has(tile_name) or not _loaded_tiles.has(tile_name):
			continue
		var tile_root := _loaded_tiles[tile_name] as Node3D
		if is_collision:
			if build_mesh_collisions:
				var body := StaticBody3D.new()
				body.name = "COL1Collision"
				body.collision_layer = 1
				body.collision_mask = 1
				var collision := CollisionShape3D.new()
				collision.name = path.get_file().get_basename()
				var collision_mesh := mesh.create_trimesh_shape() as ConcavePolygonShape3D
				if collision_mesh != null:
					collision_mesh.backface_collision = true
				collision.shape = collision_mesh
				body.add_child(collision)
				tile_root.add_child(body)
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = path.get_file().get_basename()
		mesh_instance.mesh = mesh
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mesh_instance.visibility_range_end = load_radius
		_configure_alpha_materials(mesh_instance)
		tile_root.add_child(mesh_instance)

func _configure_alpha_materials(mesh_instance: MeshInstance3D) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	for surface_index: int in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		var configured_material := material
		if _ultra_low_mode:
			var material_key := material.get_instance_id()
			if not _low_material_cache.has(material_key):
				var low_material := material.duplicate() as StandardMaterial3D
				low_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				low_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				low_material.anisotropy_enabled = false
				_low_material_cache[material_key] = low_material
			configured_material = _low_material_cache[material_key] as StandardMaterial3D
		var texture := material.albedo_texture
		if texture != null and _texture_has_alpha(texture):
			configured_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			configured_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			configured_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
		if configured_material != material:
			mesh_instance.set_surface_override_material(surface_index, configured_material)

func _part_distance_to_player(path: String, source_position: Vector3) -> float:
	var bounds: Variant = _part_bounds.get(path, null)
	if not bounds is Dictionary:
		return 0.0
	var minimum: Array = (bounds as Dictionary).get("min", [source_position.x, source_position.y])
	var maximum: Array = (bounds as Dictionary).get("max", minimum)
	var dx := maxf(maxf(float(minimum[0]) - source_position.x, 0.0), source_position.x - float(maximum[0]))
	var dy := maxf(maxf(float(minimum[1]) - source_position.y, 0.0), source_position.y - float(maximum[1]))
	return Vector2(dx, dy).length()

func _texture_has_alpha(texture: Texture2D) -> bool:
	var cache_key := texture.resource_path
	if cache_key.is_empty():
		cache_key = str(texture.get_instance_id())
	if _alpha_texture_cache.has(cache_key):
		return bool(_alpha_texture_cache[cache_key])
	var image := texture.get_image()
	var has_alpha := image != null and not image.is_empty() and image.detect_alpha()
	_alpha_texture_cache[cache_key] = has_alpha
	return has_alpha

func get_loaded_tile_names() -> PackedStringArray:
	var names := PackedStringArray()
	for tile_name: String in _loaded_tiles.keys():
		names.append(tile_name)
	names.sort()
	return names

func get_pending_mesh_count() -> int:
	return _pending_paths.size()

func get_catalog_tile_count() -> int:
	return _tile_records.size()

func is_collision_tile_loaded(tile_name: String) -> bool:
	if not _loaded_tiles.has(tile_name):
		return false
	var tile_root := _loaded_tiles[tile_name] as Node3D
	var body := tile_root.get_node_or_null("COL1Collision") as StaticBody3D
	if body == null:
		return false
	for child: Node in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			return true
	return false

func sample_ground_height(position: Vector3, reference_y: float, exclude: Array[RID] = []) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var ray_exclude: Array[RID] = exclude.duplicate()
	var start := Vector3(position.x, reference_y + 1.0, position.z)
	var finish := Vector3(position.x, reference_y - 4.0, position.z)
	for _attempt in range(8):
		var query := PhysicsRayQueryParameters3D.create(start, finish, 1)
		query.exclude = ray_exclude
		query.hit_back_faces = true
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null:
			return {}
		if collider.name == "COL1Collision":
			return hit
		var collider_rid := collider.get_rid()
		if ray_exclude.has(collider_rid):
			return {}
		ray_exclude.append(collider_rid)
	return {}

func snap_body_to_map(body: CharacterBody3D) -> bool:
	if body == null or not is_collision_tile_loaded(INITIAL_SPAWN_TILE):
		return false
	# Spawn points can sit below a building roof but above the street. Starting
	# hundreds of metres above the map hits the roof/floor first and leaves the
	# character inside it. Start just above the body so the ray selects the
	# street surface below the spawn point.
	var start := body.global_position + Vector3.UP * 0.75
	var finish := body.global_position - Vector3.UP * 250.0
	var query := PhysicsRayQueryParameters3D.create(start, finish, body.collision_mask)
	query.exclude = [body.get_rid()]
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	if collider == null or collider.name != "COL1Collision":
		return false
	body.global_position.y = (hit["position"] as Vector3).y + 0.05
	body.velocity.y = 0.0
	return true
