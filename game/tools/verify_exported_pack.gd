extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "Andre 3D", "exported identity")
	_check(ResourceLoader.exists("res://assets/models/andre.glb"), "converted Andre GLB")
	_check(ResourceLoader.exists("res://scripts/third_person.gd"), "third-person controller")
	_check(ResourceLoader.exists("res://scripts/virtual_joystick.gd"), "touch joystick script")
	_check(not ResourceLoader.exists("res://assets/source/andre.dff"), "source DFF excluded from player pack")
	_check(not ResourceLoader.exists("res://test/test_suite.tscn"), "test scene excluded")

	var packed := load("res://scenes/third_person.tscn") as PackedScene
	_check(packed != null, "third-person scene loads")
	if packed != null:
		var main := packed.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		var player := main.get_node_or_null("Player") as CharacterBody3D
		_check(player != null, "player exists")
		if player != null:
			_check(player.get_node_or_null("Camera3D") is Camera3D, "third-person camera exists")
			_check(player.get_node_or_null("AndreVisual") != null, "Andre visual exists")
		_check(main.get_node_or_null("HUD/Root/TouchJoystick") is Control, "touch HUD exists")
		_check(main.get_node_or_null("Ground/Collision") != null, "empty map ground collision exists")
		main.queue_free()
		await process_frame

	if _failures.is_empty():
		print("[exported-pack] PASS: Andre 3D identity, converted model, player, camera, touch HUD and empty map")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[exported-pack] " + failure)
		quit(1)

func _check(condition: bool, context: String) -> void:
	if not condition and context not in _failures:
		_failures.append(context)
