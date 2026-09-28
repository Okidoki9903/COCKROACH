extends Node
## Renders reference captures of camera_test: one per test position, a few
## pitch extremes, and a short yaw sweep beside the wall. Needs a real
## rendering driver (not --headless).
## Run: godot --path . res://scenes/tests/camera_capture.tscn -- --out=<dir>

const CAMERA_TEST := preload("res://scenes/tests/camera_test.tscn")

var _out := "user://camera_captures"


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var scene := CAMERA_TEST.instantiate()
	add_child(scene)
	var rig: CameraRig = scene.get_node("CameraRig")
	var panel = scene.get_node("DebugLayer/CameraDebugPanel")
	# No mouse capture during captures.
	scene.get_node("PauseController").capture_mouse = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(5)

	for marker in scene.get_node("TestPositions").get_children():
		panel.go_to(marker.name)
		await _settle()
		await _shot("pos_%s" % marker.name, rig)

	panel.go_to("SousMeuble")
	rig.pitch = deg_to_rad(rig.pitch_min_deg)
	await _settle()
	await _shot("pitch_min_SousMeuble", rig)
	panel.go_to("Ouvert")
	rig.pitch = deg_to_rad(rig.pitch_max_deg)
	await _settle()
	await _shot("pitch_max_Ouvert", rig)
	rig.pitch = deg_to_rad(rig.pitch_min_deg)
	await _settle()
	await _shot("pitch_min_Ouvert", rig)

	# Yaw sweep beside the wall: camera swings into the wall and back out.
	panel.go_to("Mur")
	rig.pitch = deg_to_rad(-20.0)
	await _settle()
	for i in 24:
		rig.yaw += deg_to_rad(7.5)
		await _frames(1)
		await _shot("sweep_%02d" % i, rig)
	get_tree().quit(0)


func _settle() -> void:
	await _frames(40)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String, rig: CameraRig) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, shot_name]
	get_viewport().get_texture().get_image().save_png(path)
	print("%s  yaw %.1f pitch %.1f dist %.4f free %.4f cam %s" % [
		shot_name, rad_to_deg(rig.yaw), rad_to_deg(rig.pitch),
		rig.current_distance, rig.get_free_distance(), rig.camera.global_position])
