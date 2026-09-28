class_name PlayerInput
extends Node
## Reads the player's intentions from InputMap actions. Moves nothing.
##
## Axis convention for move_vector (screen/camera space, not world space):
##   x > 0 = right (move_right),   x < 0 = left (move_left)
##   y > 0 = forward (move_forward), y < 0 = backward (move_backward)
## Length never exceeds 1. Mapping to 3D is the movement task's job.
##
## Look intention (mouse or right stick): consume_look() returns the
## rotation requested since the last call, in radians: x > 0 = turn right,
## y > 0 = look up. Mouse motion is a distance already measured, never
## multiplied by delta time. The stick is a speed: it is integrated once
## per physics tick (fixed step), with a squared response for fine aim.
## Movement, sprint, interact, drop, pause and F3 also have gamepad
## bindings in the InputMap (project.godot); nothing else changes.
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
## Right stick at full tilt, radians per second.
@export_range(0.5, 8.0, 0.1) var stick_look_speed := 2.5

var move_vector := Vector2.ZERO
var sprint_held := false
## The last deliberate input came from a gamepad (menus give focus to a
## control and prompts show pad buttons). Keyboard or mouse switch it
## back. Static: shared by the HUD and menus, kept across restarts.
static var using_gamepad := false

var _look_accum := Vector2.ZERO


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Refresh before PlayerMotor (-1) reads the intentions in each physics
	# tick, so ticks that run before _process in a frame are not one frame
	# late (measured: 1-3 ticks of drift at low frame rates otherwise).
	process_physics_priority = -2


func _process(_delta: float) -> void:
	_refresh()


func _physics_process(delta: float) -> void:
	_refresh()
	if not _gameplay_blocked():
		var s := Input.get_vector(&"look_left", &"look_right", &"look_down", &"look_up")
		# Squared response keeps small tilts precise; the direction is kept.
		s *= s.length()
		_look_accum.x += s.x * stick_look_speed * delta
		_look_accum.y += (-s.y if invert_look_y else s.y) * stick_look_speed * delta


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


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_gamepad = false


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
