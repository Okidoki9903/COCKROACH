class_name PlayerInput
extends Node
## Reads the player's intentions from InputMap actions. Moves nothing.
##
## Axis convention for move_vector (screen/camera space, not world space):
##   x > 0 = right (move_right),   x < 0 = left (move_left)
##   y > 0 = forward (move_forward), y < 0 = backward (move_backward)
## Length never exceeds 1. Mapping to 3D is the movement task's job.
##
## Runs while the tree is paused so it can still forward pause requests,
## but every gameplay intention is neutral and no gameplay signal is
## emitted while paused or after focus loss.

signal interact_pressed
signal drop_pressed
signal pause_requested

var move_vector := Vector2.ZERO
var sprint_held := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _gameplay_blocked():
		_clear()
		return
	move_vector = Input.get_vector(&"move_left", &"move_right", &"move_backward", &"move_forward")
	sprint_held = Input.is_action_pressed(&"sprint")


func _unhandled_input(event: InputEvent) -> void:
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
