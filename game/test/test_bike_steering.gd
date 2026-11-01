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
    for bike_name in ["Pop100e2024", "WayfarerR1200"]:
        await _test_bike(str(bike_name), "andre")
        await _test_bike(str(bike_name), "dg")
    if _failures.is_empty():
        print("[bike-steering] PASS: ", _checks, " checks")
        quit(0)
        return
    for failure in _failures:
        push_error("[bike-steering] " + failure)
    print("[bike-steering] FAIL: ", _failures.size(), " failures / ", _checks, " checks")
    quit(1)

func _test_bike(bike_name: String, character: String) -> void:
    var scene := (load("res://scenes/third_person.tscn") as PackedScene).instantiate()
    root.add_child(scene)
    await process_frame
    var player := scene.get_node("Player")
    if character == "dg":
        player.call("set_active_character", 2)
    player.global_position = Vector3(1000.0, 0.0, 1000.0)
    _check(String(player.call("get_network_character_id")) == character, bike_name + " must keep " + character + " identity")
    var bike := scene.get_node(bike_name)
    bike.global_position = player.global_position + Vector3(0.0, 0.0, -1.0)
    bike.call("_start_mount")
    await create_timer(2.0).timeout
    _check(not bool(bike.get("_mounting")), bike_name + " must finish mounting")
    bike.set_physics_process(false)
    var front := bike.get("_front_wheel") as Node3D
    var fork := bike.get("_front_fork") as Node3D
    var rear := bike.get("_rear_wheel") as Node3D
    for raw_turn in [-1.0, 1.0]:
        var turn: float = float(raw_turn)
        bike.call("_update_rider_animation", 0.0, turn)
        bike.call("_update_steering_parts", turn)
        await create_timer(0.25).timeout
        var expected_yaw: float = -turn * float(bike.get("steering_angle"))
        _check(absf(wrapf(front.rotation.y - expected_yaw, -PI, PI)) < 0.02, bike_name + " front wheel must steer with handlebar")
        _check(absf(wrapf(fork.rotation.y - expected_yaw, -PI, PI)) < 0.02, bike_name + " front fork must steer with handlebar")
        _check(_hands_at_grips(scene, bike), bike_name + " " + character + " both hands must stay on the handlebar for turn " + str(turn))
    bike.set("_speed", 3.0)
    bike.call("_physics_process", 0.1)
    _check(absf(float(bike.get("_front_spin_angle"))) > 0.1, bike_name + " front wheel must spin while moving")
    _check(absf(float(bike.get("_rear_spin_angle"))) > 0.1, bike_name + " rear wheel must spin while moving")
    print("[bike-steering] ", bike_name, " front_spin=", bike.get("_front_spin_angle"), " rear_spin=", bike.get("_rear_spin_angle"))
    scene.queue_free()
    await process_frame

func _hands_at_grips(scene: Node, bike: Node) -> bool:
    var player := scene.get_node("Player")
    var active_visual := player.get("visual") as Node3D
    var skeleton := _find_skeleton(active_visual)
    if skeleton == null:
        return false
    for side in ["left", "right"]:
        var bone_name := " L Hand" if side == "left" else " R Hand"
        var target_name := "_left_grip_target" if side == "left" else "_right_grip_target"
        var bone := skeleton.find_bone(bone_name)
        var target := bike.get(target_name) as Node3D
        if bone < 0 or target == null:
            return false
        var hand_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
        if hand_world.distance_to(target.global_position) > 0.01:
            return false
    return true

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found:
            return found
    return null

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition:
        _failures.append(message)
