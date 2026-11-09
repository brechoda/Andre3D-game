extends SceneTree

const GAME_SCENE_PATH := "res://scenes/third_person.tscn"
const TEST_DESTINATION := Vector2(567.33, 140.43)
const MAP_PANEL_POSITION := Vector2(8.0, 27.0)
const MAP_PANEL_SIZE := Vector2(196.0, 181.0)
const LOCAL_TILE := "comntop/comntop"

func _initialize() -> void:
    call_deferred("_run_check")

func _run_check() -> void:
    var packed := load(GAME_SCENE_PATH) as PackedScene
    if packed == null:
        _fail("Não foi possível carregar a cena de jogo.")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("A raiz da cena do jogo não é Node3D.")
        return
    root.add_child(scene)
    current_scene = scene
    var multiplayer := scene.get_node_or_null("OnlineMultiplayer")
    if multiplayer != null:
        multiplayer.set("enabled", false)
        multiplayer.set("server_url", "ws://127.0.0.1:9")

    var player := scene.get_node_or_null("Player") as Node3D
    var gorece := scene.get_node_or_null("GoreceNPC") as Node3D
    var map_streamer := scene.get_node_or_null("MapStreamer")
    var gps := scene.get_node_or_null("HUD/Root/GPSAutopilot")
    if player == null or gorece == null or map_streamer == null or gps == null:
        _fail("Faltam Player, GoreceNPC, MapStreamer ou GPSAutopilot na cena.")
        return
    player.set("_online_mode", false)
    gps.set("_scene", scene)
    gps.set("_player", player)
    gps.set("_gorece", gorece)
    gps.set("_map_streamer", map_streamer)

    var deadline := Time.get_ticks_msec() + 30000
    var map_ready := false
    while Time.get_ticks_msec() < deadline:
        var loaded: PackedStringArray = map_streamer.call("get_loaded_tile_names")
        var pending := int(map_streamer.call("get_pending_mesh_count"))
        if loaded.has("maps/overview") and loaded.has(LOCAL_TILE) and pending == 0 and bool(map_streamer.call("is_collision_tile_loaded", LOCAL_TILE)):
            map_ready = true
            break
        await process_frame
    if not map_ready:
        _fail("O tile local e as colisões não ficaram prontos em 30 s.")
        return
    await create_timer(0.3).timeout

    if not bool(gps.call("_ensure_road_graph")):
        _fail("O grafo de ruas não carregou no gameplay.")
        return
    var pop := scene.get_node("Pop100e2024") as Node3D
    var hilux := scene.get_node("HiluxSRX2017") as Node3D
    if not await _test_vehicle(gps, map_streamer, player, gorece, pop, "Pop 100", false):
        return
    if not await _test_vehicle(gps, map_streamer, player, gorece, hilux, "Hilux", true):
        return

    print("PASS autopilot motion: Pop e Hilux seguiram o destino marcado no minimapa; botão desligou o piloto e devolveu o controle manual.")
    scene.queue_free()
    quit(0)

func _test_vehicle(gps: Node, map_streamer: Node, player: Node3D, gorece: Node3D, vehicle: Node3D, vehicle_name: String, use_gorece: bool) -> bool:
    if vehicle == null or not vehicle.has_method("toggle_riding_from_universal") or not vehicle.has_method("set_autopilot_controls") or not vehicle.has_method("get_autopilot_speed"):
        _fail(vehicle_name + " não expõe o fluxo de montagem e a API de piloto automático.")
        return false
    player.call("set_active_character", 1 if use_gorece else 0)
    if use_gorece:
        var approach: Vector3 = vehicle.call("_approach_point")
        gorece.global_position = approach
    else:
        player.global_position = vehicle.global_position + vehicle.global_transform.basis.z * 1.8
    vehicle.call("toggle_riding_from_universal")
    var mount_deadline := Time.get_ticks_msec() + 10000
    while Time.get_ticks_msec() < mount_deadline:
        if bool(vehicle.get("_riding")) and not bool(vehicle.get("_mounting")) and not bool(vehicle.get("_dismounting")):
            break
        await process_frame
    if not bool(vehicle.get("_riding")) or bool(vehicle.get("_mounting")):
        _fail(vehicle_name + " não concluiu a montagem pelo fluxo normal.")
        return false

    var start_local: Vector3 = map_streamer.to_local(vehicle.global_position)
    var start_source := Vector2(start_local.x, start_local.y)
    var preview_route: PackedVector2Array = gps.call("_build_route", start_source, TEST_DESTINATION)
    if preview_route.size() < 35:
        _fail(vehicle_name + " não encontrou uma rota de teste suficientemente longa.")
        return false
    var selection_index := mini(30, preview_route.size() - 1)
    var tapped_source := preview_route[selection_index]
    var bounds: Rect2 = gps.get("_bounds")
    var uv := Vector2((tapped_source.x - bounds.position.x) / bounds.size.x, (bounds.end.y - tapped_source.y) / bounds.size.y)
    var map_click := MAP_PANEL_POSITION + uv * MAP_PANEL_SIZE
    gps.call("_mark_destination", map_click)
    var route: PackedVector2Array = gps.get("_route_path")
    if route.size() < 25 or not bool(gps.get("_has_destination")) or not bool(gps.get("_autopilot_active")):
        _fail(vehicle_name + " não iniciou uma rota ao marcar o destino no minimapa: " + String(gps.get("_status")))
        vehicle.call("toggle_riding_from_universal")
        return false
    var destination: Vector2 = gps.get("_destination")
    if destination.distance_to(tapped_source) > 8.0:
        _fail(vehicle_name + " não ajustou o ponto marcado para uma rua próxima.")
        gps.call("_on_autopilot_button_pressed")
        vehicle.call("toggle_riding_from_universal")
        return false

    var before := start_source
    var target_distance_before := before.distance_to(destination)
    var nearest_before := _nearest_path_index(before, route)
    await create_timer(6.0).timeout
    var end_local: Vector3 = map_streamer.to_local(vehicle.global_position)
    var after := Vector2(end_local.x, end_local.y)
    var moved := before.distance_to(after)
    var target_distance_after := after.distance_to(destination)
    var nearest_after := _nearest_path_index(after, route)
    var nearest_path_distance := after.distance_to(route[nearest_after]) if nearest_after >= 0 else INF
    var route_index_after := int(gps.get("_route_index"))
    var speed := absf(float(vehicle.call("get_autopilot_speed")))
    var auto_input: Vector2 = vehicle.get("_autopilot_input")
    var probe_travel := -vehicle.global_transform.basis.z * 0.2
    var blocked_now := bool(vehicle.call("_movement_blocked", probe_travel)) if vehicle.has_method("_movement_blocked") else false
    var blocker_names := _blocking_names(vehicle, probe_travel)
    var remained_active := bool(gps.get("_autopilot_active"))

    gps.call("_on_autopilot_button_pressed")
    vehicle.call("toggle_riding_from_universal")
    var dismount_deadline := Time.get_ticks_msec() + 10000
    while Time.get_ticks_msec() < dismount_deadline and bool(vehicle.get("_riding")):
        await process_frame
    if bool(gps.get("_autopilot_active")) or bool(vehicle.get("_autopilot_active")) or bool(vehicle.get("_riding")):
        _fail(vehicle_name + " não devolveu o controle manual após desligar o piloto.")
        return false
    var max_road_deviation := float(gps.get("_cell_size")) * 1.75
    if moved < 2.0 or route_index_after < 1 or nearest_path_distance > max_road_deviation or blocked_now:
        _fail("%s não seguiu a rota (mov=%.2f m, v=%.2f, waypoint=%d→%d, dist_destino=%.1f→%.1f m, dist_rota=%.1f m, input=%s, bloqueado=%s, colisores=%s, estado=%s, ativo=%s)." % [vehicle_name, moved, speed, nearest_before, nearest_after, target_distance_before, target_distance_after, nearest_path_distance, str(auto_input), str(blocked_now), str(blocker_names), String(gps.get("_status")), str(remained_active)])
        return false
    print("PASS %s: avançou %.1f m junto aos waypoints; botão desligou e desmontagem concluiu." % [vehicle_name, moved])
    return true

func _blocking_names(vehicle: Node3D, travel: Vector3) -> PackedStringArray:
    var names := PackedStringArray()
    var body := vehicle.get_node_or_null("CollisionBody") as StaticBody3D
    if body == null:
        return names
    var predicted := vehicle.global_transform
    predicted.origin += travel
    for child: Node in body.get_children():
        var collision_shape := child as CollisionShape3D
        if collision_shape == null or collision_shape.shape == null:
            continue
        var query := PhysicsShapeQueryParameters3D.new()
        query.shape = collision_shape.shape
        query.transform = predicted * collision_shape.transform
        query.collision_mask = 1
        query.exclude = [body.get_rid()]
        for hit: Dictionary in vehicle.get_world_3d().direct_space_state.intersect_shape(query, 5):
            var collider: Variant = hit.get("collider")
            var name := String(collider.get_path()) if collider is Node else str(collider)
            if not names.has(name):
                names.append(name)
    return names

func _nearest_path_index(position: Vector2, path: PackedVector2Array) -> int:
    var best_index := -1
    var best_distance := INF
    for index in range(path.size()):
        var distance := position.distance_to(path[index])
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return best_index

func _fail(message: String) -> void:
    push_error("AUTOPILOT MOTION CHECK FAILED: " + message)
    quit(1)
