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
## Full GTA SA unarmed combo chain from ped.ifp (FightA_1 -> FightA_2 -> FightA_3).
const COMBO_ANIMATIONS := ["FightA_1", "FightA_2", "FightA_3"]
const HIT_REACTION_ANIMATIONS := ["HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3"]
const MELEE_REACH := 1.65
## Fraction of the current clip after which a new press queues the next hit.
const COMBO_QUEUE_FROM := 0.28
## Extra seconds after a clip ends where a late press still starts the next hit.
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
var _active_character := 0 # 0 = Andre, 1 = GORECE, 2 = DG
var _follow_enabled := false
var _auto_mount_hilux_armed := false
var _follow_bike_target: Node3D
var _follow_vehicle: Node3D
var _online_mode := false
var _distance_lod_elapsed := DISTANCE_LOD_INTERVAL

func _ready() -> void:
	visual = andre_visual
	# O avatar local não pode depender do estado de conexão/mapa para ser renderizado.
	visible = true
	andre_visual.visible = true
	dg_visual.visible = false
	joystick.changed.connect(_on_joystick_changed)
	run_button.button_down.connect(_on_run_button_down)
	run_button.button_up.connect(_on_run_button_up)
	crouch_button.toggled.connect(_on_crouch_toggled)
