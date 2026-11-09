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

	var gorece := scene.get_node_or_null("GoreceNPC") as CharacterBody3D
	var multiplayer_client := scene.get_node_or_null("OnlineMultiplayer")
	if gorece == null:
		push_error("Gorece character is missing")
		quit(1)
		return
	if multiplayer_client != null:
		multiplayer_client.set("enabled", false)
	player.set("_active_character", 0)
	player.global_position = Vector3.ZERO
	var pull_origin := player.global_position
	var pull_yaw := (player.get("visual") as Node3D).global_rotation.y
	player.call("_on_pull_vehicle_selected", 1)
	await process_frame
	var pull_forward := Vector3(-sin(pull_yaw), 0.0, -cos(pull_yaw))
	var expected_pull := pull_origin + pull_forward * 2.0
	var pulled_distance := Vector2(wayfarer.global_position.x, wayfarer.global_position.z).distance_to(Vector2(expected_pull.x, expected_pull.z))
	if pulled_distance > 2.0:
		push_error("The Wayfarer did not move to the player's pull position: %.2f" % pulled_distance)
		quit(1)
		return
	wayfarer.call("toggle_riding_from_universal")
	await process_frame
	if not bool(wayfarer.call("is_riding")):
		push_error("The pulled Wayfarer stayed nearby but could not be mounted")
		quit(1)
		return
	wayfarer.call("_finish_dismount")
	# Simula o próximo arranque: o spawn normal é aplicado, seguido da pose
	# persistida do último puxar.
	player.call("_apply_selected_map_spawn")
	player.global_position = pull_origin
	await process_frame
	if wayfarer.global_position.distance_to(expected_pull) > 2.0:
		push_error("The pulled Wayfarer pose was not restored after a simulated restart")
		quit(1)
		return
	wayfarer.call("toggle_riding_from_universal")
	await process_frame
	if not bool(wayfarer.call("is_riding")):
		push_error("The persisted Wayfarer could not be mounted after a simulated restart")
		quit(1)
		return
	wayfarer.call("_finish_dismount")
	player.call("set_active_character", 1)
	gorece.global_position = pop.global_position + Vector3(0.0, 0.0, 1.0)
	await process_frame
	if not ride_button.visible or ride_button.disabled:
		push_error("The active Gorece character could not interact with a nearby motorcycle")
		quit(1)
		return
	ride_button.emit_signal("pressed")
	await process_frame
	if not bool(pop.call("is_riding")):
		push_error("The active Gorece character did not mount the nearby motorcycle")
		quit(1)
		return
	if pop.get("_rider_body") != gorece:
		push_error("The motorcycle mounted a different character than the active Gorece")
		quit(1)
		return
	pop.call("_finish_dismount")
	if bool(pop.call("is_riding")) or not gorece.is_physics_processing():
		push_error("Gorece did not regain control after dismounting")
		quit(1)
		return

	print("[vehicle-ride-button] nearby motorcycle mounts and releases the active Gorece")
	quit(0)
