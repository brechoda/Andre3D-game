extends SceneTree

var _failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/third_person.tscn") as PackedScene
	_check(packed != null, "main game scene must load")
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate()
	var map_streamer := scene.get_node_or_null("MapStreamer")
	if map_streamer != null:
		map_streamer.free()
	root.add_child(scene)
	await process_frame

	var fiat := scene.get_node_or_null("FiatUno") as FiatUnoController
	_check(fiat != null, "FiatUno controller must exist in the main scene")
	if fiat == null:
		quit(1)
		return
	var visual := fiat.get_node_or_null("FiatUnoVisual") as Node3D
	_check(visual != null and visual.get_child_count() > 0, "Fiat Uno GLB must be instanced in the scene")
	for part_name: String in ["door_lf_ok", "wheel_lf", "wheel_lb", "wheel_rb", "wheel"]:
		_check(fiat.call("_find_part", visual, part_name) != null, "Fiat Uno GLB must contain part: " + part_name)

	await process_frame
	for audio_node: String in ["FiatUnoIdleEngineAudio", "FiatUnoAccelEngineAudio", "FiatUnoDecelEngineAudio"]:
		var player := fiat.get_node_or_null(audio_node) as AudioStreamPlayer3D
		_check(player != null and player.stream != null, "Fiat Uno engine stream must load: " + audio_node)
	fiat.set("_riding", true)
	var gps := scene.get_node("HUD/Root/GPSAutopilot")
	gps.set("_scene", scene)
	_check(gps.call("_get_active_vehicle") == fiat, "GPS must recognize the Fiat Uno as the active vehicle")
	var multiplayer_client := scene.get_node("OnlineMultiplayer")
	var network_state: Dictionary = multiplayer_client.call("_local_vehicle_state")
	_check(network_state.get("vehicle") == "fiatuno", "multiplayer must identify the Fiat Uno type")
	_check(network_state.get("vehicle_id") == "fiatuno_01", "multiplayer must send the Fiat Uno network ID")
	fiat.set("_riding", false)
	var hud := scene.get_node("HUD/Root") as Control
	var joystick := hud.get_node("TouchJoystick") as AndreVirtualJoystick
	var left_button := hud.get_node_or_null("HiluxSteerLeftButton") as Button
	var right_button := hud.get_node_or_null("HiluxSteerRightButton") as Button
	_check(left_button != null and right_button != null, "shared touch steering buttons must be created")
	fiat.call("_set_driving_hud", true)
	fiat.call("_set_drive_buttons_visible", true)
	_check(not joystick.visible, "joystick must hide while driving the Fiat Uno")
	_check(left_button != null and left_button.visible, "left steering button must show in the Fiat Uno")
	_check(right_button != null and right_button.visible, "right steering button must show in the Fiat Uno")
	if left_button != null:
		fiat.set("_riding", true)
		fiat.set("_speed", 2.0)
		left_button.emit_signal("button_down")
		_check(bool(hud.get_meta("touch_hilux_steer_left", false)), "left touch button must set shared steering input")
		fiat.call("_physics_process", 0.1)
		_check(float(fiat.get("_steering")) < 0.0, "Fiat Uno must steer from shared touch input")
		left_button.emit_signal("button_up")
	fiat.set("_riding", false)
	fiat.call("_set_drive_buttons_visible", false)
	fiat.call("_set_driving_hud", false)

	var player_body := scene.get_node("Player") as CharacterBody3D
	var gorece := scene.get_node("GoreceNPC") as CharacterBody3D
	var approach: Vector3 = fiat.global_transform * Vector3(-1.35, 0.0, -0.25)
	player_body.global_position = approach + Vector3.UP * 0.98
	_check(fiat.is_near_player(), "Andre must be able to approach the Fiat Uno")
	player_body.set("_active_character", 1)
	gorece.global_position = approach + Vector3.UP * 0.98
	_check(fiat.is_near_player(), "Gorece must be able to approach the Fiat Uno")
	player_body.set("_active_character", 2)
	player_body.global_position = approach + Vector3.UP * 0.98
	_check(fiat.is_near_player(), "DG must be able to approach the Fiat Uno")

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[fiat-uno-integration] PASS: model, wheel/door controls, engine audio, touch, GPS, multiplayer, and all characters")
		quit(0)
		return
	for failure: String in _failures:
		push_error("[fiat-uno-integration] " + failure)
	print("[fiat-uno-integration] FAIL: %d checks failed" % _failures.size())
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
