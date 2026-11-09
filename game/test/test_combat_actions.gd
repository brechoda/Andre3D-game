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
    _check(action_button.text == "AÇÃO", "action button must use the unarmed action label")
    _check(scene.get_node_or_null("HUD/Root/WeaponButton") == null, "weapon button must be removed from the HUD")
    _check(scene.get_node_or_null("HUD/Root/AimButton") == null, "aim button must be removed from the HUD")
    _check(scene.get_node_or_null("HUD/Root/RifleButton") == null, "rifle button must be removed from the HUD")
    _check(player.find_child("PistolHandAttachment", true, false) == null, "player must not attach a pistol")
    _check(player.find_child("M4HandAttachment", true, false) == null, "player must not attach an M4")

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


    var gorece := scene.get_node("GoreceNPC") as GoreceNpc
    var gorece_animation_player := gorece.get("_animation_player") as AnimationPlayer
    for reaction_name in ["HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3"]:
        _check(animation_player.has_animation(reaction_name), "Andre GLB must contain IFP reaction " + reaction_name)
        _check(gorece_animation_player != null and gorece_animation_player.has_animation(reaction_name), "GORECE GLB must contain IFP reaction " + reaction_name)
    scene.queue_free()
    await process_frame
    if _failures.is_empty():
        print("[combat-actions] PASS: unarmed controls and two-way hit reactions")
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
