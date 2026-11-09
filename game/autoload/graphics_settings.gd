extends Node

signal settings_changed

const SETTINGS_PATH := "user://andre3d_graphics.json"
const RENDER_DISTANCE_NAMES := ["ULTRA BAIXA", "BAIXA", "MÉDIA", "ALTA"]
const TEXTURE_QUALITY_NAMES := ["ULTRA BAIXA", "BAIXA", "MÉDIA", "ALTA"]
const RENDER_DISTANCES := [150.0, 520.0, 780.0, 1100.0]
const MAP_TILE_LIMITS := [1, 1, 2, 3]
const MESHES_PER_FRAME := [1, 2, 4, 7]
const RESOLUTION_SCALES := [0.35, 0.65, 0.82, 1.0]

var render_distance_level := 1
var texture_quality_level := 1
var resolution_level := 1
var automatic_optimization := true

var _low_fps_time := 0.0
var _stable_fps_time := 0.0
var _adjustment_cooldown := 0.0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _load_settings()
    call_deferred("apply")

func _process(delta: float) -> void:
    if get_tree().current_scene == null or get_tree().current_scene.get_node_or_null("MapStreamer") == null:
        return
    if _adjustment_cooldown > 0.0:
        _adjustment_cooldown -= delta
    if not automatic_optimization or _adjustment_cooldown > 0.0:
        return
    var fps := Engine.get_frames_per_second()
    if fps > 0 and fps < 30:
        _low_fps_time += delta
        _stable_fps_time = 0.0
        if _low_fps_time >= 2.0:
            _low_fps_time = 0.0
            _step_down()
    elif fps >= 50:
        _stable_fps_time += delta
        _low_fps_time = 0.0
        # Recupera somente um nível depois de um período estável, evitando oscilação.
        if _stable_fps_time >= 12.0:
            _stable_fps_time = 0.0
            _step_up()
    else:
        _low_fps_time = 0.0
        _stable_fps_time = 0.0

func configure(distance: int, texture_quality: int, resolution: int, auto_mode: bool) -> void:
    render_distance_level = clampi(distance, 0, 3)
    texture_quality_level = clampi(texture_quality, 0, 3)
    resolution_level = clampi(resolution, 0, 3)
    automatic_optimization = auto_mode
    _low_fps_time = 0.0
    _stable_fps_time = 0.0
    _adjustment_cooldown = 1.0
    _save_settings()
    apply()

func _step_down() -> void:
    var old_distance := render_distance_level
    var old_texture := texture_quality_level
    var old_resolution := resolution_level
    if resolution_level > 0:
        resolution_level -= 1
    elif texture_quality_level > 0:
        texture_quality_level -= 1
    elif render_distance_level > 0:
        render_distance_level -= 1
    if old_distance != render_distance_level or old_texture != texture_quality_level or old_resolution != resolution_level:
        _adjustment_cooldown = 3.0
        _save_settings()
        apply()

func _step_up() -> void:
    # A recuperação automática é conservadora e só melhora a escala primeiro.
    if resolution_level < 3:
        resolution_level += 1
    elif texture_quality_level < 3:
        texture_quality_level += 1
    elif render_distance_level < 3:
        render_distance_level += 1
    else:
        return
    _adjustment_cooldown = 6.0
    _save_settings()
    apply()

func apply() -> void:
    var viewport := get_viewport()
    if viewport != null:
        viewport.scaling_3d_scale = RESOLUTION_SCALES[resolution_level]
    var ultra_low := render_distance_level == 0
    ProjectSettings.set_setting("rendering/textures/default_filters/use_nearest_mipmap_filter", texture_quality_level <= 1)
    ProjectSettings.set_setting("rendering/quality/shading/force_vertex_shading", ultra_low)
    ProjectSettings.set_setting("rendering/occlusion_culling/use_occlusion_culling", ultra_low)
    ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0 if ultra_low else 2)
    ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 0 if ultra_low else 1)
    ProjectSettings.set_setting("rendering/environment/volumetric_fog/volume_size", 64 if ultra_low else 128)
    for camera in get_tree().get_nodes_in_group("graphics_camera"):
        if camera is Camera3D:
            (camera as Camera3D).far = RENDER_DISTANCES[render_distance_level]
    for map_node in get_tree().get_nodes_in_group("graphics_map"):
        if map_node.has_method("apply_graphics_settings"):
            map_node.call("apply_graphics_settings", render_distance_level, texture_quality_level)
    settings_changed.emit()

func get_render_distance_name() -> String:
    return RENDER_DISTANCE_NAMES[render_distance_level]

func get_texture_quality_name() -> String:
    return TEXTURE_QUALITY_NAMES[texture_quality_level]

func get_resolution_name() -> String:
    return "%d%%" % int(round(RESOLUTION_SCALES[resolution_level] * 100.0))

func _load_settings() -> void:
    if not FileAccess.file_exists(SETTINGS_PATH):
        return
    var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
    if file == null:
        return
    var data = JSON.parse_string(file.get_as_text())
    if not data is Dictionary:
        return
    render_distance_level = clampi(int(data.get("render_distance", 1)), 0, 3)
    texture_quality_level = clampi(int(data.get("texture_quality", 1)), 0, 3)
    resolution_level = clampi(int(data.get("resolution", 1)), 0, 3)
    automatic_optimization = bool(data.get("auto_optimization", true))

func _save_settings() -> void:
    var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({
            "render_distance": render_distance_level,
            "texture_quality": texture_quality_level,
            "resolution": resolution_level,
            "auto_optimization": automatic_optimization,
        }))
