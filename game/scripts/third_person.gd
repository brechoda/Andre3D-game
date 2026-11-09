extends CharacterBody3D

const MOVE_SPEED := 4.4
const RUN_MULTIPLIER := 1.55
const FOLLOW_RUN_DISTANCE := 6.0
const FOLLOW_WALK_DISTANCE := 4.5
const ACCELERATION := 18.0
const DECELERATION := 22.0
const AIR_DRAG := 0.55
const GRAVITY := 18.0
const CAMERA_DISTANCE := 5.4
const CAMERA_TARGET_HEIGHT := 0.92
const CAMERA_HEIGHT := 1.75
const MODEL_YAW_OFFSET := 0.0
const WALK_ANIMATION := "WALK_civi"
const RUN_ANIMATION := "run_civi"
const CROUCH_ANIMATION := "Player_Sneak"
const JUMP_ANIMATION := "JUMP_launch"
const IDLE_ANIMATION := "IDLE_stance"
const PUNCH_ANIMATION := "FightA_1"
const WEAPON_IDLE_ANIMATIONS := ["Gun_stand", "Gun_2_IDLE", "IDLE_armed"]
const WEAPON_FIRE_ANIMATION := "Gun_stand"
## Full GTA SA unarmed combo chain from ped.ifp (FightA_1 -> FightA_2 -> FightA_3).
const COMBO_ANIMATIONS := ["FightA_1", "FightA_2", "FightA_3"]
const HIT_REACTION_ANIMATIONS := ["HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3"]
const MELEE_REACH := 1.65
## Fraction of the current clip after which a new press queues the next hit.
const COMBO_QUEUE_FROM := 0.28
## Extra seconds after a clip ends where a late press still starts the next hit.
const COMBO_GRACE := 0.22
const JUMP_VELOCITY := 7.0
const JUMP_FORWARD_IMPULSE := 3.0
const JUMP_BUFFER_SECONDS := 0.14
const COYOTE_SECONDS := 0.12
const ANALOG_DEADZONE := 0.05
const MIN_ANALOG_SPEED := 0.18
const ANALOG_RUN_ON_THRESHOLD := 0.84
const ANALOG_RUN_OFF_THRESHOLD := 0.72
const NPC_SIMULATION_DISTANCE := 90.0
const VEHICLE_SIMULATION_DISTANCE := 120.0
const DISTANCE_LOD_INTERVAL := 0.5
const LOADING_ART_PATH := "res://assets/template/ui/loading_gta.png"
const MAP_READY_HOLD_SECONDS := 5.0

@onready var andre_visual: Node3D = $AndreVisual
@onready var dg_visual: Node3D = $DGVisual
var visual: Node3D
@onready var camera: Camera3D = $Camera3D
@onready var joystick: AndreVirtualJoystick = $"../HUD/Root/TouchJoystick"
@onready var movement_label: Label = $"../HUD/Root/MovementLabel"
@onready var coordinates_label: Label = $"../HUD/Root/CoordinatesLabel"
@onready var run_button: Button = $"../HUD/Root/RunButton"
@onready var crouch_button: Button = $"../HUD/Root/CrouchButton"
@onready var jump_button: Button = $"../HUD/Root/JumpButton"
@onready var action_button: Button = $"../HUD/Root/ActionButton"
@onready var weapon_button: Button = $"../HUD/Root/WeaponButton"
@onready var aim_button: Button = $"../HUD/Root/AimButton"
@onready var rifle_button: Button = $"../HUD/Root/RifleButton"
@onready var switch_button: Button = $"../HUD/Root/SwitchButton"
@onready var follow_button: Button = $"../HUD/Root/FollowButton"
@onready var pull_vehicle_button: Button = $"../HUD/Root/PullVehicleButton"
@onready var ride_button: Button = $"../HUD/Root/RideButton"
var _pull_vehicle_popup: PopupMenu
var _pull_vehicle_feedback_timer: Timer
@onready var microphone_button: Button = $"../HUD/Root/MicButton"
@onready var gorece: GoreceNpc = $"../GoreceNPC"

var _joystick_value := Vector2.ZERO
var _camera_yaw := 0.0
var _camera_pitch := 0.16
var _rotating_mouse := false
var _camera_touch_id := -1
var _last_camera_touch := Vector2.ZERO
var _running := false
var _analog_sprinting := false
var _crouching := false
var _jump_requested := false
var _jumping := false
var _spawn_grounded := false
var _spawn_wait_elapsed := 0.0
const SPAWN_MAP_WAIT_SECONDS := 3.0
var _jump_buffer_remaining := 0.0
var _coyote_remaining := 0.0
var _animation_player: AnimationPlayer
var _neck_skeleton: Skeleton3D
var _neck_bone := -1
var _neck_look_angle := 0.0
var _was_walking := false
var _playing_animation := ""
var _action_busy := false
var _combo_index := 0
var _combo_queued := false
var _combo_holding := false
var _combo_clip_length := 0.0
var _combo_elapsed := 0.0
var _combo_tween: Tween
var _combo_strike_resolved := false
var _pistol_attachment: AndrePistolAttachment
var _rifle_attachment: AndreRifleAttachment
var _weapon_equipped := true
var _weapon_aiming := false
var _weapon_action_busy := false
var _weapon_mode := "pistol"
var _active_character := 0 # 0 = Andre, 1 = GORECE, 2 = DG
var _follow_enabled := false
var _auto_mount_hilux_armed := false
var _mic_toggle_in_progress := false
var _follow_bike_target: Node3D
var _follow_vehicle: Node3D
var _online_mode := false
var _distance_lod_elapsed := DISTANCE_LOD_INTERVAL
var _map_loading_layer: CanvasLayer
var _map_loading_status: Label
var _map_loading_progress: ProgressBar
var _map_loading_percent: Label
var _map_ready_elapsed := 0.0

func _ready() -> void:
    # Atualiza a interface de veículos depois dos scripts de cada veículo,
    # que compartilham o mesmo botão na HUD.
    process_priority = 100
    _show_map_loading_screen()
    visual = andre_visual
    # O avatar local não pode depender do estado de conexão/mapa para ser renderizado.
    visible = true
    andre_visual.visible = true
    dg_visual.visible = false
    movement_label.visible = false
    movement_label.text = ""
    joystick.changed.connect(_on_joystick_changed)
    run_button.toggle_mode = true
    run_button.set_pressed_no_signal(false)
    run_button.text = "CORRER"
    run_button.toggled.connect(_on_run_button_toggled)
    crouch_button.toggled.connect(_on_crouch_toggled)
    jump_button.button_down.connect(_on_jump_button_down)
    action_button.button_down.connect(_on_action_button_down)
    action_button.button_up.connect(_on_action_button_up)
    weapon_button.toggled.connect(_on_weapon_toggled)
    aim_button.toggled.connect(_on_aim_toggled)
    rifle_button.pressed.connect(_on_rifle_pressed)
    switch_button.pressed.connect(_toggle_character)
    follow_button.pressed.connect(_toggle_follow)
    pull_vehicle_button.pressed.connect(_show_pull_vehicle_menu)
    _pull_vehicle_feedback_timer = Timer.new()
    _pull_vehicle_feedback_timer.one_shot = true
    _pull_vehicle_feedback_timer.wait_time = 1.6
    _pull_vehicle_feedback_timer.timeout.connect(_reset_pull_vehicle_button_text)
    add_child(_pull_vehicle_feedback_timer)
    _pull_vehicle_popup = PopupMenu.new()
    _pull_vehicle_popup.name = "PullVehiclePopup"
    $"../HUD/Root".add_child(_pull_vehicle_popup)
    _pull_vehicle_popup.add_item("Pop 100e", 0)
    _pull_vehicle_popup.add_item("Wayfarer R1200", 1)
    _pull_vehicle_popup.add_item("Hilux SRX 2017", 2)
    _pull_vehicle_popup.add_item("Fiat Uno", 3)
    _pull_vehicle_popup.id_pressed.connect(_on_pull_vehicle_selected)
    microphone_button.toggle_mode = true
    microphone_button.toggled.connect(_on_microphone_button_toggled)
    _set_microphone_button_state(VoiceChat.enabled)
    _register_remote_hud_elements()
    camera.current = true
    camera.add_to_group("graphics_camera")
    GraphicsSettings.apply()
    _animation_player = _find_animation_player(visual)
    _setup_pistol_for_visual()
    _setup_rifle_for_visual()
    weapon_button.set_pressed_no_signal(true)
    weapon_button.text = "GUARDAR"
    aim_button.disabled = false
    rifle_button.text = "M4"
    _apply_black_shoes()
    _apply_orange_clothes()
    _apply_dark_skin()
    _apply_black_beard()
    _apply_black_hair()
    _create_blue_eyes()
    _setup_neck_look()
    if _animation_player != null:
        for animation_name in [WALK_ANIMATION, RUN_ANIMATION, CROUCH_ANIMATION, IDLE_ANIMATION]:
            if _animation_player.has_animation(animation_name):
                _animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
        if _animation_player.has_animation(JUMP_ANIMATION):
            _animation_player.get_animation(JUMP_ANIMATION).loop_mode = Animation.LOOP_NONE
        for punch_name in COMBO_ANIMATIONS:
            if _animation_player.has_animation(punch_name):
                _animation_player.get_animation(punch_name).loop_mode = Animation.LOOP_NONE
    gorece.set_player_controlled(false)
    _apply_session_settings()
    _apply_selected_map_spawn()
    if _active_character == 1:
        _update_camera_for(gorece.global_position)
    else:
        _update_camera()
    call_deferred("_apply_remote_spawn")

func _register_remote_hud_elements() -> void:
    var scene_root := get_parent()
    if scene_root == null:
        return
    var hud_root := scene_root.get_node_or_null("HUD/Root") as Control
    if hud_root == null:
        return
    RemoteUIConfig.register_element("hud.root", hud_root)
    var elements := {
        "hud.vehicle_panel": hud_root.get_node_or_null("VehiclePanel"),
        "hud.coordinates": hud_root.get_node_or_null("CoordinatesLabel"),
        "hud.camera_hint": hud_root.get_node_or_null("CameraHint"),
        "hud.touch_joystick": hud_root.get_node_or_null("TouchJoystick"),
        "hud.touch_label": hud_root.get_node_or_null("TouchJoystick/TouchLabel"),
        "hud.run": hud_root.get_node_or_null("RunButton"),
        "hud.crouch": hud_root.get_node_or_null("CrouchButton"),
        "hud.jump": hud_root.get_node_or_null("JumpButton"),
        "hud.action": hud_root.get_node_or_null("ActionButton"),
        "hud.switch": hud_root.get_node_or_null("SwitchButton"),
        "hud.microphone": hud_root.get_node_or_null("MicButton"),
        "hud.ride": hud_root.get_node_or_null("RideButton"),
        "hud.follow": hud_root.get_node_or_null("FollowButton"),
        "hud.pull_vehicle": hud_root.get_node_or_null("PullVehicleButton"),
        "hud.gps": hud_root.get_node_or_null("GPSAutopilot"),
    }
    for element_id: String in elements:
        var element_node := elements[element_id] as Node
        if element_node != null:
            RemoteUIConfig.register_element(element_id, element_node)

func _update_ride_interaction_button() -> void:
    if not is_instance_valid(ride_button):
        return
    var scene_root := get_parent()
    if scene_root == null:
        ride_button.visible = false
        ride_button.disabled = true
        return

    var active_position: Vector3 = gorece.global_position if _active_character == 1 else global_position
    var selected_vehicle: Node3D
    var selected_is_ridden := false
    var nearest_distance := INF
    for candidate: Node in scene_root.get_children():
        if candidate == self or not candidate.has_method("is_riding"):
            continue
        if candidate.has_method("is_ai_following") and bool(candidate.call("is_ai_following")):
            continue
        var is_ridden := bool(candidate.call("is_riding"))
        if is_ridden:
            selected_vehicle = candidate as Node3D
            selected_is_ridden = true
            break
        if not candidate.has_method("is_near_player") or not bool(candidate.call("is_near_player")):
            continue
        var vehicle_node := candidate as Node3D
        if vehicle_node == null:
            continue
        var distance := active_position.distance_to(vehicle_node.global_position)
        if distance < nearest_distance:
            nearest_distance = distance
            selected_vehicle = vehicle_node

    if selected_vehicle == null:
        ride_button.visible = false
        ride_button.disabled = true
        return

    var vehicle_name := String(selected_vehicle.get("vehicle_display_name")).strip_edges()
    if vehicle_name.is_empty():
        vehicle_name = String(selected_vehicle.name)
    ride_button.text = ("SAIR DA " if selected_is_ridden else "DIRIGIR ") + vehicle_name
    ride_button.disabled = false
    ride_button.visible = true

func _apply_selected_map_spawn() -> void:
    var map_streamer := get_node_or_null("../MapStreamer")
    if map_streamer == null or not map_streamer.has_method("get_selected_spawn"):
        return
    var spawn: Vector3 = map_streamer.call("get_selected_spawn")
    global_position = spawn
    var gorece_spawn := spawn + Vector3(5.0, 0.0, 0.0)
    if map_streamer.has_method("get_selected_gorece_spawn"):
        gorece_spawn = map_streamer.call("get_selected_gorece_spawn")
    gorece.global_position = gorece_spawn
    var vehicle_offsets := {
        "pop100_01": Vector3(-10.0, -1.4, 0.0),
        "wayfarer_01": Vector3(-5.0, -1.1, 0.0),
        "hilux_01": Vector3(22.7, -1.0, 1.0),
        "fiatuno_01": Vector3(-20.0, -1.5, 0.0),
    }
    var vehicle_spawns: Dictionary = {}
    if map_streamer.has_method("get_selected_vehicle_spawns"):
        vehicle_spawns = map_streamer.call("get_selected_vehicle_spawns")
    for vehicle_id: String in vehicle_offsets:
        var vehicle := _find_spawn_vehicle(vehicle_id)
        if vehicle != null:
            vehicle.global_position = vehicle_spawns.get(vehicle_id, spawn + vehicle_offsets[vehicle_id])
            if vehicle.has_method("sync_map_ground_after_spawn"):
                vehicle.call("sync_map_ground_after_spawn")

func restore_vehicle_exit_pose(heading: float) -> void:
    # O Player permanece sem rotação durante o gameplay; somente o visual
    # aponta para a direção de saída. Isso evita que a pose de desembarque da
    # moto seja reaplicada pelo AnimationPlayer no primeiro passo.
    global_rotation = Vector3.ZERO
    velocity = Vector3.ZERO
    if visual != null:
        visual.global_rotation = Vector3(0.0, heading, 0.0)
    _camera_yaw = heading
    _playing_animation = ""
    if _animation_player != null:
        _animation_player.stop()
        _play_animation(IDLE_ANIMATION)

func _apply_remote_spawn() -> void:
    var json_text := RemoteUpdater.read_remote_text("config/spawn.json")
    if not json_text.is_empty():
        _apply_remote_spawn_payload(json_text)
    await RemoteUpdater.wait_until_ready(12.0)
    json_text = RemoteUpdater.read_remote_text("config/spawn.json")
    if json_text.is_empty():
        return
    _apply_remote_spawn_payload(json_text)

func _apply_remote_spawn_payload(json_text: String) -> void:
    var parsed: Variant = JSON.parse_string(json_text)
    if not parsed is Dictionary:
        push_warning("Spawn remoto inválido; usando posições padrão do APK.")
        return
    var config := (parsed as Dictionary).duplicate(true) as Dictionary
    if str(config.get("map", "")) != "liberty_city":
        push_warning("Spawn remoto ignorado: mapa incompatível.")
        return
    var map_streamer := get_node_or_null("../MapStreamer")
    var selected_region := "center"
    if map_streamer != null and map_streamer.has_method("get_selected_region_id"):
        selected_region = str(map_streamer.call("get_selected_region_id"))
    var regional_spawns: Variant = config.get("regional_spawns", {})
    if regional_spawns is Dictionary and (regional_spawns as Dictionary).has(selected_region):
        var regional_config: Variant = (regional_spawns as Dictionary)[selected_region]
        if regional_config is Dictionary:
            for key: String in ["player", "gorece", "vehicles"]:
                if (regional_config as Dictionary).has(key):
                    config[key] = (regional_config as Dictionary)[key]
            config["map_region"] = selected_region
    elif str(config.get("map_region", "")) != selected_region:
        push_warning("Spawn remoto de %s ignorado para a região selecionada %s." % [str(config.get("map_region", "")), selected_region])
        return
    var revision_parts: PackedStringArray = str(config.get("spawn_revision", "")).split("-")
    var spawn_revision: int = revision_parts[revision_parts.size() - 1].to_int() if not revision_parts.is_empty() else 0
    if spawn_revision < 3:
        push_warning("Spawn remoto antigo ignorado; usando os spawns corrigidos do APK.")
        return

    var player_data: Variant = config.get("player", {})
    if player_data is Dictionary:
        _apply_spawn_transform(self, player_data as Dictionary)
    var gorece_data: Variant = config.get("gorece", {})
    if gorece_data is Dictionary:
        _apply_spawn_transform(gorece, gorece_data as Dictionary)
    if _active_character == 1:
        var active_visual: Node3D = gorece.get_node_or_null("GoreceVisual") as Node3D
        _camera_yaw = active_visual.global_rotation.y if active_visual != null else gorece.global_rotation.y
        gorece.camera_yaw = _camera_yaw

    var vehicles: Variant = config.get("vehicles", {})
    if vehicles is Dictionary:
        for vehicle_id: String in (vehicles as Dictionary).keys():
            var vehicle_data: Variant = (vehicles as Dictionary)[vehicle_id]
            if not vehicle_data is Dictionary:
                continue
            var vehicle := _find_spawn_vehicle(vehicle_id)
            if vehicle != null:
                _apply_spawn_transform(vehicle, vehicle_data as Dictionary)

    if map_streamer != null and map_streamer.has_method("snap_body_to_map"):
        map_streamer.call("snap_body_to_map", self)
        map_streamer.call("snap_body_to_map", gorece)
    if _active_character == 1:
        _update_camera_for(gorece.global_position)
    else:
        _update_camera()

func _apply_spawn_transform(node: Node3D, data: Dictionary) -> bool:
    var raw_position: Variant = data.get("position", [])
    if not raw_position is Array or raw_position.size() != 3:
        return false
    var position_values: Array = raw_position
    var x := float(position_values[0])
    var y := float(position_values[1])
    var z := float(position_values[2])
    if not is_finite(x) or not is_finite(y) or not is_finite(z):
        return false
    if absf(x) > 5000.0 or absf(y) > 5000.0 or absf(z) > 5000.0:
        return false
    node.global_position = Vector3(x, y, z)
    var heading := deg_to_rad(clampf(float(data.get("rotation_y", 0.0)), -3600.0, 3600.0))
    if node == self:
        node.rotation = Vector3.ZERO
        if visual != null:
            visual.global_rotation = Vector3(0.0, heading, 0.0)
        _camera_yaw = heading
    else:
        node.rotation.y = heading
    if node.has_method("sync_map_ground_after_spawn"):
        node.call("sync_map_ground_after_spawn")
    return true

func _find_spawn_vehicle(vehicle_id: String) -> Node3D:
    for child: Node in get_parent().get_children():
        if child is Node3D and str(child.get("network_vehicle_id")) == vehicle_id:
            return child as Node3D
    return null

func _apply_session_settings() -> void:
    # O jogo agora opera exclusivamente online; o arquivo de sessão mantém
    # apenas a escolha do personagem para a sala multiplayer.
    var character := "andre"
    if FileAccess.file_exists("user://andre3d_session.json"):
        var file := FileAccess.open("user://andre3d_session.json", FileAccess.READ)
        if file != null:
            var data = JSON.parse_string(file.get_as_text())
            if typeof(data) == TYPE_DICTIONARY:
                character = String(data.get("character", "andre"))
    _online_mode = true
    var online_client := get_node_or_null("../OnlineMultiplayer")
    if online_client != null:
        online_client.enabled = true
    follow_button.visible = not _online_mode
    switch_button.visible = not _online_mode
    microphone_button.visible = _online_mode
    _follow_enabled = false
    if _online_mode:
        gorece.set_follow_target(null)
        gorece.set_follow_vehicle_target(null)
    var character_index := 2 if character == "dg" else (1 if character == "gorece" else 0)
    set_active_character(character_index)

func set_active_character(character_index: int) -> void:
    if _active_character == 1 and gorece != null:
        gorece.set_running(false)
    _running = false
    _analog_sprinting = false
    _crouching = false
    _active_character = clampi(character_index, 0, 2)
    if run_button != null:
        run_button.set_pressed_no_signal(false)
        run_button.text = "CORRER"
    if switch_button != null:
        switch_button.text = "TROCAR PERSONAGEM"
    if _active_character == 1:
        visible = true
        andre_visual.visible = false
        dg_visual.visible = false
        gorece.visible = true
        gorece.set_process(true)
        gorece.set_physics_process(true)
        gorece.set_player_controlled(true)
        _setup_pistol_for_visual()
        _setup_rifle_for_visual()
        var gorece_visual := gorece.get_node_or_null("GoreceVisual") as Node3D
        if gorece_visual == null:
            gorece_visual = gorece.get("visual") as Node3D
        var gorece_yaw := _camera_yaw
        if gorece_visual != null:
            gorece_yaw = gorece_visual.global_rotation.y
        gorece.camera_yaw = gorece_yaw
        gorece.camera_pitch = _camera_pitch
        _camera_yaw = gorece_yaw
        camera.current = true
        _update_camera_for(gorece.global_position)
        action_button.text = "ATIRAR"
    else:
        visible = true
        gorece.set_player_controlled(false)
        gorece.visible = not _online_mode
        gorece.set_process(not _online_mode)
        gorece.set_physics_process(not _online_mode)
        visual = dg_visual if _active_character == 2 else andre_visual
        andre_visual.visible = _active_character == 0
        dg_visual.visible = _active_character == 2
        _animation_player = _find_animation_player(visual)
        _configure_player_animations()
        _setup_neck_look()
        _setup_pistol_for_visual()
        _setup_rifle_for_visual()
        _camera_yaw = visual.global_rotation.y
        action_button.text = "ATIRAR"
        _update_camera()

func _configure_player_animations() -> void:
    if _animation_player == null:
        return
    for animation_name in [WALK_ANIMATION, RUN_ANIMATION, CROUCH_ANIMATION, IDLE_ANIMATION]:
        if _animation_player.has_animation(animation_name):
            _animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
    if _animation_player.has_animation(JUMP_ANIMATION):
        _animation_player.get_animation(JUMP_ANIMATION).loop_mode = Animation.LOOP_NONE
    for punch_name in COMBO_ANIMATIONS:
        if _animation_player.has_animation(punch_name):
            _animation_player.get_animation(punch_name).loop_mode = Animation.LOOP_NONE

func get_network_avatar() -> Node3D:
    return gorece if _active_character == 1 else self

func get_network_character_id() -> String:
    if _active_character == 1:
        return "gorece"
    return "dg" if _active_character == 2 else "andre"

func _physics_process(delta: float) -> void:
    if not is_instance_valid(visual):
        return
    if _map_loading_layer != null:
        velocity = Vector3.ZERO
        return
    if not is_zero_approx(rotation.y) or not is_zero_approx(rotation.x) or not is_zero_approx(rotation.z):
        rotation = Vector3.ZERO
    if not _spawn_grounded:
        var map_streamer := get_node_or_null("../MapStreamer")
        var snapped := false
        if map_streamer != null and map_streamer.has_method("snap_body_to_map"):
            snapped = bool(map_streamer.call("snap_body_to_map", self))
        if snapped:
            _spawn_grounded = true
            _spawn_wait_elapsed = 0.0
        else:
            # O mapa pode terminar o carregamento depois do jogador. Não bloqueie
            # o input indefinidamente: após a tolerância, usa o Y do spawn e deixa
            # o personagem andar; a colisão passa a corrigir a altura quando chegar.
            _spawn_wait_elapsed += delta
            if _spawn_wait_elapsed < SPAWN_MAP_WAIT_SECONDS:
                return
            _spawn_grounded = true
    if is_on_floor():
        _coyote_remaining = COYOTE_SECONDS
    else:
        _coyote_remaining = maxf(0.0, _coyote_remaining - delta)
    if _jump_requested:
        _jump_buffer_remaining = maxf(0.0, _jump_buffer_remaining - delta)
        if _jump_buffer_remaining <= 0.0:
            _jump_requested = false
    if _active_character == 1:
        if _follow_enabled:
            _try_auto_mount_hilux()
        if _follow_enabled and not is_instance_valid(_follow_vehicle):
            _physics_follow_companion(delta)
        return
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    if _joystick_value.length() > 0.05:
        input_vector = _joystick_value

    var run_from_look := _running and not _crouching and not _action_busy and input_vector.length() <= 0.05
    if run_from_look:
        # Com CORRER ativo, soltar o analógico mantém o personagem em corrida
        # na direção para a qual a câmara está apontada.
        input_vector = Vector2(0.0, -1.0)
    var analog_sprinting := _update_analog_sprinting()
    var sprinting := (_running or analog_sprinting) and not _crouching
    var analog_strength: float = 1.0 if run_from_look else clampf(input_vector.length(), 0.0, 1.0)
    var direction: Vector3 = _camera_relative_direction(input_vector)
    var walking: bool = (run_from_look or analog_strength > ANALOG_DEADZONE) and direction.length_squared() > 0.001
    if walking:
        direction = direction.normalized()
        var analog_speed_factor: float = 1.0 if sprinting else lerpf(MIN_ANALOG_SPEED, 1.0, analog_strength)
        var crouch_factor: float = 0.55 if _crouching else 1.0
        var current_speed: float = MOVE_SPEED * analog_speed_factor * crouch_factor * (RUN_MULTIPLIER if sprinting else 1.0)
        velocity.x = move_toward(velocity.x, direction.x * current_speed, ACCELERATION * delta)
        velocity.z = move_toward(velocity.z, direction.z * current_speed, ACCELERATION * delta)
    else:
        var horizontal_drag: float = DECELERATION if is_on_floor() else AIR_DRAG
        velocity.x = move_toward(velocity.x, 0.0, horizontal_drag * delta)
        velocity.z = move_toward(velocity.z, 0.0, horizontal_drag * delta)

    # Face the direction the body is actually travelling.  Turning directly
    # toward the stick/input made the run cycle look twisted during curves,
    # because the animation was still moving along the previous velocity.
    var facing := Vector3(velocity.x, 0.0, velocity.z)
    if facing.length_squared() < 0.01 and walking:
        facing = direction
    if facing.length_squared() > 0.01:
        _face_visual_toward(facing.normalized(), delta, 12.0)

    if _jump_requested and not _crouching and (is_on_floor() or _coyote_remaining > 0.0):
        velocity.y = JUMP_VELOCITY
        var jump_direction: Vector3 = direction.normalized() if walking else -visual.global_transform.basis.z
        jump_direction.y = 0.0
        if jump_direction.length_squared() > 0.001:
            jump_direction = jump_direction.normalized()
            velocity.x += jump_direction.x * JUMP_FORWARD_IMPULSE
            velocity.z += jump_direction.z * JUMP_FORWARD_IMPULSE
        _jumping = true
        _jump_requested = false
        _jump_buffer_remaining = 0.0
        _coyote_remaining = 0.0
        var online_client := get_node_or_null("../OnlineMultiplayer")
        if online_client != null and bool(online_client.get("enabled")):
            online_client.call("send_jump_event")
    elif is_on_floor():
        velocity.y = -0.25
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()
    var void_guard := get_node_or_null("../MapStreamer")
    if void_guard != null and void_guard.has_method("guard_body_from_void") and bool(void_guard.call("guard_body_from_void", self)):
        _jumping = false
        _coyote_remaining = 0.0
    if _jumping and is_on_floor() and velocity.y <= 0.0:
        _jumping = false
        if _animation_player != null and _playing_animation == JUMP_ANIMATION:
            _animation_player.stop()
            _playing_animation = ""
    _update_walk_animation(walking, analog_strength, sprinting)

func _process(_delta: float) -> void:
    _update_map_loading_screen(_delta)
    _update_follow_button()
    _update_follow_vehicle()
    if _active_character == 1:
        gorece.camera_yaw = _camera_yaw
        gorece.camera_pitch = _camera_pitch
        _update_camera_for(gorece.global_position)
    else:
        _update_camera()
    _update_coordinates_label()
    _update_neck_look(_delta)
    _distance_lod_elapsed += _delta
    if _distance_lod_elapsed >= DISTANCE_LOD_INTERVAL:
        _distance_lod_elapsed = 0.0
        _update_distance_lod()
    if _action_busy:
        _combo_elapsed += _delta
        _update_combo_chain()
    _update_ride_interaction_button()

func _show_map_loading_screen() -> void:
    _map_loading_layer = CanvasLayer.new()
    _map_loading_layer.name = "MapLoadingLayer"
    _map_loading_layer.layer = 100
    add_child(_map_loading_layer)

    var overlay := Control.new()
    overlay.name = "MapLoadingScreen"
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _map_loading_layer.add_child(overlay)

    var image := TextureRect.new()
    image.texture = load(LOADING_ART_PATH) as Texture2D
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(image)

    var shade := ColorRect.new()
    shade.color = Color(0.02, 0.03, 0.05, 0.48)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(shade)

    var bottom := VBoxContainer.new()
    bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    bottom.position = Vector2(-300, -160)
    bottom.size = Vector2(600, 130)
    bottom.add_theme_constant_override("separation", 10)
    overlay.add_child(bottom)

    var title := Label.new()
    title.text = "CARREGANDO A CIDADE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    title.add_theme_color_override("font_color", Color.WHITE)
    bottom.add_child(title)

    _map_loading_status = Label.new()
    _map_loading_status.text = "Carregando o mapa e as colisões iniciais..."
    _map_loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _map_loading_status.add_theme_font_size_override("font_size", 16)
    _map_loading_status.add_theme_color_override("font_color", Color("f6d58a"))
    bottom.add_child(_map_loading_status)

    _map_loading_progress = ProgressBar.new()
    _map_loading_progress.custom_minimum_size = Vector2(0, 24)
    _map_loading_progress.max_value = 100.0
    _map_loading_progress.show_percentage = false
    bottom.add_child(_map_loading_progress)

    _map_loading_percent = Label.new()
    _map_loading_percent.text = "Aguarde..."
    _map_loading_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _map_loading_percent.add_theme_font_size_override("font_size", 20)
    _map_loading_percent.add_theme_color_override("font_color", Color.WHITE)
    bottom.add_child(_map_loading_percent)

func _update_map_loading_screen(delta: float) -> void:
    if _map_loading_layer == null:
        return
    var map_streamer := get_node_or_null("../MapStreamer")
    var map_loaded := map_streamer != null and map_streamer.has_method("is_start_area_loaded") and bool(map_streamer.call("is_start_area_loaded"))
    if not map_loaded:
        _map_ready_elapsed = 0.0
        _map_loading_status.text = "Carregando o mapa e as colisões iniciais..."
        _map_loading_progress.value = 0.0
        _map_loading_percent.text = "Aguarde..."
        return

    _map_ready_elapsed += delta
    var progress := clampf(_map_ready_elapsed / MAP_READY_HOLD_SECONDS, 0.0, 1.0)
    var seconds_left := int(ceil(maxf(0.0, MAP_READY_HOLD_SECONDS - _map_ready_elapsed)))
    _map_loading_status.text = "Mapa carregado. Preparando entrada... %d s" % seconds_left
    _map_loading_progress.value = progress * 100.0
    _map_loading_percent.text = "%d%%" % int(round(progress * 100.0))
    if _map_ready_elapsed >= MAP_READY_HOLD_SECONDS:
        _map_loading_layer.queue_free()
        _map_loading_layer = null

func _update_distance_lod() -> void:
    var player_position := gorece.global_position if _active_character == 1 else global_position
    var npc_simulation_distance := 30.0 if GraphicsSettings.render_distance_level == 0 else NPC_SIMULATION_DISTANCE
    var vehicle_simulation_distance := 45.0 if GraphicsSettings.render_distance_level == 0 else VEHICLE_SIMULATION_DISTANCE
    if gorece != null and _active_character != 1 and not _online_mode:
        var npc_active := gorece.global_position.distance_to(player_position) <= npc_simulation_distance
        gorece.set_process(npc_active)
        gorece.set_physics_process(npc_active)
    for vehicle_name: String in ["Pop100e2024", "WayfarerR1200", "HiluxSRX2017"]:
        var vehicle := get_parent().get_node_or_null(vehicle_name) as Node3D
        if vehicle == null:
            continue
        var in_use := vehicle.has_method("is_riding") and bool(vehicle.call("is_riding"))
        var vehicle_active := in_use or vehicle.global_position.distance_to(player_position) <= vehicle_simulation_distance
        var ground_support_only := vehicle.has_method("_apply_map_ground_support")
        vehicle.set_process(vehicle_active)
        vehicle.set_physics_process(vehicle_active or ground_support_only)

func _camera_relative_direction(input_vector: Vector2) -> Vector3:
    if input_vector.length_squared() < 0.001:
        return Vector3.ZERO
    var forward := Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
    var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
    return right * input_vector.x + forward * (-input_vector.y)

func _face_visual_toward(direction: Vector3, delta: float, turn_rate: float) -> void:
    if visual == null or direction.length_squared() < 0.001:
        return
    var target_yaw := atan2(-direction.x, -direction.z) + MODEL_YAW_OFFSET
    var current_yaw := visual.global_rotation.y
    var next_yaw := lerp_angle(current_yaw, target_yaw, minf(1.0, delta * turn_rate))
    visual.global_rotation = Vector3(0.0, next_yaw, 0.0)

func _update_analog_sprinting() -> bool:
    var stick_strength := _joystick_value.length()
    if _crouching or stick_strength <= ANALOG_RUN_OFF_THRESHOLD:
        _analog_sprinting = false
    elif not _analog_sprinting and stick_strength >= ANALOG_RUN_ON_THRESHOLD:
        _analog_sprinting = true
    return _analog_sprinting

func _update_camera() -> void:
    _update_camera_for(global_position)

func _update_camera_for(target_position: Vector3) -> void:
    var horizontal_distance := cos(_camera_pitch) * CAMERA_DISTANCE
    var camera_offset := Vector3(
        sin(_camera_yaw) * horizontal_distance,
        CAMERA_HEIGHT + sin(_camera_pitch) * CAMERA_DISTANCE,
        cos(_camera_yaw) * horizontal_distance
    )
    camera.global_position = target_position + camera_offset
    camera.look_at(target_position + Vector3.UP * CAMERA_TARGET_HEIGHT, Vector3.UP)

func _update_walk_animation(walking: bool, analog_strength: float, sprinting: bool = false) -> void:
    if _animation_player == null:
        return
    if _action_busy:
        return
    var desired_animation := IDLE_ANIMATION
    if _jumping and _animation_player.has_animation(JUMP_ANIMATION):
        desired_animation = JUMP_ANIMATION
    elif _crouching and _animation_player.has_animation(CROUCH_ANIMATION):
        desired_animation = CROUCH_ANIMATION
    elif walking and sprinting and _animation_player.has_animation(RUN_ANIMATION):
        desired_animation = RUN_ANIMATION
    elif walking:
        desired_animation = WALK_ANIMATION
    if _playing_animation != desired_animation:
        if not _animation_player.has_animation(desired_animation):
            return
        _animation_player.play(desired_animation)
        _playing_animation = desired_animation
    var analog_animation_speed: float = 1.0 if _jumping else (1.22 if sprinting else lerpf(0.35, 1.0, analog_strength))
    var crouch_animation_factor: float = 0.85 if _crouching else 1.0
    _animation_player.speed_scale = analog_animation_speed * crouch_animation_factor
    _was_walking = walking

func _play_animation(animation_name: String, blend: float = 0.0) -> void:
    if _animation_player == null or not _animation_player.has_animation(animation_name):
        return
    if _playing_animation == animation_name and _animation_player.is_playing():
        return
    _animation_player.play(animation_name, blend)
    _playing_animation = animation_name

func _find_animation_player(root: Node) -> AnimationPlayer:
    for child in root.get_children():
        if child is AnimationPlayer:
            return child as AnimationPlayer
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _apply_black_shoes() -> void:
    for child in _mesh_instances(visual):
        var mesh_instance := child as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        for surface in range(mesh_instance.mesh.get_surface_count()):
            var source_material := mesh_instance.get_active_material(surface)
            if source_material == null:
                continue
            var material_name := source_material.resource_name.to_lower()
            if not material_name.contains("feet") and surface != 3:
                continue
            var shoe_material := source_material.duplicate() as StandardMaterial3D
            shoe_material.albedo_color = Color("08090b")
            shoe_material.metallic = 0.05
            shoe_material.roughness = 0.72
            mesh_instance.set_surface_override_material(surface, shoe_material)

func _apply_orange_clothes() -> void:
    for child in _mesh_instances(visual):
        var mesh_instance := child as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        for surface in range(mesh_instance.mesh.get_surface_count()):
            var source_material := mesh_instance.get_active_material(surface)
            if source_material == null:
                continue
            var material_name := source_material.resource_name.to_lower()
            if not material_name.contains("jbib") and not material_name.contains("lowr") and surface != 0 and surface != 2:
                continue
            var orange_material := source_material.duplicate() as StandardMaterial3D
            orange_material.albedo_color = Color("e87522")
            orange_material.metallic = 0.0
            orange_material.roughness = 0.78
            mesh_instance.set_surface_override_material(surface, orange_material)

func _apply_dark_skin() -> void:
    for child in _mesh_instances(visual):
        var mesh_instance := child as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        for surface in range(mesh_instance.mesh.get_surface_count()):
            var source_material := mesh_instance.get_active_material(surface)
            if source_material == null:
                continue
            var material_name := source_material.resource_name.to_lower()
            if not material_name.contains("head") and not material_name == "ol":
                continue
            var skin_material := source_material.duplicate() as StandardMaterial3D
            skin_material.albedo_color = Color("6f432f")
            skin_material.metallic = 0.0
            skin_material.roughness = 0.86
            mesh_instance.set_surface_override_material(surface, skin_material)

func _apply_black_beard() -> void:
    for child in _mesh_instances(visual):
        var mesh_instance := child as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        for surface in range(mesh_instance.mesh.get_surface_count()):
            var source_material := mesh_instance.get_active_material(surface)
            if source_material == null or not source_material.resource_name.to_lower().contains("berd"):
                continue
            var beard_material := source_material.duplicate() as StandardMaterial3D
            beard_material.albedo_color = Color("080808")
            beard_material.metallic = 0.0
            beard_material.roughness = 0.82
            mesh_instance.set_surface_override_material(surface, beard_material)

func _apply_black_hair() -> void:
    for child in _mesh_instances(visual):
        var mesh_instance := child as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        for surface in range(mesh_instance.mesh.get_surface_count()):
            var source_material := mesh_instance.get_active_material(surface)
            if source_material == null or not source_material.resource_name.to_lower().contains("hair"):
                continue
            var hair_material := source_material.duplicate() as StandardMaterial3D
            hair_material.albedo_color = Color("050505")
            hair_material.metallic = 0.0
            hair_material.roughness = 0.78
            mesh_instance.set_surface_override_material(surface, hair_material)

func _create_blue_eyes() -> void:
    var skeleton := _find_skeleton(visual)
    if skeleton == null:
        return
    var head_bone := skeleton.find_bone(" Head")
    if head_bone < 0:
        head_bone = skeleton.find_bone("Head")
    if head_bone < 0:
        return
    var attachment := BoneAttachment3D.new()
    attachment.name = "BlueEyesAttachment"
    attachment.bone_name = skeleton.get_bone_name(head_bone)
    skeleton.add_child(attachment)
    var eye_material := StandardMaterial3D.new()
    eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    eye_material.albedo_color = Color("2f9cff")
    eye_material.emission_enabled = true
    eye_material.emission = Color("1685ff")
    eye_material.emission_energy_multiplier = 1.4
    for side in [-1.0, 1.0]:
        var eye := MeshInstance3D.new()
        eye.name = "BlueEye"
        var eye_mesh := SphereMesh.new()
        eye_mesh.radius = 0.009
        eye_mesh.height = 0.018
        eye_mesh.material = eye_material
        eye.mesh = eye_mesh
        eye.position = Vector3(0.14, 0.105, side * 0.043)
        attachment.add_child(eye)

func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    for child in root.get_children():
        if child is MeshInstance3D:
            result.append(child as MeshInstance3D)
        result.append_array(_mesh_instances(child))
    return result

func _find_skeleton(root: Node) -> Skeleton3D:
    if root is Skeleton3D:
        return root as Skeleton3D
    for child in root.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _setup_neck_look() -> void:
    _neck_bone = -1
    _neck_skeleton = _find_skeleton(visual)
    if _neck_skeleton == null:
        return
    for bone_name in [" Neck", "Neck", "Bip01 Neck"]:
        _neck_bone = _neck_skeleton.find_bone(bone_name)
        if _neck_bone >= 0:
            break

func _update_neck_look(delta: float) -> void:
    if _active_character == 1 or _neck_skeleton == null or _neck_bone < 0:
        return
    var desired_angle := wrapf(_camera_yaw - visual.global_rotation.y, -PI, PI)
    desired_angle = clampf(desired_angle, deg_to_rad(-22.0), deg_to_rad(22.0))
    _neck_look_angle = lerpf(_neck_look_angle, desired_angle, min(1.0, delta * 7.0))
    var base_pose := _neck_skeleton.get_bone_global_pose_no_override(_neck_bone)
    var turned_basis := Basis(Vector3.UP, _neck_look_angle) * base_pose.basis
    var turned_pose := Transform3D(turned_basis, base_pose.origin)
    _neck_skeleton.set_bone_global_pose_override(_neck_bone, turned_pose, 0.8, false)

func _toggle_character() -> void:
    set_active_character((_active_character + 1) % 3)
    _sync_follow_target()

func _toggle_follow() -> void:
    _follow_enabled = not _follow_enabled
    _auto_mount_hilux_armed = _follow_enabled and _active_character == 1
    if not _follow_enabled:
        _stop_follow_vehicle()
        _follow_bike_target = null
    _sync_follow_target()
    _update_follow_button()

func _show_pull_vehicle_menu() -> void:
    if _pull_vehicle_popup != null:
        _pull_vehicle_popup.position = Vector2i(int(pull_vehicle_button.global_position.x), int(pull_vehicle_button.global_position.y + pull_vehicle_button.size.y))
        _pull_vehicle_popup.popup()
func _on_pull_vehicle_selected(index: int) -> void:
    var ids := ["pop100_01", "wayfarer_01", "hilux_01", "fiatuno_01"]
    if index < 0 or index >= ids.size():
        return
    var vehicle_id: String = ids[index]
    var vehicle := _find_spawn_vehicle(vehicle_id)
    if vehicle == null:
        show_pull_vehicle_feedback("VEÍCULO INDISPONÍVEL")
        return
    if vehicle.has_method("is_riding") and bool(vehicle.call("is_riding")):
        show_pull_vehicle_feedback("VEÍCULO EM USO")
        return
    var mp := get_parent().get_node_or_null("OnlineMultiplayer")
    if mp != null and mp.has_method("is_connected_to_server") and bool(mp.call("is_connected_to_server")):
        mp.call("request_vehicle_pull", vehicle_id)
        pull_vehicle_button.text = "SOLICITADO..."
    else:
        _pull_vehicle_locally(vehicle, vehicle_id)
func _pull_vehicle_locally(vehicle: Node, vehicle_id: String) -> void:
    var player_position: Vector3 = gorece.global_position if _active_character == 1 else global_position
    var player_yaw := gorece.global_rotation.y if _active_character == 1 else (visual.global_rotation.y if visual != null else global_rotation.y)
    var forward := Vector3(-sin(player_yaw), 0.0, -cos(player_yaw))
    var target := player_position + forward * 4.8
    if vehicle.has_method("pull_near_player") and bool(vehicle.call("pull_near_player", target, player_yaw)):
        show_pull_vehicle_feedback("VEÍCULO PUXADO")
    else:
        show_pull_vehicle_feedback("NÃO FOI POSSÍVEL")

func show_pull_vehicle_feedback(message: String) -> void:
    if not is_instance_valid(pull_vehicle_button):
        return
    pull_vehicle_button.text = message
    if _pull_vehicle_feedback_timer != null:
        _pull_vehicle_feedback_timer.start()

func _reset_pull_vehicle_button_text() -> void:
    if is_instance_valid(pull_vehicle_button):
        pull_vehicle_button.text = "PUXAR VEÍCULO"

func _update_follow_button() -> void:
    if follow_button == null:
        return
    follow_button.text = "PARAR DE SEGUIR" if _follow_enabled else "SEGUIR"

func _sync_follow_target() -> void:
    if gorece == null:
        return
    gorece.set_follow_target(self if _follow_enabled and _active_character != 1 else null)

func _update_follow_vehicle() -> void:
    if not _follow_enabled:
        return
    var hilux := get_node_or_null("../HiluxSRX2017") as HiluxController
    var following_hilux := _active_character == 1 and hilux != null and hilux.is_riding()
    if not following_hilux:
        if is_instance_valid(_follow_vehicle) and _follow_vehicle.has_method("stop_ai_follow"):
            _follow_vehicle.call("stop_ai_follow")
        _follow_bike_target = null
        return
    if is_instance_valid(_follow_vehicle):
        return
    if not is_instance_valid(_follow_bike_target):
        _follow_bike_target = _find_free_follow_bike()

func _try_auto_mount_hilux() -> void:
    if not _auto_mount_hilux_armed:
        return
    if is_instance_valid(_follow_bike_target) or is_instance_valid(_follow_vehicle):
        return
    var hilux := get_node_or_null("../HiluxSRX2017") as HiluxController
    if hilux == null:
        return
    if hilux.is_riding():
        _auto_mount_hilux_armed = false
        return
    if hilux.is_near_player():
        _auto_mount_hilux_armed = false
        hilux.toggle_riding_from_universal()

func _find_free_follow_bike() -> Node3D:
    var nearest: Node3D
    var nearest_distance := INF
    var fastest_speed := -INF
    for candidate in get_parent().get_children():
        if candidate == self or not candidate.has_method("start_ai_follow") or not candidate.has_method("is_riding"):
            continue
        if bool(candidate.call("is_riding")):
            continue
        var distance := Vector2(candidate.global_position.x - global_position.x, candidate.global_position.z - global_position.z).length()
        var candidate_speed := float(candidate.get("max_speed"))
        if candidate_speed > fastest_speed or (is_equal_approx(candidate_speed, fastest_speed) and distance < nearest_distance):
            nearest = candidate as Node3D
            nearest_distance = distance
            fastest_speed = candidate_speed
    return nearest

func _physics_follow_companion(delta: float) -> void:
    var hilux := get_node_or_null("../HiluxSRX2017") as HiluxController
    var walking_to_bike := _active_character == 1 and hilux != null and hilux.is_riding()
    var follow_target: Node3D = _follow_bike_target if walking_to_bike else gorece
    if follow_target == null or not is_instance_valid(follow_target):
        return
    if walking_to_bike and _follow_bike_target != null:
        var bike_distance := Vector2(_follow_bike_target.global_position.x - global_position.x, _follow_bike_target.global_position.z - global_position.z).length()
        if bike_distance <= 2.25:
            _running = false
            if _follow_bike_target.has_method("start_ai_follow") and bool(_follow_bike_target.call("start_ai_follow", hilux)):
                _follow_vehicle = _follow_bike_target
                _follow_bike_target = null
            return
    var offset := follow_target.global_position - global_position
    offset.y = 0.0
    var distance := offset.length()
    var desired_gap := 2.2 if not walking_to_bike else 1.2
    var direction := offset.normalized() if distance > desired_gap else Vector3.ZERO
    var walking := direction.length_squared() > 0.0
    if not walking:
        _running = false
    else:
        _running = (_running and distance > FOLLOW_WALK_DISTANCE) or distance >= FOLLOW_RUN_DISTANCE
    if walking:
        var follow_speed := MOVE_SPEED * (RUN_MULTIPLIER if _running else 1.0)
        var target_speed := minf(follow_speed, (distance - desired_gap) * 1.4)
        velocity.x = move_toward(velocity.x, direction.x * target_speed, ACCELERATION * delta)
        velocity.z = move_toward(velocity.z, direction.z * target_speed, ACCELERATION * delta)
        _face_visual_toward(direction, delta, 10.0)
    else:
        velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
        velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)
    if is_on_floor():
        velocity.y = -0.25
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()
    _update_walk_animation(walking, 1.0 if walking else 0.0, _running)

func _stop_follow_vehicle() -> void:
    if is_instance_valid(_follow_vehicle) and _follow_vehicle.has_method("stop_ai_follow"):
        _follow_vehicle.call("stop_ai_follow")

func is_follow_enabled() -> bool:
    return _follow_enabled

func set_follow_vehicle(vehicle: Node3D) -> void:
    _follow_vehicle = vehicle
    if vehicle == null:
        _follow_bike_target = null

func set_companion_vehicle_target(target: Node3D) -> void:
    if target != null and _follow_enabled and _active_character != 1:
        gorece.set_follow_target(null)
        gorece.set_follow_vehicle_target(target)
    else:
        gorece.set_follow_vehicle_target(null)
        _sync_follow_target()

func is_gorece_active() -> bool:
    return _active_character == 1

func _setup_pistol_for_visual() -> void:
    if _active_character == 1:
        if gorece != null and gorece.has_method("setup_pistol"):
            gorece.call("setup_pistol")
        return
    if is_instance_valid(_pistol_attachment):
        _pistol_attachment.clear()
        _pistol_attachment.queue_free()
    _pistol_attachment = AndrePistolAttachment.new()
    add_child(_pistol_attachment)
    if not _pistol_attachment.setup(visual):
        _pistol_attachment.queue_free()
        _pistol_attachment = null
    else:
        _pistol_attachment.set_equipped(_weapon_equipped)

func _setup_rifle_for_visual() -> void:
    if is_instance_valid(_rifle_attachment):
        _rifle_attachment.clear()
        _rifle_attachment.queue_free()
    _rifle_attachment = AndreRifleAttachment.new()
    add_child(_rifle_attachment)
    if not _rifle_attachment.setup(visual):
        _rifle_attachment.queue_free()
        _rifle_attachment = null
    else:
        _rifle_attachment.set_equipped(_weapon_equipped and _weapon_mode == "rifle")

func _on_rifle_pressed() -> void:
    if _active_character == 1:
        return
    _weapon_mode = "rifle"
    _weapon_equipped = true
    _weapon_aiming = false
    weapon_button.set_pressed_no_signal(false)
    weapon_button.text = "PISTOLA"
    rifle_button.text = "GUARDAR M4"
    aim_button.disabled = false
    if _pistol_attachment != null:
        _pistol_attachment.set_equipped(false)
    if _rifle_attachment != null:
        _rifle_attachment.set_equipped(true)
    _play_weapon_idle()

func _on_weapon_toggled(enabled: bool) -> void:
    _weapon_mode = "pistol"
    _weapon_equipped = enabled
    weapon_button.text = "GUARDAR" if enabled else "PISTOLA"
    rifle_button.text = "M4"
    aim_button.disabled = not enabled
    if not enabled:
        aim_button.set_pressed_no_signal(false)
        _weapon_aiming = false
    if _active_character == 1:
        if gorece != null and gorece.has_method("set_pistol_equipped"):
            gorece.call("set_pistol_equipped", enabled)
    elif _pistol_attachment != null:
        _pistol_attachment.set_equipped(enabled)
    if _rifle_attachment != null:
        _rifle_attachment.set_equipped(false)
    if enabled and _active_character != 1:
        _play_weapon_idle()

func _on_aim_toggled(aiming: bool) -> void:
    _weapon_aiming = aiming and _weapon_equipped
    aim_button.text = "PARAR MIRA" if _weapon_aiming else "MIRAR"
    if _active_character == 1:
        if gorece != null and gorece.has_method("set_pistol_aiming"):
            gorece.call("set_pistol_aiming", _weapon_aiming)
    elif _weapon_aiming:
        _play_weapon_idle()

func _play_weapon_idle() -> void:
    if _animation_player == null or not _weapon_equipped or _weapon_action_busy:
        return
    for animation_name in WEAPON_IDLE_ANIMATIONS:
        if _animation_player.has_animation(animation_name):
            var clip := _animation_player.get_animation(animation_name)
            clip.loop_mode = Animation.LOOP_LINEAR
            _animation_player.play(animation_name)
            _playing_animation = animation_name
            return

func _fire_pistol() -> void:
    if not _weapon_equipped:
        return
    if _active_character == 1:
        if gorece != null and gorece.has_method("fire_pistol"):
            gorece.call("fire_pistol")
        return
    if _animation_player == null or _weapon_action_busy:
        return
    var animation_name := WEAPON_FIRE_ANIMATION if _animation_player.has_animation(WEAPON_FIRE_ANIMATION) else "Gun_stand"
    if not _animation_player.has_animation(animation_name):
        return
    var clip := _animation_player.get_animation(animation_name)
    clip.loop_mode = Animation.LOOP_NONE
    _weapon_action_busy = true
    _action_busy = true
    _animation_player.speed_scale = 1.0
    _animation_player.play(animation_name)
    _playing_animation = animation_name
    var online_client := get_node_or_null("../OnlineMultiplayer")
    if online_client != null and online_client.get("enabled") and online_client.has_method("send_combat_event"):
        online_client.call("send_combat_event", "attack", animation_name)
    var timer := get_tree().create_timer(maxf(clip.length, 0.18))
    timer.timeout.connect(_finish_pistol_action)

func _finish_pistol_action() -> void:
    _weapon_action_busy = false
    _action_busy = false
    if _weapon_aiming:
        _play_weapon_idle()
    else:
        _play_animation(IDLE_ANIMATION)

func _on_action_button_down() -> void:
    if _weapon_equipped:
        _fire_pistol()
        return
    if _active_character == 1:
        gorece.set_action_holding(true)
        gorece.perform_action()
        return
    _combo_holding = true
    _perform_action()

func _on_action_button_up() -> void:
    _combo_holding = false
    if _active_character == 1:
        gorece.set_action_holding(false)

func _available_combo_clips() -> PackedStringArray:
    var clips := PackedStringArray()
    if _animation_player == null:
        return clips
    for punch_name in COMBO_ANIMATIONS:
        if _animation_player.has_animation(punch_name):
            clips.append(punch_name)
    return clips

func _perform_action() -> void:
    var clips := _available_combo_clips()
    if clips.is_empty():
        if _action_busy:
            return
        velocity.x = 0.0
        velocity.z = 0.0
        _perform_procedural_punch()
        return

    # Already in a punch: queue the next hit if we are past the early wind-up.
    if _action_busy and _playing_animation in COMBO_ANIMATIONS:
        if _combo_elapsed >= _combo_clip_length * COMBO_QUEUE_FROM:
            _combo_queued = true
        return

    velocity.x = 0.0
    velocity.z = 0.0
    _combo_index = 0
    _combo_queued = false
    _play_combo_step(clips)

func _play_combo_step(clips: PackedStringArray) -> void:
    if clips.is_empty():
        _finish_procedural_action()
        return
    _combo_index = clampi(_combo_index, 0, clips.size() - 1)
    var punch_name: String = clips[_combo_index]
    if _animation_player == null or not _animation_player.has_animation(punch_name):
        _perform_procedural_punch()
        return
    var punch_clip: Animation = _animation_player.get_animation(punch_name)
    if punch_clip == null:
        _perform_procedural_punch()
        return
    punch_clip.loop_mode = Animation.LOOP_NONE
    if _combo_tween != null and is_instance_valid(_combo_tween):
        _combo_tween.kill()
    _action_busy = true
    _combo_queued = false
    _combo_elapsed = 0.0
    _combo_strike_resolved = false
    _combo_clip_length = maxf(punch_clip.length, 0.1)
    _playing_animation = punch_name
    _animation_player.speed_scale = 1.0
    _animation_player.play(punch_name)
    var online_client := get_node_or_null("../OnlineMultiplayer")
    if online_client != null and online_client.get("enabled") and online_client.has_method("send_combat_event"):
        online_client.call("send_combat_event", "attack", punch_name)
    _combo_tween = create_tween()
    var impact_time := minf(_combo_clip_length * 0.28, 0.34)
    _combo_tween.tween_interval(impact_time)
    _combo_tween.tween_callback(_resolve_melee_strike)
    _combo_tween.tween_interval(maxf(0.0, _combo_clip_length - impact_time))
    _combo_tween.tween_callback(_on_combo_clip_finished)

func _resolve_melee_strike() -> void:
    if _combo_strike_resolved or not _action_busy:
        return
    _combo_strike_resolved = true
    if is_instance_valid(gorece) and _is_target_in_melee_reach(gorece):
        gorece.receive_punch(global_position)
        return
    var online_client := get_node_or_null("../OnlineMultiplayer")
    if online_client != null and online_client.get("enabled") and online_client.has_method("find_remote_target"):
        var target_id := String(online_client.call("find_remote_target", self))
        if not target_id.is_empty():
            online_client.call("send_combat_event", "hit", "", target_id)

func _is_target_in_melee_reach(target: Node3D) -> bool:
    var to_target := target.global_position - global_position
    to_target.y = 0.0
    var distance := to_target.length()
    if distance < 0.05 or distance > MELEE_REACH:
        return false
    var facing := -visual.global_transform.basis.z
    facing.y = 0.0
    if facing.length_squared() < 0.001:
        return false
    return facing.normalized().dot(to_target / distance) >= 0.25

func receive_punch(attacker_position: Vector3) -> void:
    _cancel_action_for_hit()
    var reaction := _select_hit_reaction(attacker_position)
    if not reaction.is_empty() and _animation_player != null:
        var clip := _animation_player.get_animation(reaction)
        clip.loop_mode = Animation.LOOP_NONE
        _animation_player.stop()
        _animation_player.speed_scale = 1.0
        _animation_player.play(reaction)
        _playing_animation = reaction
        _action_busy = true
        _combo_clip_length = maxf(clip.length, 0.18)
        _combo_tween = create_tween()
        _combo_tween.tween_interval(_combo_clip_length)
        _combo_tween.tween_callback(_finish_hit_reaction)
        return
    _play_procedural_hit_reaction(attacker_position)

func receive_network_punch(attacker_position: Vector3) -> void:
    if _active_character == 1 and is_instance_valid(gorece):
        gorece.receive_punch(attacker_position)
    else:
        receive_punch(attacker_position)

func _select_hit_reaction(attacker_position: Vector3) -> String:
    if _animation_player == null:
        return ""
    var local_direction := visual.global_transform.basis.inverse() * (attacker_position - global_position)
    var directional := "HIT_front"
    if absf(local_direction.x) > absf(local_direction.z):
        directional = "HIT_R" if local_direction.x > 0.0 else "HIT_L"
    elif local_direction.z > 0.0:
        directional = "HIT_back"
    for candidate in [directional, "HitA_1", "HIT_front", "HitA_2", "HitA_3"]:
        if candidate in HIT_REACTION_ANIMATIONS and _animation_player.has_animation(candidate):
            return candidate
    return ""

func _cancel_action_for_hit() -> void:
    if _combo_tween != null and is_instance_valid(_combo_tween):
        _combo_tween.kill()
    _combo_tween = null
    _combo_index = 0
    _combo_queued = false
    _combo_elapsed = 0.0
    _combo_strike_resolved = true
    _action_busy = false
    if _animation_player != null:
        _animation_player.stop()

func _play_procedural_hit_reaction(attacker_position: Vector3) -> void:
    var away := global_position - attacker_position
    away.y = 0.0
    away = away.normalized() if away.length_squared() > 0.001 else Vector3.BACK
    var local_away := visual.global_transform.basis.inverse() * away
    var base_position := visual.position
    var base_rotation := visual.rotation
    var flinch_position := base_position + Vector3(local_away.x * 0.11, 0.025, local_away.z * 0.08)
    var flinch_rotation := base_rotation + Vector3(deg_to_rad(-8.0), 0.0, deg_to_rad(clampf(local_away.x * 7.0, -7.0, 7.0)))
    _action_busy = true
    _playing_animation = "ProceduralHit"
    _combo_tween = create_tween()
    _combo_tween.set_parallel(true)
    _combo_tween.tween_property(visual, "position", flinch_position, 0.10)
    _combo_tween.tween_property(visual, "rotation", flinch_rotation, 0.10)
    _combo_tween.set_parallel(false)
    _combo_tween.tween_interval(0.10)
    _combo_tween.set_parallel(true)
    _combo_tween.tween_property(visual, "position", base_position, 0.24)
    _combo_tween.tween_property(visual, "rotation", base_rotation, 0.24)
    _combo_tween.set_parallel(false)
    _combo_tween.tween_callback(_finish_hit_reaction)

func _finish_hit_reaction() -> void:
    _combo_tween = null
    _action_busy = false
    _combo_index = 0
    _combo_queued = false
    _combo_elapsed = 0.0
    _combo_clip_length = 0.0
    _playing_animation = ""

func _update_combo_chain() -> void:
    # Holding the button auto-queues the next hit once the current clip is far enough.
    if _combo_holding and not _combo_queued and _combo_elapsed >= _combo_clip_length * COMBO_QUEUE_FROM:
        _combo_queued = true

func _on_combo_clip_finished() -> void:
    var clips := _available_combo_clips()
    var can_advance := _combo_queued or _combo_holding
    var next_index := _combo_index + 1
    if can_advance and next_index < clips.size():
        _combo_index = next_index
        _play_combo_step(clips)
        return
    _combo_index = 0
    _combo_queued = false
    _finish_procedural_action()

func _perform_ifp_punch() -> void:
    # Kept for compatibility with older call sites / tests.
    _combo_index = 0
    _combo_queued = false
    var clips := _available_combo_clips()
    if clips.is_empty():
        _perform_procedural_punch()
        return
    _play_combo_step(clips)

func _perform_procedural_punch() -> void:
    var skeleton := _find_skeleton(visual)
    if skeleton == null:
        return
    _prepare_action_base_pose(IDLE_ANIMATION)
    skeleton.force_update_all_bone_transforms()
    var pose: Dictionary = _prepare_arm_pose(skeleton, "R", 0.4, -0.035, 0.26)
    if pose.is_empty():
        return
    _action_busy = true
    var upper: int = pose["upper"]
    var forearm: int = pose["forearm"]
    var from_upper: Transform3D = pose["from_upper"]
    var from_forearm: Transform3D = pose["from_forearm"]
    var to_upper: Transform3D = pose["to_upper"]
    var to_forearm: Transform3D = pose["to_forearm"]
    var tween := create_tween()
    tween.tween_method(_blend_arm_pose.bind(skeleton, upper, forearm, from_upper, from_forearm, to_upper, to_forearm), 0.0, 1.0, 0.13)
    tween.tween_interval(0.08)
    tween.tween_method(_blend_arm_pose.bind(skeleton, upper, forearm, from_upper, from_forearm, to_upper, to_forearm), 1.0, 0.0, 0.22)
    tween.tween_callback(_finish_procedural_action)

func _prepare_action_base_pose(animation_name: String) -> void:
    if _animation_player == null or not _animation_player.has_animation(animation_name):
        return
    _animation_player.play(animation_name)
    _animation_player.speed_scale = 1.0
    _animation_player.advance(0.0)
    _animation_player.pause()
    _playing_animation = ""

func _prepare_arm_pose(skeleton: Skeleton3D, side: String, reach: float, lift: float, side_offset: float) -> Dictionary:
    var upper: int = skeleton.find_bone(" %s UpperArm" % side)
    var forearm: int = skeleton.find_bone(" %s ForeArm" % side)
    var hand: int = skeleton.find_bone(" %s Hand" % side)
    if upper < 0 or forearm < 0 or hand < 0:
        return {}
    var from_upper: Transform3D = skeleton.get_bone_global_pose(upper)
    var from_forearm: Transform3D = skeleton.get_bone_global_pose(forearm)
    var from_hand: Transform3D = skeleton.get_bone_global_pose(hand)
    var shoulder: Vector3 = from_upper.origin
    var elbow: Vector3 = from_forearm.origin
    var wrist: Vector3 = from_hand.origin
    var upper_length: float = shoulder.distance_to(elbow)
    var forearm_length: float = elbow.distance_to(wrist)
    if upper_length < 0.01 or forearm_length < 0.01:
        return {}
    var forward: Vector3 = skeleton.global_transform.basis.inverse() * (-visual.global_transform.basis.z)
    var up: Vector3 = skeleton.global_transform.basis.inverse() * Vector3.UP
    var right: Vector3 = skeleton.global_transform.basis.inverse() * visual.global_transform.basis.x
    forward = forward.normalized()
    up = up.normalized()
    right = right.normalized()
    var wrist_target: Vector3 = shoulder + forward * reach + up * lift + right * side_offset
    var to_target: Vector3 = wrist_target - shoulder
    var distance: float = minf(to_target.length(), upper_length + forearm_length - 0.02)
    if distance < 0.05:
        return {}
    var direction: Vector3 = to_target.normalized()
    wrist_target = shoulder + direction * distance
    var bend_direction: Vector3 = elbow - shoulder
    bend_direction -= direction * bend_direction.dot(direction)
    if bend_direction.length_squared() < 0.0001:
        bend_direction = Vector3.RIGHT - direction * Vector3.RIGHT.dot(direction)
    bend_direction = bend_direction.normalized()
    var cosine: float = clampf((upper_length * upper_length + distance * distance - forearm_length * forearm_length) / (2.0 * upper_length * distance), -1.0, 1.0)
    var sine: float = sqrt(maxf(0.0, 1.0 - cosine * cosine))
    var elbow_target: Vector3 = shoulder + direction * (upper_length * cosine) + bend_direction * (upper_length * sine)
    var upper_child_local: Vector3 = from_upper.basis.inverse() * (elbow - shoulder)
    var current_upper_axis: Vector3 = from_upper.basis * upper_child_local
    var desired_upper_axis: Vector3 = elbow_target - shoulder
    var upper_turn := Quaternion(current_upper_axis.normalized(), desired_upper_axis.normalized())
    var to_upper: Transform3D = from_upper
    to_upper.basis = Basis(upper_turn) * from_upper.basis
    skeleton.set_bone_global_pose(upper, to_upper)
    skeleton.force_update_all_bone_transforms()
    var forearm_after_upper: Transform3D = skeleton.get_bone_global_pose(forearm)
    var hand_child_local: Vector3 = from_forearm.basis.inverse() * (wrist - elbow)
    var current_forearm_axis: Vector3 = forearm_after_upper.basis * hand_child_local
    var desired_forearm_axis: Vector3 = wrist_target - elbow_target
    var forearm_turn := Quaternion(current_forearm_axis.normalized(), desired_forearm_axis.normalized())
    var to_forearm: Transform3D = forearm_after_upper
    to_forearm.origin = elbow_target
    to_forearm.basis = Basis(forearm_turn) * forearm_after_upper.basis
    skeleton.set_bone_global_pose(forearm, to_forearm)
    skeleton.force_update_all_bone_transforms()
    skeleton.set_bone_global_pose(upper, from_upper)
    skeleton.force_update_all_bone_transforms()
    skeleton.set_bone_global_pose(forearm, from_forearm)
    skeleton.force_update_all_bone_transforms()
    return {
        "upper": upper,
        "forearm": forearm,
        "from_upper": from_upper,
        "from_forearm": from_forearm,
        "to_upper": to_upper,
        "to_forearm": to_forearm,
    }

func _blend_arm_pose(weight: float, skeleton: Skeleton3D, upper: int, forearm: int, from_upper: Transform3D, from_forearm: Transform3D, to_upper: Transform3D, to_forearm: Transform3D) -> void:
    skeleton.set_bone_global_pose(upper, from_upper.interpolate_with(to_upper, weight))
    skeleton.force_update_all_bone_transforms()
    skeleton.set_bone_global_pose(forearm, from_forearm.interpolate_with(to_forearm, weight))
    skeleton.force_update_all_bone_transforms()

func _finish_procedural_action() -> void:
    _action_busy = false
    _playing_animation = ""
    _combo_index = 0
    _combo_queued = false
    _combo_elapsed = 0.0
    _combo_clip_length = 0.0
    if _combo_tween != null and is_instance_valid(_combo_tween):
        _combo_tween.kill()
        _combo_tween = null

func _on_joystick_changed(next_value: Vector2) -> void:
    _joystick_value = next_value.limit_length(1.0)
    if _active_character == 1:
        gorece.set_joystick_value(_joystick_value)

func _update_coordinates_label() -> void:
    if coordinates_label == null:
        return
    var tracked_position := gorece.global_position if _active_character == 1 else global_position
    coordinates_label.text = "COORDENADAS\nX: %8.3f\nY: %8.3f\nZ: %8.3f" % [tracked_position.x, tracked_position.y, tracked_position.z]

func _on_microphone_button_toggled(enable_microphone: bool) -> void:
    if _mic_toggle_in_progress:
        return
    if not enable_microphone:
        VoiceChat.stop_microphone()
        _set_microphone_button_state(false)
        return
    _mic_toggle_in_progress = true
    microphone_button.disabled = true
    microphone_button.text = "PEDINDO PERMISSÃO..."
    await VoiceChat.start()
    _mic_toggle_in_progress = false
    microphone_button.disabled = false
    var microphone_active := VoiceChat.enabled
    _set_microphone_button_state(microphone_active)
    if not microphone_active:
        microphone_button.text = "MICROFONE: NEGADO"
        microphone_button.tooltip_text = "Conceda a permissão do microfone para usar o chat de voz."

func _set_microphone_button_state(microphone_active: bool) -> void:
    if microphone_button == null:
        return
    if microphone_button.button_pressed != microphone_active:
        microphone_button.set_pressed_no_signal(microphone_active)
    microphone_button.text = "MICROFONE: LIGADO" if microphone_active else "MICROFONE: DESLIGADO"
    microphone_button.tooltip_text = ""

func _on_run_button_toggled(enabled: bool) -> void:
    _set_run_button_state(enabled)

func _set_run_button_state(enabled: bool) -> void:
    var should_run := enabled
    if should_run and (_crouching or (_active_character == 1 and gorece.crouching)):
        should_run = false
    if _active_character == 1:
        gorece.set_running(should_run)
    else:
        _running = should_run
    if run_button != null:
        if run_button.button_pressed != should_run:
            run_button.set_pressed_no_signal(should_run)
        run_button.text = "PARAR DE CORRER" if should_run else "CORRER"

func _on_crouch_toggled(enabled: bool) -> void:
    if enabled:
        _set_run_button_state(false)
    if _active_character == 1:
        gorece.set_crouching(enabled)
        return
    _crouching = enabled

func _on_jump_button_down() -> void:
    if _active_character == 1:
        gorece.request_jump()
        return
    if not _crouching:
        _jump_requested = true
        _jump_buffer_remaining = JUMP_BUFFER_SECONDS

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_SPACE:
            _on_jump_button_down()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_F:
            _on_action_button_down()
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _rotating_mouse = event.pressed
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion and _rotating_mouse:
        _rotate_camera(event.relative)
        get_viewport().set_input_as_handled()
    elif event is InputEventScreenTouch:
        if event.position.x > get_viewport().get_visible_rect().size.x * 0.42:
            if event.pressed and _camera_touch_id == -1:
                _camera_touch_id = event.index
                _last_camera_touch = event.position
            elif not event.pressed and event.index == _camera_touch_id:
                _camera_touch_id = -1
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag and event.index == _camera_touch_id:
        _rotate_camera(event.position - _last_camera_touch)
        _last_camera_touch = event.position
        get_viewport().set_input_as_handled()

func _rotate_camera(delta: Vector2) -> void:
    _camera_yaw -= delta.x * 0.006
    _camera_pitch = clamp(_camera_pitch + delta.y * 0.004, -0.18, 0.56)
