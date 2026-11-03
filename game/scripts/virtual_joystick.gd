class_name AndreVirtualJoystick
extends Control

signal changed(value: Vector2)

@export var radius := 82.0
@export var knob_radius := 30.0
@export_range(0.0, 0.35, 0.01) var deadzone := 0.12
var value := Vector2.ZERO
var _pointer_id := -1
var _center := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center = size * 0.5
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_center = size * 0.5
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		reset_touch()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		reset_touch()

# Capture the finger at the viewport level. _gui_input can stop receiving a
# drag as soon as the finger leaves this Control, which used to make the pad
# stop responding or remain held on some Android devices.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_id == -1 and get_global_rect().has_point(event.position):
				_pointer_id = event.index
				_update_from_position(_screen_to_local(event.position))
				get_viewport().set_input_as_handled()
		elif event.index == _pointer_id:
			_pointer_id = -1
			_set_value(Vector2.ZERO)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _pointer_id:
		_update_from_position(_screen_to_local(event.position))
		get_viewport().set_input_as_handled()

# Keep GUI-event support for embedded/older Godot input paths. The viewport
# capture above is authoritative once a finger is attached to the pad.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _pointer_id == -1:
			_pointer_id = event.index
			_update_from_position(_screen_to_local(event.position))
			accept_event()
		elif not event.pressed and event.index == _pointer_id:
			_pointer_id = -1
			_set_value(Vector2.ZERO)
			accept_event()
	elif event is InputEventScreenDrag and event.index == _pointer_id:
		_update_from_position(_screen_to_local(event.position))
		accept_event()

func _screen_to_local(screen_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_position

func _update_from_position(position: Vector2) -> void:
	var offset := position - _center
	var raw_value := offset.limit_length(radius) / radius
	var strength := raw_value.length()
	if strength <= deadzone:
		_set_value(Vector2.ZERO)
		return
	# Remove drift near the center while preserving the full range at the edge.
	var corrected_strength := clampf((strength - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	_set_value(raw_value.normalized() * corrected_strength)

func _set_value(next_value: Vector2) -> void:
	value = next_value
	changed.emit(value)
	queue_redraw()

func reset_touch() -> void:
	_pointer_id = -1
	_set_value(Vector2.ZERO)

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius + 5.0, Color(0.03, 0.05, 0.08, 0.26))
	draw_circle(center, radius, Color(0.08, 0.12, 0.17, 0.58))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.56, 0.78, 0.84, 0.62), 2.0, true)
	draw_circle(center + value * radius * 0.78, knob_radius, Color(0.69, 0.88, 0.88, 0.92))
	draw_circle(center + value * radius * 0.78, knob_radius - 5.0, Color(0.15, 0.27, 0.31, 0.96))
