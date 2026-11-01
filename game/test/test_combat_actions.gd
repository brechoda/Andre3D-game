extends SceneTree

var _failures := PackedStringArray()

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://scenes/third_person.tscn") as PackedScene
    if packed == null:
        push_error("combat test could not load the third-person scene")
        quit(1)
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    await process_frame
    await process_frame

    var player: Node = scene.get_node("Player")
    var skeleton: Skeleton3D = player.call("_find_skeleton", player.get("visual"))
    _check(skeleton != null, "player skeleton must exist")
    if skeleton == null:
        quit(1)
        return
    var hand_index := skeleton.find_bone(" R Hand")
    _check(hand_index >= 0, "right-hand bone must exist")
    if hand_index < 0:
        quit(1)
        return

    var action_button := scene.get_node("HUD/Root/ActionButton") as Button
    _check(scene.get_node_or_null("HUD/Root/WeaponButton") == null, "weapon button must be removed from the HUD")
    _check(action_button.text == "DAR SOCO", "action button must remain a punch control")
    _check(not player.has_method("_toggle_weapon"), "weapon toggle must no longer exist")
    _check(player.find_child("AssaultRifle", true, false) == null, "player must not spawn a rifle model")
    _check(player.find_child("WeaponHandAttachment", true, false) == null, "player must not attach a weapon to the skeleton")

    var animation_player := player.get("_animation_player") as AnimationPlayer
    _check(animation_player != null and animation_player.has_animation("FightA_1"), "the original FightA_1 IFP clip must be loaded")
    if animation_player == null or not animation_player.has_animation("FightA_1"):
        quit(1)
        return
    var punch_clip: Animation = animation_player.get_animation("FightA_1")
    _check(punch_clip.length > 0.1, "FightA_1 must have a playable duration")
    var combo_count := 0
    for punch_name in ["FightA_1", "FightA_2", "FightA_3"]:
        if animation_player.has_animation(punch_name):
            combo_count += 1
    print("[combat-actions] combo clips available: %d" % combo_count)

    player.call("_update_walk_animation", true, 1.0)
    _check(animation_player.current_animation == "WALK_civi", "walking must use the civilian animation, not a weapon-hold pose")
    player.call("_update_walk_animation", false, 0.0)
    _check(animation_player.current_animation == "IDLE_stance", "standing idle must use the unarmed stance")

    var hand_start: Vector3 = skeleton.get_bone_global_pose(hand_index).origin
    player.call("_perform_action")
    var punch_sample_time: float = minf(0.15, punch_clip.length * 0.3)
    await create_timer(punch_sample_time).timeout
    _check(animation_player.current_animation == "FightA_1", "unarmed action must play the IFP punch clip")
    var punch_displacement: float = hand_start.distance_to(skeleton.get_bone_global_pose(hand_index).origin)
    _check(punch_displacement > 0.16, "punch must move the fist forward visibly")
    await create_timer(maxf(0.0, punch_clip.length - punch_sample_time) + 0.1).timeout
    _check(not bool(player.get("_action_busy")), "punch action must finish")
    _check(animation_player.current_animation == "IDLE_stance", "punch must return to the idle animation after the clip")
    _check(scene.find_child("VisualProjectile", true, false) == null, "unarmed combat must not create projectiles")
    _check(scene.find_child("MuzzleFlash", true, false) == null, "unarmed combat must not create muzzle flashes")

    var gorece := scene.get_node("GoreceNPC") as GoreceNpc
    var gorece_animation_player := gorece.get("_animation_player") as AnimationPlayer
    for reaction_name in ["HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3"]:
        _check(animation_player.has_animation(reaction_name), "Andre GLB must contain IFP reaction " + reaction_name)
        _check(gorece_animation_player != null and gorece_animation_player.has_animation(reaction_name), "GORECE GLB must contain IFP reaction " + reaction_name)
    gorece.set_player_controlled(true)
    player.global_position = Vector3.ZERO
    gorece.global_position = Vector3(0.0, 0.0, -1.0)
    (player.get("visual") as Node3D).rotation.y = 0.0
    (gorece.get("visual") as Node3D).rotation.y = PI
    player.call("_perform_action")
    var impact_delay: float = minf(punch_clip.length * 0.28, 0.34)
    await create_timer(impact_delay + 0.04).timeout
    _check(bool(gorece.get("_action_busy")), "GORECE must react when Andre lands a punch in front and in reach")
    _check(_is_ifp_hit_reaction(str(gorece.get("_playing_animation"))), "GORECE must play an imported IFP hit reaction")
    await create_timer(punch_clip.length + 0.55).timeout

    gorece.call("perform_action")
    var gorece_clip_length: float = float(gorece.get("_combo_clip_length"))
    await create_timer(minf(gorece_clip_length * 0.28, 0.34) + 0.04).timeout
    _check(bool(player.get("_action_busy")), "Andre must react when GORECE lands a punch in front and in reach")
    _check(_is_ifp_hit_reaction(str(player.get("_playing_animation"))), "Andre must play an imported IFP hit reaction")

    scene.queue_free()
    await process_frame
    if _failures.is_empty():
        print("[combat-actions] PASS: no weapon/UI/armed locomotion, punch combo and two-way hit reactions")
        quit(0)
        return
    for failure in _failures:
        push_error("[combat-actions] " + failure)
    print("[combat-actions] FAIL: %d checks failed" % _failures.size())
    quit(1)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

func _is_ifp_hit_reaction(animation_name: String) -> bool:
    return animation_name.begins_with("HIT_") or animation_name.begins_with("HitA_")
