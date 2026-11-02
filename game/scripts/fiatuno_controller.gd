extends Node3D
class_name FiatUnoController

## Fiat Uno + Escada (sem braços)
## network_vehicle_id: fiatuno_01
## Servidor já reconhece o ID. Coloque o GLB como filho visual e anexe este script.

const MOUNT_INTERACTION_DISTANCE := 3.0
const MAX_SPEED := 12.5
const REVERSE_SPEED := 3.8
const ACCELERATION := 6.5
const BRAKING := 18.0
const DRAG := 2.5
const WHEELBASE := 2.35
const MAX_STEERING_ANGLE := 0.55
const STEER_RESPONSE := 5.0
const BODY_ROLL := 0.04
const WHEEL_RADIUS := 0.32

# Coordenadas locais do carro (ajuste fino depois de testar o modelo)
const SEAT_HIP := Vector3(-0.35, 0.12, -0.08)
const DOOR_THRESHOLD_HIP := Vector3(-0.90, 0.20, -0.18)
const DOOR_APPROACH := Vector3(-1.35, 0.0, -0.25)
const MIN_SIDE_X := -0.95
const STANDING_HIP_HEIGHT := 0.98
const WALK_TO_DOOR_SPEED := 3.0
const SLIDE_IN_SECONDS := 0.85
const DOOR_SECONDS := 0.40
const DOOR_OPEN_ANGLE := deg_to_rad(-55.0)

const HIDDEN_WHILE_DRIVING := [
	"TouchJoystick", "GasButton", "BrakeButton",
	"SteerLeftButton", "SteerRightButton",
	"RunButton", "CrouchButton", "JumpButton", "ActionButton", "SwitchButton"
]

@export var vehicle_display_name := "FIAT UNO + ESCADA"
@export var network_vehicle_id := "fiatuno_01"
@export var drive_button_path: NodePath = NodePath("../HUD/Root/RideButton")

@onready var _gorece: GoreceNpc = get_node_or_null("../GoreceNPC") as GoreceNpc
@onready var _andre: CharacterBody3D = get_node_or_null("../Player") as CharacterBody3D
@onready var _ride_button: Button = get_node_or_null(drive_button_path) as Button
@onready var _hud: Control = get_node_or_null("../HUD/Root") as Control
@onready var _visual: Node3D = get_node_or_null("FiatUnoVisual") as Node3D

var _door: Node3D
var _door_base_rotation := Vector3.ZERO
var _speed := 0.0
var _riding := false
var _network_mount_pending := false
var _mounting := false
var _dismounting := false
var _steering := 0.0
var _autopilot_input := Vector2.ZERO
var _autopilot_active := false
var _visual_base_rotation := Vector3.ZERO
var _wheel_lf: Node3D
var _wheel_rf: Node3D
var _wheel_lb: Node3D
var _wheel_rb: Node3D
var _wheel_base_rotations: Dictionary = {}
var _wheel_spin := 0.0
var _engine_audio: AudioStreamPlayer3D
var _network_audio_mode := "off"
var _ground_y := 0.0
var _wheel_ground_offset := 0.0
const DRIVE_BUTTON_SIDE := 120.0

func _ready() -> void:
	var root := _visual if _visual != null else self
	_door = _find_part(root, "door_lf_ok")
	if _door == null:
		_door = _find_part(root, "door_lf")
	if _door != null:
		_door_base_rotation = _door.rotation
	if _visual != null:
		_visual_base_rotation = _visual.rotation

	_wheel_lf = _find_part(root, "wheel_lf")
	_wheel_rf = _find_part(root, "wheel_rf")
	# O GLB exportado às vezes nomeia a roda dianteira direita só como "wheel"
	if _wheel_rf == null:
		_wheel_rf = _find_part(root, "wheel")
	_wheel_lb = _find_part(root, "wheel_lb")
	_wheel_rb = _find_part(root, "wheel_rb")

	for wheel in [_wheel_lf, _wheel_rf, _wheel_lb, _wheel_rb]:
		if wheel != null:
			_wheel_base_rotations[wheel] = wheel.rotation

	var lowest_wheel_bottom := INF
	for wheel in [_wheel_lf, _wheel_rf, _wheel_lb, _wheel_rb]:
		if wheel != null:
			lowest_wheel_bottom = minf(lowest_wheel_bottom, to_local(wheel.global_position).y - WHEEL_RADIUS)
	if lowest_wheel_bottom != INF:
		_wheel_ground_offset = lowest_wheel_bottom
	_ground_y = global_position.y + _wheel_ground_offset

	call_deferred("_setup_engine_audio")
	_ensure_drive_buttons()
	_set_drive_buttons_visible(false)
	_update_ride_button()

func _find_part(root: Node, part_name: String) -> Node3D:
	if root == null:
		return null
	if root.name == part_name and root is Node3D:
		return root as Node3D
	for child in root.get_children():
		var found := _find_part(child, part_name)
		if found != null:
			return found
	return null

func _load_engine_stream() -> AudioStream:
	# Áudio próprio do Fiat Uno (motor ligado / marcha lenta).
	var stream := load("res://assets/audio/fiat_uno_motor_ligado.wav") as AudioStreamWAV
	if stream == null:
		# Fallback temporário se o arquivo ainda não estiver no projeto.
		stream = load("res://assets/audio/hilux_srx_2017_parada_simulacao.wav") as AudioStreamWAV
	if stream != null:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream

func _setup_engine_audio() -> void:
	var stream := _load_engine_stream()
	if stream == null:
		push_warning("FiatUno: áudio de motor não encontrado (fiat_uno_motor_ligado.wav)")
		return
	_engine_audio = AudioStreamPlayer3D.new()
	_engine_audio.name = "FiatUnoEngineAudio"
	_engine_audio.stream = stream
	_engine_audio.volume_db = -4.0
	_engine_audio.unit_size = 6.5
	_engine_audio.max_distance = 28.0
	add_child(_engine_audio)

func _apply_engine_audio_mode(mode: String) -> void:
	if _engine_audio == null:
		return
	if mode == "off":
		_engine_audio.stop()
	elif not _engine_audio.playing:
		_engine_audio.play()

func get_network_audio_mode() -> String:
	if not _riding or _mounting or _dismounting:
		return "off"
	var throttle := Input.get_axis("move_down", "move_up")
	if _autopilot_active:
		throttle = _autopilot_input.x
	elif _hud != null:
		if bool(_hud.get_meta("touch_hilux_gas", false)):
			throttle = 1.0
		elif bool(_hud.get_meta("touch_hilux_brake", false)):
			throttle = -1.0
	if throttle > 0.01:
		return "accel"
	if absf(_speed) > 0.12:
		return "decel"
	return "idle"

func set_network_audio_mode(mode: String) -> void:
	_network_audio_mode = mode if mode in ["off", "idle", "accel", "decel"] else "off"
	if not _riding:
		_apply_engine_audio_mode(_network_audio_mode)

func _update_engine_audio() -> void:
	if not _riding and _network_audio_mode != "off":
		_apply_engine_audio_mode(_network_audio_mode)
	elif _riding:
		_network_audio_mode = get_network_audio_mode()
		_apply_engine_audio_mode(_network_audio_mode)
	else:
		_network_audio_mode = "off"
		_apply_engine_audio_mode("off")

func _apply_map_ground_support() -> void:
	var streamer := get_node_or_null("../MapStreamer")
	if streamer == null or not streamer.has_method("sample_ground_height"):
		return
	var exclude: Array[RID] = []
	var collision_body := get_node_or_null("CollisionBody") as StaticBody3D
	if collision_body != null:
		exclude.append(collision_body.get_rid())
	var sample: Dictionary = streamer.call("sample_ground_height", global_position, _ground_y, exclude)
	if sample.is_empty():
		return
	var surface: Vector3 = sample["position"]
	_ground_y = surface.y
	global_position.y = _ground_y - _wheel_ground_offset

func _process(_delta: float) -> void:
	_update_engine_audio()
	_update_ride_button()
	_update_vehicle_panel()
	if _riding and not _mounting and not _dismounting:
		_place_driver()

func _physics_process(delta: float) -> void:
	_apply_map_ground_support()
	if not _riding or _mounting or _dismounting:
		return
	var throttle := Input.get_axis("move_down", "move_up")
	var steer := Input.get_axis("move_left", "move_right")
	if _hud != null:
		var touch_steer_left := bool(_hud.get_meta("touch_hilux_steer_left", false))
		var touch_steer_right := bool(_hud.get_meta("touch_hilux_steer_right", false))
		if touch_steer_left or touch_steer_right:
			steer = float(touch_steer_right) - float(touch_steer_left)
		if bool(_hud.get_meta("touch_hilux_gas", false)):
			throttle = float(_hud.get_meta("touch_hilux_gas_power", 1.0))
		elif bool(_hud.get_meta("touch_hilux_brake", false)):
			throttle = -1.0
	if _autopilot_active:
		throttle = _autopilot_input.x
		steer = _autopilot_input.y
	if throttle > 0.01:
		_speed = move_toward(_speed, MAX_SPEED * throttle, ACCELERATION * delta)
	elif throttle < -0.01:
		if _speed > 0.05:
			_speed = move_toward(_speed, 0.0, BRAKING * delta)
		else:
			_speed = move_toward(_speed, -REVERSE_SPEED, ACCELERATION * 0.45 * delta)
	else:
		_speed = move_toward(_speed, 0.0, DRAG * delta)
	_steering = move_toward(_steering, steer, STEER_RESPONSE * delta)
	if absf(_speed) > 0.05:
		var speed_ratio := clampf(absf(_speed) / MAX_SPEED, 0.0, 1.0)
		var steering_angle := _steering * MAX_STEERING_ANGLE * lerpf(1.0, 0.58, speed_ratio)
		var yaw_rate := tan(steering_angle) * _speed / WHEELBASE
		rotation.y -= yaw_rate * delta
	var travel := -global_transform.basis.z * _speed * delta
	var movement_result := _resolve_vehicle_collision(travel)
	if bool(movement_result.get("blocked", false)):
		_speed = move_toward(_speed, 0.0, BRAKING * delta * 0.35)
	else:
		global_position += movement_result.get("travel", travel)
	_apply_map_ground_support()
	_wheel_spin = wrapf(_wheel_spin - (_speed / WHEEL_RADIUS) * delta, -TAU, TAU)
	_update_wheels()
	if _visual != null:
		var target_roll := -_steering * BODY_ROLL * clampf(absf(_speed) / 5.0, 0.0, 1.0)
		_visual.rotation = _visual_base_rotation
		_visual.rotation.z += target_roll
	_place_driver()

func _resolve_vehicle_collision(travel: Vector3) -> Dictionary:
	var collision_body := get_node_or_null("CollisionBody") as StaticBody3D
	var collision_shape := get_node_or_null("CollisionBody/Collision") as CollisionShape3D
	if collision_body == null or collision_shape == null or collision_shape.shape == null:
		return {"blocked": false, "travel": travel}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	var predicted := global_transform
	predicted.origin += travel
	query.transform = predicted * collision_shape.transform
	query.collision_mask = 1
	query.exclude = [collision_body.get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 16)
	if hits.is_empty():
		return {"blocked": false, "travel": travel}
	var push_direction := Vector3(travel.x, 0.0, travel.z)
	if push_direction.length_squared() < 0.0001:
		return {"blocked": false, "travel": travel}
	push_direction = push_direction.normalized()
	var pushed_any := false
	var push_amount := clampf(travel.length() * 5.0, 0.04, 0.42)
	for hit in hits:
		var collider := hit.get("collider") as Node3D
		if collider == null or collider == collision_body:
			continue
		var target := _collision_target(collider)
		if target == null or target == self or target.name == "Ground":
			continue
		if target is StaticBody3D and target.get_parent() == get_tree().current_scene:
			continue
		if target is CharacterBody3D or target.has_node("CollisionBody"):
			target.global_position += push_direction * push_amount
			if target is CharacterBody3D:
				target.velocity.x = push_direction.x * maxf(absf(_speed) * 0.65, 1.0)
				target.velocity.z = push_direction.z * maxf(absf(_speed) * 0.65, 1.0)
			pushed_any = true
	return {"blocked": not pushed_any, "travel": travel}

func _collision_target(collider: Node3D) -> Node3D:
	if collider is StaticBody3D and collider.get_parent() is Node3D:
		return collider.get_parent() as Node3D
	return collider

func _update_wheels() -> void:
	var front_angle := -_steering * MAX_STEERING_ANGLE * 0.82
	for wheel in [_wheel_lf, _wheel_rf]:
		_apply_wheel_transform(wheel, front_angle)
	for wheel in [_wheel_lb, _wheel_rb]:
		_apply_wheel_transform(wheel, 0.0)

func update_remote_wheel_spin(world_velocity: Vector3, delta: float) -> void:
	if delta <= 0.0:
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var planar_velocity := Vector3(world_velocity.x, 0.0, world_velocity.z)
	var longitudinal_speed := planar_velocity.dot(forward)
	_wheel_spin = wrapf(_wheel_spin - longitudinal_speed / WHEEL_RADIUS * delta, -TAU, TAU)
	_update_wheels()

func _apply_wheel_transform(wheel: Node3D, steering_angle: float) -> void:
	if wheel == null or not _wheel_base_rotations.has(wheel):
		return
	var rot := _wheel_base_rotations[wheel] as Vector3
	rot.y += steering_angle
	rot.x += _wheel_spin
	wheel.rotation = rot

func toggle_riding_from_universal() -> void:
	if _riding:
		if not _mounting and not _dismounting:
			_start_dismount()
	elif is_near_player():
		_start_mount()

func is_riding() -> bool:
	return _riding

func set_autopilot_controls(input: Vector2, enabled := true) -> void:
	_autopilot_active = enabled and _riding
	_autopilot_input = Vector2(clampf(input.x, -1.0, 1.0), clampf(input.y, -1.0, 1.0)) if _autopilot_active else Vector2.ZERO

func get_autopilot_speed() -> float:
	return _speed

func get_autopilot_speed_limit() -> float:
	return MAX_SPEED

func is_near_player() -> bool:
	if _gorece == null or _riding:
		return false
	if _andre != null and _andre.has_method("is_gorece_active") and not _andre.is_gorece_active():
		return false
	var local_position := global_transform.affine_inverse() * _gorece.global_position
	if local_position.x > MIN_SIDE_X:
		return false
	var approach := _approach_point()
	var distance := Vector2(approach.x - _gorece.global_position.x, approach.z - _gorece.global_position.z).length()
	return distance <= MOUNT_INTERACTION_DISTANCE

func _approach_point() -> Vector3:
	var point := global_transform * DOOR_APPROACH
	point.y = _ground_y
	return point

func _place_driver() -> void:
	var driver: Node3D = null
	if _andre != null and _andre.has_method("is_gorece_active") and _andre.is_gorece_active() and _gorece != null:
		driver = _gorece
	elif _andre != null:
		driver = _andre
	if driver == null:
		return
	var seat_world := global_transform * SEAT_HIP
	driver.global_position = seat_world - Vector3.UP * STANDING_HIP_HEIGHT * 0.15
	driver.rotation.y = rotation.y

func _start_mount(allow_follow_mount := false) -> void:
	if _gorece == null and _andre == null:
		return
	if not allow_follow_mount and not is_near_player():
		return
	if not allow_follow_mount:
		for sibling in get_parent().get_children():
			if sibling != self and sibling.has_method("is_riding") and sibling.is_riding():
				return
		var multiplayer_client := get_node_or_null("../OnlineMultiplayer")
		if multiplayer_client != null and bool(multiplayer_client.get("enabled")):
			if _network_mount_pending:
				return
			_network_mount_pending = true
			var granted: bool = await multiplayer_client.request_vehicle_claim(network_vehicle_id)
			_network_mount_pending = false
			if not granted or not is_near_player():
				if granted:
					multiplayer_client.release_vehicle(network_vehicle_id)
				return
	_riding = true
	_mounting = true
	_speed = 0.0
	_set_driving_hud(true)
	if _door != null:
		var t := create_tween()
		t.tween_property(_door, "rotation:y", _door_base_rotation.y + DOOR_OPEN_ANGLE, DOOR_SECONDS)
		await t.finished
	_place_driver()
	if _door != null:
		var t2 := create_tween()
		t2.tween_property(_door, "rotation:y", _door_base_rotation.y, DOOR_SECONDS)
		await t2.finished
	_mounting = false
	_set_drive_buttons_visible(true)

func start_ai_mount_for_follow() -> void:
	if _riding or _mounting or _dismounting:
		return
	_start_mount(true)

func _start_dismount() -> void:
	_dismounting = true
	_speed = 0.0
	_set_drive_buttons_visible(false)
	if _door != null:
		var t := create_tween()
		t.tween_property(_door, "rotation:y", _door_base_rotation.y + DOOR_OPEN_ANGLE, DOOR_SECONDS)
		await t.finished
	var exit_pos := _approach_point()
	if _gorece != null:
		_gorece.global_position = exit_pos + Vector3.UP * 0.1
	elif _andre != null:
		_andre.global_position = exit_pos + Vector3.UP * 0.1
	if _door != null:
		var t2 := create_tween()
		t2.tween_property(_door, "rotation:y", _door_base_rotation.y, DOOR_SECONDS)
		await t2.finished
	_riding = false
	_dismounting = false
	_set_driving_hud(false)
	var multiplayer_client := get_node_or_null("../OnlineMultiplayer")
	if multiplayer_client != null and multiplayer_client.has_method("release_vehicle"):
		multiplayer_client.release_vehicle(network_vehicle_id)

func _set_driving_hud(driving: bool) -> void:
	if _hud == null:
		return
	for child_name in HIDDEN_WHILE_DRIVING:
		var n := _hud.get_node_or_null(child_name)
		if n != null:
			n.visible = not driving

func _ensure_drive_buttons() -> void:
	pass

func _set_drive_buttons_visible(visible: bool) -> void:
	if _hud == null:
		return
	for child_name in ["GasButton", "BrakeButton", "SteerLeftButton", "SteerRightButton"]:
		var n := _hud.get_node_or_null(child_name)
		if n != null:
			n.visible = visible

func _update_ride_button() -> void:
	if _ride_button == null:
		return
	if _riding:
		_ride_button.text = "DESCER"
		_ride_button.visible = true
	elif is_near_player():
		_ride_button.text = "DIRIGIR " + vehicle_display_name
		_ride_button.visible = true
	else:
		_ride_button.visible = false

func _update_vehicle_panel() -> void:
	var panel := get_node_or_null("../HUD/Root/VehiclePanel") as Label
	if panel == null:
		return
	if _riding:
		panel.text = "%s  %.0f km/h" % [vehicle_display_name, absf(_speed) * 3.6]
		panel.visible = true
	else:
		panel.visible = false
