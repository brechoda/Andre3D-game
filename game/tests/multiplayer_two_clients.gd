extends SceneTree

const WORLD_SCENE := "res://scenes/third_person.tscn"
const TEST_SERVER := "ws://127.0.0.1:18888/ws"
const TEST_ROOM := "GODOT_VEHICLE_TEST"

var _worlds: Array[Node3D] = []
var _session_existed := false
var _old_session_text := ""

func _initialize() -> void:
    call_deferred("_run_test")

func _run_test() -> void:
    _save_and_enable_online_session()
    for index in range(2):
        var packed := load(WORLD_SCENE) as PackedScene
        if packed == null:
            _fail("Não foi possível carregar a cena do mundo")
            return
        var world := packed.instantiate() as Node3D
        root.add_child(world)
        _worlds.append(world)
        var client := world.get_node_or_null("OnlineMultiplayer")
        if client == null:
            _fail("Cliente multiplayer não encontrado no mundo")
            return
        client.set("server_url", TEST_SERVER)
        client.set("room_code", TEST_ROOM)
        client.set("player_name", "GodotTest%d" % index)
        client.set("enabled", true)

    for world in _worlds:
        var client = world.get_node("OnlineMultiplayer")
        if not await _wait_for(func() -> bool: return not String(client.get("local_id")).is_empty(), 6.0):
            _fail("Cliente Godot não entrou na sala pelo servidor local")
            return

    if not await _test_remote_avatars_are_unarmed():
        return
    if not await _test_motorcycle_claim_and_shared_transform():
        return
    if not await _test_jump_animation_sync():
        return
    if not await _test_hilux_claim_and_shared_transform():
        return

    print("GODOT MULTIPLAYER TEST OK: 2 mundos; pulo sincronizado; moto/Hilux compartilhadas com rodas girando no observador; assentos exclusivos; sem veículos remotos duplicados")
    _finish(0)

func _test_remote_avatars_are_unarmed() -> bool:
    var first_client = _worlds[0].get_node("OnlineMultiplayer")
    var second_client = _worlds[1].get_node("OnlineMultiplayer")
    var first_id := String(first_client.get("local_id"))
    var remote := _remote_for(second_client, first_id)
    if remote == null:
        if not await _wait_for(func() -> bool: return _remote_for(second_client, first_id) != null, 3.0):
            _fail("O avatar remoto não apareceu para a checagem sem armas")
            return false
        remote = _remote_for(second_client, first_id)
    var animator := remote.get("animation_player") as AnimationPlayer
    if animator == null:
        _fail("O avatar remoto não tem AnimationPlayer")
        return false
    if remote.find_child("PistolHandAttachment", true, false) != null or remote.find_child("M4HandAttachment", true, false) != null:
        _fail("O avatar remoto não deve anexar armas")
        return false
    for world in _worlds:
        if world.get_node_or_null("HUD/Root/WeaponButton") != null or world.get_node_or_null("HUD/Root/AimButton") != null or world.get_node_or_null("HUD/Root/RifleButton") != null:
            _fail("Os botões de armas não devem existir em cada HUD multiplayer")
            return false
    return true

func _test_motorcycle_claim_and_shared_transform() -> bool:
    var first_world := _worlds[0]
    var second_world := _worlds[1]
    var first_bike := first_world.get_node("WayfarerR1200")
    var second_bike := second_world.get_node("WayfarerR1200")
    var second_client = second_world.get_node("OnlineMultiplayer")

    var first_local_player := first_world.get_node("Player") as Node3D
    first_local_player.global_position = first_bike.global_position + Vector3(0.0, 0.0, 0.5)
    first_bike.call("_start_mount")
    if not await _wait_for(func() -> bool: return bool(first_bike.call("is_riding")), 6.0):
        var first_client = first_world.get_node("OnlineMultiplayer")
        print("DIAGNOSTIC bike_near=", first_bike.call("is_near_player"), " enabled=", first_client.get("enabled"), " id=", first_client.get("local_id"), " url=", first_client.get("server_url"), " claim_results=", first_client.get("_vehicle_claim_results"), " pending=", first_bike.get("_network_mount_pending"))
        _fail("O primeiro cliente não conseguiu montar a Wayfarer via reserva do servidor")
        return false
    second_bike.call("_start_mount")
    await create_timer(0.5).timeout
    if bool(second_bike.call("is_riding")):
        _fail("O servidor permitiu dois jogadores no mesmo assento da Wayfarer")
        return false

    first_bike.global_position += Vector3(2.0, 0.0, 0.0)
    var remote_biker := _remote_for(second_client, String(_worlds[0].get_node("OnlineMultiplayer").get("local_id")))
    if not await _wait_for(func() -> bool: return _bike_sync_ready(remote_biker, first_bike, second_bike), 5.0):
        _fail("O segundo cliente não viu o piloto e a mesma instância da Wayfarer se moverem")
        return false
    if not await _wait_for(func() -> bool: return String(remote_biker.get("_vehicle_audio_mode")) == "idle", 3.0):
        _fail("O modo de áudio do veículo não foi retransmitido ao segundo cliente")
        return false
    first_bike.set("_speed", 4.0)
    first_bike.set_physics_process(false)
    if not await _wait_for(func() -> bool: return _bike_wheels_rotating(remote_biker, second_bike), 3.0):
        _fail("As rodas da Wayfarer não giraram no segundo cliente enquanto o primeiro acelerava")
        return false
    first_bike.set("_wheelie", 0.42)
    first_bike.call("_apply_lean")
    if not await _wait_for(func() -> bool: return _bike_wheelie_synced(remote_biker, second_bike), 3.0):
        _fail("A empinada da Wayfarer não apareceu no segundo cliente")
        return false

    first_bike.call("_finish_dismount")
    await create_timer(0.2).timeout
    return true

func _test_jump_animation_sync() -> bool:
    var first_world := _worlds[0]
    var second_world := _worlds[1]
    var first_player := first_world.get_node("Player")
    var second_client = second_world.get_node("OnlineMultiplayer")
    var first_client = first_world.get_node("OnlineMultiplayer")
    var remote := _remote_for(second_client, String(first_client.get("local_id")))
    if remote == null:
        _fail("O avatar remoto não existia antes do teste de pulo")
        return false
    if not await _wait_for(func() -> bool: return bool(first_player.call("is_on_floor")), 3.0):
        _fail("O jogador local não chegou ao chão para o teste de pulo")
        return false

    first_player.call("_on_jump_button_down")
    if not await _wait_for(func() -> bool: return bool(first_player.get("_jumping")), 1.0):
        _fail("O takeoff local não foi iniciado no teste de pulo")
        return false
    if not await _wait_for(func() -> bool: return _remote_is_playing_jump(remote), 1.0):
        _fail("O servidor não retransmitiu a animação JUMP_launch para o outro cliente")
        return false
    return true

func _remote_is_playing_jump(remote: Node3D) -> bool:
    var animator := remote.get("animation_player") as AnimationPlayer
    return animator != null and animator.current_animation == "JUMP_launch"

func _test_hilux_claim_and_shared_transform() -> bool:
    var first_world := _worlds[0]
    var second_world := _worlds[1]
    var first_player := first_world.get_node("Player")
    var second_player := second_world.get_node("Player")
    var first_car := first_world.get_node("HiluxSRX2017")
    var second_car := second_world.get_node("HiluxSRX2017")
    var second_client = second_world.get_node("OnlineMultiplayer")
    var first_gorece := first_world.get_node("GoreceNPC")
    var second_gorece := second_world.get_node("GoreceNPC")

    first_player.call("set_active_character", 1)
    second_player.call("set_active_character", 1)
    first_gorece.set_physics_process(false)
    second_gorece.set_physics_process(false)
    first_gorece.global_position = first_car.call("_approach_point")
    second_gorece.global_position = second_car.call("_approach_point")

    first_car.call("_start_mount")
    if not await _wait_for(func() -> bool: return bool(first_car.call("is_riding")), 6.0):
        var first_client = first_world.get_node("OnlineMultiplayer")
        print("DIAGNOSTIC hilux_near=", first_car.call("is_near_player"), " enabled=", first_client.get("enabled"), " id=", first_client.get("local_id"), " claim_results=", first_client.get("_vehicle_claim_results"), " pending=", first_car.get("_network_mount_pending"))
        _fail("O primeiro cliente não conseguiu reservar e entrar na Hilux")
        return false
    second_car.call("_start_mount")
    await create_timer(0.5).timeout
    if bool(second_car.call("is_riding")):
        _fail("O servidor permitiu dois jogadores no assento da Hilux")
        return false

    if not await _wait_for(func() -> bool: return not bool(first_car.get("_mounting")), 5.0):
        _fail("A animação de entrada na Hilux não concluiu")
        return false
    first_car.set("_speed", 5.0)
    first_car.set_physics_process(false)
    first_car.global_position += Vector3(3.0, 0.0, 0.0)
    var remote_driver := _remote_for(second_client, String(first_world.get_node("OnlineMultiplayer").get("local_id")))
    if not await _wait_for(func() -> bool: return _hilux_sync_ready(remote_driver, first_car, second_car), 5.0):
        _fail("O segundo cliente não viu o motorista sentado e a mesma Hilux se moverem")
        return false
    if not await _wait_for(func() -> bool: return _hilux_wheels_rotating(second_car), 3.0):
        _fail("As quatro rodas da Hilux não giraram no segundo cliente enquanto o primeiro acelerava")
        return false

    for child in second_world.get_children():
        if String(child.name).begins_with("RemoteVehicle"):
            _fail("Foi criado um veículo remoto duplicado")
            return false
    return true

func _remote_for(client: Node, remote_id: String) -> Node3D:
    var remotes: Dictionary = client.get("_remotes")
    return remotes.get(remote_id) as Node3D

func _bike_sync_ready(remote: Node3D, first_bike: Node3D, second_bike: Node3D) -> bool:
    if remote == null:
        return false
    var first_player := _worlds[0].get_node("Player") as Node3D
    return String(remote.get("_vehicle_id")) == "wayfarer_01" \
        and is_same(remote.get("_shared_vehicle"), second_bike) \
        and (remote.global_position - first_player.global_position).length() < 1.5 \
        and (second_bike.global_position - first_bike.global_position).length() < 0.4

func _hilux_sync_ready(remote: Node3D, first_car: Node3D, second_car: Node3D) -> bool:
    if remote == null:
        return false
    return String(remote.get("_vehicle_id")) == "hilux_01" \
        and is_same(remote.get("_shared_vehicle"), second_car) \
        and bool(remote.get("_seated_pose_ready")) \
        and (second_car.global_position - first_car.global_position).length() < 0.4

func _bike_wheels_rotating(remote: Node3D, bike: Node3D) -> bool:
    return remote != null \
        and is_same(remote.get("_shared_vehicle"), bike) \
        and absf(float(bike.get("_front_spin_angle"))) > 0.1 \
        and absf(float(bike.get("_rear_spin_angle"))) > 0.1

func _bike_wheelie_synced(remote: Node3D, bike: Node3D) -> bool:
    return remote != null \
        and is_same(remote.get("_shared_vehicle"), bike) \
        and absf(float(bike.get("_wheelie")) - 0.42) < 0.08

func _hilux_wheels_rotating(car: Node3D) -> bool:
    return absf(float(car.get("_wheel_spin"))) > 0.1 \
        and (car.get("_wheel_lf") as Node3D) != null \
        and (car.get("_wheel_rf") as Node3D) != null \
        and (car.get("_wheel_lb") as Node3D) != null \
        and (car.get("_wheel_rb") as Node3D) != null

func _wait_for(predicate: Callable, timeout_seconds: float) -> bool:
    var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
    while Time.get_ticks_msec() < deadline:
        if predicate.call():
            return true
        await process_frame
    return predicate.call()

func _save_and_enable_online_session() -> void:
    var path := "user://andre3d_session.json"
    _session_existed = FileAccess.file_exists(path)
    if _session_existed:
        var previous := FileAccess.open(path, FileAccess.READ)
        if previous != null:
            _old_session_text = previous.get_as_text()
            previous.close()
    var session := FileAccess.open(path, FileAccess.WRITE)
    session.store_string(JSON.stringify({"mode": "online", "character": "andre"}))
    session.close()

func _finish(exit_code: int) -> void:
    for world in _worlds:
        var client := world.get_node_or_null("OnlineMultiplayer")
        if client != null:
            client.set("enabled", false)
            var socket: WebSocketPeer = client.get("socket")
            if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
                socket.close()
        world.queue_free()
    if _session_existed:
        var session := FileAccess.open("user://andre3d_session.json", FileAccess.WRITE)
        session.store_string(_old_session_text)
        session.close()
    else:
        DirAccess.remove_absolute(ProjectSettings.globalize_path("user://andre3d_session.json"))
    await process_frame
    quit(exit_code)

func _fail(reason: String) -> void:
    push_error(reason)
    _finish(1)
