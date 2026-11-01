extends Node3D
class_name AndreRemoteAvatar

var character := "andre"
var visual: Node3D
var animation_player: AnimationPlayer
var target_position := Vector3.ZERO
var target_rotation := 0.0
var _last_position := Vector3.ZERO
var _has_state := false
var _moving := false
var _running := false
var _last_state_sequence := 0
var _target_velocity := Vector3.ZERO
var _state_received_at_msec := 0
var _network_age_seconds := 0.0
var _position_error_offset := Vector3.ZERO
var _combat_until_msec := 0
var _jump_until_msec := 0
var _last_jump_sequence := 0
var _shared_vehicle: Node3D
var _vehicle_type := "on_foot"
var _vehicle_id := ""
var _riding := false
var _target_vehicle_position := Vector3.ZERO
var _target_vehicle_rotation := 0.0
var _target_vehicle_velocity := Vector3.ZERO
var _vehicle_received_at_msec := 0
var _vehicle_network_age_seconds := 0.0
var _vehicle_audio_mode := "off"
var _target_vehicle_wheelie := 0.0


var _vehicle_error_offset := Vector3.ZERO

const MAX_LEAD_SECONDS := 0.2
const SNAP_DISTANCE := 1.6
const VEHICLE_SNAP_DISTANCE := 3.0
const CORRECTION_SMOOTH_SECONDS := 0.06
const ROTATION_SMOOTH_SPEED := 22.0
const HILUX_SEATED_POSE_DEGREES := {
    "Spine": -16.0, "Neck": 16.0, "L Thigh": 80.0, "R Thigh": 80.0,
    "L Calf": -80.0, "R Calf": -80.0, "L Foot": 8.0, "R Foot": 8.0,
    "L UpperArm": 50.0, "R UpperArm": 50.0, "L ForeArm": 14.0, "R ForeArm": 14.0,
}
var _seated_skeleton: Skeleton3D
var _seated_pose_start: Dictionary = {}
var _seated_pose_ready := false

func setup(visual_instance: Node3D, selected_character: String) -> void:
    if is_instance_valid(visual):
        remove_child(visual)
        visual.queue_free()
    character = selected_character if selected_character in ["andre", "gorece", "dg"] else "andre"
    visual = visual_instance
    if visual == null:
        animation_player = null
        return
    add_child(visual)
    visual.position = Vector3(0, 0.98, 0)
    animation_player = _find_animation_player(visual)
    if character == "andre":
        _apply_andre_appearance(visual)
    _play_idle()

func apply_state(position: Vector3, rotation_y: float, vehicle_type: String = "on_foot", riding: bool = false, vehicle_position := Vector3.ZERO, vehicle_rotation := 0.0, vehicle_id := "", sequence: int = 0, velocity := Vector3.ZERO, vehicle_velocity := Vector3.ZERO, vehicle_audio_mode := "off", network_age_seconds := 0.0, running: bool = false, vehicle_wheelie := 0.0) -> void:
    if sequence > 0 and sequence <= _last_state_sequence:
        return
    if sequence > 0:
        _last_state_sequence = sequence
    var now_msec := Time.get_ticks_msec()
    var first_state := not _has_state
    if _has_state:
        _moving = Vector2(velocity.x, velocity.z).length() > 0.12 or _last_position.distance_to(position) > 0.015
    else:
        # O primeiro pacote já contém a velocidade real do jogador; não espere
        # um segundo pacote para decidir entre parado, andando e correndo.
        _moving = Vector2(velocity.x, velocity.z).length() > 0.12
    _last_position = position
    _has_state = true
    _running = running and not riding
    target_position = position
    target_rotation = rotation_y
    _target_velocity = velocity
    _state_received_at_msec = now_msec
    _network_age_seconds = clampf(network_age_seconds, 0.0, MAX_LEAD_SECONDS)
    var projected_position := _predict(position, velocity, _network_age_seconds)
    if first_state:
        global_position = projected_position
        _position_error_offset = Vector3.ZERO
    else:
        var correction := global_position - projected_position
        if correction.length() > SNAP_DISTANCE:
            global_position = projected_position
            _position_error_offset = Vector3.ZERO
        else:
            _position_error_offset = correction
    # A rotação de gameplay fica no visual do personagem, não no nó raiz.
    global_rotation.y = 0.0
    if first_state and visual != null:
        visual.global_rotation.y = rotation_y
    _apply_vehicle_state(vehicle_type, vehicle_id, riding, vehicle_position, vehicle_rotation, vehicle_velocity, _network_age_seconds, vehicle_audio_mode, vehicle_wheelie)
    if now_msec < _combat_until_msec or now_msec < _jump_until_msec:
        return
    if _riding:
        _play_riding()
    elif _moving:
        _play_run() if _running else _play_walk()
    else:
        _play_idle()

func _process(delta: float) -> void:
    if not _has_state:
        return
    var rotation_weight := 1.0 - exp(-ROTATION_SMOOTH_SPEED * delta)
    var now_msec := Time.get_ticks_msec()
    var position_age := minf(_network_age_seconds + maxf(0.0, float(now_msec - _state_received_at_msec) / 1000.0), MAX_LEAD_SECONDS)
    var predicted_position := _predict(target_position, _target_velocity, position_age)
    var correction_weight := 1.0 - exp(-delta / CORRECTION_SMOOTH_SECONDS)
    _position_error_offset = _position_error_offset.lerp(Vector3.ZERO, correction_weight)
    global_position = predicted_position + _position_error_offset
    if visual != null:
        visual.global_rotation.y = lerp_angle(visual.global_rotation.y, target_rotation, rotation_weight)
    if is_instance_valid(_shared_vehicle):
        var vehicle_age := minf(_vehicle_network_age_seconds + maxf(0.0, float(now_msec - _vehicle_received_at_msec) / 1000.0), MAX_LEAD_SECONDS)
        var predicted_vehicle_position := _predict(_target_vehicle_position, _target_vehicle_velocity, vehicle_age)
        _vehicle_error_offset = _vehicle_error_offset.lerp(Vector3.ZERO, correction_weight)
        _shared_vehicle.global_position = predicted_vehicle_position + _vehicle_error_offset
        _shared_vehicle.global_rotation.y = lerp_angle(_shared_vehicle.global_rotation.y, _target_vehicle_rotation, rotation_weight)
        if _riding and vehicle_age < MAX_LEAD_SECONDS and _shared_vehicle.has_method("update_remote_wheel_spin"):
            _shared_vehicle.call("update_remote_wheel_spin", _target_vehicle_velocity, delta)
        if _shared_vehicle.has_method("set_remote_wheelie"):
            _shared_vehicle.call("set_remote_wheelie", _target_vehicle_wheelie if _riding else 0.0)

func _predict(position: Vector3, velocity: Vector3, age_seconds: float) -> Vector3:
    return position + velocity * clampf(age_seconds, 0.0, MAX_LEAD_SECONDS)

func _apply_vehicle_state(vehicle_type: String, vehicle_id: String, riding: bool, vehicle_position: Vector3, vehicle_rotation: float, vehicle_velocity: Vector3, network_age_seconds: float, vehicle_audio_mode: String = "off", vehicle_wheelie: float = 0.0) -> void:
    var normalized_type := vehicle_type if riding else "on_foot"
    var normalized_id := vehicle_id if riding else ""
    var vehicle_changed := normalized_type != _vehicle_type or normalized_id != _vehicle_id
    var had_shared_vehicle := is_instance_valid(_shared_vehicle)
    if vehicle_changed:
        _vehicle_type = normalized_type
        _vehicle_id = normalized_id
        _shared_vehicle = _find_shared_vehicle(normalized_id) if riding else null
    elif riding and not is_instance_valid(_shared_vehicle):
        _shared_vehicle = _find_shared_vehicle(normalized_id)
    _riding = riding
    _target_vehicle_position = vehicle_position
    _target_vehicle_rotation = vehicle_rotation
    _target_vehicle_velocity = vehicle_velocity
    _vehicle_audio_mode = vehicle_audio_mode
    _target_vehicle_wheelie = clampf(vehicle_wheelie, 0.0, 0.72)
    if is_instance_valid(_shared_vehicle) and _shared_vehicle.has_method("set_network_audio_mode"):
        _shared_vehicle.call("set_network_audio_mode", _vehicle_audio_mode if riding else "off")
    if is_instance_valid(_shared_vehicle) and _shared_vehicle.has_method("set_remote_wheelie"):
        _shared_vehicle.call("set_remote_wheelie", _target_vehicle_wheelie if riding else 0.0)
    _vehicle_received_at_msec = Time.get_ticks_msec()
    _vehicle_network_age_seconds = clampf(network_age_seconds, 0.0, MAX_LEAD_SECONDS)
    if is_instance_valid(_shared_vehicle):
        var projected_vehicle_position := _predict(vehicle_position, vehicle_velocity, _vehicle_network_age_seconds)
        if vehicle_changed or not had_shared_vehicle:
            _shared_vehicle.global_position = projected_vehicle_position
            _vehicle_error_offset = Vector3.ZERO
            _shared_vehicle.global_rotation.y = vehicle_rotation
        else:
            var vehicle_correction := _shared_vehicle.global_position - projected_vehicle_position
            if vehicle_correction.length() > VEHICLE_SNAP_DISTANCE:
                _shared_vehicle.global_position = projected_vehicle_position
                _vehicle_error_offset = Vector3.ZERO
            else:
                _vehicle_error_offset = vehicle_correction
    if not riding or normalized_type != "hilux":
        _restore_hilux_seated_pose()
    if visual != null:
        visual.position = Vector3(0.0, 0.98, 0.0)

func _find_shared_vehicle(vehicle_id: String) -> Node3D:
    if vehicle_id.is_empty() or get_parent() == null:
        return null
    for sibling in get_parent().get_children():
        if sibling == self or not sibling is Node3D:
            continue
        if not sibling.has_method("is_riding"):
            continue
        if String(sibling.get("network_vehicle_id")) == vehicle_id:
            return sibling as Node3D
    return null

func _play_riding() -> void:
    if animation_player == null:
        return
    if _vehicle_type == "hilux":
        if not _seated_pose_ready:
            if animation_player.has_animation("IDLE_stance"):
                animation_player.play("IDLE_stance")
                animation_player.seek(0.0, true)
                animation_player.pause()
                animation_player.process_mode = Node.PROCESS_MODE_DISABLED
            _apply_hilux_seated_pose()
        return
    _play_first(["BIKEd_Ride", "BIKEd_Still", "IDLE_stance", "Idle", "idle"])

func _apply_hilux_seated_pose() -> void:
    _seated_skeleton = _find_skeleton(visual)
    if _seated_skeleton == null:
        return
    _seated_pose_start.clear()
    var bones: Array[int] = []
    for bone_name: String in HILUX_SEATED_POSE_DEGREES:
        var bone := _seated_skeleton.find_bone(bone_name)
        if bone < 0:
            bone = _seated_skeleton.find_bone(" " + bone_name)
        if bone >= 0:
            bones.append(bone)
            _seated_pose_start[bone] = _seated_skeleton.get_bone_pose_rotation(bone)
    bones.sort_custom(func(a: int, b: int) -> bool: return _bone_depth(a) < _bone_depth(b))
    var axis := (_seated_skeleton.global_transform.basis.inverse() * visual.global_transform.basis * Vector3.RIGHT).normalized()
    for bone: int in bones:
        var parent := _seated_skeleton.get_bone_parent(bone)
        var parent_basis := Basis.IDENTITY
        if parent >= 0:
            parent_basis = _seated_skeleton.get_bone_global_pose(parent).basis.orthonormalized()
        var current := _seated_skeleton.get_bone_global_pose(bone).basis.orthonormalized()
        var bone_name := _seated_skeleton.get_bone_name(bone).trim_prefix(" ")
        var rotated := Basis(axis, deg_to_rad(float(HILUX_SEATED_POSE_DEGREES[bone_name]))) * current
        _seated_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * rotated).get_rotation_quaternion())
    _seated_pose_ready = true

func _restore_hilux_seated_pose() -> void:
    if _seated_skeleton != null and is_instance_valid(_seated_skeleton):
        for bone in _seated_pose_start:
            _seated_skeleton.set_bone_pose_rotation(int(bone), _seated_pose_start[bone])
    _seated_pose_start.clear()
    _seated_pose_ready = false
    if animation_player != null:
        animation_player.process_mode = Node.PROCESS_MODE_INHERIT

func _bone_depth(bone: int) -> int:
    var depth := 0
    var current := _seated_skeleton.get_bone_parent(bone)
    while current >= 0:
        depth += 1
        current = _seated_skeleton.get_bone_parent(current)
    return depth

func _play_idle() -> void:
    if animation_player == null:
        return
    _play_first(["IDLE_stance", "Idle", "idle"])

func _play_walk() -> void:
    if animation_player == null:
        return
    _play_first(["WALK_civi", "Walk", "walk"])

func _play_run() -> void:
    if animation_player == null:
        return
    _play_first(["run_civi", "RUN_civi", "Run", "run", "WALK_civi", "Walk", "walk"])

func _play_first(names: Array) -> void:
    for animation_name in names:
        if animation_player.has_animation(animation_name):
            if animation_player.current_animation != animation_name or not animation_player.is_playing():
                var animation := animation_player.get_animation(animation_name)
                animation.loop_mode = Animation.LOOP_LINEAR
                animation_player.play(animation_name)
            return

func play_combat_animation(animation_name: String) -> void:
    if animation_name not in ["FightA_1", "FightA_2", "FightA_3"]:
        return
    _play_timed_combat_clip(animation_name)

func play_jump_animation(sequence: int = 0) -> void:
    if sequence > 0 and sequence <= _last_jump_sequence:
        return
    if sequence > 0:
        _last_jump_sequence = sequence
    if _riding or animation_player == null or Time.get_ticks_msec() < _combat_until_msec:
        return
    if not animation_player.has_animation("JUMP_launch"):
        return
    var animation := animation_player.get_animation("JUMP_launch")
    animation.loop_mode = Animation.LOOP_NONE
    animation_player.speed_scale = 1.0
    animation_player.stop()
    animation_player.play("JUMP_launch")
    _jump_until_msec = Time.get_ticks_msec() + int(maxf(animation.length, 0.25) * 1000.0)

func play_hit_reaction(attacker_position: Vector3) -> void:
    if animation_player == null or visual == null:
        return
    var local_direction := visual.global_transform.basis.inverse() * (attacker_position - global_position)
    var reaction := "HIT_front"
    if absf(local_direction.x) > absf(local_direction.z):
        reaction = "HIT_R" if local_direction.x > 0.0 else "HIT_L"
    elif local_direction.z > 0.0:
        reaction = "HIT_back"
    for candidate in [reaction, "HitA_1", "HIT_front", "HitA_2", "HitA_3"]:
        if animation_player.has_animation(candidate):
            _play_timed_combat_clip(candidate)
            return

func _play_timed_combat_clip(animation_name: String) -> void:
    if animation_player == null or not animation_player.has_animation(animation_name):
        return
    var animation := animation_player.get_animation(animation_name)
    animation.loop_mode = Animation.LOOP_NONE
    animation_player.speed_scale = 1.0
    animation_player.stop()
    animation_player.play(animation_name)
    _combat_until_msec = Time.get_ticks_msec() + int(maxf(animation.length, 0.18) * 1000.0)

func _apply_andre_appearance(root: Node) -> void:
    for node in _walk_nodes(root):
        if not node is MeshInstance3D:
            continue
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        for surface in range(mesh_instance.mesh.get_surface_count()):
            var source := mesh_instance.get_active_material(surface)
            if source == null or not source is StandardMaterial3D:
                continue
            var material_name := source.resource_name.to_lower()
            var skin_color: Variant = null
            if material_name.contains("head") or material_name == "ol":
                skin_color = Color("6f432f")
            elif material_name.contains("jbib") or material_name.contains("lowr"):
                skin_color = Color("e87522")
            elif material_name.contains("berd") or material_name.contains("hair") or material_name.contains("feet"):
                skin_color = Color("111111")
            if skin_color == null:
                continue
            var styled := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
            styled.albedo_color = skin_color
            styled.metallic = 0.0
            styled.roughness = 0.84
            mesh_instance.set_surface_override_material(surface, styled)

func _walk_nodes(root: Node) -> Array[Node]:
    var result: Array[Node] = [root]
    for child in root.get_children():
        result.append_array(_walk_nodes(child))
    return result

func _find_skeleton(root: Node) -> Skeleton3D:
    if root is Skeleton3D:
        return root as Skeleton3D
    for child in root.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_animation_player(root: Node) -> AnimationPlayer:
    if root is AnimationPlayer:
        return root as AnimationPlayer
    for child in root.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null
