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
    await process_frame
    await process_frame

    var pop := scene.get_node("Pop100e2024")
    var wayfarer := scene.get_node("WayfarerR1200")
    var decel := pop.get("_decel_engine_audio") as AudioStreamPlayer3D
    var accel := pop.get("_accel_engine_audio") as AudioStreamPlayer3D
    var idle := pop.get("_idle_engine_audio") as AudioStreamPlayer3D
    _check(decel != null, "Pop must create a deceleration AudioStreamPlayer3D")
    _check(wayfarer.get("_decel_engine_audio") != null, "Wayfarer must expose a synchronized engine sound")
    var wayfarer_decel := wayfarer.get("_decel_engine_audio") as AudioStreamPlayer3D
    _check(wayfarer_decel != null and (wayfarer_decel.stream as AudioStreamMP3).resource_path == "res://assets/audio/r1200_desacelerando.mp3", "R1200 must use the uploaded deceleration MP3")
    var wayfarer_accel := wayfarer.get("_accel_engine_audio") as AudioStreamPlayer3D
    _check(wayfarer_accel != null and (wayfarer_accel.stream as AudioStreamMP3).resource_path == "res://assets/audio/r1200_acelerando.mp3", "R1200 must use the uploaded acceleration MP3")
    var wayfarer_idle := wayfarer.get("_idle_engine_audio") as AudioStreamPlayer3D
    _check(wayfarer_idle != null and (wayfarer_idle.stream as AudioStreamMP3).resource_path == "res://assets/audio/r1200_marcha_lenta.mp3", "R1200 must use the uploaded idle MP3")
    wayfarer.set("_riding", true)
    wayfarer.set("_speed", 0.0)
    wayfarer.call("_update_idle_engine_audio")
    _check(wayfarer_idle != null and wayfarer_idle.playing, "R1200 idle mode must play its idle MP3")
    var wayfarer_hud := scene.get_node("HUD/Root")
    wayfarer_hud.set_meta("touch_gas", true)
    wayfarer.call("_update_idle_engine_audio")
    _check(wayfarer_accel != null and wayfarer_accel.playing and not wayfarer_idle.playing, "R1200 acceleration mode must play its acceleration MP3")
    wayfarer_hud.set_meta("touch_gas", false)
    wayfarer.set("_speed", 2.0)
    wayfarer.call("_update_idle_engine_audio")
    _check(wayfarer_decel != null and wayfarer_decel.playing and not wayfarer_accel.playing, "R1200 deceleration mode must play its deceleration MP3")
    wayfarer.set("_riding", false)
    if decel == null or accel == null or idle == null:
        quit(1)
        return
    var stream := decel.stream as AudioStreamMP3
    _check(stream != null and stream.resource_path == "res://assets/audio/pop100_desacelerando_v2_1.mp3", "Pop must load the user-provided deceleration MP3")
    _check(stream != null, "deceleration clip must be available for coasting")

    pop.set("_riding", true)
    pop.set("_speed", 2.0)
    pop.call("_update_idle_engine_audio")
    _check(decel.playing, "coasting while moving must start the deceleration sound")
    _check(not accel.playing and not idle.playing, "deceleration must replace acceleration and idle sounds")
    decel.stop()
    pop.call("_update_idle_engine_audio")
    _check(not decel.playing, "deceleration one-shot must not restart during the same coast")
    await create_timer(0.15).timeout
    pop.call("_update_idle_engine_audio")

    var hud := scene.get_node("HUD/Root")
    hud.set_meta("touch_gas", true)
    pop.call("_update_idle_engine_audio")
    _check(accel.playing and not decel.playing, "pressing the throttle must stop deceleration and play acceleration")
    hud.set_meta("touch_gas", false)

    pop.set("_speed", -1.0)
    pop.call("_update_idle_engine_audio")
    _check(not decel.playing and idle.playing, "reversing must not play the deceleration sound")

    pop.set("_speed", 0.0)
    pop.call("_update_idle_engine_audio")
    _check(idle.playing and not accel.playing, "with the bike stopped, the idle sound must take over")
    pop.set("_riding", false)
    pop.call("_update_idle_engine_audio")
    _check(not idle.playing and not decel.playing and not accel.playing, "dismounting must stop all engine sounds")

    idle.stop()
    accel.stop()
    decel.stop()
    scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("[pop-deceleration-audio] PASS: Pop deceleration one-shot and engine sound transitions")
        quit(0)
        return
    for failure in _failures:
        push_error("[pop-deceleration-audio] " + failure)
    print("[pop-deceleration-audio] FAIL: %d checks failed" % _failures.size())
    quit(1)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)
