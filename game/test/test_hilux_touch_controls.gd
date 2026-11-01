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
	var left_button := hud.get_node_or_null("SteerLeftButton") as Button
	var right_button := hud.get_node_or_null("SteerRightButton") as Button
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
	_check(bool(hud.get_meta("touch_steer_left", false)), "pressing the left button must set left steering input")
	hilux.call("_physics_process", 0.1)
	_check(float(hilux.get("_steering")) < 0.0, "left touch button must steer the car left")
	left_button.emit_signal("button_up")
	right_button.emit_signal("button_down")
	_check(bool(hud.get_meta("touch_steer_right", false)), "pressing the right button must set right steering input")
	hilux.call("_physics_process", 0.2)
	_check(float(hilux.get("_steering")) > 0.0, "right touch button must steer the car right")
	right_button.emit_signal("button_up")

	hilux.call("_set_drive_buttons_visible", false)
	hilux.set("_riding", false)
	hilux.call("_set_driving_hud", false)
	_check(joystick.visible, "analog joystick must return after leaving the car")
	_check(left_button != null and not left_button.visible, "car steering buttons must hide after leaving the car")
	_check(not bool(hud.get_meta("touch_steer_left", false)) and not bool(hud.get_meta("touch_steer_right", false)), "steering input must clear after leaving the car")

	var motorcycle := scene.get_node("Pop100e2024")
	motorcycle.call("_set_riding_hud", true)
	_check(joystick.visible, "motorcycles must keep the analog joystick")
	_check(left_button != null and not left_button.visible, "Hilux steering buttons must not appear on motorcycles")
	motorcycle.call("_set_riding_hud", false)

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
