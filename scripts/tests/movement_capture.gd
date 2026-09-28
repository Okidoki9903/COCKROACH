extends Node
## Renders short sequences of the player moving on movement_test with the
## camera following. Needs a real rendering driver (not --headless).
## Run: godot --fixed-fps 60 --path . res://scenes/tests/movement_capture.tscn -- --out=<dir>

const MOVEMENT_TEST := preload("res://scenes/tests/movement_test.tscn")

## [position, input, sprint, ticks, camera yaw offset (deg), pitch (deg)]
const SEQUENCES := [
	["Depart", Vector2(0, 1), true, 60, 0.0, -20.0],
	["Mur", Vector2(0.7071, 0.7071), true, 60, 0.0, -20.0],
	["Pente", Vector2(0, 1), false, 150, 0.0, -15.0],
	["Passage", Vector2(0, 1), true, 150, 0.0, -20.0],
	["Bord", Vector2(0, 1), true, 100, 0.0, -30.0],
]

var _out := "user://movement_captures"


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var scene := MOVEMENT_TEST.instantiate()
	scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(scene)
	scene.get_node("PauseController").capture_mouse = false
	var player: PlayerMotor = scene.get_node("Player")
	var rig: CameraRig = scene.get_node("CameraRig")
	var panel = scene.get_node("DebugLayer/MovementDebugPanel")
	await _frames(5)
	for seq in SEQUENCES:
		panel.go_to(seq[0])
		rig.yaw += deg_to_rad(seq[4])
		rig.pitch = deg_to_rad(seq[5])
		await _frames(30)
		_press(seq[1], seq[2])
		for i in seq[3]:
			await _frames(1)
			if i % 10 == 0:
				await _shot("%s_%03d" % [seq[0], i], player, rig)
		_press(Vector2.ZERO, false)
	get_tree().quit(0)


func _press(v: Vector2, sprint: bool) -> void:
	for a in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(a)
	if v.x > 0: Input.action_press(&"move_right", v.x)
	if v.y > 0: Input.action_press(&"move_forward", v.y)
	if sprint: Input.action_press(&"sprint")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String, player: PlayerMotor, rig: CameraRig) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
	print("%s pos %s speed %.4f floor %s cam_dist %.4f" % [shot_name, player.global_position, player.horizontal_speed(), player.is_on_floor(), rig.current_distance])
