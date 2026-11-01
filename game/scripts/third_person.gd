extends CharacterBody3D

const MOVE_SPEED := 4.4
const RUN_MULTIPLIER := 1.55
const FOLLOW_RUN_DISTANCE := 6.0
const FOLLOW_WALK_DISTANCE := 4.5
const ACCELERATION := 18.0
const DECELERATION := 22.0
const AIR_DRAG := 0.55
const GRAVITY := 18.0
const CAMERA_DISTANCE := 5.4
const CAMERA_TARGET_HEIGHT := 0.92
const CAMERA_HEIGHT := 1.75
const MODEL_YAW_OFFSET := 0.0
const WALK_ANIMATION := "WALK_civi"
const RUN_ANIMATION := "run_civi"
const CROUCH_ANIMATION := "Player_Sneak"
const JUMP_ANIMATION := "JUMP_launch"
const IDLE_ANIMATION := "IDLE_stance"
const PUNCH_ANIMATION := "FightA_1"
const COMBO_ANIMATIONS := ["FightA_1", "FightA_2", "FightA_3"]
const HIT_REACTION_ANIMATIONS := ["HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3"]
const MELEE_REACH := 1.65
const COMBO_QUEUE_FROM := 0.28
const COMBO_GRACE := 0.22
const JUMP_VELOCITY := 7.0
const JUMP_FORWARD_IMPULSE := 3.0
const JUMP_BUFFER_SECONDS := 0.14
const COYOTE_SECONDS := 0.12
const ANALOG_DEADZONE := 0.05
const MIN_ANALOG_SPEED := 0.18
const NPC_SIMULATION_DISTANCE := 90.0
const VEHICLE_SIMULATION_DISTANCE := 120.0
const DISTANCE_LOD_INTERVAL := 0.5

@onready var andre_visual: Node3D = $AndreVisual
@onready var dg_visual: Node3D = $DGVisual
var visual: Node3D
@onready var camera: Camera3D = $Camera3D
@onready var joystick: AndreVirtualJoystick = $"../HUD/Root/TouchJoystick"
@onready var movement_label: Label = $"../HUD/Root/MovementLabel"
@onready var coordinates_label: Label = $"../HUD/Root/CoordinatesLabel"
@onready var run_button: Button = $"../HUD/Root/RunButton"
@onready var crouch_button: Button = $"../HUD/Root/CrouchButton"
@onready var jump_button: Button = $"../HUD/Root/JumpButton"
@onready var action_button: Button = $"../HUD/Root/ActionButton"
@onready var switch_button: Button = $"../HUD/Root/SwitchButton"
@onready var follow_button: Button = $"../HUD/Root/FollowButton"
@onready var gorece: GoreceNpc = $"../GoreceNPC"

var _joystick_value := Vector2.ZERO
var _camera_yaw := 0.0
var _camera_pitch := 0.16
var _rotating_mouse := false
var _camera_touch_id := -1
var _last_camera_touch := Vector2.ZERO
var _running := false
var _crouching := false
var _jump_requested := false
var _jumping := false
var _spawn_grounded := false
var _spawn_wait_elapsed := 0.0
const SPAWN_MAP_WAIT_SECONDS := 3.0
var _jump_buffer_remaining := 0.0
var _coyote_remaining := 0.0
var _animation_player: AnimationPlayer
var _neck_skeleton: Skeleton3D
var _neck_bone := -1
var _neck_look_angle := 0.0
var _was_walking := false
var _playing_animation := ""
var _action_busy := false
var _combo_index := 0
var _combo_queued := false
var _combo_holding := false
var _combo_clip_length := 0.0
var _combo_elapsed := 0.0
var _combo_tween: Tween
var _combo_strike_resolved := false
var _active_character := 0
var _follow_enabled := false
var _auto_mount_hilux_armed := false
var _follow_bike_target: Node3D
var _follow_vehicle: Node3D
var _online_mode := false
var _distance_lod_elapsed := DISTANCE_LOD_INTERVAL

func _ready() -> void:
	visual = andre_visual
	visible = true
	andre_visual.visible = true
	dg_visual.visible = false
	joystick.changed.connect(_on_joystick_changed)
	run_button.button_down.connect(_on_run_button_down)
	run_button.button_up.connect(_on_run_button_up)
	crouch_button.toggled.connect(_on_crouch_toggled)
	jump_button.button_down.connect(_on_jump_button_down)
	action_button.button_down.connect(_on_action_button_down)
	action_button.button_up.connect(_on_action_button_up)
	switch_button.pressed.connect(_toggle_character)
	follow_button.pressed.connect(_toggle_follow)
	camera.current = true
	camera.add_to_group("graphics_camera")
	GraphicsSettings.apply()
	_animation_player = _find_animation_player(visual)
	_apply_black_shoes()
	_apply_orange_clothes()
	_apply_dark_skin()
	_apply_black_beard()
	_apply_black_hair()
	_create_blue_eyes()
	_setup_neck_look()
	if _animation_player != null:
		for animation_name in [WALK_ANIMATION, RUN_ANIMATION, CROUCH_ANIMATION, IDLE_ANIMATION]:
			if _animation_player.has_animation(animation_name):
				_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
		if _animation_player.has_animation(JUMP_ANIMATION):
			_animation_player.get_animation(JUMP_ANIMATION).loop_mode = Animation.LOOP_NONE
		for punch_name in COMBO_ANIMATIONS:
			if _animation_player.has_animation(punch_name):
				_animation_player.get_animation(punch_name).loop_mode = Animation.LOOP_NONE
	movement_label.text = "WASD / setas para mover  •  arraste à direita para girar a câmera"
	gorece.set_player_controlled(false)
	_apply_session_settings()
	if _active_character == 1:
		_update_camera_for(gorece.global_position)
	else:
		_update_camera()
	call_deferred("_apply_remote_spawn")

func restore_vehicle_exit_pose(heading: float) -> void:
	global_rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	if visual != null:
		visual.global_rotation = Vector3(0.0, heading, 0.0)
	_camera_yaw = heading
	_playing_animation = ""
	if _animation_player != null:
		_animation_player.stop()
		_play_animation(IDLE_ANIMATION)

func _apply_remote_spawn() -> void:
	var json_text := RemoteUpdater.read_remote_text("config/spawn.json")
	if not json_text.is_empty():
		_apply_remote_spawn_payload(json_text)
	await RemoteUpdater.wait_until_ready(12.0)
	json_text = RemoteUpdater.read_remote_text("config/spawn.json")
	if json_text.is_empty():
		return
	_apply_remote_spawn_payload(json_text)

func _apply_remote_spawn_payload(json_text: String) -> void:
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		push_warning("Spawn remoto inválido; usando posições padrão do APK.")
		return
	var config := parsed as Dictionary
	if str(config.get("map", "")) != "liberty_city":
		push_warning("Spawn remoto ignorado: mapa incompatível.")
		return
	var revision_parts: PackedStringArray = str(config.get("spawn_revision", "")).split("-")
	var spawn_revision: int = revision_parts[revision_parts.size() - 1].to_int() if not revision_parts.is_empty() else 0
	if spawn_revision < 3:
		push_warning("Spawn remoto antigo ignorado; usando os spawns corrigidos do APK.")
		return
	var player_data: Variant = config.get("player", {})
	if player_data is Dictionary:
		_apply_spawn_transform(self, player_data as Dictionary)
	var gorece_data: Variant = config.get("gorece", {})
	if gorece_data is Dictionary:
		_apply_spawn_transform(gorece, gorece_data as Dictionary)
	var vehicles: Variant = config.get("vehicles", {})
	if vehicles is Dictionary:
		for vehicle_id: String in (vehicles as Dictionary).keys():
			var vehicle_data: Variant = (vehicles as Dictionary)[vehicle_id]
			if not vehicle_data is Dictionary:
				continue
			var vehicle := _find_spawn_vehicle(vehicle_id)
			if vehicle != null:
				_apply_spawn_transform(vehicle, vehicle_data as Dictionary)
	var map_streamer := get_node_or_null("../MapStreamer")
	if map_streamer != null and map_streamer.has_method("snap_body_to_map"):
		map_streamer.call("snap_body_to_map", self)
		map_streamer.call("snap_body_to_map", gorece)
	if _active_character == 1:
		_update_camera_for(gorece.global_position)
	else:
		_update_camera()

func _apply_spawn_transform(node: Node3D, data: Dictionary) -> bool:
	var raw_position: Variant = data.get("position", [])
	if not raw_position is Array or raw_position.size() != 3:
		return false
	var position_values: Array = raw_position
	var x := float(position_values[0])
	var y := float(position_values[1])
	var z := float(position_values[2])
	if not is_finite(x) or not is_finite(y) or not is_finite(z):
		return false
	if absf(x) > 5000.0 or absf(y) > 5000.0 or absf(z) > 5000.0:
		return false
	node.global_position = Vector3(x, y, z)
	var heading := deg_to_rad(clampf(float(data.get("rotation_y", 0.0)), -3600.0, 3600.0))
	# O Player (CharacterBody3D) deve permanecer sem rotação no nó raiz.
	# A orientação de gameplay fica só no visual — senão o personagem anda
	# num sentido e o modelo aponta para o outro.
	if node == self:
		node.rotation = Vector3.ZERO
		if visual != null:
			visual.rotation = Vector3(0.0, heading, 0.0)
		_camera_yaw = heading
	else:
		node.rotation.y = heading
	return true

func _find_spawn_vehicle(vehicle_id: String) -> Node3D:
	for child: Node in get_parent().get_children():
		if child is Node3D and str(child.get("network_vehicle_id")) == vehicle_id:
			return child as Node3D
	return null
