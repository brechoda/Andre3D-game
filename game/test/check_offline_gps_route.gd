extends SceneTree

const GPS_SCRIPT := preload("res://scripts/offline_gps_autopilot.gd")
const PLAYER_STUB_SCRIPT := preload("res://test/gps_test_player_stub.gd")
const START_SOURCE := Vector2(160.6, -58.6)
const FAR_DESTINATION_SOURCE := Vector2(567.33, 140.43)

func _initialize() -> void:
    call_deferred("_run_check")

func _run_check() -> void:
    var scene := Node3D.new()
    scene.name = "TestRoot"
    var player := Node3D.new()
    player.name = "Player"
    player.set_script(PLAYER_STUB_SCRIPT)
    scene.add_child(player)
    var map_streamer := Node3D.new()
    map_streamer.name = "MapStreamer"
    scene.add_child(map_streamer)
    var hud := CanvasLayer.new()
    hud.name = "HUD"
    scene.add_child(hud)
    var hud_root := Control.new()
    hud_root.name = "Root"
    hud.add_child(hud_root)
    root.add_child(scene)
    current_scene = scene

    var gps := Control.new()
    gps.name = "OfflineGPS"
    gps.set_script(GPS_SCRIPT)
    hud_root.add_child(gps)
    await process_frame

    if not gps.has_method("_ensure_road_graph"):
        _fail("O script do nó OfflineGPS não foi carregado.")
        return
    var graph_ok := bool(gps.call("_ensure_road_graph"))
    if not graph_ok:
        _fail("O grafo de ruas não foi carregado.")
        return
    var route: PackedVector2Array = gps.call("_build_route", START_SOURCE, FAR_DESTINATION_SOURCE)
    if route.size() < 100:
        _fail("A rota de teste ficou vazia ou curta demais: %d pontos." % route.size())
        return
    if route[0].distance_to(START_SOURCE) > 8.0:
        _fail("O início da rota não foi ajustado para uma rua próxima.")
        return
    if route[route.size() - 1].distance_to(FAR_DESTINATION_SOURCE) > 8.0:
        _fail("O destino da rota não foi ajustado para uma rua próxima.")
        return

    var path_length := 0.0
    for i in range(1, route.size()):
        path_length += route[i - 1].distance_to(route[i])
    player.set("_online_mode", true)
    gps.call("_process", 0.2)
    if bool(gps.get("visible")):
        _fail("O GPS deveria ficar oculto no modo online.")
        return
    player.set("_online_mode", false)
    gps.call("_process", 0.2)
    if not bool(gps.get("visible")):
        _fail("O GPS deveria aparecer no modo offline.")
        return

    print("PASS GPS offline: rota conectada com %d pontos, %.0f m, grid A* carregado e interface restrita ao offline." % [route.size(), path_length])
    scene.queue_free()
    quit(0)

func _fail(message: String) -> void:
    push_error("GPS CHECK FAILED: " + message)
    quit(1)
