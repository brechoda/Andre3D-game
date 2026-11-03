extends SceneTree

var _failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/third_person.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var hud := scene.get_node("HUD/Root") as Control
	var joystick := hud.get_node("TouchJoystick") as AndreVirtualJoystick
	var hilux := scene.get_node("HiluxSRX2017")
	var left_button := hud.get_node_or_null("HiluxSteerLeftButton") as Button
	var right_button := hud.get_node_or_null("HiluxSteerRightButton") as Button
	if joystick == null or hilux == null or left_button == null or right_button == null:
		push_error("[hilux-touch-controls] required joystick, Hilux or steering controls are missing")
		scene.queue_free()
		await process_frame
		quit(1)
		return
	_check(joystick.visible, "analog joystick must be available outside cars")
	_check(left_button != null and right_button != null, "Hilux must create left and right steering buttons")
	if left_button != null and right_button != null:
		_check(not left_button.visible and not right_button.visible, "Hilux steering buttons must stay hidden while on foot or on a motorcycle")

	joystick.call("_set_value", Vector2(0.8, 0.0))
	hilux.call("_set_driving_hud", true)
	hilux.call("_set_drive_buttons_visible", true)
	_check(not joystick.visible, "analog joystick must disappear while driving the car")
	_check(joystick.value == Vector2.ZERO, "hiding the joystick must clear its held input")
	_check(left_button != null and left_button.visible, "left steering button must show while driving the Hilux")
	_check(right_button != null and right_button.visible, "right steering button must show while driving the Hilux")

	hilux.set("_riding", true)
	hilux.set("_speed", 2.0)
	left_button.emit_signal("button_down")
	_check(bool(hud.get_meta("touch_hilux_steer_left", false)), "pressing the left button must set left steering input")
	hilux.call("_physics_process", 0.1)
	_check(float(hilux.get("_steering")) < 0.0, "left touch button must steer the car left")
	left_button.emit_signal("button_up")
	right_button.emit_signal("button_down")
	_check(bool(hud.get_meta("touch_hilux_steer_right", false)), "pressing the right button must set right steering input")
	hilux.call("_physics_process", 0.2)
	_check(float(hilux.get("_steering")) > 0.0, "right touch button must steer the car right")
	right_button.emit_signal("button_up")

	hilux.call("_set_drive_buttons_visible", false)
	hilux.set("_riding", false)
	hilux.call("_set_driving_hud", false)
	_check(joystick.visible, "analog joystick must return after leaving the car")
	_check(left_button != null and not left_button.visible, "car steering buttons must hide after leaving the car")
	_check(not bool(hud.get_meta("touch_hilux_steer_left", false)) and not bool(hud.get_meta("touch_hilux_steer_right", false)), "steering input must clear after leaving the car")

	var motorcycle := scene.get_node("Pop100e2024")
	motorcycle.call("_set_riding_hud", true)
	_check(joystick.visible, "motorcycles must keep the analog joystick")
	_check(left_button != null and not left_button.visible, "Hilux steering buttons must not appear on motorcycles")
	motorcycle.call("_set_riding_hud", false)

	var touch_center: Vector2 = joystick.get_global_transform_with_canvas() * (joystick.size * 0.5)
	joystick.call("_input", _make_touch(5, true, touch_center))
	_check(int(joystick.get("_pointer_id")) == 5, "joystick must capture the first touch inside its area")
	joystick.call("_input", _make_drag(5, touch_center + Vector2(0.0, -joystick.radius * 0.05)))
	_check(joystick.value.length() < 0.001, "small movement inside deadzone must not move the character")
	joystick.call("_input", _make_drag(5, touch_center + Vector2(0.0, -joystick.radius * 0.5)))
	_check(joystick.value.y < -0.1 and joystick.value.length() <= 1.001, "upward drag must produce a bounded forward value")
	joystick.call("_input", _make_touch(6, true, touch_center))
	joystick.call("_input", _make_touch(6, false, touch_center))
	_check(int(joystick.get("_pointer_id")) == 5 and joystick.value.y < -0.1, "secondary finger release must not cancel the captured joystick finger")
	joystick.call("_input", _make_touch(5, false, touch_center))
	_check(int(joystick.get("_pointer_id")) == -1 and joystick.value.length() < 0.001, "releasing the captured finger must reset the joystick")
	joystick.call("_input", _make_touch(7, true, touch_center))
	joystick.call("_input", _make_drag(7, touch_center + Vector2(joystick.radius, 0.0)))
	joystick.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(int(joystick.get("_pointer_id")) == -1 and joystick.value.length() < 0.001, "losing app focus must release the joystick")

	var player := scene.get_node("Player") as CharacterBody3D
	var player_visual := scene.get_node("Player/AndreVisual") as Node3D
	player.rotation = Vector3(0.0, PI * 0.5, 0.0)
	player_visual.rotation = Vector3.ZERO
	player.call("set_active_character", 0)
	_check(is_equal_approx(float(player.get("_camera_yaw")), PI * 0.5), "camera yaw must use the player visual's world orientation")
	player.call("_face_visual_toward", Vector3.LEFT, 1.0, 12.0)
	_check(_faces_direction(player_visual, Vector3.LEFT), "player animation must face the world direction of movement despite a rotated parent")
	joystick.call("_set_value", Vector2(0.0, -0.86))
	_check(bool(player.call("_update_analog_sprinting")), "strong analog deflection must switch from walking to running")
	joystick.call("_set_value", Vector2(0.0, -0.78))
	_check(bool(player.call("_update_analog_sprinting")), "analog sprint hysteresis must prevent flicker near the threshold")
	joystick.call("_set_value", Vector2(0.0, -0.70))
	_check(not bool(player.call("_update_analog_sprinting")), "reducing analog deflection must return to walking")
	player.call("_on_run_button_toggled", true)
	_check(bool(player.get("_running")) and bool(hud.get_node("RunButton").get("button_pressed")), "one run-button tap must latch continuous sprint")
	_check(str(hud.get_node("RunButton").get("text")) == "PARAR DE CORRER", "latched sprint must label the button as the stop action")
	player.call("_on_run_button_toggled", false)
	_check(not bool(player.get("_running")) and not bool(hud.get_node("RunButton").get("button_pressed")), "a second run-button tap must stop continuous sprint")

	var gorece := scene.get_node("GoreceNPC") as Node3D
	var gorece_visual := scene.get_node("GoreceNPC/GoreceVisual") as Node3D
	gorece.rotation = Vector3(0.0, PI * 0.5, 0.0)
	gorece_visual.rotation = Vector3.ZERO
	player.call("set_active_character", 1)
	_check(is_equal_approx(float(player.get("_camera_yaw")), PI * 0.5), "Gorece camera yaw must use world orientation rather than local child yaw")
	_check(is_equal_approx(float(gorece.get("camera_yaw")), PI * 0.5), "Gorece movement camera yaw must match the world orientation")
	gorece.call("_face_visual_toward", Vector3.LEFT, 1.0)
	_check(_faces_direction(gorece_visual, Vector3.LEFT), "Gorece animation must face the world direction despite a rotated parent")
	gorece.call("set_joystick_value", Vector2(0.0, -0.86))
	_check(bool(gorece.call("_update_analog_sprinting")), "strong analog deflection must switch Gorece from walking to running")
	gorece.call("set_joystick_value", Vector2(0.0, -0.70))
	_check(not bool(gorece.call("_update_analog_sprinting")), "releasing the analog sprint zone must return Gorece to walking")
	player.call("_on_run_button_toggled", true)
	_check(bool(gorece.get("running")), "run-button toggle must also latch sprint for Gorece")
	player.call("_on_run_button_toggled", false)
	_check(not bool(gorece.get("running")), "second run-button toggle must stop Gorece sprint")

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[hilux-touch-controls] PASS: car arrows, joystick hide/restore, and motorcycle joystick retained")
		quit(0)
		return
	for failure in _failures:
		push_error("[hilux-touch-controls] " + failure)
	print("[hilux-touch-controls] FAIL: %d checks failed" % _failures.size())
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _make_touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event

func _make_drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event

func _faces_direction(visual: Node3D, direction: Vector3) -> bool:
	var forward := -visual.global_transform.basis.z.normalized()
	return forward.dot(direction.normalized()) > 0.99
