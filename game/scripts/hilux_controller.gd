extends Node3D
class_name HiluxController

const MOUNT_INTERACTION_DISTANCE := 3.0
const MAX_SPEED := 16.5
const REVERSE_SPEED := 4.5
const ACCELERATION := 7.0
const BRAKING := 22.0
const DRAG := 2.2
const WHEELBASE := 2.85
const MAX_STEERING_ANGLE := 0.52
const STEER_RESPONSE := 5.5
const BODY_ROLL := 0.045
# Quadril (pelve) do motorista sentado e pontos da rota de entrada, em coordenadas do carro.
const SEAT_HIP := Vector3(-0.38, 0.14, -0.10)
const DOOR_THRESHOLD_HIP := Vector3(-0.95, 0.22, -0.22)
const DOOR_APPROACH := Vector3(-1.45, 0.0, -0.30) # ponto no chão ao lado da porta (x, z locais)
const MIN_SIDE_X := -1.0 # precisa estar do lado esquerdo do carro para entrar
const STANDING_HIP_HEIGHT := 0.98
const WALK_TO_DOOR_SPEED := 3.0
const SLIDE_IN_SECONDS := 0.9
const DOOR_SECONDS := 0.42
const DOOR_OPEN_ANGLE := deg_to_rad(-58.0)
const HIDDEN_WHILE_DRIVING := ["TouchJoystick", "GasButton", "BrakeButton", "SteerLeftButton", "SteerRightButton", "RunButton", "CrouchButton", "JumpButton", "ActionButton", "SwitchButton"]

@export var vehicle_display_name := "HILUX SRX 2017"
@export var network_vehicle_id := "hilux_01"
@export var drive_button_path: NodePath = NodePath("../HUD/Root/RideButton")

@onready var _gorece: GoreceNpc = get_node_or_null("../GoreceNPC") as GoreceNpc
@onready var _andre: CharacterBody3D = get_node_or_null("../Player") as CharacterBody3D
@onready var _ride_button: Button = get_node_or_null(drive_button_path) as Button
@onready var _hud: Control = get_node_or_null("../HUD/Root") as Control
@onready var _visual: Node3D = get_node_or_null("HiluxVisual") as Node3D

var _door: Node3D
var _door_base_rotation := Vector3.ZERO
var _speed := 0.0
var _riding := false
var _network_mount_pending := false
var _mounting := false
var _dismounting := false
var _door_open := false
var _door_tween: Tween
var _steering := 0.0
var _autopilot_input := Vector2.ZERO
var _autopilot_active := false
var _visual_base_rotation := Vector3.ZERO
var _wheel_lf: Node3D
var _wheel_rf: Node3D
var _wheel_lb: Node3D
var _wheel_rb: Node3D
var _wheel_base_rotations: Dictionary = {}
var _wheel_spin := 0.0
var _engine_audio: AudioStreamPlayer3D
var _network_audio_mode := "off"
var _ground_y := 0.0
var _wheel_ground_offset := 0.0
const WHEEL_RADIUS := 0.40
const DRIVE_BUTTON_SIDE := 120.0

func _ready() -> void:
    _door = _find_part(_visual if _visual != null else self, "door_lf_ok")
    if _door == null:
        _door = _find_part(_visual if _visual != null else self, "door_lf")
    if _door != null:
        _door_base_rotation = _door.rotation
    if _visual != null:
        _visual_base_rotation = _visual.rotation
    _wheel_lf = _find_part(_visual if _visual != null else self, "wheel_lf")
    _wheel_rf = _find_part(_visual if _visual != null else self, "wheel_rf")
    _wheel_lb = _find_part(_visual if _visual != null else self, "wheel_lb")
    _wheel_rb = _find_part(_visual if _visual != null else self, "wheel_rb")
    for wheel in [_wheel_lf, _wheel_rf, _wheel_lb, _wheel_rb]:
        if wheel != null:
            _wheel_base_rotations[wheel] = wheel.rotation
    var lowest_wheel_bottom := INF
    for wheel in [_wheel_lf, _wheel_rf, _wheel_lb, _wheel_rb]:
        if wheel != null:
            lowest_wheel_bottom = minf(lowest_wheel_bottom, to_local(wheel.global_position).y - WHEEL_RADIUS)
    if lowest_wheel_bottom != INF:
        _wheel_ground_offset = lowest_wheel_bottom
    _ground_y = global_position.y + _wheel_ground_offset
    call_deferred("_setup_engine_audio")
    _ensure_drive_buttons()
    _set_drive_buttons_visible(false)
    _update_ride_button()

func _load_hilux_engine_stream() -> AudioStreamWAV:
    # O áudio é intencionalmente local e próprio da Hilux. Não depender do
    # atualizador remoto evita que o APK fique sem som quando estiver offline.
    var stream := load("res://assets/audio/hilux_srx_2017_parada_simulacao.wav") as AudioStreamWAV
    if stream != null:
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    return stream

func _setup_engine_audio() -> void:
    var stream := _load_hilux_engine_stream()
    if stream == null:
        push_error("Hilux engine audio is missing from the exported project")
        return
    _engine_audio = AudioStreamPlayer3D.new()
    _engine_audio.name = "HiluxOriginalEngineAudio"
    _engine_audio.stream = stream
    _engine_audio.volume_db = -3.0
    _engine_audio.unit_size = 7.0
    _engine_audio.max_distance = 32.0
    add_child(_engine_audio)

func _apply_engine_audio_mode(mode: String) -> void:
    if _engine_audio == null: return
    if mode == "off":
        _engine_audio.stop()
    elif not _engine_audio.playing:
        _engine_audio.play()

func get_network_audio_mode() -> String:
    if not _riding or _mounting or _dismounting: return "off"
    var throttle := Input.get_axis("move_down", "move_up")
    if _autopilot_active:
        throttle = _autopilot_input.x
    elif _hud != null:
        if bool(_hud.get_meta("touch_hilux_gas", false)): throttle = 1.0
        elif bool(_hud.get_meta("touch_hilux_brake", false)): throttle = -1.0
    if throttle > 0.01: return "accel"
    if absf(_speed) > 0.12: return "decel"
    return "idle"

func set_network_audio_mode(mode: String) -> void:
    _network_audio_mode = mode if mode in ["off", "idle", "accel", "decel"] else "off"
    if not _riding: _apply_engine_audio_mode(_network_audio_mode)

func _update_engine_audio() -> void:
    if not _riding and _network_audio_mode != "off":
        _apply_engine_audio_mode(_network_audio_mode)
    elif _riding:
        _network_audio_mode = get_network_audio_mode()
        _apply_engine_audio_mode(_network_audio_mode)
    else:
        _network_audio_mode = "off"
        _apply_engine_audio_mode("off")

func _apply_map_ground_support() -> void:
    var streamer := get_node_or_null("../MapStreamer")
    if streamer == null or not streamer.has_method("sample_ground_height"):
        return
    var exclude: Array[RID] = []
    var collision_body := get_node_or_null("CollisionBody") as StaticBody3D
    if collision_body != null:
        exclude.append(collision_body.get_rid())
    var sample: Dictionary = streamer.call("sample_ground_height", global_position, _ground_y, exclude)
    if sample.is_empty():
        return
    var surface: Vector3 = sample["position"]
    _ground_y = surface.y
    global_position.y = _ground_y - _wheel_ground_offset

func _process(_delta: float) -> void:
    _update_engine_audio()
    _update_ride_button()
    _update_vehicle_panel()
    if _riding and not _mounting and not _dismounting:
        _place_gorece()

func _physics_process(delta: float) -> void:
    _apply_map_ground_support()
    if not _riding or _mounting or _dismounting:
        return
    var throttle := Input.get_axis("move_down", "move_up")
    var steer := Input.get_axis("move_left", "move_right")
    if _hud != null:
        var touch_steer_left := bool(_hud.get_meta("touch_hilux_steer_left", false))
        var touch_steer_right := bool(_hud.get_meta("touch_hilux_steer_right", false))
        if touch_steer_left or touch_steer_right:
            steer = float(touch_steer_right) - float(touch_steer_left)
        if bool(_hud.get_meta("touch_hilux_gas", false)):
            throttle = float(_hud.get_meta("touch_hilux_gas_power", 1.0))
        elif bool(_hud.get_meta("touch_hilux_brake", false)):
            throttle = -1.0
    if _autopilot_active:
        throttle = _autopilot_input.x
        steer = _autopilot_input.y
    if throttle > 0.01:
        _speed = move_toward(_speed, MAX_SPEED * throttle, ACCELERATION * delta)
    elif throttle < -0.01:
        if _speed > 0.05:
            _speed = move_toward(_speed, 0.0, BRAKING * delta)
        else:
            _speed = move_toward(_speed, -REVERSE_SPEED, ACCELERATION * 0.45 * delta)
    else:
        _speed = move_toward(_speed, 0.0, DRAG * delta)
    _steering = move_toward(_steering, steer, STEER_RESPONSE * delta)
    if absf(_speed) > 0.05:
        var speed_ratio := clampf(absf(_speed) / MAX_SPEED, 0.0, 1.0)
        var steering_angle := _steering * MAX_STEERING_ANGLE * lerpf(1.0, 0.58, speed_ratio)
        var yaw_rate := tan(steering_angle) * _speed / WHEELBASE
        rotation.y -= yaw_rate * delta
    var travel := -global_transform.basis.z * _speed * delta
    # A Hilux não freia instantaneamente ao encontrar outro veículo ou personagem.
    # Primeiro tenta abrir espaço com um empurrão proporcional ao deslocamento;
    # somente geometrias fixas continuam bloqueando o carro.
    var movement_result := _resolve_vehicle_collision(travel)
    if bool(movement_result.get("blocked", false)):
        _speed = move_toward(_speed, 0.0, BRAKING * delta * 0.35)
    else:
        global_position += movement_result.get("travel", travel)
    _apply_map_ground_support()
    _wheel_spin = wrapf(_wheel_spin - (_speed / WHEEL_RADIUS) * delta, -TAU, TAU)
    _update_wheels()
    # Pequena rolagem da carroceria, limitada para não virar um efeito arcade.
    if _visual != null:
        var target_roll := -_steering * BODY_ROLL * clampf(absf(_speed) / 5.0, 0.0, 1.0)
        _visual.rotation = _visual_base_rotation
        _visual.rotation.z += target_roll
    _place_gorece()

func _resolve_vehicle_collision(travel: Vector3) -> Dictionary:
    var collision_body := get_node_or_null("CollisionBody") as StaticBody3D
    var collision_shape := get_node_or_null("CollisionBody/Collision") as CollisionShape3D
    if collision_body == null or collision_shape == null or collision_shape.shape == null:
        return {"blocked": false, "travel": travel}
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = collision_shape.shape
    var predicted := global_transform
    predicted.origin += travel
    query.transform = predicted * collision_shape.transform
    query.collision_mask = 1
    query.exclude = [collision_body.get_rid()]
    var hits := get_world_3d().direct_space_state.intersect_shape(query, 16)
    if hits.is_empty():
        return {"blocked": false, "travel": travel}

    var push_direction := Vector3(travel.x, 0.0, travel.z)
    if push_direction.length_squared() < 0.0001:
        return {"blocked": false, "travel": travel}
    push_direction = push_direction.normalized()
    var pushed_any := false
    var push_amount := clampf(push_direction.length() * travel.length() * 5.0, 0.04, 0.42)

    for hit in hits:
        var collider := hit.get("collider") as Node3D
        if collider == null or collider == collision_body:
            continue
        var target := _collision_target(collider)
        if target == null or target == self or target.name == "Ground":
            continue
        # Obstáculos estáticos e o próprio cenário não são empurráveis.
        if target is StaticBody3D and target.get_parent() == get_tree().current_scene:
            continue
        if target is CharacterBody3D or target.has_node("CollisionBody") or target.get_parent() == get_tree().current_scene:
            target.global_position += push_direction * push_amount
            if target is CharacterBody3D:
                target.velocity.x = push_direction.x * maxf(absf(_speed) * 0.65, 1.0)
                target.velocity.z = push_direction.z * maxf(absf(_speed) * 0.65, 1.0)
            pushed_any = true

    return {"blocked": not pushed_any, "travel": travel}

func _collision_target(collider: Node3D) -> Node3D:
    if collider is StaticBody3D and collider.get_parent() is Node3D:
        return collider.get_parent() as Node3D
    return collider

func _update_wheels() -> void:
    var front_angle := -_steering * MAX_STEERING_ANGLE * 0.82
    for wheel in [_wheel_lf, _wheel_rf]:
        _apply_wheel_transform(wheel, front_angle)
    for wheel in [_wheel_lb, _wheel_rb]:
        _apply_wheel_transform(wheel, 0.0)

func update_remote_wheel_spin(world_velocity: Vector3, delta: float) -> void:
    if delta <= 0.0:
        return
    var forward := -global_transform.basis.z
    forward.y = 0.0
    if forward.length_squared() < 0.0001:
        return
    forward = forward.normalized()
    var planar_velocity := Vector3(world_velocity.x, 0.0, world_velocity.z)
    var longitudinal_speed := planar_velocity.dot(forward)
    _wheel_spin = wrapf(_wheel_spin - longitudinal_speed / WHEEL_RADIUS * delta, -TAU, TAU)
    _update_wheels()

func _apply_wheel_transform(wheel: Node3D, steering_angle: float) -> void:
    if wheel == null or not _wheel_base_rotations.has(wheel):
        return
    var rotation := _wheel_base_rotations[wheel] as Vector3
    rotation.y += steering_angle
    rotation.x += _wheel_spin
    wheel.rotation = rotation

func toggle_riding_from_universal() -> void:
    if _riding:
        if not _mounting and not _dismounting:
            _start_dismount()
    elif is_near_player():
        _start_mount()

func is_riding() -> bool:
    return _riding

func set_autopilot_controls(input: Vector2, enabled := true) -> void:
    _autopilot_active = enabled and _riding
    _autopilot_input = Vector2(clampf(input.x, -1.0, 1.0), clampf(input.y, -1.0, 1.0)) if _autopilot_active else Vector2.ZERO

func get_autopilot_speed() -> float:
    return _speed

func get_autopilot_speed_limit() -> float:
    return MAX_SPEED

func is_near_player() -> bool:
    if _gorece == null or _riding:
        return false
    if _andre != null and _andre.has_method("is_gorece_active") and not _andre.is_gorece_active():
        return false
    # Só dá para entrar pela porta do motorista (lado esquerdo), sem atravessar a lataria.
    var local_position := global_transform.affine_inverse() * _gorece.global_position
    if local_position.x > MIN_SIDE_X:
        return false
    var approach := _approach_point()
    var distance := Vector2(approach.x - _gorece.global_position.x, approach.z - _gorece.global_position.z).length()
    return distance <= MOUNT_INTERACTION_DISTANCE

func _is_close_to_body() -> bool:
    if _gorece == null:
        return false
    var distance := Vector2(global_position.x - _gorece.global_position.x, global_position.z - _gorece.global_position.z).length()
    return distance <= MOUNT_INTERACTION_DISTANCE + 1.0

func _approach_point() -> Vector3:
    var point := global_transform * DOOR_APPROACH
    point.y = _ground_y
    return point

func _cabin_transform() -> Transform3D:
    var cabin := _visual.global_transform if _visual != null else global_transform
    return Transform3D(cabin.basis.orthonormalized(), cabin.origin)

func _yaw_for(direction: Vector3) -> float:
    return atan2(-direction.x, -direction.z)

func _bezier(a: Vector3, b: Vector3, c: Vector3, weight: float) -> Vector3:
    return a.lerp(b, weight).lerp(b.lerp(c, weight), weight)

# Posiciona o corpo do Gorece com o quadril em hip_world e a orientação dada.
func _place_body(hip_world: Vector3, body_basis: Basis) -> void:
    if _gorece == null:
        return
    _gorece.global_position = hip_world - Vector3.UP * STANDING_HIP_HEIGHT
    _gorece.global_rotation = Vector3.ZERO
    _gorece.visual.global_transform = Transform3D(body_basis, hip_world)

func _tween_steps(duration: float, step: Callable, transition := Tween.TRANS_SINE) -> void:
    var tween := create_tween()
    tween.set_trans(transition).set_ease(Tween.EASE_IN_OUT)
    tween.tween_method(step, 0.0, 1.0, maxf(duration, 0.01))
    await tween.finished

func _start_mount(allow_follow_mount := false) -> void:
    if _gorece == null:
        return
    if allow_follow_mount:
        if not _is_close_to_body():
            return
    elif not is_near_player():
        return
    if not allow_follow_mount:
        for sibling in get_parent().get_children():
            if sibling != self and sibling.has_method("is_riding") and sibling.is_riding():
                return
        var multiplayer_client := get_node_or_null("../OnlineMultiplayer")
        if multiplayer_client != null and bool(multiplayer_client.get("enabled")):
            if _network_mount_pending:
                return
            _network_mount_pending = true
            var granted: bool = await multiplayer_client.request_vehicle_claim(network_vehicle_id)
            _network_mount_pending = false
            if not granted or not is_near_player():
                if granted:
                    multiplayer_client.release_vehicle(network_vehicle_id)
                return
    _riding = true
    _mounting = true
    _speed = 0.0
    _set_driving_hud(true)
    _run_mount_sequence()

func start_ai_mount_for_follow() -> void:
    if _riding or _mounting or _dismounting:
        return
    _start_mount(true)

func _run_mount_sequence() -> void:
    var npc := _gorece
    npc.set_player_controlled(false)
    npc.enter_vehicle_mode()
    npc.visible = true
    npc.collision_layer = 0
    npc.collision_mask = 0
    # 1) Caminha até a porta do motorista.
    var start_ground := Vector3(npc.global_position.x, npc.global_position.y, npc.global_position.z)
    var approach := _approach_point()
    var start_yaw: float = npc.visual.global_rotation.y
    var distance := start_ground.distance_to(approach)
    if distance > 0.15:
        var walk_yaw := _yaw_for((approach - start_ground).normalized())
        npc.play_vehicle_clip(GoreceNpc.WALK_ANIMATION)
        await _tween_steps(distance / WALK_TO_DOOR_SPEED, _step_walk.bind(start_ground, approach, start_yaw, walk_yaw), Tween.TRANS_LINEAR)
    npc.play_vehicle_clip(GoreceNpc.IDLE_ANIMATION)
    # 2) Vira para o carro enquanto a porta abre.
    var face_car_yaw := _yaw_for(global_transform.basis.x)
    var from_yaw: float = npc.visual.global_rotation.y
    var turn := create_tween()
    turn.tween_method(_step_turn.bind(approach, from_yaw, face_car_yaw), 0.0, 1.0, DOOR_SECONDS)
    var door_tween := _animate_door(true)
    await turn.finished
    if door_tween != null and door_tween.is_running():
        await door_tween.finished
    # 3) Entra e senta, curvando o corpo para a pose de motorista.
    await npc.prepare_seated_pose()
    var cabin_start := global_transform
    var hip_start := cabin_start.affine_inverse() * (approach + Vector3.UP * STANDING_HIP_HEIGHT)
    var car_yaw := _yaw_for(-cabin_start.basis.z)
    await _tween_steps(SLIDE_IN_SECONDS, _step_enter.bind(npc, cabin_start, hip_start, face_car_yaw, car_yaw))
    npc.set_seated_blend(1.0)
    _place_gorece()
    # 4) Fecha a porta e libera a direção.
    var close_tween := _animate_door(false)
    if close_tween != null:
        await close_tween.finished
    _mounting = false
    _set_drive_buttons_visible(true)

func _start_dismount() -> void:
    _dismounting = true
    _speed = 0.0
    _set_drive_buttons_visible(false)
    _run_dismount_sequence()

func _run_dismount_sequence() -> void:
    var npc := _gorece
    if npc == null:
        _riding = false
        _dismounting = false
        _set_driving_hud(false)
        return
    var open_tween := _animate_door(true)
    if open_tween != null:
        await open_tween.finished
    var cabin := global_transform
    var approach := _approach_point()
    var hip_end := cabin.affine_inverse() * (approach + Vector3.UP * STANDING_HIP_HEIGHT)
    var car_yaw := _yaw_for(-cabin.basis.z)
    var out_yaw := _yaw_for(-cabin.basis.x)
    # Levanta e sai pela porta.
    await _tween_steps(SLIDE_IN_SECONDS, _step_exit.bind(npc, cabin, hip_end, car_yaw, out_yaw))
    # Devolve o corpo ao controle normal do jogo.
    npc.release_seated_pose()
    npc.exit_vehicle_mode()
    npc.global_position = Vector3(approach.x, _ground_y, approach.z)
    npc.global_rotation = Vector3.ZERO
    npc.visual.position = Vector3(0.0, STANDING_HIP_HEIGHT, 0.0)
    npc.visual.rotation = Vector3(0.0, out_yaw, 0.0)
    npc.visible = true
    npc.collision_layer = 1
    npc.collision_mask = 1
    npc.set_player_controlled(true)
    _riding = false
    _dismounting = false
    _mounting = false
    var multiplayer_client := get_node_or_null("../OnlineMultiplayer")
    if multiplayer_client != null and bool(multiplayer_client.get("enabled")):
        multiplayer_client.release_vehicle(network_vehicle_id)
    _set_driving_hud(false)
    _animate_door(false)

func _step_walk(weight: float, start_ground: Vector3, approach: Vector3, start_yaw: float, walk_yaw: float) -> void:
    var ground := start_ground.lerp(approach, weight)
    var yaw := lerp_angle(start_yaw, walk_yaw, minf(1.0, weight * 6.0))
    _place_body(ground + Vector3.UP * STANDING_HIP_HEIGHT, Basis(Vector3.UP, yaw))

func _step_turn(weight: float, approach: Vector3, from_yaw: float, to_yaw: float) -> void:
    _place_body(approach + Vector3.UP * STANDING_HIP_HEIGHT, Basis(Vector3.UP, lerp_angle(from_yaw, to_yaw, weight)))

func _step_enter(weight: float, npc: GoreceNpc, cabin: Transform3D, hip_start: Vector3, face_yaw: float, car_yaw: float) -> void:
    var hip_local := _bezier(hip_start, DOOR_THRESHOLD_HIP, SEAT_HIP, weight)
    var yaw := lerp_angle(face_yaw, car_yaw, smoothstep(0.15, 0.85, weight))
    npc.set_seated_blend(smoothstep(0.2, 1.0, weight))
    _place_body(cabin * hip_local, Basis(Vector3.UP, yaw))

func _step_exit(weight: float, npc: GoreceNpc, cabin: Transform3D, hip_end: Vector3, car_yaw: float, out_yaw: float) -> void:
    var hip_local := _bezier(SEAT_HIP, DOOR_THRESHOLD_HIP, hip_end, weight)
    var yaw := lerp_angle(car_yaw, out_yaw, smoothstep(0.1, 0.7, weight))
    npc.set_seated_blend(1.0 - smoothstep(0.0, 0.8, weight))
    _place_body(cabin * hip_local, Basis(Vector3.UP, yaw))

func _place_gorece() -> void:
    if _gorece == null:
        return
    var cabin := _cabin_transform()
    _place_body(cabin * SEAT_HIP, cabin.basis)

func _animate_door(open: bool) -> Tween:
    if _door == null:
        return null
    if _door_tween != null and is_instance_valid(_door_tween):
        _door_tween.kill()
    var target := _door_base_rotation
    if open:
        target.y += DOOR_OPEN_ANGLE
    _door_tween = create_tween()
    _door_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
    _door_tween.tween_property(_door, "rotation", target, DOOR_SECONDS)
    _door_open = open
    return _door_tween

func _set_driving_hud(on: bool) -> void:
    if not on:
        _set_drive_buttons_visible(false)
    if _ride_button != null:
        _ride_button.text = "SAIR DA HILUX" if on else "ENTRAR NA HILUX"
        _ride_button.disabled = false
    if _hud == null:
        return
    if on:
        var touch_joystick := _hud.get_node_or_null("TouchJoystick")
        if touch_joystick != null and touch_joystick.has_method("reset_touch"):
            touch_joystick.call("reset_touch")
    for node_name: String in HIDDEN_WHILE_DRIVING:
        var control := _hud.get_node_or_null(node_name) as Control
        if control == null:
            continue
        if on:
            if not control.has_meta("hidden_for_hilux"):
                control.set_meta("hidden_for_hilux", control.visible)
            control.visible = false
        elif control.has_meta("hidden_for_hilux"):
            control.visible = bool(control.get_meta("hidden_for_hilux"))
            control.remove_meta("hidden_for_hilux")

func _update_ride_button() -> void:
    if _ride_button == null:
        return
    if _riding:
        _ride_button.text = "SAIR DA HILUX"
        _ride_button.disabled = _mounting or _dismounting
    elif is_near_player():
        _ride_button.text = "ENTRAR NA HILUX"
        _ride_button.disabled = false
    elif _andre != null and _andre.has_method("is_gorece_active") and _andre.is_gorece_active():
        _ride_button.text = "VÁ ATÉ A PORTA ESQUERDA" if _is_close_to_body() else "APROXIME-SE DA HILUX"
        _ride_button.disabled = true

func _update_vehicle_panel() -> void:
    var panel := get_node_or_null("../HUD/Root/VehiclePanel") as Label
    if panel == null:
        return
    if _riding:
        panel.text = "HILUX SRX 2017\nVELOCIDADE: %03d km/h" % roundi(absf(_speed) * 3.6)
    elif _andre != null and _andre.has_method("is_gorece_active") and _andre.is_gorece_active():
        panel.text = "HILUX SRX 2017\nGORECE: ENTRADA EXCLUSIVA\nAPROXIME-SE PARA DIRIGIR"

func _find_part(root: Node, wanted: String) -> Node3D:
    if root == null:
        return null
    for child in root.get_children():
        if child is Node3D and String(child.name).to_lower() == wanted.to_lower():
            return child as Node3D
        var found := _find_part(child, wanted)
        if found != null:
            return found
    return null

# Botões de tela ACELERAR / FREAR. Compartilhados com as motos: se já existem na HUD, reaproveita.
func _ensure_drive_buttons() -> void:
    if _hud == null:
        return
    if not _hud.has_node("HiluxGasButton"):
        var gas := ScreenFactory.button("ACELERAR", DRIVE_BUTTON_SIDE)
        gas.name = "HiluxGasButton"
        _place_drive_button(gas, -150.0)
        _hud.add_child(gas)
    _configure_accelerator_button(_hud.get_node("HiluxGasButton") as Button)
    if not _hud.has_node("HiluxBrakeButton"):
        var brake := ScreenFactory.button("FREAR", DRIVE_BUTTON_SIDE)
        brake.name = "HiluxBrakeButton"
        _place_drive_button(brake, -290.0)
        brake.button_down.connect(func() -> void: _hud.set_meta("touch_hilux_brake", true))
        brake.button_up.connect(func() -> void: _hud.set_meta("touch_hilux_brake", false))
        _hud.add_child(brake)
    _ensure_steering_button("HiluxSteerLeftButton", "ESQUERDA", "touch_hilux_steer_left", 30.0)
    _ensure_steering_button("HiluxSteerRightButton", "DIREITA", "touch_hilux_steer_right", 170.0)

func _configure_accelerator_button(button: Button) -> void:
    if button == null or bool(button.get_meta("accelerator_handler_connected", false)):
        return
    button.set_meta("accelerator_handler_connected", true)
    button.gui_input.connect(_on_accelerator_gui_input.bind(button))

func _on_accelerator_gui_input(event: InputEvent, button: Button) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            _set_accelerator_power_from_position(button, event.position.x)
        else:
            _release_accelerator()
    elif event is InputEventScreenDrag:
        _set_accelerator_power_from_position(button, event.position.x)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _set_accelerator_power_from_position(button, event.position.x)
        else:
            _release_accelerator()
    elif event is InputEventMouseMotion and bool(button.get_meta("accelerator_dragging", false)):
        _set_accelerator_power_from_position(button, event.position.x)

func _set_accelerator_power_from_position(button: Button, local_x: float) -> void:
    var width := maxf(button.size.x, DRIVE_BUTTON_SIDE)
    var power := clampf(local_x / width, 0.0, 1.0)
    button.set_meta("accelerator_dragging", true)
    _hud.set_meta("touch_hilux_gas", true)
    _hud.set_meta("touch_hilux_gas_power", power)

func _release_accelerator() -> void:
    _hud.set_meta("touch_hilux_gas", false)
    _hud.set_meta("touch_hilux_gas_power", 0.0)
    var button := _hud.get_node_or_null("HiluxGasButton") as Button
    if button != null:
        button.set_meta("accelerator_dragging", false)

func _ensure_steering_button(node_name: String, label: String, touch_meta: String, left: float) -> void:
    if _hud.has_node(node_name):
        return
    var steer_button := ScreenFactory.button(label, DRIVE_BUTTON_SIDE)
    steer_button.name = node_name
    steer_button.custom_minimum_size = Vector2(DRIVE_BUTTON_SIDE, DRIVE_BUTTON_SIDE)
    steer_button.add_theme_font_size_override("font_size", 14)
    steer_button.focus_mode = Control.FOCUS_NONE
    steer_button.anchor_left = 0.0
    steer_button.anchor_right = 0.0
    steer_button.anchor_top = 1.0
    steer_button.anchor_bottom = 1.0
    steer_button.offset_left = left
    steer_button.offset_right = left + DRIVE_BUTTON_SIDE
    steer_button.offset_top = -160.0
    steer_button.offset_bottom = -160.0 + DRIVE_BUTTON_SIDE
    steer_button.visible = false
    steer_button.button_down.connect(func() -> void: _hud.set_meta(touch_meta, true))
    steer_button.button_up.connect(func() -> void: _hud.set_meta(touch_meta, false))
    _hud.add_child(steer_button)

func _place_drive_button(button_control: Button, left: float) -> void:
    button_control.custom_minimum_size = Vector2(DRIVE_BUTTON_SIDE, DRIVE_BUTTON_SIDE)
    button_control.focus_mode = Control.FOCUS_NONE
    button_control.anchor_left = 1.0
    button_control.anchor_top = 1.0
    button_control.anchor_right = 1.0
    button_control.anchor_bottom = 1.0
    button_control.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    button_control.grow_vertical = Control.GROW_DIRECTION_BEGIN
    button_control.offset_left = left
    button_control.offset_right = left + DRIVE_BUTTON_SIDE
    button_control.offset_top = -200.0
    button_control.offset_bottom = -200.0 + DRIVE_BUTTON_SIDE

func _set_drive_buttons_visible(on: bool) -> void:
    if _hud == null:
        return
    _ensure_drive_buttons()
    for node_name: String in ["HiluxGasButton", "HiluxBrakeButton", "HiluxSteerLeftButton", "HiluxSteerRightButton"]:
        var control := _hud.get_node_or_null(node_name) as Control
        if control != null:
            control.visible = on
    if not on:
        _hud.set_meta("touch_hilux_gas", false)
        _hud.set_meta("touch_hilux_brake", false)
        _hud.set_meta("touch_hilux_steer_left", false)
        _hud.set_meta("touch_hilux_steer_right", false)
