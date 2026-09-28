class_name PlayerInput
extends Node
## Reads the player's intentions from InputMap actions. Moves nothing.
##
## Axis convention for move_vector (screen/camera space, not world space):
##   x > 0 = right (move_right),   x < 0 = left (move_left)
##   y > 0 = forward (move_forward), y < 0 = backward (move_backward)
## Length never exceeds 1. Mapping to 3D is the movement task's job.
##
## Look intention (mouse): consume_look() returns the rotation requested
## since the last call, in radians: x > 0 = turn right, y > 0 = look up.
## It is a distance already measured by the mouse, so it must never be
## multiplied by delta time.
##
## Runs while the tree is paused so it can still forward pause requests,
## but every gameplay intention is neutral and no gameplay signal is
## emitted while paused or after focus loss.

signal interact_pressed
signal drop_pressed
signal pause_requested

## Radians of rotation per pixel of mouse motion.
@export_range(0.0005, 0.02, 0.0005) var look_sensitivity := 0.003
@export var invert_look_y := false

var move_vector := Vector2.ZERO
var sprint_held := false

var _look_accum := Vector2.ZERO


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Refresh before PlayerMotor (-1) reads the intentions in each physics
	# tick, so ticks that run before _process in a frame are not one frame
	# late (measured: 1-3 ticks of drift at low frame rates otherwise).
	process_physics_priority = -2


func _process(_delta: float) -> void:
	_refresh()


func _physics_process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _gameplay_blocked():
		_clear()
		return
	move_vector = Input.get_vector(&"move_left", &"move_right", &"move_backward", &"move_forward")
	sprint_held = Input.is_action_pressed(&"sprint")


## Returns the look rotation accumulated since the last call and resets it.
func consume_look() -> Vector2:
	var look := _look_accum
	_look_accum = Vector2.ZERO
	return look


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not _gameplay_blocked():
			# screen_relative ignores viewport stretch: same feel at any resolution.
			var rel: Vector2 = event.screen_relative
			_look_accum.x += rel.x * look_sensitivity
			_look_accum.y += (rel.y if invert_look_y else -rel.y) * look_sensitivity
		return
	# is_action_pressed() ignores key-repeat echoes by default.
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		pause_requested.emit()
		return
	if _gameplay_blocked():
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		interact_pressed.emit()
	elif event.is_action_pressed(&"drop"):
		get_viewport().set_input_as_handled()
		drop_pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear()


func _gameplay_blocked() -> bool:
	return get_tree().paused


func _clear() -> void:
	move_vector = Vector2.ZERO
	sprint_held = false
	_look_accum = Vector2.ZERO
