extends SceneTree

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var packed := load("res://scenes/third_person.tscn") as PackedScene
	if packed == null:
		push_error("Could not load the gameplay scene")
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var ride_button := scene.get_node_or_null("HUD/Root/RideButton") as Button
	var pop := scene.get_node_or_null("Pop100e2024") as Node3D
	var wayfarer := scene.get_node_or_null("WayfarerR1200") as Node3D
	var hilux := scene.get_node_or_null("HiluxSRX2017") as Node3D
	var fiat := scene.get_node_or_null("FiatUno") as Node3D
	if player == null or ride_button == null or pop == null or wayfarer == null or hilux == null or fiat == null:
		push_error("The player, shared ride button, or one of the vehicles is missing")
		quit(1)
		return

	player.set("_active_character", 0)
	player.global_position = Vector3.ZERO
	pop.global_position = Vector3(1.0, 0.0, 0.0)
	wayfarer.global_position = Vector3(1000.0, 0.0, 0.0)
	hilux.global_position = Vector3(1000.0, 0.0, 1000.0)
	fiat.global_position = Vector3(-1000.0, 0.0, -1000.0)
	await process_frame

	if not ride_button.visible or ride_button.disabled:
		push_error("A distant Fiat hid the shared ride button beside the Pop 100")
		quit(1)
		return
	if not ride_button.text.contains("MOTO POP 100E"):
		push_error("The shared ride button did not select the nearby Pop 100: " + ride_button.text)
		quit(1)
		return

	print("[vehicle-ride-button] nearby motorcycle remains interactable when Fiat is distant")
	quit(0)
