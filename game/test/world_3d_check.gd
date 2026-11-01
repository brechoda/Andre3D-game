extends SceneTree
## Starter foundation check only. Adapt this hook to the requested game's
## real objectives, failure and replay; passing it does not complete a game.

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	if packed == null:
		_failures.append("active scene must load")
		_finish()
		return
	var world: Node = packed.instantiate()
	root.add_child(world)
	await process_frame
	_check(world is Node3D, "active world must be Node3D")
	_check(world.get_node_or_null("Camera") is Camera3D, "world must have a Camera3D")
	var player := world.get_node_or_null("Player") as CharacterBody3D
	_check(player != null, "world must have its movement controller")
	if player != null:
		var start: Vector3 = player.position
		Input.action_press("move_right")
		for frame: int in range(12):
			await physics_frame
		Input.action_release("move_right")
		_check(player.position.x > start.x + 0.1, "movement input must move the player")
	world.queue_free()
	await process_frame
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[3d-scaffold] PASS: world, camera and movement; game outcomes still required")
		quit(0)
		return
	for failure: String in _failures:
		push_error("[3d-scaffold] " + failure)
	quit(1)
