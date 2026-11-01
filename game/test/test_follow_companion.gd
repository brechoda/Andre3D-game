extends SceneTree

var _failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/third_person.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var player := scene.get_node("Player")
	var gorece := scene.get_node("GoreceNPC") as GoreceNpc
	var hilux := scene.get_node("HiluxSRX2017")
	var follow_button := scene.get_node("HUD/Root/FollowButton") as Button
	_check(follow_button.text == "SEGUIR", "follow button must start with the SEGUIR label")

	follow_button.emit_signal("pressed")
	_check(bool(player.get("_follow_enabled")), "pressing follow must enable companion following")
	_check(follow_button.text == "PARAR DE SEGUIR", "enabled follow button must offer stopping follow")
	_check(gorece.follow_target == player, "when Andre is active, Gorece must follow Andre")
	var start_distance := gorece.global_position.distance_to(player.global_position)
	for _step in range(30):
		gorece.call("_physics_process", 0.05)
	_check(gorece.global_position.distance_to(player.global_position) < start_distance, "Gorece must move toward Andre while following on foot")

	player.call("_toggle_character")
	_check(bool(player.get("_active_character") == 1), "character switch must make Gorece the active character")
	_check(gorece.follow_target == null, "a controlled Gorece must not keep an AI follow target")
	player.global_position = gorece.global_position + Vector3(8.0, 0.0, 0.0)
	var andre_start_distance: float = player.global_position.distance_to(gorece.global_position)
	for _step in range(18):
		player.call("_physics_follow_companion", 0.05)
	_check(player.global_position.distance_to(gorece.global_position) < andre_start_distance, "Andre must follow Gorece on foot when Gorece is active")
	hilux.set("_riding", true)
	player.call("_update_follow_vehicle")
	var bike := player.get("_follow_bike_target") as Node3D
	_check(bike != null, "Andre must select an available motorcycle when Gorece drives the Hilux")
	if bike != null:
		_check(float(bike.get("max_speed")) >= 18.0, "Andre must choose a motorcycle fast enough to keep up with the Hilux")
		player.global_position = bike.global_position + Vector3(8.0, 0.0, 0.0)
		player.call("_physics_follow_companion", 0.016)
		_check(bool(player.get("_running")), "Andre must run toward a distant motorcycle")
		_check(player.get("_playing_animation") == "run_civi", "distant motorcycle follow must use the run animation")
		player.global_position = bike.global_position
		player.call("_physics_follow_companion", 0.016)
		_check(not bool(player.get("_running")), "Andre must stop running when he reaches the motorcycle")
		_check(is_instance_valid(player.get("_follow_vehicle")), "Andre must start following the Hilux on a motorcycle after reaching it")
		_check(bool(bike.call("is_ai_following")), "selected motorcycle must enter AI follow-driving mode")
		_check(not player.is_physics_processing(), "AI motorcycle must take over Andre movement while riding")
		await create_timer(1.8).timeout
		_check(absf(float(bike.get("_speed"))) > 0.1, "AI motorcycle must accelerate to follow the Hilux")
		var hilux_forward: Vector3 = -hilux.global_transform.basis.z
		hilux_forward.y = 0.0
		var follow_spot: Vector3 = hilux.global_position - hilux_forward.normalized() * 5.5
		_check(bike.global_position.distance_to(follow_spot) < 4.8, "AI motorcycle must close the distance to a point behind the Hilux")
		hilux.set("_riding", false)
		await create_timer(2.0).timeout
		_check(not bool(bike.call("is_riding")), "Andre must dismount when the Hilux stops being driven")
		_check(player.is_physics_processing(), "Andre on-foot follow movement must resume after dismounting")

	follow_button.emit_signal("pressed")
	_check(not bool(player.get("_follow_enabled")), "pressing the button again must disable following")
	_check(gorece.follow_target == null, "disabling follow must clear Gorece follow target")
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[follow-companion] PASS: toggle, walking follow, AI motorcycle follow, and dismount handoff")
		quit(0)
		return
	for failure in _failures:
		push_error("[follow-companion] " + failure)
	print("[follow-companion] FAIL: %d checks failed" % _failures.size())
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
