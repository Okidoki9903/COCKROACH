extends Node
## Targeted locomotion scenarios on movement_test.tscn. Prints measurements
## and checks them against tolerances chosen for a 3 cm body.
## Run (deterministic, one physics step per frame):
##   godot --headless --fixed-fps 60 --path . res://scenes/tests/movement_test_runner.tscn
## Optional user args (after --):
##   --shape=cylinder|capsule|sphere   collision shape under evaluation
##   --render-check=<max_fps>          only measure distance after 90 ticks
## Exit code 0 = all checks passed, 1 = failure, 2 = watchdog timeout.

const MOVEMENT_TEST := preload("res://scenes/tests/movement_test.tscn")
const WATCHDOG_SECONDS := 240.0
const TICK := 1.0 / 60.0
const NEAR_CLEARANCE := 0.0015
const SIDE_WALL_X := 0.58
const BACK_WALL_Z := -0.9

## Emitted from _physics_process after the player and the camera rig.
signal tick_done

var _failures := 0
var _checks := 0
var _scene: Node3D
var _player: PlayerMotor
var _rig: CameraRig
var _input: PlayerInput
var _panel
var _radius := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000


func _physics_process(_delta: float) -> void:
	tick_done.emit()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_scene = MOVEMENT_TEST.instantiate()
	# As in the game: the course pauses, this runner keeps measuring.
	_scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_scene)
	_player = _scene.get_node("Player")
	_rig = _scene.get_node("CameraRig")
	_input = _scene.get_node("PlayerInput")
	_panel = _scene.get_node("DebugLayer/MovementDebugPanel")
	_scene.get_node("PauseController").capture_mouse = false
	if args.has("shape"):
		_set_shape(args["shape"])
	if args.has("margin"):
		_player.safe_margin = float(args["margin"])
	var shape: Shape3D = _player.get_node("Collision").shape
	_radius = shape.radius
	print("shape %s radius %.4f height %.4f safe_margin %.4f" % [shape.get_class(), shape.radius, shape.get("height") if "height" in shape else shape.radius * 2.0, _player.safe_margin])
	await _ticks(5)
	if args.has("render-check"):
		await _render_check(int(args["render-check"]))
		return
	await _run()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	_section("standing still")
	await _go("Depart")
	var p0 := _player.global_position
	var floor_ticks := 0
	for i in 120:
		await tick_done
		floor_ticks += int(_player.is_on_floor())
	var drift := _player.global_position.distance_to(p0)
	print("  drift over 2 s: %.4f mm, on floor %d/120" % [drift * 1000, floor_ticks])
	_check(drift < 0.0001, "no drift at rest (< 0.1 mm)")
	_check(floor_ticks == 120, "stays on floor at rest")

	_section("straight line, walk and sprint")
	for sprint in [false, true]:
		await _go("Depart")
		var speed := _player.sprint_speed if sprint else _player.walk_speed
		_hold(Vector2(0, 1), sprint)
		var reach := -1
		for i in 30:
			await tick_done
			if reach < 0 and _player.horizontal_speed() >= speed * 0.99:
				reach = i + 1
		var z0 := _player.global_position.z
		await _ticks(60)
		var dist := z0 - _player.global_position.z
		_release()
		var stop := 0
		while _player.horizontal_speed() > 0.0 and stop < 60:
			await tick_done
			stop += 1
		var label := "sprint" if sprint else "walk"
		print("  %s: reaches speed in %d ticks (%.3f s), 1 s distance %.2f mm (expected %.2f), stops in %d ticks" % [label, reach, reach * TICK, dist * 1000, speed * 1000, stop])
		_check(absf(dist - speed) < 0.001, "%s: 1 s at speed covers %.1f mm ± 1 mm" % [label, speed * 1000])
		_check(reach > 0 and absf(reach * TICK - _player.accel_time) <= TICK * 1.01, "%s: speed reached in accel_time ± 1 tick" % label)
		_check(absf(stop * TICK - _player.stop_time) <= TICK * 1.01, "%s: stops in stop_time ± 1 tick" % label)

	_section("diagonal vs axial")
	await _go("Depart")
	_hold(Vector2(1, 1).normalized(), true)
	await _ticks(30)
	var diag := _player.horizontal_speed()
	_release()
	print("  diagonal speed %.5f vs sprint %.5f" % [diag, _player.sprint_speed])
	_check(diag <= _player.sprint_speed + 1e-6, "diagonal does not exceed sprint speed")
	_check(absf(diag - _player.sprint_speed) < 1e-4, "diagonal reaches sprint speed")

	_section("camera-relative, pitch independent")
	var bad := 0
	for yaw_deg in [0.0, 90.0, 135.0, -60.0]:
		for pitch_deg in [-70.0, -20.0, 10.0]:
			await _go("Depart")
			_rig.yaw = deg_to_rad(yaw_deg)
			_rig.pitch = deg_to_rad(pitch_deg)
			await _ticks(2)
			var start := _player.global_position
			_hold(Vector2(0, 1), false)
			await _ticks(30)
			_release()
			var moved := _player.global_position - start
			var expected := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(yaw_deg))
			var along := Vector2(moved.x, moved.z).normalized().dot(Vector2(expected.x, expected.z))
			var horiz := Vector2(moved.x, moved.z).length()
			if along < 0.9999 or absf(horiz - _dist_for(30, _player.walk_speed)) > 0.0002:
				bad += 1
				print("  yaw %.0f pitch %.0f: along %.5f dist %.4f" % [yaw_deg, pitch_deg, along, horiz])
	_check(bad == 0, "forward follows camera yaw at 4 yaws x 3 pitches, same distance")
	_rig.pitch = deg_to_rad(-20.0)

	_section("wall: push, then slide")
	await _go("Mur")
	_hold(Vector2(1, 0), true)
	var xs: Array[float] = []
	for i in 90:
		await tick_done
		if i >= 60:
			xs.append(_player.global_position.x)
	var gap: float = SIDE_WALL_X - (xs.max() + _radius)
	var jitter: float = xs.max() - xs.min()
	print("  pushing into wall: gap %.3f mm (negative = penetration), jitter %.4f mm" % [gap * 1000, jitter * 1000])
	_check(gap > -0.0005 and gap < 0.002, "rests against the wall: gap between -0.5 mm and 2 mm")
	_check(jitter < 0.0001, "no vibration while pushing (< 0.1 mm)")
	_hold(Vector2(1, 1).normalized(), true)
	await _ticks(20)
	var z0 := _player.global_position.z
	var xs2: Array[float] = []
	for i in 60:
		await tick_done
		xs2.append(_player.global_position.x)
	_release()
	var slide := (z0 - _player.global_position.z)
	var expected_slide := _player.sprint_speed * sqrt(0.5)
	print("  sliding along wall: %.2f mm/s (full-speed projection %.2f), lateral jitter %.4f mm" % [slide * 1000, expected_slide * 1000, (xs2.max() - xs2.min()) * 1000])
	_check(slide > expected_slide * 0.9, "slides along the wall at >= 90 % of the projected speed")
	_check(xs2.max() - xs2.min() < 0.0001, "no lateral vibration while sliding")
	_check(_camera_clear(), "camera clear of scenery at the wall")

	_section("inner corner")
	await _go("Coin")
	_hold(Vector2(0, 1), true)
	var ps: Array[Vector3] = []
	var cam_bad := 0
	for i in 120:
		await tick_done
		if i >= 90:
			ps.append(_player.global_position)
		cam_bad += int(not _camera_clear())
	_release()
	var spread: float = 0.0
	for p in ps:
		spread = maxf(spread, p.distance_to(ps[0]))
	var last := ps[-1]
	print("  corner: gaps x %.3f mm, z %.3f mm, jitter %.4f mm, camera bad ticks %d" % [(SIDE_WALL_X - last.x - _radius) * 1000, (last.z - _radius - BACK_WALL_Z) * 1000, spread * 1000, cam_bad])
	_check(SIDE_WALL_X - last.x - _radius > -0.0005 and last.z - _radius - BACK_WALL_Z > -0.0005, "no penetration in the corner (> -0.5 mm)")
	_check(spread < 0.0001, "stable in the corner (< 0.1 mm)")
	_check(cam_bad == 0, "camera clear of scenery in the corner")

	_section("coplanar floor seam (z = 0)")
	await _go("Joint")
	var min_speed := 1.0
	var max_dy := 0.0
	var off_floor := 0
	for lap in 6:
		var dir := 1.0 if lap % 2 == 0 else -1.0
		_hold(Vector2(0, dir), true)
		for i in 75:
			await tick_done
			# Skip the U-turn (12 ticks at sprint) between laps.
			if i >= 15:
				min_speed = minf(min_speed, _player.horizontal_speed())
			max_dy = maxf(max_dy, absf(_player.global_position.y))
			off_floor += int(not _player.is_on_floor())
	_release()
	print("  6 crossings: min speed %.5f (sprint %.3f), max |y| %.4f mm, ticks off floor %d" % [min_speed, _player.sprint_speed, max_dy * 1000, off_floor])
	_check(min_speed > _player.sprint_speed * 0.99, "no slowdown across the seam")
	_check(max_dy < 0.0001 and off_floor == 0, "no bump across the seam")

	_section("allowed 25° slope: up, stop, down")
	await _go("Pente")
	_hold(Vector2(0, 1), false)
	var slope_speeds: Array[float] = []
	for i in 150:
		await tick_done
		if _player.global_position.y > 0.01 and _player.global_position.y < 0.03:
			slope_speeds.append(_player.get_real_velocity().length())
	var top_y := _player.global_position.y
	_release()
	print("  climbed to y %.2f mm; speed on slope %.4f..%.4f m/s" % [top_y * 1000, slope_speeds.min(), slope_speeds.max()])
	_check(absf(top_y - 0.04) < 0.001, "reaches the 4 cm platform")
	_check(slope_speeds.min() > _player.walk_speed * 0.95, "keeps walking speed on the slope")
	await _go("Pente")
	_hold(Vector2(0, 1), false)
	while _player.global_position.y < 0.02:
		await tick_done
	_release()
	await _ticks(10)
	var on_slope := _player.global_position
	await _ticks(60)
	var slide_back := _player.global_position.distance_to(on_slope)
	print("  stopped on slope at y %.2f mm, drift over 1 s %.4f mm" % [on_slope.y * 1000, slide_back * 1000])
	_check(slide_back < 0.0001 and _player.is_on_floor(), "stays put on the slope")
	_hold(Vector2(0, -1), false)
	var air := 0
	for i in 60:
		await tick_done
		air += int(not _player.is_on_floor())
	_release()
	print("  walking down: ticks off floor %d, end y %.2f mm" % [air, _player.global_position.y * 1000])
	_check(air == 0, "stays on the ground walking down")

	_section("forbidden 50° slope")
	await _go("PenteRaide")
	_hold(Vector2(0, 1), true)
	var max_y := 0.0
	for i in 150:
		await tick_done
		max_y = maxf(max_y, _player.global_position.y)
	_release()
	await _ticks(30)
	print("  max height %.2f mm, end y %.2f mm" % [max_y * 1000, _player.global_position.y * 1000])
	_check(max_y < 0.003, "does not climb the 50° slope (< 3 mm)")

	_section("edge and gravity")
	await _go("Bord")
	_hold(Vector2(0, 1), false)
	var left_floor := -1
	var landed := -1
	for i in 180:
		await tick_done
		if left_floor < 0 and not _player.is_on_floor():
			left_floor = i
		if left_floor >= 0 and landed < 0 and _player.is_on_floor():
			landed = i
	_release()
	var fall_ticks := landed - left_floor
	print("  left platform at tick %d, landed after %d ticks (free fall of 4 cm ≈ %.1f ticks), end y %.3f mm" % [left_floor, fall_ticks, sqrt(2 * 0.04 / _player.gravity) / TICK, _player.global_position.y * 1000])
	_check(left_floor > 0 and landed > left_floor, "falls off the edge and lands")
	# At rest a CharacterBody3D sits between contact and safe_margin above the floor.
	var rest_y := _player.global_position.y
	_check(_player.is_on_floor() and rest_y > -0.0001 and rest_y <= _player.safe_margin + 0.0001, "back on the floor, within safe_margin (y %.3f mm)" % (rest_y * 1000))

	_section("under the cabinet and through the passage")
	for pos in ["SousMeuble", "Passage"]:
		await _go(pos)
		_hold(Vector2(0, 1), false)
		var start_z := _player.global_position.z
		var cam_fail := 0
		var stuck := 0
		var prev_d := -1.0
		var max_step := 0.0
		for i in 300:
			await tick_done
			cam_fail += int(not _camera_clear())
			if i > 10 and _player.horizontal_speed() < _player.walk_speed * 0.5:
				stuck += 1
			# Camera steadiness inside the uniform part of the passage.
			var z := _player.global_position.z
			if pos == "Passage" and z < -0.28 and z > -0.47:
				if prev_d >= 0.0:
					max_step = maxf(max_step, absf(_rig.current_distance - prev_d))
				prev_d = _rig.current_distance
		_release()
		if pos == "Passage":
			print("  Passage: max camera distance change per tick %.2f mm" % (max_step * 1000))
			_check(max_step < 0.002, "Passage: camera distance steady (< 2 mm per tick)")
		print("  %s: travelled %.1f mm, slow ticks %d, camera bad ticks %d, min camera distance %.3f" % [pos, (start_z - _player.global_position.z) * 1000, stuck, cam_fail, _rig.current_distance])
		_check(stuck == 0, "%s: never blocked" % pos)
		_check(cam_fail == 0, "%s: camera never in scenery" % pos)

	_section("camera follows without lag or rotation")
	await _go("Depart")
	_rig.yaw = deg_to_rad(30.0)
	var yaw0 := _rig.yaw
	var lag := 0.0
	_hold(Vector2(1, 1).normalized(), true)
	for i in 60:
		await tick_done
		lag = maxf(lag, _rig.global_position.distance_to(_player.global_position + Vector3(0, _rig.pivot_height, 0)))
	_release()
	print("  max pivot offset while moving %.6f mm" % (lag * 1000))
	_check(lag < 1e-6, "pivot on the player every tick (no lag)")
	_check(is_equal_approx(_rig.yaw, yaw0), "moving does not rotate the camera")

	_section("visual orientation")
	await _go("Depart")
	var vis0: float = _player.visual.rotation.y
	_rig.yaw += 1.2
	await _ticks(30)
	_check(is_equal_approx(_player.visual.rotation.y, vis0), "turning the camera at rest does not turn the cockroach")
	_hold(Vector2(1, 0), false)
	await _ticks(30)
	_release()
	var travel := Vector3(1, 0, 0).rotated(Vector3.UP, _rig.yaw)
	var facing := Vector3(0, 0, -1).rotated(Vector3.UP, _player.visual.rotation.y)
	_check(facing.dot(travel) > 0.999, "visual faces the direction of travel")
	_check(_player.get_node("Collision").global_basis.is_equal_approx(Basis()), "collision shape never rotates")
	_rig.yaw = 0.0

	_section("pause during acceleration")
	await _go("Depart")
	_hold(Vector2(0, 1), true)
	await _ticks(3)
	var speed_before := _player.horizontal_speed()
	get_tree().paused = true
	var frozen := _player.global_position
	await _ticks(30)
	_check(_player.global_position == frozen, "no progress while paused")
	get_tree().paused = false
	var prev := _player.global_position
	await tick_done
	var step := _player.global_position.distance_to(prev)
	var speed_after := _player.horizontal_speed()
	print("  speed before %.4f, first tick after resume %.4f, step %.4f mm" % [speed_before, speed_after, step * 1000])
	_check(speed_after <= speed_before + _player.sprint_speed / _player.accel_time * TICK + 1e-6, "no accumulated acceleration on resume")
	_check(step <= _player.sprint_speed * TICK + 1e-6, "no jump on resume")
	_release()

	_section("focus loss while moving")
	await _go("Depart")
	_hold(Vector2(0, 1), true)
	await _ticks(20)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _ticks(5)
	_check(get_tree().paused, "focus loss pauses")
	get_tree().paused = false
	await _ticks(20)
	_check(_player.horizontal_speed() == 0.0, "no stuck intention after focus loss")

	_section("diagnostic reset")
	await _go("Depart")
	_hold(Vector2(0, 1), true)
	await _ticks(40)
	_release()
	_panel.go_to("Depart")
	_check(_player.velocity == Vector3.ZERO, "velocity cleared")
	var marker: Node3D = _scene.get_node("TestPositions/Depart")
	_check(_player.global_position.is_equal_approx(marker.global_position), "back on the start marker")
	_check(_rig.camera.position == Vector3.ZERO, "camera restarts from the pivot")
	await _ticks(30)
	_check(_player.global_position.distance_to(marker.global_position) < 0.0001, "no motion after reset")


func _render_check(max_fps: int) -> void:
	Engine.max_fps = max_fps
	await _go("Depart")
	var frames0 := Engine.get_process_frames()
	var drawn0 := Engine.get_frames_drawn()
	var start := _player.global_position
	_hold(Vector2(0, 1), true)
	await _ticks(90)
	_release()
	var d := _player.global_position.distance_to(start)
	print("RENDER_CHECK max_fps %d: %d process frames, %d drawn, for 90 physics ticks, distance %.6f m" % [max_fps, Engine.get_process_frames() - frames0, Engine.get_frames_drawn() - drawn0, d])
	get_tree().quit(0)


func _set_shape(kind: String) -> void:
	var col: CollisionShape3D = _player.get_node("Collision")
	var s: Shape3D
	match kind:
		"capsule":
			s = CapsuleShape3D.new()
			s.radius = 0.007
			s.height = 0.016
		"sphere":
			s = SphereShape3D.new()
			s.radius = 0.008
		_:
			return
	col.shape = s
	col.position.y = s.height / 2.0 if s is CapsuleShape3D else s.radius


func _go(pos: String) -> void:
	_release()
	_panel.go_to(pos)
	await _ticks(20)


func _hold(v: Vector2, sprint: bool) -> void:
	_release()
	if v.x > 0: Input.action_press(&"move_right", v.x)
	if v.x < 0: Input.action_press(&"move_left", -v.x)
	if v.y > 0: Input.action_press(&"move_forward", v.y)
	if v.y < 0: Input.action_press(&"move_backward", -v.y)
	if sprint: Input.action_press(&"sprint")


func _release() -> void:
	for a in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(a)


func _ticks(n: int) -> void:
	for i in n:
		await tick_done


## Distance covered in n ticks from rest with linear acceleration.
func _dist_for(n: int, speed: float) -> float:
	var v := 0.0
	var d := 0.0
	for i in n:
		v = minf(v + speed / _player.accel_time * TICK, speed)
		d += v * TICK
	return d


func _camera_clear() -> bool:
	var shape := SphereShape3D.new()
	shape.radius = NEAR_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), _rig.camera.global_position)
	return _scene.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _section(title: String) -> void:
	print("-- ", title)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
