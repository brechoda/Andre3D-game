extends SceneTree

var _failures := PackedStringArray()

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://scenes/third_person.tscn") as PackedScene
    _check(packed != null, "third-person scene must load")
    if packed == null:
        quit(1)
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    await physics_frame
    await physics_frame

    var gorece := scene.get_node("GoreceNPC") as GoreceNpc
    var animation_player := gorece.get("_animation_player") as AnimationPlayer
    _check(animation_player != null, "GORECE AnimationPlayer must exist")
    if animation_player == null:
        quit(1)
        return
    for clip in ["IDLE_stance", "Player_Sneak", "Player_Sneak_walkstart", "JUMP_launch", "JUMP_glide", "JUMP_land", "FALL_fall", "FALL_land", "FightA_1", "FightA_2", "FightA_3"]:
        _check(animation_player.has_animation(clip), "GORECE IFP clip must be imported: " + clip)
    _check(animation_player.get_animation("FightA_3").length > 1.2, "GORECE's original finalizer timing must remain; only arm rotations are corrected")

    gorece.set_player_controlled(true)
    gorece.set_crouching(true)
    await create_timer(0.7).timeout
    _check(str(gorece.get("_playing_animation")) == "Player_Sneak", "stationary crouch must use the non-weapon sneak pose")
    var capsule := gorece.get_node("Collision") .shape as CapsuleShape3D
    _check(absf(capsule.height - 0.95) < 0.01, "deep crouch collision must be shorter than the standing capsule")
    gorece.request_jump()
    await physics_frame
    _check(not bool(gorece.get("_jumping")), "jump must remain blocked while crouched")

    gorece.set_crouching(false)
    gorece.global_position = Vector3(20.0, 0.0, 0.0)
    (gorece.get("visual") as Node3D).rotation.y = PI / 2.0
    gorece.velocity = Vector3.ZERO
    await physics_frame
    await physics_frame
    gorece.request_jump()
    await physics_frame
    _check(bool(gorece.get("_jumping")), "ground jump must start")
    var launch_velocity := gorece.velocity.y
    var horizontal_speed := Vector2(gorece.velocity.x, gorece.velocity.z).length()
    _check(horizontal_speed > 3.5, "jump must have a strong forward impulse")
    gorece.request_jump()
    await physics_frame
    _check(gorece.velocity.y < launch_velocity, "a second request in midair must not relaunch the jump")

    var saw_landing := false
    for _frame in range(180):
        if animation_player.current_animation == "FALL_land":
            saw_landing = true
            break
        await physics_frame
    _check(saw_landing, "landing after a jump must play the calmer FALL_land IFP clip")
    _check(Vector2(gorece.velocity.x, gorece.velocity.z).length() < 0.1, "a stopped character must not carry run velocity into the landing animation")
    await create_timer(1.45).timeout

    gorece.perform_action()
    _check(animation_player.current_animation == "FightA_1", "GORECE combo must start with FightA_1 like Andre")
    gorece.set_action_holding(true)
    var saw_second_punch := false
    for _frame in range(360):
        if animation_player.current_animation == "FightA_2":
            saw_second_punch = true
            break
        await process_frame
    _check(saw_second_punch, "held combo must advance from FightA_1 to FightA_2")
    if not saw_second_punch:
        gorece.set_action_holding(false)
        scene.queue_free()
        quit(1)
        return
    var saw_third_punch := false
    for _frame in range(360):
        if animation_player.current_animation == "FightA_3":
            saw_third_punch = true
            break
        await process_frame
    _check(saw_third_punch, "held combo must advance from FightA_2 to FightA_3")
    if not saw_third_punch:
        gorece.set_action_holding(false)
        scene.queue_free()
        quit(1)
        return
    gorece.set_action_holding(false)
    var combo_finished := false
    for _frame in range(240):
        if not bool(gorece.get("_action_busy")):
            combo_finished = true
            break
        await process_frame
    _check(combo_finished, "the final combo clip must finish cleanly")

    scene.queue_free()
    await process_frame
    if _failures.is_empty():
        print("[gorece-motion] PASS: deep crouch, stopped FALL_land, GORECE FightA timing and corrected arm rotations")
        quit(0)
        return
    for failure in _failures:
        push_error("[gorece-motion] " + failure)
    print("[gorece-motion] FAIL: %d checks failed" % _failures.size())
    quit(1)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)
