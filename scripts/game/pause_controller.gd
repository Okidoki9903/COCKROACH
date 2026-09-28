class_name PauseController
extends Node
## Toggles the scene tree pause on request and pauses on focus loss.
## Regaining focus never resumes by itself.

signal paused_changed(paused: bool)

## Actions forced to "released" on focus loss: a key released outside the
## window never sends its release event.
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_backward", &"move_left", &"move_right",
	&"sprint", &"interact", &"drop",
]

@export var player_input: PlayerInput


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if player_input:
		player_input.pause_requested.connect(toggle)


func toggle() -> void:
	set_paused(not get_tree().paused)


func set_paused(value: bool) -> void:
	if get_tree().paused == value:
		return
	get_tree().paused = value
	paused_changed.emit(value)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		for action in GAMEPLAY_ACTIONS:
			Input.action_release(action)
		set_paused(true)
