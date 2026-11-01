extends CharacterBody3D
class_name GoreceNpc

const MOVE_SPEED := 3.0
const RUN_SPEED := 4.8
const FOLLOW_RUN_DISTANCE := 6.0
const FOLLOW_WALK_DISTANCE := 4.5
const ACCELERATION := 14.0
const DECELERATION := 18.0
const AIR_DRAG := 0.55
const GRAVITY := 18.0
const JUMP_VELOCITY := 7.0
const JUMP_FORWARD_IMPULSE := 4.4
const JUMP_BUFFER_SECONDS := 0.14
const COYOTE_SECONDS := 0.12
const STANDING_COLLISION_HEIGHT := 1.8
const CROUCH_COLLISION_HEIGHT := 0.95
const COMBO_QUEUE_FROM := 0.28
const WAYPOINTS := [
    Vector3(6.0, 0.0, 5.0),
    Vector3(11.0, 0.0, 5.0),
    Vector3(11.0, 0.0, -5.0),
    Vector3(4.0, 0.0, -5.0),
]
const WAYPOINT_RADIUS := 0.55
const WALK_ANIMATION := "WALK_civi"
const RUN_ANIMATION := "run_civi"
const IDLE_ANIMATION := "IDLE_stance"
const CROUCH_WALK_ANIMATION := "Player_Sneak"
const CROUCH_IDLE_ANIMATION := "Player_Sneak"
const CROUCH_ENTER_ANIMATION := "Player_Sneak_walkstart"
const JUMP_LAUNCH_ANIMATION := "JUMP_launch"
const JUMP_GLIDE_ANIMATION := "JUMP_glide"
const JUMP_LAND_ANIMATION := "JUMP_land"
const FALL_ANIMATION := "FALL_fall"
const FALL_LAND_ANIMATION := "FALL_land"
const COMBO_ANIMATIONS := ["FightA_1", "FightA_2", "FightA_3"]
const HIT_REACTION_ANIMATIONS := ["HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3"]
const MELEE_REACH := 1.65
# Pose sentada de motorista: rotações em graus em torno do eixo lateral (X) do modelo,
# aplicadas sobre a pose parada (IDLE). Valores validados contra a cabine da Hilux.
const SEATED_POSE_DEGREES := {
    "Spine": -16.0,
    "Neck": 16.0,
    "L Thigh": 80.0,
    "R Thigh": 80.0,
    "L Calf": -80.0,
    "R Calf": -80.0,
    "L Foot": 8.0,
    "R Foot": 8.0,
    "L UpperArm": 50.0,
    "R UpperArm": 50.0,
    "L ForeArm": 14.0,
    "R ForeArm": 14.0,
}

@onready var visual: Node3D = $GoreceVisual
@onready var joystick: AndreVirtualJoystick = $"../HUD/Root/TouchJoystick"
@onready var collision_shape: CollisionShape3D = $Collision

var player_controlled := false
var running := false
var crouching := false
var jump_requested := false
var _jumping := false
var _spawn_grounded := false
var _landing := false
var _crouch_entering := false
var camera_yaw := 0.0
var camera_pitch := 0.16
var joystick_value := Vector2.ZERO
var follow_target: Node3D
var follow_vehicle_target: Node3D
var _waypoint_index := 1
var _animation_player: AnimationPlayer
var _playing_animation := ""
var _action_busy := false
var _combo_index := 0
var _combo_queued := false
var _combo_holding := false
var _combo_elapsed := 0.0
var _combo_clip_length := 0.0
var _combo_tween: Tween
var _combo_strike_resolved := false
var _jump_buffer_remaining := 0.0
var _coyote_remaining := 0.0
var _skeleton: Skeleton3D
var _seat_start: Dictionary = {}
var _seat_target: Dictionary = {}

func _ready() -> void:
    _animation_player = _find_animation_player(visual)
    _make_collision_shape_unique()
    if _animation_player != null:
        for animation_name in [WALK_ANIMATION, RUN_ANIMATION, IDLE_ANIMATION, CROUCH_WALK_ANIMATION, CROUCH_IDLE_ANIMATION, JUMP_GLIDE_ANIMATION, FALL_ANIMATION]:
            if _animation_player.has_animation(animation_name):
                _animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
        for animation_name in [CROUCH_ENTER_ANIMATION, JUMP_LAUNCH_ANIMATION, JUMP_LAND_ANIMATION, FALL_LAND_ANIMATION] + COMBO_ANIMATIONS:
            if _animation_player.has_animation(animation_name):
                _animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_NONE
    _play_animation(IDLE_ANIMATION)

func _process(delta: float) -> void:
    if _action_busy:
        _combo_elapsed += delta
        if _combo_holding and not _combo_queued and _combo_elapsed >= _combo_clip_length * COMBO_QUEUE_FROM:
            _combo_queued = true

    if _jumping and not _landing and _animation_player != null:
        if _playing_animation == JUMP_LAUNCH_ANIMATION and not _animation_player.is_playing():
            if _animation_player.has_animation(JUMP_GLIDE_ANIMATION):
                _play_animation(JUMP_GLIDE_ANIMATION)
            elif _animation_player.has_animation(FALL_ANIMATION):
                _play_animation(FALL_ANIMATION)

    if _landing and (_animation_player == null or not _animation_player.is_playing()):
        _landing = false
        _playing_animation = ""

func _physics_process(delta: float) -> void:
    if not is_instance_valid(visual):
        return
    if not _spawn_grounded:
        var map_streamer := get_node_or_null("../MapStreamer")
        if map_streamer != null and not bool(map_streamer.call("snap_body_to_map", self)):
            return
        _spawn_grounded = true
    if is_on_floor():
        _coyote_remaining = COYOTE_SECONDS
    else:
        _coyote_remaining = maxf(0.0, _coyote_remaining - delta)
    if jump_requested:
        _jump_buffer_remaining = maxf(0.0, _jump_buffer_remaining - delta)
        if _jump_buffer_remaining <= 0.0:
            jump_requested = false

    var input_vector := Vector2.ZERO
    if player_controlled and not _action_busy:
        input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
        if joystick_value.length() > 0.05:
            input_vector = joystick_value
    elif not player_controlled and is_instance_valid(follow_vehicle_target) and not _action_busy:
        var vehicle_offset := follow_vehicle_target.global_position - global_position
        vehicle_offset.y = 0.0
        var vehicle_distance := vehicle_offset.length()
        if vehicle_distance > 3.0:
            running = running and vehicle_distance > FOLLOW_WALK_DISTANCE or vehicle_distance >= FOLLOW_RUN_DISTANCE
            input_vector = _world_vector_to_input(vehicle_offset.normalized())
        else:
            running = false
            if follow_vehicle_target.has_method("start_ai_mount_for_follow"):
                follow_vehicle_target.call("start_ai_mount_for_follow")
    elif not player_controlled and is_instance_valid(follow_target) and not _action_busy:
        var follow_offset := follow_target.global_position - global_position
        follow_offset.y = 0.0
        var follow_distance := follow_offset.length()
        if follow_distance > 2.2:
            running = running and follow_distance > FOLLOW_WALK_DISTANCE or follow_distance >= FOLLOW_RUN_DISTANCE
            input_vector = _world_vector_to_input(follow_offset.normalized())
        else:
            running = false
    else:
        var target: Vector3 = WAYPOINTS[_waypoint_index]
        var to_target: Vector3 = target - global_position
        to_target.y = 0.0
        if to_target.length() <= WAYPOINT_RADIUS:
            _waypoint_index = (_waypoint_index + 1) % WAYPOINTS.size()
            target = WAYPOINTS[_waypoint_index]
            to_target = target - global_position
            to_target.y = 0.0
        if not player_controlled and to_target.length_squared() > 0.01 and not _action_busy:
            input_vector = _world_vector_to_input(to_target.normalized())

    var analog_strength := clampf(input_vector.length(), 0.0, 1.0)
    var direction := _camera_relative_direction(input_vector) if player_controlled else Vector3(input_vector.x, 0.0, -input_vector.y)
    var walking := direction.length_squared() > 0.001 and analog_strength > 0.05 and not _action_busy
    if walking:
        direction = direction.normalized()
        var speed := (RUN_SPEED if running else MOVE_SPEED) * (0.55 if crouching else 1.0)
        velocity.x = move_toward(velocity.x, direction.x * speed, ACCELERATION * delta)
        velocity.z = move_toward(velocity.z, direction.z * speed, ACCELERATION * delta)
        var facing := Vector3(velocity.x, 0.0, velocity.z).normalized()
        if facing.length_squared() > 0.01:
            visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-facing.x, -facing.z), minf(1.0, delta * 10.0))
    else:
        var horizontal_drag := DECELERATION if is_on_floor() else AIR_DRAG
        velocity.x = move_toward(velocity.x, 0.0, horizontal_drag * delta)
        velocity.z = move_toward(velocity.z, 0.0, horizontal_drag * delta)

    var can_launch := jump_requested and not _jumping and not crouching and not _action_busy and (is_on_floor() or _coyote_remaining > 0.0)
    if can_launch:
        velocity.y = JUMP_VELOCITY
        var jump_direction := direction.normalized() if walking else -visual.global_transform.basis.z
        jump_direction.y = 0.0
        if jump_direction.length_squared() > 0.001:
            jump_direction = jump_direction.normalized()
            velocity.x += jump_direction.x * JUMP_FORWARD_IMPULSE
            velocity.z += jump_direction.z * JUMP_FORWARD_IMPULSE
        jump_requested = false
        _jump_buffer_remaining = 0.0
        _coyote_remaining = 0.0
        _jumping = true
        _landing = false
        var online_client := get_node_or_null("../OnlineMultiplayer")
        if online_client != null and bool(online_client.get("enabled")):
            online_client.call("send_jump_event")
        _play_animation(JUMP_LAUNCH_ANIMATION)
    elif is_on_floor():
        velocity.y = -0.25
    else:
        velocity.y -= GRAVITY * delta

    move_and_slide()

    if _jumping and is_on_floor() and velocity.y <= 0.0:
        _jumping = false
        if not walking:
            velocity.x = 0.0
            velocity.z = 0.0
        var landing_animation := FALL_LAND_ANIMATION if _animation_player != null and _animation_player.has_animation(FALL_LAND_ANIMATION) else JUMP_LAND_ANIMATION
        if _animation_player != null and _animation_player.has_animation(landing_animation):
            _landing = true
            _play_animation(landing_animation)
        else:
            _landing = false
            _playing_animation = ""

    if _landing or _action_busy:
        return
    if _jumping:
        return

    var desired := IDLE_ANIMATION
    if crouching and _animation_player != null:
        if _crouch_entering and _playing_animation == CROUCH_ENTER_ANIMATION and _animation_player.is_playing():
            desired = CROUCH_ENTER_ANIMATION
        else:
            _crouch_entering = false
            if walking and _animation_player.has_animation(CROUCH_WALK_ANIMATION):
                desired = CROUCH_WALK_ANIMATION
            elif _animation_player.has_animation(CROUCH_IDLE_ANIMATION):
                desired = CROUCH_IDLE_ANIMATION
            else:
                desired = CROUCH_WALK_ANIMATION
    elif walking:
        desired = RUN_ANIMATION if running else WALK_ANIMATION
    _play_animation(desired)

func _world_vector_to_input(direction: Vector3) -> Vector2:
    return Vector2(direction.x, -direction.z)

func _camera_relative_direction(input_vector: Vector2) -> Vector3:
    if input_vector.length_squared() < 0.001:
        return Vector3.ZERO
    var forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
    var right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
    return right * input_vector.x + forward * (-input_vector.y)

func set_player_controlled(enabled: bool) -> void:
    player_controlled = enabled
    if not enabled:
        running = false
        set_crouching(false)
        joystick_value = Vector2.ZERO
        jump_requested = false
        _jump_buffer_remaining = 0.0
        set_action_holding(false)

func set_joystick_value(value: Vector2) -> void:
    joystick_value = value

func set_follow_target(target: Node3D) -> void:
    follow_target = target

func set_follow_vehicle_target(target: Node3D) -> void:
    follow_vehicle_target = target

func set_running(enabled: bool) -> void:
    running = enabled and not crouching

func set_crouching(enabled: bool) -> void:
    if crouching == enabled:
        return
    crouching = enabled
    _set_crouch_collision(enabled)
    if enabled:
        running = false
        _crouch_entering = _animation_player != null and _animation_player.has_animation(CROUCH_ENTER_ANIMATION)
        if _crouch_entering:
            _play_animation(CROUCH_ENTER_ANIMATION)
    else:
        _crouch_entering = false

func _set_crouch_collision(enabled: bool) -> void:
    if collision_shape == null or not collision_shape.shape is CapsuleShape3D:
        return
    var capsule := collision_shape.shape as CapsuleShape3D
    capsule.height = CROUCH_COLLISION_HEIGHT if enabled else STANDING_COLLISION_HEIGHT
    collision_shape.position.y = capsule.height * 0.5

func _make_collision_shape_unique() -> void:
    if collision_shape != null and collision_shape.shape is CapsuleShape3D:
        collision_shape.shape = (collision_shape.shape as CapsuleShape3D).duplicate()
        _set_crouch_collision(crouching)

func request_jump() -> void:
    if not player_controlled or crouching or _jumping or _action_busy:
        return
    if is_on_floor() or _coyote_remaining > 0.0:
        jump_requested = true
        _jump_buffer_remaining = JUMP_BUFFER_SECONDS

func set_action_holding(enabled: bool) -> void:
    _combo_holding = enabled
    if enabled and _action_busy and _combo_elapsed >= _combo_clip_length * COMBO_QUEUE_FROM:
        _combo_queued = true

func perform_action() -> void:
    if _animation_player == null:
        return
    if _action_busy:
        if _playing_animation in COMBO_ANIMATIONS and _combo_elapsed >= _combo_clip_length * COMBO_QUEUE_FROM:
            _combo_queued = true
        return
    var clips := _available_combo_clips()
    if clips.is_empty():
        return
    velocity.x = 0.0
    velocity.z = 0.0
    _combo_index = 0
    _combo_queued = false
    _play_combo_step(clips)

func _available_combo_clips() -> PackedStringArray:
    var clips := PackedStringArray()
    if _animation_player == null:
        return clips
    for animation_name in COMBO_ANIMATIONS:
        if _animation_player.has_animation(animation_name):
            clips.append(animation_name)
    return clips

func _play_combo_step(clips: PackedStringArray) -> void:
    if clips.is_empty():
        _finish_combo()
        return
    _combo_index = clampi(_combo_index, 0, clips.size() - 1)
    var animation_name: String = clips[_combo_index]
    if not _animation_player.has_animation(animation_name):
        _finish_combo()
        return
    var animation := _animation_player.get_animation(animation_name)
    animation.loop_mode = Animation.LOOP_NONE
    if _combo_tween != null and is_instance_valid(_combo_tween):
        _combo_tween.kill()
    _action_busy = true
    _combo_queued = false
    _combo_elapsed = 0.0
    _combo_strike_resolved = false
    _combo_clip_length = maxf(animation.length, 0.1)
    _animation_player.stop()
    _playing_animation = ""
    _animation_player.speed_scale = 1.0
    _animation_player.play(animation_name)
    _animation_player.seek(0.0, true)
    _playing_animation = animation_name
    var online_client := get_node_or_null("../OnlineMultiplayer")
    if online_client != null and online_client.get("enabled") and online_client.has_method("send_combat_event"):
        online_client.call("send_combat_event", "attack", animation_name)
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
    var player := get_node_or_null("../Player") as Node3D
    var player_is_gorece := player != null and player.has_method("is_gorece_active") and bool(player.call("is_gorece_active"))
    if player != null and not player_is_gorece and _is_target_in_melee_reach(player):
        player.call("receive_punch", global_position)
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

func _on_combo_clip_finished() -> void:
    _combo_tween = null
    var clips := _available_combo_clips()
    var next_index := _combo_index + 1
    if (_combo_queued or _combo_holding) and next_index < clips.size():
        _combo_index = next_index
        _play_combo_step(clips)
        return
    _finish_combo()

func _finish_combo() -> void:
    _combo_index = 0
    _combo_queued = false
    _combo_elapsed = 0.0
    _action_busy = false
    _playing_animation = ""

func _play_animation(animation_name: String) -> void:
    if _animation_player == null or not _animation_player.has_animation(animation_name):
        return
    if _playing_animation == animation_name and _animation_player.is_playing():
        return
    _animation_player.speed_scale = 1.0
    _animation_player.play(animation_name)
    _playing_animation = animation_name

func _find_animation_player(root: Node) -> AnimationPlayer:
    for child in root.get_children():
        if child is AnimationPlayer:
            return child as AnimationPlayer
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

# --- Veículos -------------------------------------------------------------

# Entrega o controle do corpo ao veículo: sem patrulha, gravidade ou colisão própria.
func enter_vehicle_mode() -> void:
    velocity = Vector3.ZERO
    _jumping = false
    _landing = false
    _crouch_entering = false
    jump_requested = false
    _action_busy = false
    _combo_index = 0
    _combo_queued = false
    if _combo_tween != null and is_instance_valid(_combo_tween):
        _combo_tween.kill()
    set_physics_process(false)
    set_process(false)

func exit_vehicle_mode() -> void:
    velocity = Vector3.ZERO
    set_physics_process(true)
    set_process(true)
    _playing_animation = ""
    _play_animation(IDLE_ANIMATION)

func play_vehicle_clip(animation_name: String) -> void:
    _play_animation(animation_name)

# Congela a pose parada e calcula a pose sentada. Use com await.
func prepare_seated_pose() -> void:
    if _animation_player == null:
        return
    _skeleton = _skeleton if _skeleton != null else _find_skeleton(visual)
    if _skeleton == null:
        return
    _play_animation(IDLE_ANIMATION)
    _animation_player.seek(0.0, true)
    await get_tree().process_frame
    _animation_player.pause()
    _animation_player.process_mode = Node.PROCESS_MODE_DISABLED
    _compute_seat_targets()

func set_seated_blend(weight: float) -> void:
    var w := clampf(weight, 0.0, 1.0)
    for bone in _seat_target:
        var start: Quaternion = _seat_start[bone]
        var target: Quaternion = _seat_target[bone]
        _skeleton.set_bone_pose_rotation(bone, start.slerp(target, w))

func release_seated_pose() -> void:
    if _skeleton != null:
        for bone in _seat_start:
            _skeleton.set_bone_pose_rotation(bone, _seat_start[bone])
    _seat_start.clear()
    _seat_target.clear()
    if _animation_player != null:
        _animation_player.process_mode = Node.PROCESS_MODE_INHERIT
    _playing_animation = ""
    _play_animation(IDLE_ANIMATION)

func _compute_seat_targets() -> void:
    _seat_start.clear()
    _seat_target.clear()
    var ids: Array[int] = []
    for bone_name: String in SEATED_POSE_DEGREES:
        var bone := _skeleton.find_bone(bone_name)
        if bone < 0:
            bone = _skeleton.find_bone(" " + bone_name)
        if bone >= 0:
            ids.append(bone)
            _seat_start[bone] = _skeleton.get_bone_pose_rotation(bone)
    ids.sort_custom(func(a: int, b: int) -> bool: return _bone_depth(a) < _bone_depth(b))
    # Eixo lateral do personagem, expresso no espaço do esqueleto.
    var axis := (_skeleton.global_transform.basis.inverse() * visual.global_transform.basis * Vector3.RIGHT).normalized()
    var degrees_by_bone := {}
    for bone_name: String in SEATED_POSE_DEGREES:
        var bone := _skeleton.find_bone(bone_name)
        if bone < 0:
            bone = _skeleton.find_bone(" " + bone_name)
        if bone >= 0:
            degrees_by_bone[bone] = float(SEATED_POSE_DEGREES[bone_name])
    for bone: int in ids:
        var parent := _skeleton.get_bone_parent(bone)
        var parent_basis := Basis.IDENTITY
        if parent >= 0:
            parent_basis = _skeleton.get_bone_global_pose(parent).basis.orthonormalized()
        var current := _skeleton.get_bone_global_pose(bone).basis.orthonormalized()
        var rotated := Basis(axis, deg_to_rad(float(degrees_by_bone[bone]))) * current
        var local_rotation := (parent_basis.inverse() * rotated).get_rotation_quaternion()
        _skeleton.set_bone_pose_rotation(bone, local_rotation)
        _seat_target[bone] = local_rotation
    for bone: int in ids:
        _skeleton.set_bone_pose_rotation(bone, _seat_start[bone])

func _bone_depth(bone: int) -> int:
    var depth := 0
    var current := _skeleton.get_bone_parent(bone)
    while current >= 0:
        depth += 1
        current = _skeleton.get_bone_parent(current)
    return depth

func _find_skeleton(root: Node) -> Skeleton3D:
    for child in root.get_children():
        if child is Skeleton3D:
            return child as Skeleton3D
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null
