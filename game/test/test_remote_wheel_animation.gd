extends SceneTree

var _failures := PackedStringArray()
var _checks := 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var session_file := FileAccess.open("user://andre3d_session.json", FileAccess.WRITE)
    if session_file != null:
        session_file.store_string(JSON.stringify({"mode": "offline", "character": "andre"}))
        session_file.close()

    var packed := load("res://scenes/third_person.tscn") as PackedScene
    _check(packed != null, "third-person scene must load")
    if packed == null:
        _finish()
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    await process_frame
    await process_frame

    var player := scene.get_node("Player") as Node3D
    player.global_position = Vector3(1000.0, 0.0, 1000.0)
    for vehicle_name in ["Pop100e2024", "WayfarerR1200", "HiluxSRX2017"]:
        (scene.get_node(vehicle_name) as Node).set_physics_process(false)

    var remote_script := load("res://scripts/net/remote_avatar.gd") as Script
    var remote := remote_script.new() as Node3D
    remote.name = "RemotePlayer_wheel_test"
    scene.add_child(remote)
    var remote_visual := (scene.get_node("Player/AndreVisual") as Node3D).duplicate()
    remote.call("setup", remote_visual, "andre")
    remote.set_process(false)
    var sequence := 1

    remote.call("apply_state", Vector3.ZERO, 0.0, "on_foot", false, Vector3.ZERO, 0.0, "", sequence, Vector3(0.0, 0.0, -7.0), Vector3.ZERO, "off", 0.0, true)
    var remote_animation_player := remote.get("animation_player") as AnimationPlayer
    _check(remote_animation_player != null and remote_animation_player.current_animation == "run_civi", "remote running state must use the run animation")
    sequence += 1
    remote.call("apply_state", Vector3.ZERO, 0.0, "on_foot", false, Vector3.ZERO, 0.0, "", sequence, Vector3(0.0, 0.0, -3.0), Vector3.ZERO, "off", 0.0, false)
    _check(remote_animation_player != null and remote_animation_player.current_animation == "WALK_civi", "remote walking state must use the walk animation")

    for bike_name in ["Pop100e2024", "WayfarerR1200"]:
        var bike := scene.get_node(bike_name) as Node3D
        var front := bike.get("_front_wheel") as Node3D
        var rear := bike.get("_rear_wheel") as Node3D
        _check(front != null and rear != null, bike_name + " must expose both wheel nodes")
        if front == null or rear == null:
            continue
        var front_basis_before := front.transform.basis
        var rear_basis_before := rear.transform.basis
        var forward := -bike.global_transform.basis.z
        forward.y = 0.0
        forward = forward.normalized()
        _apply_remote_vehicle_state(remote, bike, "pop100" if bike_name == "Pop100e2024" else "wayfarer", sequence, forward * 4.0)
        var bike_position_before_spin := bike.global_position
        var bike_rotation_before_spin := bike.global_rotation.y
        bike.call("update_remote_wheel_spin", forward * 4.0, 0.05)
        _check(bike.global_position.distance_to(bike_position_before_spin) < 0.0001, bike_name + " remote wheel spin must not move the vehicle")
        _check(absf(wrapf(bike.global_rotation.y - bike_rotation_before_spin, -PI, PI)) < 0.0001, bike_name + " remote wheel spin must not rotate the vehicle body")
        for _frame in range(4):
            remote.call("_process", 0.05)
        _check(absf(float(bike.get("_front_spin_angle"))) > 0.1, bike_name + " remote front wheel spin must advance")
        _check(absf(float(bike.get("_rear_spin_angle"))) > 0.1, bike_name + " remote rear wheel spin must advance")
        _check(_basis_changed(front_basis_before, front.transform.basis), bike_name + " remote front wheel transform must rotate")
        _check(_basis_changed(rear_basis_before, rear.transform.basis), bike_name + " remote rear wheel transform must rotate")
        _check(not bool(bike.call("is_riding")), bike_name + " remote visual update must not enable local driving")
        sequence += 1

    var hilux := scene.get_node("HiluxSRX2017") as Node3D
    var hilux_wheels := {
        "left front": hilux.get("_wheel_lf") as Node3D,
        "right front": hilux.get("_wheel_rf") as Node3D,
        "left rear": hilux.get("_wheel_lb") as Node3D,
        "right rear": hilux.get("_wheel_rb") as Node3D,
    }
    var hilux_bases: Dictionary = {}
    for wheel_name in hilux_wheels:
        var wheel := hilux_wheels[wheel_name] as Node3D
        _check(wheel != null, "Hilux " + String(wheel_name) + " wheel must exist")
        if wheel != null:
            hilux_bases[wheel_name] = wheel.transform.basis

    var hilux_forward := -hilux.global_transform.basis.z
    hilux_forward.y = 0.0
    hilux_forward = hilux_forward.normalized()
    _apply_remote_vehicle_state(remote, hilux, "hilux", sequence, hilux_forward * 5.0)
    var hilux_position_before_spin := hilux.global_position
    var hilux_rotation_before_spin := hilux.global_rotation.y
    hilux.call("update_remote_wheel_spin", hilux_forward * 5.0, 0.05)
    _check(hilux.global_position.distance_to(hilux_position_before_spin) < 0.0001, "remote Hilux wheel spin must not move the vehicle")
    _check(absf(wrapf(hilux.global_rotation.y - hilux_rotation_before_spin, -PI, PI)) < 0.0001, "remote Hilux wheel spin must not rotate the vehicle body")
    for _frame in range(4):
        remote.call("_process", 0.05)
    _check(absf(float(hilux.get("_wheel_spin"))) > 0.1, "remote Hilux wheel spin must advance")
    for wheel_name in hilux_wheels:
        var wheel := hilux_wheels[wheel_name] as Node3D
        if wheel != null:
            _check(_basis_changed(hilux_bases[wheel_name], wheel.transform.basis), "remote Hilux " + String(wheel_name) + " wheel must rotate")

    var forward_spin := float(hilux.get("_wheel_spin"))
    sequence += 1
    _apply_remote_vehicle_state(remote, hilux, "hilux", sequence, -hilux_forward * 3.0)
    for _frame in range(4):
        remote.call("_process", 0.05)
    var reverse_spin_delta := wrapf(float(hilux.get("_wheel_spin")) - forward_spin, -PI, PI)
    _check(reverse_spin_delta > 0.1, "remote reverse velocity must spin Hilux wheels in the opposite direction")

    var spin_at_stop := float(hilux.get("_wheel_spin"))
    sequence += 1
    _apply_remote_vehicle_state(remote, hilux, "hilux", sequence, Vector3.ZERO)
    for _frame in range(3):
        remote.call("_process", 0.05)
    _check(is_equal_approx(float(hilux.get("_wheel_spin")), spin_at_stop), "remote wheels must stop accumulating spin when vehicle velocity is zero")

    sequence += 1
    remote.call("apply_state", Vector3.ZERO, 0.0, "on_foot", false, remote.global_position, 0.0, "", sequence, Vector3.ZERO, Vector3.ZERO, "off", 0.0)
    remote.call("_process", 0.1)
    _check(is_equal_approx(float(hilux.get("_wheel_spin")), spin_at_stop), "remote wheels must stop after the driver dismounts")

    scene.queue_free()
    await process_frame
    _finish()

func _apply_remote_vehicle_state(remote: Node3D, vehicle: Node3D, vehicle_type: String, sequence: int, world_velocity: Vector3) -> void:
    remote.call(
        "apply_state",
        Vector3.ZERO,
        0.0,
        vehicle_type,
        true,
        vehicle.global_position,
        vehicle.global_rotation.y,
        String(vehicle.get("network_vehicle_id")),
        sequence,
        Vector3.ZERO,
        world_velocity,
        "off",
        0.0
    )

func _basis_changed(before: Basis, after: Basis) -> bool:
    return before.y.normalized().dot(after.y.normalized()) < 0.999 or before.z.normalized().dot(after.z.normalized()) < 0.999

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition:
        _failures.append(message)

func _finish() -> void:
    if _failures.is_empty():
        print("[remote-wheel-animation] PASS: ", _checks, " checks")
        quit(0)
        return
    for failure in _failures:
        push_error("[remote-wheel-animation] " + failure)
    print("[remote-wheel-animation] FAIL: ", _failures.size(), " failures / ", _checks, " checks")
    quit(1)
