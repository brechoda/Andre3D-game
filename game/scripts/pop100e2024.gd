extends Node3D

@export var ride_button_path: NodePath = NodePath("../HUD/Root/RideButton")
@export var ride_button_idle_text := "TESTAR PILOTAGEM"
@export var vehicle_display_name := "MOTO POP 100E"
@export var network_vehicle_id := ""
@export var universal_ride_controller := false

# Handling REALISTA (dados reais das motos, não GTA arcade).
# Escala: 1 unidade ≈ 1 m. Velocidades em m/s.
# Honda Pop 100: vmax ≈ 105 km/h (29.2 m/s), 6.2 cv, 85 kg → lenta, arranque fraco.
# BMW R1200: vmax ≈ 215 km/h (59.7 m/s), 110 cv, ~220 kg → 0-100 em ~3.4 s.
@export var max_speed: float = 8.5           # default Pop (ajustado no _ready)
@export var acceleration: float = 6.5        # default Pop
@export var braking: float = 14.0
@export var rolling_drag: float = 4.5
@export var wheel_radius: float = 0.30
@export var ground_y: float = 0.0
@export var steering_angle: float = 0.55     # Pop tem esterço bem aberto (ágil cidade)
@export var reverse_speed: float = 2.0
@export var steer_rate: float = 1.35
@export var high_speed_steer_factor: float = 0.55
# Guidão em modelos cujo nó não está no lugar certo: posição de repouso e gira em torno do centro da barra.
@export var handlebar_rest_offset := Vector3.ZERO
@export var handlebar_pivot_at_center := false
# Largura da barra em relação ao original (1.0 = do modelo). Ajusta para as mãos alcançarem as pontas.
@export var handlebar_width_scale := 1.0
# Retrovisores (malha "retro") acompanham o guidão. Este ajuste extra só mexe neles.
@export var mirror_extra_offset := Vector3.ZERO
# Colisão gameplay simplificada; a malha visual não deve ser usada como colisão.
# As motos têm dezenas/centenas de milhares de triângulos e ficam muito pesadas
# quando o CharacterBody3D chega perto delas.
@export var collision_box_size := Vector3(1.35, 1.45, 2.65)
@export var collision_box_center := Vector3(0.0, 0.72, 0.0)

const BIKE_MOUNT_ANIMATION := "BIKEd_jumponL"
const BIKE_IDLE_ANIMATION := "BIKEd_Ride"
const BIKE_FORWARD_ANIMATION := "BIKEd_Fwd"
const BIKE_BACK_ANIMATION := "BIKEd_Back"
const BIKE_PUSHES_ANIMATION := "BIKEd_pushes"  # pé no chão empurrando (ré / quase parado)
const BIKE_STILL_ANIMATION := "BIKEd_Still"
const BIKE_LEFT_ANIMATION := "BIKEd_Left"
const BIKE_RIGHT_ANIMATION := "BIKEd_Right"
const BIKE_GETOFF_ANIMATION := "BIKEd_getoffLHS"
const BIKE_ANIMATION_SPEED := 1.0
# Onde o piloto senta (relativo à origem da moto) e onde ele desce (lado ESQUERDO,
# porque a animação usada é BIKEd_getoffLHS = "left hand side").
@export var rider_seat_offset := Vector3(0.0, -0.60, 0.02)
const DISMOUNT_SIDE_OFFSET := -1.0
const RIDER_BLEND := 0.12
const MOUNT_BLEND := 0.15
const MOUNT_INTERACTION_DISTANCE := 2.8
# Lean padrão (Pop é mais leve e inclina mais fácil em baixa)
var MAX_LEAN := 0.38   # ~22°
var LEAN_SPEED := 6.5
# Botões da tela que somem ao pilotar (o de pilotar/descer e os de ACELERAR/FREAR ficam).
const HIDDEN_WHILE_RIDING := ["RunButton", "CrouchButton", "JumpButton", "ActionButton", "SwitchButton", "RideButton"]
const DRIVE_BUTTON_SIDE := 120.0
# Câmera da moto: posição base atrás da moto (0, 2.25, 5.5), que pode ser girada pelo jogador.
const CAM_BASE_OFFSET := Vector3(0.0, 2.25, 5.5)
const CAM_YAW_SPEED := 0.006
const CAM_PITCH_SPEED := 0.004
const CAM_PITCH_MIN := -0.25
const CAM_PITCH_MAX := 0.5

# O GLB veio de um DFF do GTA, onde roda e paralama eram FILHOS dos garfos.
# O conversor achatou tudo e perdeu o offset do pai. Aqui a gente reaplica.
const FLATTENED_CHILDREN := {
    "wheel_front": "forks_front",
    "mudguard": "forks_front",
    "wheel_rear": "forks_rear",
}

var _speed := 0.0
var _steering_input := 0.0
var _autopilot_input := Vector2.ZERO
var _autopilot_active := false
var _wheelbase := 1.32
var _front_radius := 0.30
var _rear_radius := 0.30
var _lean := 0.0
var _wheelie := 0.0          # 0 = rodas no chão, positivo = grau (roda dianteira sobe)
var _ground_local_y := -0.55
const MAX_WHEELIE := 0.72    # ~41° de grau; empina mais alto
const WHEELIE_UP_SPEED := 2.1 # subida mais pesada/lenta
const WHEELIE_DOWN_SPEED := 4.0 # desce só um pouco mais devagar
var _visual_root: Node3D
var _rider_visual_offset := Vector3(0.0, 0.98, 0.0)
var _mount_from_pos := Vector3.ZERO
var _mount_from_yaw := 0.0
var _riding := false
var _network_mount_pending := false
var _mounting := false
var _dismounting := false
var _ai_driving := false
var _ai_target: Node3D
var _front_wheel: Node3D
var _rear_wheel: Node3D
var _front_fork: Node3D
var _front_mudguard: Node3D
var _front_fork_base := Transform3D.IDENTITY
var _front_wheel_base := Transform3D.IDENTITY
var _front_mudguard_base := Transform3D.IDENTITY
var _rear_wheel_base := Transform3D.IDENTITY
var _front_steering_pivot := Vector3.ZERO
var _front_spin_angle := 0.0
var _rear_spin_angle := 0.0
var _handlebar: Node3D
var _dashboard: Node3D
var _rider_visual: Node3D
var _rider_animator: AnimationPlayer
var _rider_skeleton: Skeleton3D
var _left_grip_target: Node3D
var _right_grip_target: Node3D
var _left_upper_bone := -1
var _left_forearm_bone := -1
var _left_hand_bone := -1
var _right_upper_bone := -1
var _right_forearm_bone := -1
var _right_hand_bone := -1
var _left_grip_local := Transform3D.IDENTITY
var _right_grip_local := Transform3D.IDENTITY
var _grips_calibrated := false
var _grip_calibration_frames := 0
var _handlebar_base_rotation := Vector3.ZERO
var _handlebar_center_local := Vector3.ZERO
var _cam_yaw := 0.0  # 0 = atrás da moto; positivo gira em volta dela
var _cam_pitch := 0.0  # ajuste de altura, somado ao ângulo base
var _cam_drag_mouse := false
var _cam_touch_id := -1
var _cam_last_touch := Vector2.ZERO
var _retro: Node3D
var _retro_base := Vector3.ZERO
var _bar_scale := Vector3.ONE
var _dashboard_base_rotation := Vector3.ZERO
var _idle_engine_audio: AudioStreamPlayer3D
var _accel_engine_audio: AudioStreamPlayer3D
var _decel_engine_audio: AudioStreamPlayer3D
var _decel_played_this_coast := false
var _network_audio_mode := "off"
var _network_audio_remote := false



@onready var _player: CharacterBody3D = get_node_or_null("../Player") as CharacterBody3D
@onready var _camera: Camera3D = get_node_or_null("../Player/Camera3D") as Camera3D
@onready var _panel_label: Label = get_node_or_null("../HUD/Root/VehiclePanel") as Label
@onready var _ride_button: Button = get_node_or_null(ride_button_path) as Button
@onready var _joystick: AndreVirtualJoystick = get_node_or_null("../HUD/Root/TouchJoystick") as AndreVirtualJoystick

## Aplica handling realista de acordo com a moto (Pop 100 vs Wayfarer R1200).
## Valores baseados em fichas técnicas reais + escala do mundo do jogo.
func _apply_realistic_handling() -> void:
    var name_upper := vehicle_display_name.to_upper()
    var is_wayfarer := "WAYFARER" in name_upper or "R1200" in name_upper or String(name).contains("Wayfarer")

    if is_wayfarer:
        # BMW R1200 (R / GS / RT): ~215 km/h, 110 cv, 0-100 ≈ 3.4 s
        # Escala: top real 59.7 m/s → usamos 18.5 (sensação de potência sem explodir o mapa)
        max_speed = 18.5
        acceleration = 22.0          # arranque forte (torque de boxer)
        braking = 22.0               # freios a disco potentes
        rolling_drag = 2.8
        reverse_speed = 3.2
        steering_angle = 0.42        # mais estável em alta (menos esterço extremo)
        steer_rate = 0.95
        high_speed_steer_factor = 0.35
        MAX_LEAN = 0.48              # ~27.5° (mais lean possível)
        LEAN_SPEED = 8.0
        max_speed = float(TuningStore.get_active_value("vehicle.wayfarer.max_speed", max_speed))
        print("[Handling] Wayfarer R1200 REALISTA: vmax=%s | accel=22 | brake=22" % max_speed)
    else:
        # Honda Pop 100: ~105 km/h, 6.2 cv, peso 85 kg
        # Escala: top real 29.2 m/s → usamos 8.2 (lenta, urbana)
        max_speed = 8.2
        acceleration = 5.8           # arranque fraco (motor pequenininho)
        braking = 12.0               # freio a tambor
        rolling_drag = 5.0
        reverse_speed = 1.8
        steering_angle = 0.58        # esterço bem aberto (ágil no trânsito)
        steer_rate = 1.45
        high_speed_steer_factor = 0.60
        MAX_LEAN = 0.36              # ~20.6°
        LEAN_SPEED = 6.0
        max_speed = float(TuningStore.get_active_value("vehicle.pop.max_speed", max_speed))
        print("[Handling] Honda Pop 100 REALISTA: vmax=%s | accel=5.8 | brake=12" % max_speed)

func _ready() -> void:
    _apply_realistic_handling()
    _visual_root = get_node_or_null("MotorcycleVisual") as Node3D
    _restore_flattened_hierarchy()
    _build_dff_collision()
    _setup_idle_engine_audio()
    _front_wheel = _find_part(self, "wheel_front")
    _rear_wheel = _find_part(self, "wheel_rear")
    _front_fork = _find_part(self, "forks_front")
    _front_mudguard = _find_part(self, "mudguard")
    _handlebar = _find_part(self, "guidao")
    if _handlebar == null:
        _handlebar = _find_part(self, "guidon")
    _dashboard = _find_part(self, "painel")
    if is_zero_approx(ground_y):
        ground_y = global_position.y
    _align_wheels_to_ground()
    if _front_fork != null:
        _front_fork_base = _front_fork.transform
        _front_steering_pivot = _front_fork_base.origin
    if _front_wheel != null:
        _front_wheel_base = _front_wheel.transform
    if _front_mudguard != null:
        _front_mudguard_base = _front_mudguard.transform
    if _rear_wheel != null:
        _rear_wheel_base = _rear_wheel.transform
    if _handlebar != null and handlebar_pivot_at_center:
        var bar_original := _handlebar.position
        _handlebar.position = handlebar_rest_offset
        _bar_scale = Vector3(handlebar_width_scale, 1.0, 1.0)
        _handlebar.scale = _bar_scale
        var bar_mesh := _handlebar as MeshInstance3D
        if bar_mesh != null:
            _handlebar_center_local = bar_mesh.get_aabb().get_center()
        # Os retrovisores estão no mesmo conjunto do guidão: recebem o mesmo deslocamento.
        _retro = _find_part(self, "retro")
        if _retro != null:
            _retro_base = _retro.position + (handlebar_rest_offset - bar_original) + mirror_extra_offset
            _retro.position = _retro_base
            _retro.scale = _bar_scale
    if _handlebar != null:
        _handlebar_base_rotation = _handlebar.rotation
    if _dashboard != null:
        _dashboard_base_rotation = _dashboard.rotation
    if _player != null:
        _refresh_rider_visual()
    if _ride_button != null and universal_ride_controller:
        _ride_button.pressed.connect(_toggle_riding)
    _ensure_drive_buttons()
    _update_panel()

func _setup_idle_engine_audio() -> void:
    var name_upper := vehicle_display_name.to_upper()
    var is_wayfarer := "WAYFARER" in name_upper or "R1200" in name_upper or String(name).contains("Wayfarer")
    var idle_path := "res://assets/audio/r1200_marcha_lenta.mp3" if is_wayfarer else "res://assets/audio/pop100_marcha_lenta_v2.mp3"
    var stream := load(idle_path) as AudioStreamMP3
    if stream == null:
        push_warning("Som de marcha lenta não encontrado: " + idle_path)
        return
    stream.loop = true
    _idle_engine_audio = AudioStreamPlayer3D.new()
    _idle_engine_audio.name = "PopIdleEngineAudio"
    _idle_engine_audio.stream = stream
    _idle_engine_audio.volume_db = -2.0
    _idle_engine_audio.unit_size = 6.0
    _idle_engine_audio.max_distance = 28.0
    _idle_engine_audio.autoplay = false
    add_child(_idle_engine_audio)

    var accel_path := "res://assets/audio/r1200_acelerando.mp3" if is_wayfarer else "res://assets/audio/pop100_acelerando_1.mp3"
    var accel_stream := load(accel_path) as AudioStreamMP3
    if accel_stream == null:
        push_warning("Som de aceleração não encontrado: " + accel_path)
        return
    accel_stream.loop = true
    _accel_engine_audio = AudioStreamPlayer3D.new()
    _accel_engine_audio.name = "PopAccelerationEngineAudio"
    _accel_engine_audio.stream = accel_stream
    _accel_engine_audio.volume_db = -2.0
    _accel_engine_audio.unit_size = 6.0
    _accel_engine_audio.max_distance = 28.0
    _accel_engine_audio.autoplay = false
    add_child(_accel_engine_audio)

    var decel_path := "res://assets/audio/r1200_desacelerando.mp3" if is_wayfarer else "res://assets/audio/pop100_desacelerando_v2_1.mp3"
    var decel_stream := load(decel_path) as AudioStreamMP3
    if decel_stream == null:
        push_warning("Som de desaceleração não encontrado: " + decel_path)
        return
    decel_stream.loop = false
    _decel_engine_audio = AudioStreamPlayer3D.new()
    _decel_engine_audio.name = "PopDecelerationEngineAudio"
    _decel_engine_audio.stream = decel_stream
    _decel_engine_audio.volume_db = -2.0
    _decel_engine_audio.unit_size = 6.0
    _decel_engine_audio.max_distance = 28.0
    _decel_engine_audio.autoplay = false
    add_child(_decel_engine_audio)

func _apply_engine_audio_mode(mode: String) -> void:
    if _idle_engine_audio == null or _accel_engine_audio == null:
        return
    if mode == "accel":
        _decel_played_this_coast = false
        _idle_engine_audio.stop()
        if _decel_engine_audio != null: _decel_engine_audio.stop()
        if not _accel_engine_audio.playing: _accel_engine_audio.play()
    elif mode == "decel":
        _accel_engine_audio.stop()
        _idle_engine_audio.stop()
        # O clipe da Pop é um efeito de uma vez; não reinicia a cada frame.
        if _decel_engine_audio != null and not _decel_played_this_coast:
            _decel_engine_audio.play()
            _decel_played_this_coast = true
    elif mode == "idle":
        _decel_played_this_coast = false
        _accel_engine_audio.stop()
        if _decel_engine_audio != null: _decel_engine_audio.stop()
        if not _idle_engine_audio.playing: _idle_engine_audio.play()
    else:
        _decel_played_this_coast = false
        _idle_engine_audio.stop()
        _accel_engine_audio.stop()
        if _decel_engine_audio != null: _decel_engine_audio.stop()

func get_network_audio_mode() -> String:
    if not _riding or _mounting or _dismounting:
        return "off"
    var throttle_pressed := false
    if _autopilot_active:
        throttle_pressed = _autopilot_input.x > 0.03
    elif _ai_driving:
        throttle_pressed = _get_ai_follow_inputs().x > 0.03
    else:
        throttle_pressed = Input.get_axis("move_down", "move_up") > 0.03
        var hud := _hud_root()
        if hud != null:
            throttle_pressed = throttle_pressed or bool(hud.get_meta("touch_gas", false))
    if throttle_pressed: return "accel"
    # Dar ré não é desacelerar: mantém o som de marcha lenta.
    if _speed < -0.12: return "idle"
    if _speed > 0.12: return "decel"
    return "idle"

func set_network_audio_mode(mode: String) -> void:
    _network_audio_mode = mode if mode in ["off", "idle", "accel", "decel"] else "off"
    _network_audio_remote = _network_audio_mode != "off"
    if not _riding:
        _apply_engine_audio_mode(_network_audio_mode)

func _update_idle_engine_audio() -> void:
    # A scene vehicle can be controlled by another client. In that case its
    # local _riding flag is false, so only the replicated mode may drive audio.
    if not _riding and _network_audio_remote and _network_audio_mode != "off":
        _apply_engine_audio_mode(_network_audio_mode)
        return
    if not _riding:
        _network_audio_remote = false
        _network_audio_mode = "off"
        _apply_engine_audio_mode("off")
        return
    var mode := get_network_audio_mode()
    _network_audio_remote = false
    _network_audio_mode = mode
    _apply_engine_audio_mode(mode)

## Cria uma colisão gameplay simples, independente da quantidade de triângulos
## do GLB. A geometria visual continua livre para renderização/animação, mas não
## entra no broad/narrow phase da física.
func _build_dff_collision() -> void:
    var collision_body := get_node_or_null("CollisionBody") as StaticBody3D
    if collision_body == null:
        return
    for child in collision_body.get_children():
        child.free()
    var box_shape := BoxShape3D.new()
    box_shape.size = collision_box_size
    var collision := CollisionShape3D.new()
    collision.name = "GameplayCollision"
    collision.shape = box_shape
    collision.position = collision_box_center
    collision_body.add_child(collision)

func _restore_flattened_hierarchy() -> void:
    for child_name in FLATTENED_CHILDREN:
        var child := _find_part(self, String(child_name))
        var parent := _find_part(self, String(FLATTENED_CHILDREN[child_name]))
        if child != null and parent != null:
            # Soma posição e rotação do garfo. No pneu traseiro a rotação do
            # braço oscilante cancela a do pneu, então ele fica reto.
            child.transform = parent.transform * child.transform

func _wheel_radius_of(wheel: Node3D) -> float:
    var mesh_instance := wheel as MeshInstance3D
    if mesh_instance != null and mesh_instance.mesh != null:
        var box := mesh_instance.get_aabb()
        return maxf((box.size.y + box.size.z) * 0.25, 0.05)
    return wheel_radius

func _align_wheels_to_ground() -> void:
    if _front_wheel == null or _rear_wheel == null:
        return
    _front_radius = _wheel_radius_of(_front_wheel)
    _rear_radius = _wheel_radius_of(_rear_wheel)
    var front_bottom := _front_wheel.position.y - _front_radius
    var rear_bottom := _rear_wheel.position.y - _rear_radius
    # Os dois pneus têm que encostar no mesmo chão.
    _rear_wheel.position.y += front_bottom - rear_bottom
    # Sobe a moto inteira pro pneu tocar o chão (antes: y fixo 0.30 na cena).
    _ground_local_y = front_bottom
    global_position.y = ground_y - front_bottom

func _apply_map_ground_support() -> void:
    var streamer := get_node_or_null("../MapStreamer")
    if streamer == null or not streamer.has_method("sample_ground_height"):
        return
    var exclude: Array[RID] = []
    var collision_body := get_node_or_null("CollisionBody") as StaticBody3D
    if collision_body != null:
        exclude.append(collision_body.get_rid())
    var sample: Dictionary = streamer.call("sample_ground_height", global_position, ground_y, exclude)
    if sample.is_empty():
        return
    var surface: Vector3 = sample["position"]
    ground_y = surface.y
    global_position.y = ground_y - _ground_local_y

func _physics_process(delta: float) -> void:
    _apply_map_ground_support()
    if not _riding or _mounting or _dismounting:
        return

    var throttle := Input.get_axis("move_down", "move_up")
    var steer := Input.get_axis("move_left", "move_right")
    var wheelie_input := 0.0
    if _autopilot_active:
        throttle = _autopilot_input.x
        steer = _autopilot_input.y
    elif _ai_driving:
        var ai_inputs := _get_ai_follow_inputs()
        throttle = ai_inputs.x
        steer = ai_inputs.y
    # Analógico: eixo X = direção | eixo Y puxado pra baixo = grau (empinar)
    # Velocidade continua nos botões ACELERAR/FREAR ou teclas W/S.
    if not _ai_driving and not _autopilot_active and _joystick != null:
        if absf(_joystick.value.x) > 0.08:
            steer = clampf(_joystick.value.x, -1.0, 1.0)
        # Puxar o stick para baixo (value.y > 0) pede grau.
        if _joystick.value.y > 0.25:
            wheelie_input = clampf(_joystick.value.y, 0.0, 1.0)
    # Botões ACELERAR / FREAR na tela sobrepõem o teclado.
    var hud := _hud_root()
    if not _ai_driving and not _autopilot_active and hud != null:
        if bool(hud.get_meta("touch_gas", false)):
            throttle = float(hud.get_meta("touch_gas_power", 1.0))
        elif bool(hud.get_meta("touch_brake", false)):
            throttle = -1.0
    _apply_throttle(throttle, delta)
    _update_wheelie(throttle, wheelie_input, delta)

    _steering_input = move_toward(_steering_input, steer, steer_rate * 2.8 * delta)
    if absf(_steering_input) > 0.01 and absf(_speed) > 0.05:
        # Modelo de bicicleta: a taxa de guinada vem do ângulo da roda e do
        # entre-eixos, em vez de girar a carroceria a uma taxa fixa.
        var ratio := clampf(absf(_speed) / max_speed, 0.0, 1.0)
        var authority := clampf(ratio, 0.2, 1.0) * lerpf(1.0, high_speed_steer_factor, ratio)
        var wheel_angle := _steering_input * steering_angle
        var yaw_rate := tan(wheel_angle) * _speed / _wheelbase
        rotation.y -= yaw_rate * delta * authority
    _update_lean(_steering_input, delta)
    _update_steering_parts(_steering_input)
    _update_rider_animation(throttle, _steering_input)

    var travel := -global_transform.basis.z * _speed * delta
    if _movement_blocked(travel):
        _speed = 0.0
    else:
        global_position += travel
    _apply_map_ground_support()
    # O eixo local X atravessa o cubo dos dois pneus; o giro acumula distância
    # percorrida e é composto com o esterço da roda dianteira.
    if _front_wheel != null:
        _front_spin_angle = wrapf(_front_spin_angle - (_speed / _front_radius) * delta, -TAU, TAU)
    if _rear_wheel != null:
        _rear_spin_angle = wrapf(_rear_spin_angle - (_speed / _rear_radius) * delta, -TAU, TAU)
    _apply_front_steering(-steer * steering_angle)
    _apply_wheel_spin()
    _follow_with_player_and_camera()
    if not _ai_driving:
        _update_panel()

func _movement_blocked(travel: Vector3) -> bool:
    var collision_body := get_node_or_null("CollisionBody") as StaticBody3D
    if collision_body == null:
        return false
    var predicted := global_transform
    predicted.origin += travel
    for child in collision_body.get_children():
        var collision_shape := child as CollisionShape3D
        if collision_shape == null or collision_shape.shape == null:
            continue
        var query := PhysicsShapeQueryParameters3D.new()
        query.shape = collision_shape.shape
        query.transform = predicted * collision_shape.transform
        query.collision_mask = 1
        query.exclude = [collision_body.get_rid()]
        if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
            return true
    return false

func _process(_delta: float) -> void:
    if universal_ride_controller and not _ai_driving:
        _update_universal_ride_button()
    _update_idle_engine_audio()
    if _riding:
        _follow_with_player_and_camera()
        if _mounting and _rider_animator != null and not _rider_animator.is_playing():
            _mounting = false
            _play_rider_animation(BIKE_IDLE_ANIMATION, true)
        elif _dismounting and _rider_animator != null and not _rider_animator.is_playing():
            if _ai_driving:
                _finish_ai_dismount()
            else:
                _finish_dismount()
        _update_rider_grip_ik()
        if _ai_driving and (not is_instance_valid(_ai_target) or not bool(_ai_target.call("is_riding"))):
            stop_ai_follow()

func _apply_throttle(throttle: float, delta: float) -> void:
    if throttle > 0.01:
        var ratio := clampf(absf(_speed) / max_speed, 0.0, 1.0)
        # Torque forte em baixa (estilo GTA engineAccel), perde força perto da Vmax.
        var rate := braking if _speed < -0.05 else acceleration * (1.0 - ratio * 0.72)
        _speed = move_toward(_speed, max_speed * throttle, rate * delta)
    elif throttle < -0.01:
        if _speed > 0.05:
            # Freio: desacelera rápido; parado, o mesmo comando dá ré devagar.
            _speed = move_toward(_speed, 0.0, braking * delta)
        else:
            _speed = move_toward(_speed, -reverse_speed * -throttle, acceleration * 0.4 * delta)
    else:
        _speed = move_toward(_speed, 0.0, rolling_drag * delta)

func _hud_root() -> Node:
    return _ride_button.get_parent() if _ride_button != null else null

func _ensure_drive_buttons() -> void:
    # Os dois botões são criados una vez, na HUD compartilhada pelas duas motos.
    var hud := _hud_root()
    if hud == null:
        return
    if not hud.has_node("GasButton"):
        var gas := ScreenFactory.button("ACELERAR", DRIVE_BUTTON_SIDE)
        gas.name = "GasButton"
        _place_drive_button(gas, -150.0)
        hud.add_child(gas)
    _configure_accelerator_button(hud.get_node("GasButton") as Button)
    var brake: Button
    if hud.has_node("BrakeButton"):
        brake = hud.get_node("BrakeButton") as Button
    else:
        brake = ScreenFactory.button("FREAR", DRIVE_BUTTON_SIDE)
        brake.name = "BrakeButton"
        _place_drive_button(brake, -290.0)
        brake.button_down.connect(func() -> void: hud.set_meta("touch_brake", true))
        brake.button_up.connect(func() -> void: hud.set_meta("touch_brake", false))
        hud.add_child(brake)
    _set_drive_buttons_visible(false)

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
    var hud := _hud_root()
    if hud != null:
        hud.set_meta("touch_gas", true)
        hud.set_meta("touch_gas_power", power)

func _release_accelerator() -> void:
    var hud := _hud_root()
    if hud != null:
        hud.set_meta("touch_gas", false)
        hud.set_meta("touch_gas_power", 0.0)
        var button := hud.get_node_or_null("GasButton") as Button
        if button != null:
            button.set_meta("accelerator_dragging", false)

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
    var hud := _hud_root()
    if hud == null:
        return
    for node_name: String in ["GasButton", "BrakeButton"]:
        var control := hud.get_node_or_null(node_name) as Control
        if control != null:
            control.visible = on

func _set_riding_hud(on: bool) -> void:
    var hud := _hud_root()
    if hud == null:
        return
    for node_name: String in HIDDEN_WHILE_RIDING:
        var control := hud.get_node_or_null(node_name) as Control
        if control == null or control == _ride_button:
            continue
        if on:
            if not control.has_meta("hidden_for_ride"):
                control.set_meta("hidden_for_ride", control.visible)
            control.visible = false
        elif control.has_meta("hidden_for_ride"):
            control.visible = bool(control.get_meta("hidden_for_ride"))
            control.remove_meta("hidden_for_ride")
    _set_drive_buttons_visible(on)
    if not on:
        hud.set_meta("touch_gas", false)
        hud.set_meta("touch_brake", false)

func _toggle_riding() -> void:
    var target := _nearest_ride_target()
    if target != null and target.has_method("toggle_riding_from_universal"):
        target.toggle_riding_from_universal()

func toggle_riding_from_universal() -> void:
    if _riding:
        if not _mounting and not _dismounting:
            _start_dismount()
    elif is_near_player():
        _start_mount()

func is_near_player() -> bool:
    if _player == null or _riding:
        return false
    if _player.has_method("is_gorece_active") and _player.is_gorece_active():
        return false
    var distance := Vector2(global_position.x - _player.global_position.x, global_position.z - _player.global_position.z).length()
    return distance <= MOUNT_INTERACTION_DISTANCE

func _nearest_ride_target() -> Node:
    var nearest: Node = null
    var nearest_distance := INF
    for sibling in get_parent().get_children():
        if not sibling.has_method("toggle_riding_from_universal") or not sibling.has_method("is_riding"):
            continue
        if sibling.has_method("is_ai_following") and bool(sibling.call("is_ai_following")):
            continue
        if sibling.is_riding():
            return sibling
        if not sibling.is_near_player():
            continue
        var distance := Vector2(sibling.global_position.x - _player.global_position.x, sibling.global_position.z - _player.global_position.z).length()
        if distance < nearest_distance:
            nearest_distance = distance
            nearest = sibling
    return nearest

func _update_universal_ride_button() -> void:
    if _ride_button == null:
        return
    var target := _nearest_ride_target()
    if target != null and target.is_riding():
        _ride_button.text = "SAIR DE " + String(target.get("vehicle_display_name"))
        _ride_button.disabled = false
    elif target != null:
        _ride_button.text = "MONTAR " + String(target.get("vehicle_display_name"))
        _ride_button.disabled = false
    else:
        _ride_button.text = "APROXIME-SE DA MOTO"
        _ride_button.disabled = true

func _start_mount() -> void:
    if not is_near_player() or _network_mount_pending:
        return
    _refresh_rider_visual()
    if _rider_visual == null or _rider_animator == null:
        return
    for sibling in get_parent().get_children():
        if sibling != self and sibling.has_method("is_riding") and sibling.is_riding():
            return
    var multiplayer_client := get_node_or_null("../OnlineMultiplayer")
    if multiplayer_client != null and bool(multiplayer_client.get("enabled")):
        _network_mount_pending = true
        var vehicle_id := _stable_vehicle_id()
        var granted: bool = await multiplayer_client.request_vehicle_claim(vehicle_id)
        _network_mount_pending = false
        if not granted or not is_near_player():
            if granted:
                multiplayer_client.release_vehicle(vehicle_id)
            return
    for sibling in get_parent().get_children():
        if sibling != self and sibling.has_method("is_riding") and sibling.is_riding():
            _release_network_vehicle()
            return
    _stop_rider_grip_ik()
    _grips_calibrated = false
    _grip_calibration_frames = 0
    _riding = true
    _mounting = true
    _cam_yaw = 0.0
    _cam_pitch = 0.0
    _speed = 0.0
    _lean = 0.0
    _wheelie = 0.0
    _apply_lean()
    var seat_world := global_transform * rider_seat_offset
    if _player != null:
        var hilux := get_node_or_null("../HiluxSRX2017") as HiluxController
        if hilux != null and _player.has_method("set_companion_vehicle_target"):
            _player.call("set_companion_vehicle_target", hilux)
        _player.set_physics_process(false)
        _player.set_process(false)
        _player.visible = true
        _player.collision_layer = 0
        _player.collision_mask = 0
        # A montagem só é permitida perto da moto; começa na posição atual do personagem.
        _mount_from_pos = _player.global_position
        _mount_from_yaw = _rider_visual.global_rotation.y if _rider_visual != null else global_rotation.y
    if _camera != null:
        _camera.current = true
    if _ride_button != null:
        _ride_button.text = "DESCER DA MOTO"
    _set_riding_hud(true)
    # Toca a animação ANTES de posicionar, pra o progresso começar em 0.
    _play_rider_animation(BIKE_MOUNT_ANIMATION, false, MOUNT_BLEND)
    if _rider_animator == null:
        _mounting = false
    _place_rider()
    _update_panel()

func _refresh_rider_visual() -> void:
    if _player == null:
        _rider_visual = null
        _rider_animator = null
        _rider_skeleton = null
        return
    _rider_visual = _player.get("visual") as Node3D
    if _rider_visual == null:
        _rider_visual = _player.get_node_or_null("AndreVisual") as Node3D
    if _rider_visual == null:
        _rider_animator = null
        _rider_skeleton = null
        return
    _rider_animator = _find_animation_player(_rider_visual)
    _rider_skeleton = _find_skeleton(_rider_visual)
    _rider_visual_offset = _rider_visual.position
    _setup_rider_grip_ik()

func _start_dismount() -> void:
    _dismounting = true
    _speed = 0.0
    _lean = 0.0
    _wheelie = 0.0
    _apply_lean()
    _play_rider_animation(BIKE_GETOFF_ANIMATION, false, MOUNT_BLEND)
    if _ride_button != null:
        _ride_button.disabled = true
    if _rider_animator == null:
        _finish_dismount()
        return
    _update_panel()

func _finish_dismount() -> void:
    _dismounting = false
    _set_riding_hud(false)
    _riding = false
    _mounting = false
    _release_network_vehicle()
    _stop_rider_grip_ik()
    _update_steering_parts(0.0)
    var heading := global_rotation.y
    if _player != null:
        # Desce pelo lado ESQUERDO (a animação é getoffLHS), no chão.
        _player.global_position = _dismount_target()
        # O corpo do Player nunca gira; quem gira é o visual. Assim o andar normal
        # (third_person.gd) continua apontando pro lado certo depois de descer.
        _player.global_rotation = Vector3.ZERO
        _player.velocity = Vector3.ZERO
        if _rider_visual != null:
            _rider_visual.position = _rider_visual_offset
            _rider_visual.global_rotation = Vector3(0.0, heading, 0.0)
        # Câmera e animação do jogador voltam coerentes com a moto.
        _player.set("_camera_yaw", heading)
        _player.set("_playing_animation", "")
        _player.visible = true
        _player.collision_layer = 1
        _player.collision_mask = 1
        _player.set_process(true)
        _player.set_physics_process(true)
        if _player.has_method("set_companion_vehicle_target"):
            _player.call("set_companion_vehicle_target", null)
        if _player.has_method("restore_vehicle_exit_pose"):
            _player.call_deferred("restore_vehicle_exit_pose", heading)
    _play_rider_animation("IDLE_stance", true, MOUNT_BLEND)
    if _ride_button != null:
        _ride_button.disabled = false
        _ride_button.text = ride_button_idle_text
    _update_panel()

func _dismount_target() -> Vector3:
    var target := global_transform * Vector3(DISMOUNT_SIDE_OFFSET, 0.0, rider_seat_offset.z)
    target.y = ground_y
    return target

func _animation_progress() -> float:
    if _rider_animator == null or _rider_animator.current_animation_length <= 0.0:
        return 1.0
    return clampf(_rider_animator.current_animation_position / _rider_animator.current_animation_length, 0.0, 1.0)

func _lean_transform() -> Transform3D:
    # Inclina (roll nas curvas) + grau (pitch: roda dianteira sobe).
    # Pivot no eixo do pneu traseiro pra o grau parecer natural.
    var rear_z := 0.0
    if _rear_wheel != null:
        rear_z = _rear_wheel.position.z
    var pivot := Vector3(0.0, _ground_local_y, rear_z)
    # Pitch positivo em X levanta a frente (grau).
    var pitch := Basis(Vector3.RIGHT, _wheelie)
    var roll := Basis(Vector3.BACK, _lean)
    var rot := roll * pitch
    return Transform3D(rot, pivot - rot * pivot)

func _apply_lean() -> void:
    if _visual_root != null:
        _visual_root.transform = _lean_transform()

func _update_lean(steer: float, delta: float) -> void:
    var speed_factor := clampf(absf(_speed) / max_speed, 0.0, 1.0)
    # Rotação positiva em Z joga o topo pra ESQUERDA, então curva à direita = ângulo negativo.
    var target := -steer * MAX_LEAN * speed_factor
    # Em grau alto, reduz a inclinação lateral (mais estável).
    target *= clampf(1.0 - _wheelie / MAX_WHEELIE * 0.7, 0.3, 1.0)
    _lean = move_toward(_lean, target, LEAN_SPEED * MAX_LEAN * delta)
    _apply_lean()

func _update_wheelie(throttle: float, wheelie_input: float, delta: float) -> void:
    # Grau: puxar o analógico pra baixo + acelerando.
    # Também sobe sozinho um pouco se acelerar forte de baixa (opcional leve).
    var want_wheelie := false
    if throttle > 0.4 and _speed > -0.1:
        if wheelie_input > 0.25:
            want_wheelie = true
        elif _speed < max_speed * 0.35 and throttle > 0.85 and wheelie_input < 0.1:
            # Arranque forte sem puxar o stick: sobe um pouco sozinho (grau leve).
            want_wheelie = _speed > 0.8
    if want_wheelie and wheelie_input > 0.25:
        var target := MAX_WHEELIE * clampf(wheelie_input, 0.0, 1.0)
        # Mais fácil empinar em baixa velocidade.
        var ease := clampf(1.2 - absf(_speed) / max_speed, 0.35, 1.0)
        _wheelie = move_toward(_wheelie, target * ease, WHEELIE_UP_SPEED * delta)
    elif want_wheelie and throttle > 0.85 and _speed < max_speed * 0.35:
        _wheelie = move_toward(_wheelie, MAX_WHEELIE * 0.35, WHEELIE_UP_SPEED * 0.45 * delta)
    else:
        # Freio ou soltar o stick = desce o grau.
        var down := WHEELIE_DOWN_SPEED
        if throttle < -0.1:
            down *= 1.8
        _wheelie = move_toward(_wheelie, 0.0, down * delta)
    _apply_lean()

func _place_rider() -> void:
    if _player == null:
        return
    var yaw := global_rotation.y
    var feet := global_transform * rider_seat_offset
    var visual_origin := feet + _rider_visual_offset
    var visual_basis := Basis(Vector3.UP, yaw)
    if _mounting:
        var k := smoothstep(0.0, 0.75, _animation_progress())
        feet = _mount_from_pos.lerp(feet, k)
        visual_origin = feet + _rider_visual_offset
        visual_basis = Basis(Vector3.UP, lerp_angle(_mount_from_yaw, yaw, k))
    elif _dismounting:
        var k := smoothstep(0.2, 1.0, _animation_progress())
        feet = feet.lerp(_dismount_target(), k)
        visual_origin = feet + _rider_visual_offset
    else:
        # Pilotando: o piloto acompanha a inclinação da moto.
        var lean_t := _lean_transform()
        visual_origin = global_transform * (lean_t * (rider_seat_offset + _rider_visual_offset))
        visual_basis = global_transform.basis * lean_t.basis
    _player.global_position = feet
    if _rider_visual != null:
        # O visual do Andre é quem aponta pra frente (third_person.gd gira ele, não o Player).
        # Antes só o Player girava e o piloto ficava virado pra onde andou por último.
        _rider_visual.global_transform = Transform3D(visual_basis.scaled(_rider_visual.scale), visual_origin)

func _follow_with_player_and_camera() -> void:
    _place_rider()
    if _camera != null and not _ai_driving:
        # Órbita em volta da moto: mesma distância e altura da posição base.
        var dist := sqrt(CAM_BASE_OFFSET.y * CAM_BASE_OFFSET.y + CAM_BASE_OFFSET.z * CAM_BASE_OFFSET.z)
        var base_pitch := atan2(CAM_BASE_OFFSET.y, CAM_BASE_OFFSET.z)
        var pitch := base_pitch + _cam_pitch
        var offset := Vector3(
            sin(_cam_yaw) * dist * cos(pitch),
            dist * sin(pitch),
            cos(_cam_yaw) * dist * cos(pitch)
        )
        _camera.global_position = global_position + global_transform.basis * offset
        _camera.look_at(global_position + Vector3.UP * 1.0, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
    if not _riding or _mounting or _dismounting or _ai_driving:
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _cam_drag_mouse = event.pressed
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion and _cam_drag_mouse:
        _orbit_camera(event.relative)
        get_viewport().set_input_as_handled()
    elif event is InputEventScreenTouch:
        # Só o lado direito da tela gira a câmera; o esquerdo é o joystick.
        if event.position.x > get_viewport().get_visible_rect().size.x * 0.42:
            if event.pressed and _cam_touch_id == -1:
                _cam_touch_id = event.index
                _cam_last_touch = event.position
            elif not event.pressed and event.index == _cam_touch_id:
                _cam_touch_id = -1
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag and event.index == _cam_touch_id:
        _orbit_camera(event.position - _cam_last_touch)
        _cam_last_touch = event.position
        get_viewport().set_input_as_handled()

func _orbit_camera(delta: Vector2) -> void:
    _cam_yaw -= delta.x * CAM_YAW_SPEED
    _cam_pitch = clampf(_cam_pitch + delta.y * CAM_PITCH_SPEED, CAM_PITCH_MIN, CAM_PITCH_MAX)

func _update_rider_animation(throttle: float, steer: float) -> void:
    # Ré ou quase parado: animação de pé no chão empurrando a moto (BIKEd_pushes).
    var is_reversing := _speed < -0.08 or (throttle < -0.05 and _speed < 0.25)
    var is_almost_stopped := absf(_speed) < 0.18 and absf(throttle) < 0.05
    var is_wheelie := _wheelie > 0.12

    if is_reversing:
        _play_rider_animation(BIKE_PUSHES_ANIMATION, true)
    elif is_wheelie:
        # Grau: usa a animação de inclinar pra trás (BIKEd_Back).
        _play_rider_animation(BIKE_BACK_ANIMATION, true)
    elif absf(steer) > 0.2 and absf(_speed) > 0.2:
        _play_rider_animation(BIKE_LEFT_ANIMATION if steer < 0.0 else BIKE_RIGHT_ANIMATION, true)
    elif throttle > 0.05:
        _play_rider_animation(BIKE_FORWARD_ANIMATION, true)
    elif is_almost_stopped:
        if _rider_animator != null and _rider_animator.has_animation(BIKE_STILL_ANIMATION):
            _play_rider_animation(BIKE_STILL_ANIMATION, true)
        else:
            _play_rider_animation(BIKE_IDLE_ANIMATION, true)
    else:
        _play_rider_animation(BIKE_IDLE_ANIMATION, true)

func _get_ai_follow_inputs() -> Vector2:
    if not is_instance_valid(_ai_target):
        return Vector2.ZERO
    var target_forward := -_ai_target.global_transform.basis.z
    target_forward.y = 0.0
    var target_point := _ai_target.global_position - target_forward.normalized() * 5.5
    var offset := target_point - global_position
    offset.y = 0.0
    var distance := offset.length()
    if distance < 0.1:
        return Vector2.ZERO
    var local_offset := global_transform.basis.inverse() * offset
    var turn_angle := atan2(local_offset.x, -local_offset.z)
    var steer := clampf(turn_angle * 1.5, -1.0, 1.0)
    var desired_speed := clampf((distance - 2.5) * 0.9, 0.0, max_speed * 0.78)
    if absf(_speed) > desired_speed + 0.7:
        return Vector2(-1.0, steer)
    if desired_speed > _speed + 0.45:
        return Vector2(1.0, steer)
    return Vector2(0.0, steer)

func start_ai_follow(target: Node3D) -> bool:
    if _riding or target == null or _player == null or _rider_visual == null or _rider_animator == null:
        return false
    if not _rider_animator.has_animation(BIKE_MOUNT_ANIMATION) or not _rider_animator.has_animation(BIKE_FORWARD_ANIMATION):
        return false
    _ai_driving = true
    _ai_target = target
    _riding = true
    _mounting = true
    _dismounting = false
    _speed = 0.0
    _lean = 0.0
    _wheelie = 0.0
    _apply_lean()
    _mount_from_pos = _player.global_position
    _mount_from_yaw = _rider_visual.global_rotation.y
    _player.velocity = Vector3.ZERO
    _player.set_physics_process(false)
    _player.visible = true
    _player.collision_layer = 0
    _player.collision_mask = 0
    _play_rider_animation(BIKE_MOUNT_ANIMATION, false, MOUNT_BLEND)
    _player.call("set_follow_vehicle", self)
    _place_rider()
    return true

func stop_ai_follow() -> void:
    if not _ai_driving or _dismounting:
        return
    _speed = 0.0
    _dismounting = true
    _mounting = false
    _play_rider_animation(BIKE_GETOFF_ANIMATION, false, MOUNT_BLEND)
    if _rider_animator == null or not _rider_animator.has_animation(BIKE_GETOFF_ANIMATION):
        _finish_ai_dismount()

func is_ai_following() -> bool:
    return _ai_driving

func _finish_ai_dismount() -> void:
    var heading := global_rotation.y
    var target_position := _dismount_target()
    _riding = false
    _mounting = false
    _dismounting = false
    _ai_driving = false
    _ai_target = null
    _speed = 0.0
    _stop_rider_grip_ik()
    _update_steering_parts(0.0)
    if _player != null:
        _player.global_position = target_position
        _player.global_rotation = Vector3.ZERO
        _player.velocity = Vector3.ZERO
        if _rider_visual != null:
            _rider_visual.position = _rider_visual_offset
            _rider_visual.global_rotation = Vector3(0.0, heading, 0.0)
        _player.visible = true
        _player.collision_layer = 1
        _player.collision_mask = 1
        _player.set_physics_process(true)
        _player.call("set_follow_vehicle", null)
        if _player.has_method("restore_vehicle_exit_pose"):
            _player.call_deferred("restore_vehicle_exit_pose", heading)
    _play_rider_animation("IDLE_stance", true, MOUNT_BLEND)

func _play_rider_animation(animation_name: String, loop: bool, blend: float = RIDER_BLEND) -> void:
    if _rider_animator == null or not _rider_animator.has_animation(animation_name):
        return
    var animation := _rider_animator.get_animation(animation_name)
    animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
    _rider_animator.speed_scale = BIKE_ANIMATION_SPEED
    if _rider_animator.current_animation != animation_name:
        _rider_animator.play(animation_name, blend)

func _update_steering_parts(steer: float) -> void:
    var angle := steer * steering_angle
    if _handlebar != null and handlebar_pivot_at_center:
        _handlebar.transform = _handlebar_pivot_transform(handlebar_rest_offset, -angle)
        if _retro != null:
            _retro.transform = _handlebar_pivot_transform(_retro_base, -angle)
    elif _handlebar != null:
        _handlebar.rotation = _handlebar_base_rotation
        _handlebar.rotate_y(-angle)
    if _dashboard != null:
        _dashboard.rotation = _dashboard_base_rotation
        _dashboard.rotate_y(-angle)
    _apply_front_steering(-angle)
    _update_rider_grip_ik()

func _apply_front_steering(yaw: float) -> void:
    var turn := Basis(Vector3.UP, yaw)
    if _front_fork != null:
        _front_fork.transform = _steered_part_transform(_front_fork_base, turn)
    if _front_wheel != null:
        var wheel_transform := _steered_part_transform(_front_wheel_base, turn)
        wheel_transform.basis *= Basis(Vector3.RIGHT, _front_spin_angle)
        _front_wheel.transform = wheel_transform
    if _front_mudguard != null:
        _front_mudguard.transform = _steered_part_transform(_front_mudguard_base, turn)

func _steered_part_transform(base: Transform3D, turn: Basis) -> Transform3D:
    var position := _front_steering_pivot + turn * (base.origin - _front_steering_pivot)
    return Transform3D(turn * base.basis, position)

func _apply_wheel_spin() -> void:
    if _rear_wheel != null:
        var rear_transform := _rear_wheel_base
        rear_transform.basis *= Basis(Vector3.RIGHT, _rear_spin_angle)
        _rear_wheel.transform = rear_transform

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
    if _front_wheel != null:
        _front_spin_angle = wrapf(_front_spin_angle - longitudinal_speed / maxf(_front_radius, 0.05) * delta, -TAU, TAU)
    if _rear_wheel != null:
        _rear_spin_angle = wrapf(_rear_spin_angle - longitudinal_speed / maxf(_rear_radius, 0.05) * delta, -TAU, TAU)
    _apply_front_steering(0.0)
    _apply_wheel_spin()

func get_network_wheelie() -> float:
    return _wheelie if _riding and not _mounting and not _dismounting else 0.0

func set_remote_wheelie(value: float) -> void:
    # O observador só aplica a inclinação visual recebida; não assume a física
    # nem altera a posição autoritativa da moto local.
    _wheelie = clampf(value, 0.0, MAX_WHEELIE)
    _apply_lean()

func _setup_rider_grip_ik() -> void:
    if _rider_skeleton == null:
        return
    _left_upper_bone = _rider_skeleton.find_bone(" L UpperArm")
    _left_forearm_bone = _rider_skeleton.find_bone(" L ForeArm")
    _left_hand_bone = _rider_skeleton.find_bone(" L Hand")
    _right_upper_bone = _rider_skeleton.find_bone(" R UpperArm")
    _right_forearm_bone = _rider_skeleton.find_bone(" R ForeArm")
    _right_hand_bone = _rider_skeleton.find_bone(" R Hand")
    if _left_upper_bone < 0 or _left_forearm_bone < 0 or _left_hand_bone < 0:
        return
    if _right_upper_bone < 0 or _right_forearm_bone < 0 or _right_hand_bone < 0:
        return
    var unique_suffix := str(get_instance_id())
    _left_grip_target = Node3D.new()
    _left_grip_target.name = "LeftGripTarget_" + unique_suffix
    _rider_skeleton.add_child(_left_grip_target)
    _right_grip_target = Node3D.new()
    _right_grip_target.name = "RightGripTarget_" + unique_suffix
    _rider_skeleton.add_child(_right_grip_target)

func _update_rider_grip_ik() -> void:
    if not _riding or _mounting or _dismounting or _handlebar == null or _rider_skeleton == null:
        _stop_rider_grip_ik()
        return
    if _left_grip_target == null or _right_grip_target == null:
        _stop_rider_grip_ik()
        return
    if not _grips_calibrated:
        if _grip_calibration_frames < 2:
            _grip_calibration_frames += 1
            return
        var bar_inverse := _handlebar.global_transform.affine_inverse()
        var left_hand_world := _rider_skeleton.global_transform * _rider_skeleton.get_bone_global_pose(_left_hand_bone)
        var right_hand_world := _rider_skeleton.global_transform * _rider_skeleton.get_bone_global_pose(_right_hand_bone)
        _left_grip_local = bar_inverse * left_hand_world
        _right_grip_local = bar_inverse * right_hand_world
        _grips_calibrated = true
    var left_target_world := _handlebar.global_transform * _left_grip_local
    var right_target_world := _handlebar.global_transform * _right_grip_local
    _left_grip_target.global_transform = left_target_world
    _right_grip_target.global_transform = right_target_world
    _solve_arm_to_target(_left_upper_bone, _left_forearm_bone, _left_hand_bone, left_target_world)
    _solve_arm_to_target(_right_upper_bone, _right_forearm_bone, _right_hand_bone, right_target_world)

func _solve_arm_to_target(upper_bone: int, forearm_bone: int, hand_bone: int, target_world: Transform3D) -> void:
    if upper_bone < 0 or forearm_bone < 0 or hand_bone < 0:
        return
    var target_local := _rider_skeleton.global_transform.affine_inverse() * target_world
    var upper_pose := _rider_skeleton.get_bone_global_pose(upper_bone)
    var forearm_pose := _rider_skeleton.get_bone_global_pose(forearm_bone)
    var hand_pose := _rider_skeleton.get_bone_global_pose(hand_bone)
    var shoulder := upper_pose.origin
    var elbow := forearm_pose.origin
    var wrist := hand_pose.origin
    var upper_length := shoulder.distance_to(elbow)
    var forearm_length := elbow.distance_to(wrist)
    var aim := target_local.origin - shoulder
    if upper_length < 0.001 or forearm_length < 0.001 or aim.length_squared() < 0.000001:
        return

    var direction := aim.normalized()
    var reach := clampf(aim.length(), absf(upper_length - forearm_length) + 0.001, upper_length + forearm_length - 0.001)
    var along := (upper_length * upper_length - forearm_length * forearm_length + reach * reach) / (2.0 * reach)
    var elbow_height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
    var bend := elbow - shoulder
    bend -= direction * bend.dot(direction)
    if bend.length_squared() < 0.0001:
        bend = direction.cross(Vector3.UP)
    if bend.length_squared() < 0.0001:
        bend = direction.cross(Vector3.RIGHT)
    var elbow_target := shoulder + direction * along + bend.normalized() * elbow_height

    var upper_from := (elbow - shoulder).normalized()
    var upper_to := (elbow_target - shoulder).normalized()
    upper_pose.basis = Basis(Quaternion(upper_from, upper_to)) * upper_pose.basis
    _rider_skeleton.set_bone_global_pose(upper_bone, upper_pose)
    _rider_skeleton.force_update_all_bone_transforms()

    forearm_pose = _rider_skeleton.get_bone_global_pose(forearm_bone)
    hand_pose = _rider_skeleton.get_bone_global_pose(hand_bone)
    var forearm_from := hand_pose.origin - forearm_pose.origin
    var forearm_to := target_local.origin - forearm_pose.origin
    if forearm_from.length_squared() > 0.000001 and forearm_to.length_squared() > 0.000001:
        forearm_pose.basis = Basis(Quaternion(forearm_from.normalized(), forearm_to.normalized())) * forearm_pose.basis
        _rider_skeleton.set_bone_global_pose(forearm_bone, forearm_pose)
        _rider_skeleton.force_update_all_bone_transforms()

    hand_pose = _rider_skeleton.get_bone_global_pose(hand_bone)
    hand_pose.origin = target_local.origin
    hand_pose.basis = target_local.basis.orthonormalized()
    _rider_skeleton.set_bone_global_pose(hand_bone, hand_pose)
    _rider_skeleton.force_update_all_bone_transforms()

func _stop_rider_grip_ik() -> void:
    _grips_calibrated = false
    _grip_calibration_frames = 0

func _handlebar_pivot_transform(base: Vector3, yaw: float) -> Transform3D:
    # Gira a peça em volta do centro do guidão (coluna de direção), a partir da posição base dela.
    var rot := Basis(Vector3.UP, yaw)
    var pivot := handlebar_rest_offset + _handlebar_center_local
    return Transform3D(rot * Basis.from_scale(_bar_scale), rot * (base - pivot) + pivot)

func _update_panel() -> void:
    if _panel_label == null:
        return
    var kmh := absf(_speed) * 3.6
    if _riding:
        _panel_label.text = "%s  •  PILOTANDO\nVELOCIDADE: %03d km/h\nW/S ACELERAR • A/D VIRAR" % [vehicle_display_name, int(round(kmh))]
    else:
        _panel_label.text = "%s\nAPERTE O BOTÃO DA MOTO\nW/S ACELERAR • A/D VIRAR" % vehicle_display_name

func _stable_vehicle_id() -> String:
    if not network_vehicle_id.is_empty():
        return network_vehicle_id
    return "wayfarer_01" if "WAYFARER" in vehicle_display_name.to_upper() else "pop100_01"

func _release_network_vehicle() -> void:
    var multiplayer_client := get_node_or_null("../OnlineMultiplayer")
    if multiplayer_client != null and bool(multiplayer_client.get("enabled")):
        multiplayer_client.release_vehicle(_stable_vehicle_id())

func is_riding() -> bool:
    return _riding

func set_autopilot_controls(input: Vector2, enabled := true) -> void:
    _autopilot_active = enabled and _riding and not _ai_driving
    _autopilot_input = Vector2(clampf(input.x, -1.0, 1.0), clampf(input.y, -1.0, 1.0)) if _autopilot_active else Vector2.ZERO

func get_autopilot_speed() -> float:
    return _speed

func get_autopilot_speed_limit() -> float:
    return max_speed

func _find_animation_player(root: Node) -> AnimationPlayer:
    for child in root.get_children():
        if child is AnimationPlayer:
            return child as AnimationPlayer
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _find_skeleton(root: Node) -> Skeleton3D:
    for child in root.get_children():
        if child is Skeleton3D:
            return child as Skeleton3D
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_part(root: Node, wanted_name: String) -> Node3D:
    for child in root.get_children():
        if child.name.to_lower() == wanted_name.to_lower() and child is Node3D:
            return child as Node3D
        var found := _find_part(child, wanted_name)
        if found != null:
            return found
    return null
