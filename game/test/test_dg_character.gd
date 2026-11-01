extends SceneTree

var _failures := PackedStringArray()

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var session_file := FileAccess.open("user://andre3d_session.json", FileAccess.WRITE)
    if session_file != null:
        session_file.store_string(JSON.stringify({"mode": "offline", "character": "andre"}))
        session_file.close()
    var menu_packed := load("res://scenes/session_menu.tscn") as PackedScene
    _check(menu_packed != null, "session menu must load")
    if menu_packed != null:
        var menu := menu_packed.instantiate()
        root.add_child(menu)
        await process_frame
        var dg_button_found := false
        for option in menu.find_children("*", "Button", true, false):
            if (option as Button).text == "DG":
                dg_button_found = true
        _check(dg_button_found, "character menu must offer DG")
        menu.call("_select_character", "dg")
        _check(String(menu.get("selected_character")) == "dg", "character menu must save DG selection")
        menu.queue_free()
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

    var player := scene.get_node("Player")
    player.call("set_active_character", 2)
    var dg_visual := player.get("visual") as Node3D
    var andre_visual := player.get_node("AndreVisual") as Node3D
    _check(String(player.call("get_network_character_id")) == "dg", "DG identity must be exposed to multiplayer")
    _check(dg_visual == player.get_node("DGVisual"), "DG must use its own visual scene")
    _check(dg_visual.visible and not andre_visual.visible, "DG must be visible while Andre is hidden")
    var textured_surfaces := 0
    for node in _walk_nodes(dg_visual):
        if not node is MeshInstance3D:
            continue
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        for surface in range(mesh_instance.mesh.get_surface_count()):
            var material := mesh_instance.get_active_material(surface) as StandardMaterial3D
            if material != null and material.albedo_texture != null:
                textured_surfaces += 1
    _check(textured_surfaces >= 10, "DG must use the character textures supplied in SKIN_COMPLETA.zip")

    var andre_animation_player := player.call("_find_animation_player", andre_visual) as AnimationPlayer
    var dg_animation_player := player.call("_find_animation_player", dg_visual) as AnimationPlayer
    _check(andre_animation_player != null and dg_animation_player != null, "both character rigs must expose AnimationPlayer")
    if andre_animation_player == null or dg_animation_player == null:
        quit(1)
        return
    var andre_clips := andre_animation_player.get_animation_list()
    var dg_clips := dg_animation_player.get_animation_list()
    _check(andre_clips.size() == 40, "Andre model must provide 40 current animation clips")
    _check(dg_clips.size() == andre_clips.size(), "DG must have the same number of clips as Andre")
    for clip in andre_clips:
        _check(dg_animation_player.has_animation(clip), "DG must contain Andre clip " + String(clip))
    for required_clip in [
        "IDLE_stance", "WALK_civi", "run_civi", "Player_Sneak", "JUMP_launch",
        "FightA_1", "FightA_2", "FightA_3", "HIT_front", "HIT_back", "HIT_L", "HIT_R",
        "BIKEd_jumponL", "BIKEd_Ride", "BIKEd_Fwd", "BIKEd_Back", "BIKEd_pushes",
        "BIKEd_Still", "BIKEd_Left", "BIKEd_Right", "BIKEd_getoffLHS",
    ]:
        _check(dg_animation_player.has_animation(required_clip), "DG is missing required clip " + required_clip)

    for bike_name in ["Pop100e2024", "WayfarerR1200"]:
        var bike := scene.get_node(bike_name)
        bike.global_position = player.global_position + Vector3(0.0, 0.0, -1.0)
        bike.call("_refresh_rider_visual")
        _check(bike.get("_rider_visual") == dg_visual, bike_name + " must bind its rider to DG")
        _check((bike.get("_rider_animator") as AnimationPlayer).has_animation("BIKEd_Ride"), bike_name + " must find DG riding animation")
        _check(bool(bike.call("is_near_player")), bike_name + " must allow DG to approach for mounting")
        bike.call("_start_mount")
        _check(bool(bike.call("is_riding")), bike_name + " must allow DG to mount and ride")
        _check(bike.get("_rider_visual") == dg_visual, bike_name + " must keep DG as the visible rider")
        bike.call("_finish_dismount")
    var hilux := scene.get_node("HiluxSRX2017")
    _check(not bool(hilux.call("is_near_player")), "DG must not be allowed to enter or drive the Hilux")

    var remote: Node = (load("res://scripts/net/remote_avatar.gd") as Script).new()
    root.add_child(remote)
    remote.call("setup", (load("res://assets/models/dg_rigged.glb") as PackedScene).instantiate(), "dg")
    _check(String(remote.get("character")) == "dg", "remote avatar must retain DG identity")
    _check((remote.get("animation_player") as AnimationPlayer).has_animation("BIKEd_Ride"), "remote DG must be able to play motorcycle animation")

    scene.queue_free()
    remote.queue_free()
    await process_frame
    if _failures.is_empty():
        print("[dg-character] PASS: selection, 40 matching clips, bikes, remote avatar and Hilux restriction")
        quit(0)
        return
    for failure in _failures:
        push_error("[dg-character] " + failure)
    print("[dg-character] FAIL: %d checks failed" % _failures.size())
    quit(1)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

func _walk_nodes(root_node: Node) -> Array[Node]:
    var result: Array[Node] = [root_node]
    for child in root_node.get_children():
        result.append_array(_walk_nodes(child))
    return result
