extends Node
class_name AndreMultiplayerClient

const REMOTE_AVATAR_SCENE := preload("res://scenes/remote_avatar.tscn")
const BUILD := "andre3d-mp-v4"
const CONFIG_PATH := "res://config/multiplayer.json"
const SEND_INTERVAL := 1.0 / 20.0
const PING_INTERVAL := 1.0
const CONNECT_TIMEOUT_MS := 70000
const RECONNECT_DELAY := 5.0
const REMOTE_SCENE_PATH := "res://assets/models/andre_armed_biked.glb"
const REMOTE_GORECE_SCENE_PATH := "res://assets/models/gorece_rigged.glb"
const REMOTE_DG_SCENE_PATH := "res://assets/models/dg_rigged.glb"
const MELEE_REACH := 1.65
const ATTACK_ANIMATIONS := ["FightA_1", "FightA_2", "FightA_3"]

var socket := WebSocketPeer.new()
var server_url := ""
var room_code := "ANDRE3D"
var player_name := "Jogador"
var character := "andre"
var enabled := false
var local_id := ""
var _send_elapsed := 0.0
var _ping_elapsed := 0.0
var _ping_ms := -1
var _state_sequence := 0
var _jump_sequence := 0
var _status_text := ""
var _remotes: Dictionary = {}
var _vehicle_claim_results: Dictionary = {}
var _status_label: Label
var _fps_label: Label
var _coordinates_label: Label
var _fps_elapsed := 0.0
var _remote_scene: PackedScene
var _remote_gorece_scene: PackedScene
var _remote_dg_scene: PackedScene
var _connecting := false
var _reconnect_scheduled := false

func _ready() -> void:
    _load_config()
    if not enabled:
        return
    _remote_scene = load(REMOTE_SCENE_PATH) as PackedScene
    _remote_gorece_scene = load(REMOTE_GORECE_SCENE_PATH) as PackedScene
    _remote_dg_scene = load(REMOTE_DG_SCENE_PATH) as PackedScene
    _status_label = _create_status_label()
    if not VoiceChat.voice_frame.is_connected(_on_voice_frame):
        VoiceChat.voice_frame.connect(_on_voice_frame)
    VoiceChat.start()
    call_deferred("_connect_to_server")

func _process(delta: float) -> void:
    if not enabled:
        return
    VoiceChat.set_listener_position(_get_tracked_position())
    _fps_elapsed += delta
    if _fps_elapsed >= 0.25:
        _fps_elapsed = 0.0
        _refresh_fps_label()
    socket.poll()
    if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        _send_elapsed += delta
        _ping_elapsed += delta
        if _send_elapsed >= SEND_INTERVAL:
            _send_elapsed = fmod(_send_elapsed, SEND_INTERVAL)
            _send_local_state()
        if _ping_elapsed >= PING_INTERVAL:
            _ping_elapsed = 0.0
            _send({"type": "ping", "sent_at": Time.get_ticks_msec()})
        while socket.get_available_packet_count() > 0:
            _handle_message(socket.get_packet().get_string_from_utf8())
    elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and not _connecting:
        _set_status("Multiplayer: desconectado; tentando reconectar...")
        _schedule_reconnect()

func _load_config() -> void:
    if not FileAccess.file_exists(CONFIG_PATH):
        return
    var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
    if file == null:
        return
    var data = JSON.parse_string(file.get_as_text())
    if typeof(data) != TYPE_DICTIONARY:
        return
    enabled = bool(data.get("enabled", false))
    server_url = String(data.get("server_url", ""))
    room_code = String(data.get("room", "ANDRE3D")).to_upper()
    player_name = String(data.get("player_name", "Jogador"))
    character = String(data.get("character", "andre"))
    if FileAccess.file_exists("user://andre3d_session.json"):
        var session_file := FileAccess.open("user://andre3d_session.json", FileAccess.READ)
        if session_file != null:
            var session = JSON.parse_string(session_file.get_as_text())
            if typeof(session) == TYPE_DICTIONARY:
                enabled = true
                character = String(session.get("character", character))
    if server_url.is_empty():
        enabled = false

func _connect_to_server() -> void:
    if _connecting or socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        return
    _connecting = true
    _set_status("Multiplayer: conectando...")
    socket = WebSocketPeer.new()
    var error := socket.connect_to_url(server_url)
    if error != OK:
        _connecting = false
        _set_status("Multiplayer: erro de conexão")
        _schedule_reconnect()
        return
    var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
    while socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() < deadline:
        socket.poll()
        await get_tree().process_frame
    _connecting = false
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        _set_status("Multiplayer: aguardando servidor...")
        _schedule_reconnect()
        return
    _send({
        "type": "join",
        "build": BUILD,
        "app_version": ProjectSettings.get_setting("application/config/version", "0.0.0"),
        "room": room_code,
        "name": player_name,
        "character": character,
    })

func _schedule_reconnect() -> void:
    if _reconnect_scheduled or not enabled:
        return
    _reconnect_scheduled = true
    await get_tree().create_timer(RECONNECT_DELAY).timeout
    _reconnect_scheduled = false
    if enabled and socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        _connect_to_server()

func _send_local_state() -> void:
    var player := get_parent().get_node_or_null("Player") as Node3D
    var player_controller := player
    if player != null and player.has_method("get_network_avatar"):
        player = player.call("get_network_avatar") as Node3D
    if player == null:
        return
    if player_controller != null and player_controller.has_method("get_network_character_id"):
        character = String(player_controller.call("get_network_character_id"))
    elif player_controller != null and player_controller.has_method("is_gorece_active"):
        character = "gorece" if bool(player_controller.call("is_gorece_active")) else "andre"
    # A orientação de gameplay fica no visual do personagem, não no
    # CharacterBody3D raiz. Enviar a rotação do raiz fazia o remoto receber
    # quase sempre 0 rad e caminhar de costas para a direção real.
    var avatar_rotation := player.global_rotation.y
    var avatar_visual := player.get("visual") as Node3D
    if avatar_visual != null:
        avatar_rotation = avatar_visual.global_rotation.y
    var movement_velocity := Vector3.ZERO
    if player is CharacterBody3D:
        movement_velocity = (player as CharacterBody3D).velocity
    var vehicle_state := _local_vehicle_state()
    if bool(vehicle_state.get("riding", false)):
        movement_velocity = Vector3(
            float(vehicle_state.get("vx", 0.0)),
            float(vehicle_state.get("vy", 0.0)),
            float(vehicle_state.get("vz", 0.0))
        )
    var running := false
    if not bool(vehicle_state.get("riding", false)) and player_controller != null:
        if player_controller.has_method("is_gorece_active") and bool(player_controller.call("is_gorece_active")):
            var gorece := player_controller.get("gorece") as Node
            running = gorece != null and bool(gorece.get("running"))
        else:
            running = bool(player_controller.get("_running"))
    _state_sequence += 1
    _send({
        "type": "state",
        "seq": _state_sequence,
        "x": player.global_position.x,
        "y": player.global_position.y,
        "z": player.global_position.z,
        "ry": avatar_rotation,
        "vx": movement_velocity.x,
        "vy": movement_velocity.y,
        "vz": movement_velocity.z,
        "running": running,
        "latency_ms": maxi(0, _ping_ms / 2),
        "vehicle": vehicle_state.get("vehicle", "on_foot"),
        "vehicle_id": vehicle_state.get("vehicle_id", ""),
        "riding": vehicle_state.get("riding", false),
        "vehicle_x": vehicle_state.get("x", player.global_position.x),
        "vehicle_y": vehicle_state.get("y", player.global_position.y),
        "vehicle_z": vehicle_state.get("z", player.global_position.z),
        "vehicle_ry": vehicle_state.get("ry", avatar_rotation),
        "vehicle_vx": vehicle_state.get("vx", 0.0),
        "vehicle_vy": vehicle_state.get("vy", 0.0),
        "vehicle_vz": vehicle_state.get("vz", 0.0),
        "vehicle_audio": vehicle_state.get("audio", "off"),
        "vehicle_wheelie": vehicle_state.get("wheelie", 0.0),
        "character": character,
    })

func _local_vehicle_state() -> Dictionary:
    for node in get_parent().get_children():
        if not node.has_method("is_riding") or not bool(node.call("is_riding")):
            continue
        var vehicle_type := "vehicle"
        var vehicle_id := String(node.get("network_vehicle_id"))
        if node.name == "Pop100e2024":
            vehicle_type = "pop100"
            if vehicle_id.is_empty(): vehicle_id = "pop100_01"
        elif node.name == "WayfarerR1200":
            vehicle_type = "wayfarer"
            if vehicle_id.is_empty(): vehicle_id = "wayfarer_01"
        elif node.name == "HiluxSRX2017":
            vehicle_type = "hilux"
            if vehicle_id.is_empty(): vehicle_id = "hilux_01"
        var vehicle_node := node as Node3D
        var vehicle_speed := float(node.get("_speed"))
        var vehicle_velocity: Vector3 = -vehicle_node.global_transform.basis.z * vehicle_speed
        var vehicle_audio := String(node.call("get_network_audio_mode")) if node.has_method("get_network_audio_mode") else "off"
        var vehicle_wheelie := float(node.call("get_network_wheelie")) if node.has_method("get_network_wheelie") else 0.0
        return {
            "vehicle": vehicle_type,
            "vehicle_id": vehicle_id,
            "riding": true,
            "x": node.global_position.x,
            "y": node.global_position.y,
            "z": node.global_position.z,
            "ry": node.global_rotation.y,
            "vx": vehicle_velocity.x,
            "vy": vehicle_velocity.y,
            "vz": vehicle_velocity.z,
            "audio": vehicle_audio,
            "wheelie": vehicle_wheelie,
        }
    return {"vehicle": "on_foot", "vehicle_id": "", "riding": false}

func request_vehicle_claim(vehicle_id: String) -> bool:
    if not enabled:
        return true
    if vehicle_id.is_empty() or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        _set_status("Multiplayer: veículo indisponível para montar")
        return false
    _vehicle_claim_results.erase(vehicle_id)
    _vehicle_claim_results[vehicle_id] = null
    _send({"type": "vehicle_claim", "vehicle_id": vehicle_id})
    var deadline := Time.get_ticks_msec() + 5000
    while Time.get_ticks_msec() < deadline:
        var response: Variant = _vehicle_claim_results.get(vehicle_id, null)
        if response is Dictionary:
            _vehicle_claim_results.erase(vehicle_id)
            return bool(response.get("granted", false))
        await get_tree().process_frame
    _vehicle_claim_results.erase(vehicle_id)
    _send({"type": "vehicle_release", "vehicle_id": vehicle_id})
    _set_status("Multiplayer: sem resposta ao solicitar o veículo")
    return false

func release_vehicle(vehicle_id: String) -> void:
    if not vehicle_id.is_empty() and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        _send({"type": "vehicle_release", "vehicle_id": vehicle_id})
    _vehicle_claim_results.erase(vehicle_id)

func send_jump_event() -> void:
    if not enabled or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    _jump_sequence += 1
    _send({"type": "jump", "seq": _jump_sequence})

func _send(message: Dictionary) -> void:
    if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        socket.send_text(JSON.stringify(message))

func send_combat_event(action: String, animation_name: String = "", target_id: String = "") -> void:
    if not enabled or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    if action == "attack" and animation_name not in ATTACK_ANIMATIONS:
        return
    if action == "hit" and target_id.is_empty():
        return
    if action not in ["attack", "hit"]:
        return
    _send({
        "type": "combat",
        "action": action,
        "animation": animation_name,
        "target_id": target_id,
    })

func find_remote_target(attacker: Node3D) -> String:
    if attacker == null:
        return ""
    var attacker_visual := attacker.get("visual") as Node3D
    if attacker_visual == null:
        return ""
    var forward := -attacker_visual.global_transform.basis.z
    forward.y = 0.0
    if forward.length_squared() < 0.001:
        return ""
    forward = forward.normalized()
    var best_id := ""
    var best_distance := MELEE_REACH
    for remote_id in _remotes:
        var remote := _remotes[remote_id] as Node3D
        if remote == null:
            continue
        var toward := remote.global_position - attacker.global_position
        toward.y = 0.0
        var distance := toward.length()
        if distance < 0.05 or distance > best_distance:
            continue
        if forward.dot(toward / distance) < 0.25:
            continue
        best_distance = distance
        best_id = String(remote_id)
    return best_id

func _handle_message(text: String) -> void:
    var message = JSON.parse_string(text)
    if typeof(message) != TYPE_DICTIONARY:
        return
    match String(message.get("type", "")):
        "welcome":
            local_id = String(message.get("id", ""))
            _set_status("Sala %s: conectado" % String(message.get("room", room_code)))
            for player in message.get("players", []):
                _upsert_remote(player)
        "player_joined":
            _upsert_remote(message.get("player", {}))
        "player_left":
            _remove_remote(String(message.get("id", "")))
        "snapshot":
            for player in message.get("players", []):
                if String(player.get("id", "")) != local_id:
                    _upsert_remote(player)
        "combat":
            _handle_combat(message)
        "voice":
            var voice_id := String(message.get("id", ""))
            if voice_id != local_id:
                VoiceChat.play_remote_voice(
                    voice_id,
                    String(message.get("data", "")),
                    Vector3(float(message.get("x", 0.0)), float(message.get("y", 0.0)), float(message.get("z", 0.0)))
                )
        "jump":
            var remote_id := String(message.get("id", ""))
            var remote: Node = _remotes.get(remote_id)
            if remote != null and remote.has_method("play_jump_animation"):
                remote.call("play_jump_animation", int(message.get("seq", 0)))
        "vehicle_claim_result":
            var vehicle_id := String(message.get("vehicle_id", ""))
            if not vehicle_id.is_empty():
                _vehicle_claim_results[vehicle_id] = message
            if bool(message.get("granted", false)):
                _set_status("Veículo reservado para você")
            else:
                _set_status("Veículo ocupado por outro jogador")
        "pong":
            var sent_at := int(message.get("sent_at", 0))
            if sent_at > 0:
                _ping_ms = maxi(0, Time.get_ticks_msec() - sent_at)
                _refresh_status_label()
        "error":
            _set_status("Multiplayer: " + String(message.get("code", "erro")))

func _handle_combat(message: Dictionary) -> void:
    var attacker_id := String(message.get("attacker_id", ""))
    var action := String(message.get("action", ""))
    # O servidor também envia o impacto ao atacante para que ele veja o
    # avatar remoto reagir. O ataque local já foi animado imediatamente, mas
    # o evento "hit" ainda precisa ser processado neste cliente.
    if attacker_id.is_empty() or (attacker_id == local_id and action != "hit"):
        return
    var attacker_position := Vector3(
        float(message.get("x", 0.0)),
        float(message.get("y", 0.0)),
        float(message.get("z", 0.0))
    )
    var attacker: Node = _remotes.get(attacker_id)
    if action == "attack":
        if attacker != null and attacker.has_method("play_combat_animation"):
            attacker.call("play_combat_animation", String(message.get("animation", "")))
    elif action == "hit":
        var target_id := String(message.get("target_id", ""))
        if target_id == local_id:
            var local_player := get_parent().get_node_or_null("Player")
            if local_player != null and local_player.has_method("receive_network_punch"):
                local_player.call("receive_network_punch", attacker_position)
        else:
            var victim: Node = _remotes.get(target_id)
            if victim != null and victim.has_method("play_hit_reaction"):
                victim.call("play_hit_reaction", attacker_position)

func _upsert_remote(data: Dictionary) -> void:
    var remote_id := String(data.get("id", ""))
    if remote_id.is_empty() or remote_id == local_id:
        return
    var remote: Node3D = _remotes.get(remote_id)
    var requested_character := String(data.get("character", "andre"))
    var remote_character := requested_character if requested_character in ["andre", "gorece", "dg"] else "andre"
    if remote == null:
        remote = REMOTE_AVATAR_SCENE.instantiate() as Node3D
        remote.name = "RemotePlayer_" + remote_id
        get_parent().add_child(remote)
        _remotes[remote_id] = remote
    if remote.get("visual") == null or String(remote.get("character")) != remote_character:
        var remote_scene := _remote_gorece_scene if remote_character == "gorece" else (_remote_dg_scene if remote_character == "dg" else _remote_scene)
        if remote_scene != null:
            remote.call("setup", remote_scene.instantiate(), remote_character)
    var remote_position := Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
    if remote.has_method("apply_state"):
        var vehicle_position := Vector3(
            float(data.get("vehicle_x", remote_position.x)),
            float(data.get("vehicle_y", remote_position.y)),
            float(data.get("vehicle_z", remote_position.z))
        )
        var remote_velocity := Vector3(
            float(data.get("vx", 0.0)),
            float(data.get("vy", 0.0)),
            float(data.get("vz", 0.0))
        )
        var remote_vehicle_velocity := Vector3(
            float(data.get("vehicle_vx", 0.0)),
            float(data.get("vehicle_vy", 0.0)),
            float(data.get("vehicle_vz", 0.0))
        )
        var sender_latency_ms := maxf(0.0, float(data.get("latency_ms", 0.0)))
        var receiver_latency_ms := maxf(0.0, float(_ping_ms)) * 0.5
        var estimated_age := clampf((sender_latency_ms + receiver_latency_ms) / 1000.0, 0.0, 0.2)
        remote.call(
            "apply_state",
            remote_position,
            float(data.get("ry", 0.0)),
            String(data.get("vehicle", "on_foot")),
            bool(data.get("riding", false)),
            vehicle_position,
            float(data.get("vehicle_ry", data.get("ry", 0.0))),
            String(data.get("vehicle_id", "")),
            int(data.get("seq", 0)),
            remote_velocity,
            remote_vehicle_velocity,
            String(data.get("vehicle_audio", "off")),
            estimated_age,
            bool(data.get("running", false)),
            float(data.get("vehicle_wheelie", 0.0))
        )
    else:
        remote.global_position = remote_position
        remote.global_rotation.y = float(data.get("ry", 0.0))

func _remove_remote(remote_id: String) -> void:
    VoiceChat.remove_remote(remote_id)
    var remote: Node3D = _remotes.get(remote_id)
    if remote != null:
        remote.queue_free()
        _remotes.erase(remote_id)

func _on_voice_frame(encoded: String) -> void:
    if not enabled or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    _send({"type": "voice", "data": encoded})

func _create_status_label() -> Label:
    var hud := get_parent().get_node_or_null("HUD/Root") as Control
    if hud == null:
        return null
    var stack := VBoxContainer.new()
    stack.name = "NetworkPerformanceStatus"
    stack.position = Vector2(24, 92)
    stack.add_theme_constant_override("separation", 2)
    hud.add_child(stack)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    stack.add_child(row)
    var label := Label.new()
    label.name = "MultiplayerStatus"
    label.add_theme_font_size_override("font_size", 16)
    row.add_child(label)
    _fps_label = Label.new()
    _fps_label.name = "FPSCounter"
    _fps_label.add_theme_font_size_override("font_size", 16)
    row.add_child(_fps_label)
    _coordinates_label = Label.new()
    _coordinates_label.name = "WorldCoordinates"
    _coordinates_label.add_theme_font_size_override("font_size", 14)
    _coordinates_label.add_theme_color_override("font_color", Color("9bd8e8"))
    stack.add_child(_coordinates_label)
    _refresh_fps_label()
    return label

func _refresh_fps_label() -> void:
    if _fps_label == null:
        return
    var fps := int(round(Engine.get_frames_per_second()))
    _fps_label.text = "FPS: %d" % fps
    _fps_label.add_theme_color_override("font_color", Color("ff5c5c") if fps < 25 else Color("62e886"))
    if _coordinates_label != null:
        var tracked := _get_tracked_position()
        _coordinates_label.text = "X: %.2f  Y: %.2f" % [tracked.x, tracked.y]

func _get_tracked_position() -> Vector3:
    var scene_root := get_parent()
    if scene_root == null:
        return Vector3.ZERO
    # Durante a pilotagem, o veículo é o objeto que realmente se desloca.
    for child: Node in scene_root.get_children():
        if child.has_method("is_riding") and bool(child.call("is_riding")) and child is Node3D:
            return (child as Node3D).global_position
    var player := scene_root.get_node_or_null("Player") as Node3D
    return player.global_position if player != null else Vector3.ZERO

func _set_status(text: String) -> void:
    _status_text = text
    _refresh_status_label()

func _refresh_status_label() -> void:
    if _status_label != null:
        if _ping_ms >= 0 and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
            _status_label.text = "%s  •  ping: %d ms" % [_status_text, _ping_ms]
        else:
            _status_label.text = _status_text
