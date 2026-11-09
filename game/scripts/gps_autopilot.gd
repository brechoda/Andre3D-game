extends Control

const GRID_PATH := "res://assets/maps/liberty_city/road_grid.json"
const MAP_TEXTURE_PATH := "res://assets/maps/liberty_city/road_map.png"
const MAP_RECT := Rect2(Vector2(8.0, 27.0), Vector2(196.0, 181.0))
const MAP_BUTTON_RECT := Rect2(Vector2(8.0, 214.0), Vector2(196.0, 38.0))
const STATUS_RECT := Rect2(Vector2(8.0, 255.0), Vector2(196.0, 42.0))
const GRAPH_NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
const MAX_ROUTE_SNAP_CELLS := 12

var _scene: Node
var _player: Node3D
var _gorece: Node3D
var _map_streamer: Node3D
var _map_texture: Texture2D
var _button: Button
var _status_label: Label
var _font: Font

var _grid_width := 0
var _grid_height := 0
var _cell_size := 4.0
var _bounds := Rect2()
var _map_view_bounds := Rect2()
var _map_region_label := "MAPA"
var _road_mask := PackedByteArray()
var _road_graph: AStar2D
var _graph_ready := false

var _route_path := PackedVector2Array()
var _destination := Vector2.ZERO
var _has_destination := false
var _autopilot_active := false
var _control_vehicle: Node3D
var _route_index := 0
var _stuck_time := 0.0
var _refresh_elapsed := 0.0
var _status := "Toque no mapa para marcar um destino."

func _ready() -> void:
    custom_minimum_size = Vector2(212.0, 304.0)
    mouse_filter = Control.MOUSE_FILTER_STOP
    RemoteUIConfig.register_element("hud.gps", self)
    _scene = get_tree().current_scene
    _player = _scene.get_node_or_null("Player") as Node3D if _scene != null else null
    _gorece = _scene.get_node_or_null("GoreceNPC") as Node3D if _scene != null else null
    _map_streamer = _scene.get_node_or_null("MapStreamer") as Node3D if _scene != null else null
    _map_texture = load(MAP_TEXTURE_PATH) as Texture2D
    _configure_map_view()
    _font = load("res://assets/template/fonts/Figtree-VF.subset.woff2") as Font
    _create_ui()
    _set_status(_status)
    queue_redraw()

func _configure_map_view() -> void:
    _map_view_bounds = _bounds
    if _map_streamer == null:
        return
    if _map_streamer.has_method("get_selected_region_id"):
        _map_region_label = String(_map_streamer.call("get_selected_region_id")).to_upper()
    if not _map_streamer.has_method("get_selected_spawn"):
        return
    var grid_file := FileAccess.open(GRID_PATH, FileAccess.READ)
    if grid_file == null:
        return
    var grid_data: Variant = JSON.parse_string(grid_file.get_as_text())
    if not grid_data is Dictionary or not (grid_data as Dictionary).get("bounds", {}) is Dictionary:
        return
    var grid_bounds: Dictionary = (grid_data as Dictionary).get("bounds", {})
    var min_x := float(grid_bounds.get("min_x", 0.0))
    var min_y := float(grid_bounds.get("min_y", 0.0))
    var max_x := float(grid_bounds.get("max_x", 0.0))
    var max_y := float(grid_bounds.get("max_y", 0.0))
    _bounds = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
    var spawn: Vector3 = _map_streamer.call("get_selected_spawn")
    var local_spawn := _map_streamer.to_local(spawn)
    var half_height := 600.0
    var half_width := half_height * MAP_RECT.size.x / MAP_RECT.size.y
    _map_view_bounds = Rect2(
        Vector2(local_spawn.x - half_width, local_spawn.y - half_height),
        Vector2(half_width * 2.0, half_height * 2.0)
    )

func _create_ui() -> void:
    _button = Button.new()
    _button.name = "AutopilotButton"
    _button.position = MAP_BUTTON_RECT.position
    _button.size = MAP_BUTTON_RECT.size
    _button.text = "ATIVAR PILOTO AUTOMÁTICO"
    _button.focus_mode = Control.FOCUS_NONE
    _button.add_theme_font_size_override("font_size", 13)
    _button.add_theme_color_override("font_color", Color("d9f7f4"))
    _button.add_theme_color_override("font_hover_color", Color.WHITE)
    _button.add_theme_color_override("font_pressed_color", Color("09201e"))
    if _font != null:
        _button.add_theme_font_override("font", _font)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color("123238")
    normal.border_color = Color("4b9a93")
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(8)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color("1b4b4b")
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color("55c5a8")
    _button.add_theme_stylebox_override("normal", normal)
    _button.add_theme_stylebox_override("hover", hover)
    _button.add_theme_stylebox_override("pressed", pressed)
    _button.pressed.connect(_on_autopilot_button_pressed)
    add_child(_button)
    RemoteUIConfig.register_element("hud.gps.autopilot", _button)

    _status_label = Label.new()
    _status_label.name = "GPSStatus"
    _status_label.position = STATUS_RECT.position
    _status_label.size = STATUS_RECT.size
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _status_label.add_theme_font_size_override("font_size", 11)
    _status_label.add_theme_color_override("font_color", Color("d2e8e8"))
    if _font != null:
        _status_label.add_theme_font_override("font", _font)
    _status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_status_label)
    RemoteUIConfig.register_element("hud.gps.status", _status_label)

func _process(delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        return
    # O GPS e o piloto automático funcionam no mapa local enquanto os demais
    # jogadores/veículos continuam sendo sincronizados pelo multiplayer.

    _refresh_elapsed += delta
    if _refresh_elapsed >= 0.12:
        _refresh_elapsed = 0.0
        _refresh_button_text()
        queue_redraw()

func _physics_process(delta: float) -> void:
    if not _autopilot_active:
        return
    if not is_instance_valid(_control_vehicle) or _map_streamer == null:
        _stop_autopilot("Veículo indisponível; piloto automático desligado.")
        return
    if not _control_vehicle.has_method("is_riding") or not bool(_control_vehicle.call("is_riding")):
        _stop_autopilot("Você saiu do veículo; piloto automático desligado.")
        return
    if not _control_vehicle.has_method("set_autopilot_controls"):
        _stop_autopilot("Este veículo ainda não aceita piloto automático.")
        return
    if _route_path.is_empty():
        _stop_autopilot("Não há rota válida para seguir.")
        return

    var source_pos_3d: Vector3 = _map_streamer.to_local(_control_vehicle.global_position)
    var source_pos := Vector2(source_pos_3d.x, source_pos_3d.y)
    var speed := float(_control_vehicle.call("get_autopilot_speed")) if _control_vehicle.has_method("get_autopilot_speed") else 0.0
    var speed_limit := float(_control_vehicle.call("get_autopilot_speed_limit")) if _control_vehicle.has_method("get_autopilot_speed_limit") else 12.0
    speed_limit = maxf(speed_limit, 4.0)
    var remaining := source_pos.distance_to(_route_path[_route_path.size() - 1])
    var speed_abs := absf(speed)

    if remaining <= maxf(3.4, _cell_size * 0.45) and speed_abs <= 0.5:
        _stop_autopilot("Destino alcançado.")
        return

    while _route_index < _route_path.size() - 1 and source_pos.distance_to(_route_path[_route_index]) < maxf(2.2, _cell_size * 0.55):
        _route_index += 1
    var target_index := clampi(_route_index, 0, _route_path.size() - 1)
    # A grelha representa o centro das faixas. Um lookahead longo corta as
    # esquinas e manda a moto contra prédios, por isso a aproximação é curta.
    var lookahead := clampf(5.0 + speed_abs * 0.35, _cell_size * 0.7, 12.0)
    var along_route := source_pos.distance_to(_route_path[target_index])
    while target_index < _route_path.size() - 1 and along_route < lookahead:
        along_route += _route_path[target_index].distance_to(_route_path[target_index + 1])
        target_index += 1
    var target_source := _route_path[target_index]
    var target_world: Vector3 = _map_streamer.to_global(Vector3(target_source.x, target_source.y, source_pos_3d.z))
    var offset := target_world - _control_vehicle.global_position
    offset.y = 0.0
    if offset.length_squared() < 0.0001:
        _control_vehicle.call("set_autopilot_controls", Vector2(0.0, 0.35), true)
        return
    var local_offset: Vector3 = _control_vehicle.global_transform.basis.inverse() * offset
    var turn_angle := atan2(local_offset.x, -local_offset.z)
    var steer := clampf(turn_angle * 1.08, -1.0, 1.0)

    var turn_factor := 1.0
    if absf(turn_angle) > 1.05:
        turn_factor = 0.22
    elif absf(turn_angle) > 0.62:
        turn_factor = 0.42
    var target_speed := speed_limit * 0.48 * turn_factor
    if remaining < 18.0:
        target_speed = minf(target_speed, speed_limit * 0.52 * clampf(remaining / 18.0, 0.12, 1.0))
    var throttle := 0.0
    if speed < -0.15 or speed_abs < target_speed - 0.55:
        throttle = 0.78
    elif speed_abs > target_speed + 1.1:
        throttle = -0.62
    if remaining < 3.4:
        throttle = -1.0 if speed_abs > 0.35 else 0.0

    # Travar antes do obstáculo é preferível a insistir no acelerador. A
    # própria colisão da viatura é usada como sonda, sem criar raycasts extra.
    var blocked_ahead := false
    if _control_vehicle.has_method("_movement_blocked") and speed_abs > 0.2:
        var probe_distance := clampf(1.2 + speed_abs * 0.12, 1.2, 3.0)
        var probe := -_control_vehicle.global_transform.basis.z * probe_distance
        blocked_ahead = bool(_control_vehicle.call("_movement_blocked", probe))
    if blocked_ahead:
        throttle = -0.9 if speed_abs > 0.7 else 0.12
        steer = clampf(turn_angle * 1.8, -1.0, 1.0)
        _status = "A abrandar antes do obstáculo..."

    if speed_abs < 0.18 and throttle > 0.3 and remaining > 8.0:
        _stuck_time += delta
    else:
        _stuck_time = 0.0
    if _stuck_time > 4.0:
        _stop_autopilot("Rota bloqueada; piloto automático desligado.")
        return

    _control_vehicle.call("set_autopilot_controls", Vector2(throttle, steer), true)
    _status = "Piloto automático ligado • %.0f m restantes" % remaining
    _status_label.text = _status

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("07141d", 0.94), true)
    draw_rect(Rect2(Vector2.ZERO, size), Color("4b7d83", 0.95), false, 1.4)
    draw_string(_font, Vector2(9.0, 19.0), "GPS  •  %s" % _map_region_label, HORIZONTAL_ALIGNMENT_LEFT, 194.0, 11, Color("bde1df"))
    if _map_texture != null and _bounds.size.x > 0.0 and _map_view_bounds.size.x > 0.0:
        var source_rect := Rect2(
            Vector2(
                (_map_view_bounds.position.x - _bounds.position.x) / _bounds.size.x * _map_texture.get_width(),
                (_bounds.end.y - _map_view_bounds.end.y) / _bounds.size.y * _map_texture.get_height()
            ),
            Vector2(
                _map_view_bounds.size.x / _bounds.size.x * _map_texture.get_width(),
                _map_view_bounds.size.y / _bounds.size.y * _map_texture.get_height()
            )
        )
        draw_texture_rect_region(_map_texture, MAP_RECT, source_rect)
    elif _map_texture != null:
        draw_texture_rect(_map_texture, MAP_RECT, false)
    else:
        draw_rect(MAP_RECT, Color("10252e"), true)
    draw_rect(MAP_RECT, Color("78a4a8", 0.9), false, 1.0)

    if _route_path.size() > 1:
        var route_points := PackedVector2Array()
        for source_point in _route_path:
            route_points.append(_source_to_panel(source_point))
        draw_polyline(route_points, Color("ffad4f"), 2.5, true)
    if _has_destination:
        var marker := _source_to_panel(_destination)
        draw_circle(marker, 5.0, Color("ffad4f"))
        draw_arc(marker, 8.0, 0.0, TAU, 24, Color.WHITE, 1.5, true)

    var actor := _get_map_actor()
    if actor != null and _map_streamer != null:
        var local_pos: Vector3 = _map_streamer.to_local(actor.global_position)
        var player_marker := _source_to_panel(Vector2(local_pos.x, local_pos.y))
        draw_circle(player_marker, 4.5, Color("4be5c2"))
        draw_arc(player_marker, 7.0, 0.0, TAU, 24, Color("06221d"), 1.4, true)
        var forward := -actor.global_transform.basis.z
        var ahead: Vector3 = _map_streamer.to_local(actor.global_position + forward * 7.0)
        var heading_marker := _source_to_panel(Vector2(ahead.x, ahead.y))
        draw_line(player_marker, heading_marker, Color("e6fff7"), 1.8, true)

func _gui_input(event: InputEvent) -> void:
    var local_position := Vector2.ZERO
    var pressed := false
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        pressed = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
        local_position = mouse.position
    elif event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        pressed = touch.pressed
        local_position = touch.position
    if not pressed or not MAP_RECT.has_point(local_position):
        return
    accept_event()
    _mark_destination(local_position)

func _mark_destination(local_position: Vector2) -> void:
    if _map_streamer == null:
        _set_status("Mapa indisponível.")
        return
    if not _ensure_road_graph():
        _set_status("Não foi possível carregar a rede viária do GPS.")
        return
    var uv := (local_position - MAP_RECT.position) / MAP_RECT.size
    var source_click := Vector2(
        lerpf(_map_view_bounds.position.x, _map_view_bounds.end.x, uv.x),
        lerpf(_map_view_bounds.end.y, _map_view_bounds.position.y, uv.y)
    )
    var destination_id := _nearest_road_id(source_click)
    if destination_id < 0:
        _set_status("Não encontrei uma rua perto desse ponto.")
        return
    _destination = _road_graph.get_point_position(destination_id)
    _has_destination = true

    var actor := _get_map_actor()
    if actor == null:
        _route_path = PackedVector2Array()
        _set_status("Destino marcado. Selecione um personagem ou veículo.")
        queue_redraw()
        return
    var actor_local: Vector3 = _map_streamer.to_local(actor.global_position)
    var new_path := _build_route(Vector2(actor_local.x, actor_local.y), _destination)
    if new_path.is_empty():
        _route_path = PackedVector2Array()
        _set_status("Não há rota conectada até esse destino.")
        queue_redraw()
        return
    _route_path = new_path
    _route_index = 0
    var vehicle := _get_active_vehicle()
    if vehicle != null:
        _start_autopilot(vehicle)
    else:
        _set_status("Destino marcado. Entre em um veículo e toque no botão.")
    queue_redraw()

func _ensure_road_graph() -> bool:
    if _graph_ready:
        return _road_graph != null
    var file := FileAccess.open(GRID_PATH, FileAccess.READ)
    if file == null:
        push_warning("GPS grid não encontrado: " + GRID_PATH)
        return false
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        return false
    var data := parsed as Dictionary
    _grid_width = int(data.get("width", 0))
    _grid_height = int(data.get("height", 0))
    _cell_size = float(data.get("cell_size", 4.0))
    var bounds: Variant = data.get("bounds", {})
    if _grid_width <= 0 or _grid_height <= 0 or not bounds is Dictionary:
        return false
    var min_x := float(bounds.get("min_x", 0.0))
    var min_y := float(bounds.get("min_y", 0.0))
    var max_x := float(bounds.get("max_x", 0.0))
    var max_y := float(bounds.get("max_y", 0.0))
    _bounds = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
    var encoded := Marshalls.base64_to_raw(String(data.get("mask_zlib_base64", "")))
    _road_mask = encoded.decompress(_grid_width * _grid_height, FileAccess.COMPRESSION_DEFLATE)
    if _road_mask.size() != _grid_width * _grid_height:
        push_warning("GPS grid possui tamanho inválido.")
        return false

    _road_graph = AStar2D.new()
    for index in range(_road_mask.size()):
        if _road_mask[index] == 0:
            continue
        var cell_x := index % _grid_width
        var cell_y := int(index / _grid_width)
        var source_x := min_x + (float(cell_x) + 0.5) * _cell_size
        var source_y := max_y - (float(cell_y) + 0.5) * _cell_size
        _road_graph.add_point(index, Vector2(source_x, source_y))

    for index in range(_road_mask.size()):
        if _road_mask[index] == 0:
            continue
        var x := index % _grid_width
        var y := int(index / _grid_width)
        for step in GRAPH_NEIGHBORS:
            var nx: int = x + step.x
            var ny: int = y + step.y
            if nx < 0 or nx >= _grid_width or ny < 0 or ny >= _grid_height:
                continue
            var neighbor_id: int = ny * _grid_width + nx
            if _road_mask[neighbor_id] == 0:
                continue
            if step.x != 0 and step.y != 0:
                var side_a: int = y * _grid_width + nx
                var side_b: int = ny * _grid_width + x
                if _road_mask[side_a] == 0 and _road_mask[side_b] == 0:
                    continue
            _road_graph.connect_points(index, neighbor_id, true)
    _graph_ready = true
    return true

func _nearest_road_id(source_position: Vector2) -> int:
    if _road_mask.is_empty():
        return -1
    var min_x := _bounds.position.x
    var max_y := _bounds.end.y
    var base_x := clampi(int((source_position.x - min_x) / _cell_size), 0, _grid_width - 1)
    var base_y := clampi(int((max_y - source_position.y) / _cell_size), 0, _grid_height - 1)
    var best_id := -1
    var best_distance := INF
    for radius in range(MAX_ROUTE_SNAP_CELLS + 1):
        for y in range(maxi(0, base_y - radius), mini(_grid_height, base_y + radius + 1)):
            for x in range(maxi(0, base_x - radius), mini(_grid_width, base_x + radius + 1)):
                if maxi(abs(x - base_x), abs(y - base_y)) != radius:
                    continue
                var index := y * _grid_width + x
                if _road_mask[index] == 0:
                    continue
                var point := _road_graph.get_point_position(index)
                var distance := source_position.distance_to(point)
                if distance < best_distance:
                    best_distance = distance
                    best_id = index
        if best_id >= 0:
            return best_id
    return -1

func _build_route(start_source: Vector2, destination_source: Vector2) -> PackedVector2Array:
    if not _ensure_road_graph():
        return PackedVector2Array()
    var start_id := _nearest_road_id(start_source)
    var destination_id := _nearest_road_id(destination_source)
    if start_id < 0 or destination_id < 0:
        return PackedVector2Array()
    return _road_graph.get_point_path(start_id, destination_id)

func _start_autopilot(vehicle: Node3D) -> void:
    if vehicle == null or not is_instance_valid(vehicle):
        _set_status("Entre em um veículo para usar o piloto automático.")
        return
    if not vehicle.has_method("set_autopilot_controls"):
        _set_status("Este veículo ainda não aceita piloto automático.")
        return
    var local_pos: Vector3 = _map_streamer.to_local(vehicle.global_position)
    var new_path := _build_route(Vector2(local_pos.x, local_pos.y), _destination)
    if new_path.is_empty():
        _set_status("Não há rota conectada do veículo até o destino.")
        return
    _route_path = new_path
    _route_index = 0
    _control_vehicle = vehicle
    _autopilot_active = true
    _stuck_time = 0.0
    _set_status("Piloto automático ligado.")
    _refresh_button_text()
    queue_redraw()

func _on_autopilot_button_pressed() -> void:
    if _autopilot_active:
        _stop_autopilot("Piloto automático desligado; controle manual liberado.")
        return
    if not _has_destination:
        _set_status("Toque no mapa para marcar um destino.")
        return
    var vehicle := _get_active_vehicle()
    if vehicle == null:
        _set_status("Entre em uma moto ou na Hilux para ativar o piloto.")
        return
    _start_autopilot(vehicle)

func _stop_autopilot(message: String) -> void:
    if is_instance_valid(_control_vehicle) and _control_vehicle.has_method("set_autopilot_controls"):
        _control_vehicle.call("set_autopilot_controls", Vector2.ZERO, false)
    _control_vehicle = null
    _autopilot_active = false
    _stuck_time = 0.0
    if not message.is_empty():
        _set_status(message)
    _refresh_button_text()
    queue_redraw()

func _get_active_vehicle() -> Node3D:
    if _scene == null:
        return null
    var hilux := _scene.get_node_or_null("HiluxSRX2017") as Node3D
    if hilux != null and hilux.has_method("is_riding") and bool(hilux.call("is_riding")):
        return hilux
    for vehicle_name in ["Pop100e2024", "WayfarerR1200"]:
        var vehicle := _scene.get_node_or_null(String(vehicle_name)) as Node3D
        if vehicle == null or not vehicle.has_method("is_riding") or not bool(vehicle.call("is_riding")):
            continue
        if vehicle.has_method("is_ai_following") and bool(vehicle.call("is_ai_following")):
            continue
        return vehicle
    return null

func _get_map_actor() -> Node3D:
    var vehicle := _get_active_vehicle()
    if vehicle != null:
        return vehicle
    if _player == null:
        return null
    var active_character := 0
    var raw_active_character: Variant = _player.get("_active_character")
    if raw_active_character != null:
        active_character = int(raw_active_character)
    if active_character == 1 and _gorece != null:
        return _gorece
    return _player

func _source_to_panel(source_position: Vector2) -> Vector2:
    if _map_view_bounds.size.x <= 0.0 or _map_view_bounds.size.y <= 0.0:
        return MAP_RECT.position
    var u := (source_position.x - _map_view_bounds.position.x) / _map_view_bounds.size.x
    var v := (_map_view_bounds.end.y - source_position.y) / _map_view_bounds.size.y
    return MAP_RECT.position + Vector2(u * MAP_RECT.size.x, v * MAP_RECT.size.y)

func _refresh_button_text() -> void:
    if _button == null:
        return
    _button.text = "PARAR PILOTO AUTOMÁTICO" if _autopilot_active else "ATIVAR PILOTO AUTOMÁTICO"
    _button.disabled = _get_active_vehicle() == null

func _set_status(message: String) -> void:
    _status = message
    if _status_label != null:
        _status_label.text = message
