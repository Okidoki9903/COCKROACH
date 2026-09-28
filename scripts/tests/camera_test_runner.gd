extends Node
## Automated check of CameraRig, look input and mouse capture.
## Feeds simulated mouse and key events through Input.parse_input_event.
## Run: godot --headless --path . res://scenes/tests/camera_test_runner.tscn
## Exit code 0 = all checks passed, 1 = failure, 2 = watchdog timeout.

const CAMERA_TEST := preload("res://scenes/tests/camera_test.tscn")
const WATCHDOG_SECONDS := 60.0
const EPS := 0.0005
const WALL_Z := -0.9
const WALL_X := -0.9
const CABINET_UNDERSIDE := 0.10
const PASSAGE_CEILING := 0.03
const PASSAGE_HALF_WIDTH := 0.025
## Half-diagonal of the near plane (near 1 mm, fov 70, 16:9) plus margin:
## nothing may intersect this sphere around the camera.
const NEAR_CLEARANCE := 0.0015

## Emitted from this node's _process, which runs after every other node's
## _process (highest priority): checks then see what will be rendered.
## SceneTree.process_frame fires *before* _process and would show the new
## rotation with the previous frame's camera distance.
signal frame_done

var _failures := 0
var _checks := 0
var _scene: Node3D
var _rig: CameraRig
var _input: PlayerInput
var _pause: PauseController
var _panel
var _target: Node3D
var _headless := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000


func _process(_delta: float) -> void:
	frame_done.emit()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	_headless = DisplayServer.get_name() == "headless"
	_scene = CAMERA_TEST.instantiate()
	add_child(_scene)
	_rig = _scene.get_node("CameraRig")
	_input = _scene.get_node("PlayerInput")
	_pause = _scene.get_node("PauseController")
	_panel = _scene.get_node("DebugLayer/CameraDebugPanel")
	_target = _scene.get_node("Target")
	await _frames(5)
	await _run()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	_section("rotation direction")
	await _go("Ouvert")
	var yaw0 := _rig.yaw
	await _mouse(Vector2(100, 0))
	_check(is_equal_approx(_rig.yaw, yaw0 - 100 * _input.look_sensitivity), "mouse right: yaw -= 100 px * sensitivity")
	_check(_cam_forward().x > 0.2, "mouse right turns the view right (forward.x %.3f)" % _cam_forward().x)
	var pitch0 := _rig.pitch
	var fy0 := _cam_forward().y
	await _mouse(Vector2(0, -50))
	_check(_rig.pitch > pitch0 and _cam_forward().y > fy0, "mouse up looks up")
	await _mouse(Vector2(0, 50))
	_check(is_equal_approx(_rig.pitch, pitch0), "mouse down returns")

	_section("no delta-time scaling")
	yaw0 = _rig.yaw
	for i in 10:
		_send_motion(Vector2(10, 0))
	await _frames(3)
	var many := yaw0 - _rig.yaw
	yaw0 = _rig.yaw
	await _mouse(Vector2(100, 0))
	var single := yaw0 - _rig.yaw
	_check(is_equal_approx(many, single), "10 x 10 px == 1 x 100 px (%.5f vs %.5f rad)" % [many, single])
	await _frames(20)
	_check(is_equal_approx(_rig.yaw, yaw0 - single), "no drift without motion")

	_section("invert Y")
	_input.invert_look_y = true
	pitch0 = _rig.pitch
	await _mouse(Vector2(0, -50))
	_check(_rig.pitch < pitch0, "inverted: mouse up looks down")
	_input.invert_look_y = false
	await _mouse(Vector2(0, -50))
	_check(is_equal_approx(_rig.pitch, pitch0), "restored")

	_section("vertical limits")
	await _mouse(Vector2(0, 100000))
	_check(is_equal_approx(_rig.pitch, deg_to_rad(_rig.pitch_min_deg)), "clamped at pitch_min (%.1f°)" % rad_to_deg(_rig.pitch))
	_check(_rig.camera.global_basis.y.y > 0.0, "camera not upside down at pitch_min")
	await _mouse(Vector2(0, -100000))
	_check(is_equal_approx(_rig.pitch, deg_to_rad(_rig.pitch_max_deg)), "clamped at pitch_max (%.1f°)" % rad_to_deg(_rig.pitch))
	_check(_rig.camera.global_basis.y.y > 0.0, "camera not upside down at pitch_max")
	_check(_rig.camera.global_position.y > 0.0, "camera above the floor at pitch_max")
	_rig.pitch = deg_to_rad(-20.0)

	_section("positions")
	for pos in ["Ouvert", "Mur", "Coin", "SousMeuble", "PassageEtroit"]:
		await _go(pos)
		_check(_clear_of_scenery(), "%s: near plane clear of scenery" % pos)
		_check(_rig.current_distance > 0.03, "%s: target not overlapped by camera (dist %.3f)" % [pos, _rig.current_distance])
	await _go("Ouvert")
	_check(absf(_rig.current_distance - _rig.desired_distance) < EPS, "Ouvert: full distance")
	await _go("Mur")
	_check(_rig.current_distance < _rig.desired_distance - 0.02, "Mur: camera pulled in (%.3f)" % _rig.current_distance)
	_check(_rig.camera.global_position.z > WALL_Z, "Mur: camera on the room side")
	await _go("Coin")
	var c := _rig.camera.global_position
	_check(c.x > WALL_X and c.z > WALL_Z, "Coin: camera inside both walls %s" % c)
	await _go("SousMeuble")
	_rig.pitch = deg_to_rad(_rig.pitch_min_deg)
	await _frames(40)
	_check(_rig.camera.global_position.y < CABINET_UNDERSIDE, "SousMeuble pitch_min: camera stays under the cabinet (y %.3f)" % _rig.camera.global_position.y)
	_check(_clear_of_scenery(), "SousMeuble pitch_min: near plane clear")
	_rig.pitch = deg_to_rad(-20.0)
	await _go("PassageEtroit")
	c = _rig.camera.global_position
	_check(c.y < PASSAGE_CEILING and absf(c.x - 0.5) < PASSAGE_HALF_WIDTH, "PassageEtroit: camera inside the passage %s" % c)

	_section("sweeps (full turn by mouse at every position, 3 pitches)")
	for pos in ["Mur", "Coin", "SousMeuble", "PassageEtroit"]:
		await _go(pos)
		var bad := 0
		for p in [-60.0, -20.0, 5.0]:
			_rig.pitch = deg_to_rad(p)
			for i in 48:
				_send_motion(Vector2(0.125 * PI / _input.look_sensitivity / 4.0, 0))
				await get_tree().physics_frame
				await _frames(1)
				if not _clear_of_scenery() or _rig.camera.global_position.z < WALL_Z or _rig.camera.global_position.x < WALL_X:
					bad += 1
		_check(bad == 0, "%s: camera never in scenery over 144 steps (%d bad frames)" % [pos, bad])
	_rig.pitch = deg_to_rad(-20.0)

	_section("obstacle appears then disappears")
	await _go("Ouvert")
	var blocker := _add_blocker()
	await get_tree().physics_frame
	await _frames(1)
	_check(_rig.current_distance < 0.06, "moves in on the first frame after the physics step (%.3f)" % _rig.current_distance)
	_check(_clear_of_scenery(), "clear of the new obstacle")
	var before := _rig.current_distance
	blocker.queue_free()
	await get_tree().physics_frame
	await _frames(1)
	var trace: Array[float] = [before]
	var elapsed := 0.0
	while elapsed < 1.5:
		elapsed += await _timed_frame()
		trace.append(_rig.current_distance)
	var monotonic := true
	for i in range(1, trace.size()):
		if trace[i] < trace[i - 1] - 1e-6:
			monotonic = false
	_check(trace[1] < _rig.desired_distance - 0.01, "returns progressively (first frame %.3f)" % trace[1])
	_check(monotonic, "no oscillation: distance never decreases while returning")
	_check(absf(trace[-1] - _rig.desired_distance) < EPS, "back to desired distance within 1.5 s (%.3f)" % trace[-1])

	_section("target body exclusion")
	# At pitch_max the arm goes down and back past the target's body.
	await _go("Ouvert")
	_rig.pitch = deg_to_rad(_rig.pitch_max_deg)
	_rig.collision_mask = 1 | 2
	await _frames(40)
	var with_exclusion := _rig.get_free_distance()
	_rig._arm.clear_excluded_objects()
	await _frames(3)
	var without_exclusion := _rig.get_free_distance()
	_check(without_exclusion < with_exclusion - 0.01, "control: target on the mask blocks the arm without exclusion (%.3f < %.3f)" % [without_exclusion, with_exclusion])
	_rig.target = _target
	await _frames(3)
	_check(is_equal_approx(_rig.get_free_distance(), with_exclusion), "with exclusion the target body is ignored (%.3f)" % _rig.get_free_distance())
	_rig.collision_mask = 1
	_rig.pitch = deg_to_rad(-20.0)
	await _frames(40)

	_section("teleport resets following")
	await _go("Ouvert")
	_panel.go_to("Mur")
	_check(_rig.camera.global_position.distance_to(_target.global_position + Vector3(0, _rig.pivot_height, 0)) < EPS, "right after teleport the camera sits on the new pivot")
	var min_z := 1.0
	for i in 30:
		await frame_done
		min_z = minf(min_z, _rig.camera.global_position.z)
	_check(min_z > WALL_Z, "no frame behind the wall after teleport (min z %.4f)" % min_z)

	_section("pause freezes look, no accumulation on resume")
	await _go("Ouvert")
	await _key(KEY_ESCAPE)
	_check(get_tree().paused, "paused")
	_mouse_mode_check(Input.MOUSE_MODE_VISIBLE, "mouse released on pause")
	var frozen := Vector2(_rig.yaw, _rig.pitch)
	for i in 5:
		await _mouse(Vector2(200, -80))
	_check(Vector2(_rig.yaw, _rig.pitch).is_equal_approx(frozen), "no rotation while paused")
	_panel.go_to("Mur")
	await _frames(40)
	_check(_rig.current_distance < _rig.desired_distance - 0.02 and _clear_of_scenery(), "teleport while paused: obstacle still measured (%.3f)" % _rig.current_distance)
	frozen = Vector2(_rig.yaw, _rig.pitch)
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused, "resumed")
	_mouse_mode_check(Input.MOUSE_MODE_CAPTURED, "mouse captured on resume")
	await _frames(5)
	_check(Vector2(_rig.yaw, _rig.pitch).is_equal_approx(frozen), "no jump on resume")
	await _mouse(Vector2(100, 0))
	_check(is_equal_approx(_rig.yaw, frozen.x - 100 * _input.look_sensitivity), "look works again after resume")

	_section("focus loss")
	_send_motion(Vector2(300, 0))
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(3)
	frozen = Vector2(_rig.yaw, _rig.pitch)
	_check(get_tree().paused, "focus loss pauses")
	_mouse_mode_check(Input.MOUSE_MODE_VISIBLE, "mouse released on focus loss")
	await _mouse(Vector2(200, 0))
	_check(Vector2(_rig.yaw, _rig.pitch).is_equal_approx(frozen), "no rotation after focus loss")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(3)
	_check(get_tree().paused, "focus regain does not resume")
	_mouse_mode_check(Input.MOUSE_MODE_VISIBLE, "mouse stays released on focus regain")
	await _key(KEY_ESCAPE)
	await _frames(5)
	_check(not get_tree().paused and Vector2(_rig.yaw, _rig.pitch).is_equal_approx(frozen), "explicit resume, no accumulated rotation")
	_mouse_mode_check(Input.MOUSE_MODE_CAPTURED, "mouse recaptured after explicit resume")

	_section("target does not move")
	var tp := _target.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(30)
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	_check(_target.global_position.is_equal_approx(tp), "target unchanged while move keys are held")


func _go(pos: String) -> void:
	_panel.go_to(pos)
	await _frames(40)


func _send_motion(rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.screen_relative = rel
	Input.parse_input_event(e)


func _mouse(rel: Vector2, frames := 3) -> void:
	_send_motion(rel)
	await _frames(frames)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = key
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await frame_done


func _timed_frame() -> float:
	var t0 := Time.get_ticks_usec()
	await frame_done
	return (Time.get_ticks_usec() - t0) / 1_000_000.0


func _cam_forward() -> Vector3:
	return -_rig.camera.global_basis.z


func _clear_of_scenery() -> bool:
	var shape := SphereShape3D.new()
	shape.radius = NEAR_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), _rig.camera.global_position)
	return _scene.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _add_blocker() -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.2, 0.02)
	col.shape = box
	body.add_child(col)
	_scene.add_child(body)
	# 4 cm behind the target, across the camera arm.
	body.global_position = _target.global_position + _target.global_basis.z * 0.05 + Vector3(0, 0.05, 0)
	return body


func _mouse_mode_check(expected: Input.MouseMode, label: String) -> void:
	if _headless:
		print("  SKIP ", label, " (headless display server has no mouse mode)")
		return
	_check(Input.mouse_mode == expected, label)


func _section(title: String) -> void:
	print("-- ", title)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
