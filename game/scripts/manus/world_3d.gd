extends Node3D
## Dimension-correct starting geometry, not a completed game. Replace these
## primitives with the requested world, objectives and character/controller.

@export var move_speed: float = 6.0
var player: CharacterBody3D

func _ready() -> void:
	_ensure_movement_actions()
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position.y = -0.2
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(24.0, 0.4, 24.0)
	var floor_visual := MeshInstance3D.new()
	floor_visual.mesh = floor_mesh
	floor_body.add_child(floor_visual)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_mesh.size
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	add_child(floor_body)

	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, 0.8, 0.0)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	var player_visual := MeshInstance3D.new()
	player_visual.mesh = capsule
	var player_material := StandardMaterial3D.new()
	player_material.albedo_color = Color(0.18, 0.62, 0.88)
	player_visual.material_override = player_material
	player.add_child(player_visual)
	var player_shape := CapsuleShape3D.new()
	player_shape.radius = capsule.radius
	player_shape.height = capsule.height
	var player_collision := CollisionShape3D.new()
	player_collision.shape = player_shape
	player.add_child(player_collision)
	add_child(player)

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.4
	light.shadow_enabled = false
	add_child(light)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, 10.0, 12.0)
	camera.current = true
	add_child(camera)
	# look_at requires the camera to be in the scene tree.
	camera.look_at(global_position + Vector3(0.0, 0.5, 0.0))

func _physics_process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.velocity.x = direction.x * move_speed
	player.velocity.z = direction.y * move_speed
	if not player.is_on_floor():
		player.velocity.y -= 9.8 * delta
	player.move_and_slide()
	if player.position.y < -8.0:
		player.position = Vector3(0.0, 0.8, 0.0)
		player.velocity = Vector3.ZERO

func _ensure_movement_actions() -> void:
	var defaults := {"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S}
	for action: String in defaults:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = defaults[action]
		InputMap.action_add_event(action, event)
