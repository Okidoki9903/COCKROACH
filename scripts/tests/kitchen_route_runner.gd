extends Node
## Drives the player along the planned routes of kitchen_blockout.tscn by
## steering the camera toward waypoints and holding forward, as a player
## would. Proves traversability and measures time and length; it says
## nothing about readability or fun.
## Run: godot --headless --fixed-fps 60 --path . res://scenes/tests/kitchen_route_runner.tscn
## User args (after --): --capture=<dir> (needs rendering) saves frames of
## two routes; --overview=<dir> saves overview and eye-level views only;
## --routes=direct,couverte and --modes=marche restrict the run.

const KITCHEN := preload("res://scenes/levels/kitchen_blockout.tscn")
const WATCHDOG_SECONDS := 600.0
const NEAR_CLEARANCE := 0.0015
const REFUGE_IN := Vector2(-0.06, 0.91)
const EXIT := Vector2(0.06, 0.91)
const FOOD := Vector2(1.5525, 0.6625)
const WATER := Vector2(0.8, 0.13)

## Outbound waypoints (x, z) from the refuge; returns use them reversed.
var ROUTES := {
	"direct": [EXIT, FOOD],
	"couverte": [EXIT, Vector2(0.2, 0.66), Vector2(0.2, 0.30), Vector2(1.4, 0.30), Vector2(1.4, 0.64), FOOD],
	"bascule": [EXIT, Vector2(0.75, 0.70), Vector2(0.75, 0.30), Vector2(1.4, 0.30), Vector2(1.4, 0.64), FOOD],
	"detour_eau": [EXIT, Vector2(0.2, 0.66), Vector2(0.2, 0.30), Vector2(0.8, 0.30), WATER],
}

signal tick_done
## Emitted from _process after every other node's _process: the camera
## distance is only final then (it is applied in CameraRig._process).
signal frame_done

var _failures := 0
var _checks := 0
var _scene: Node3D
var _player: PlayerMotor
var _rig: CameraRig
var _panel
var _capture_dir := ""
var _results := {}
var _routes: PackedStringArray = []
var _modes: PackedStringArray = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000
	process_priority = 1000


func _physics_process(_delta: float) -> void:
	tick_done.emit()


func _process(_delta: float) -> void:
	frame_done.emit()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_scene = KITCHEN.instantiate()
	_scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_scene)
	_player = _scene.get_node("Player")
	_rig = _scene.get_node("CameraRig")
	_panel = _scene.get_node("DebugLayer/LevelDebugPanel")
	_scene.get_node("PauseController").capture_mouse = false
	await _ticks(10)
	if args.has("overview"):
		await _overview(args["overview"])
		get_tree().quit(0)
		return
	_capture_dir = args.get("capture", "")
	_routes = args.get("routes", ",".join(ROUTES.keys())).split(",")
	_modes = args.get("modes", "marche,sprint").split(",")
	await _run()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	for sprint in [false, true]:
		var mode := "sprint" if sprint else "marche"
		if mode not in _modes:
			continue
		_section(mode)
		for route in ROUTES:
			if route not in _routes:
				continue
			var pts: Array = ROUTES[route]
			var out := await _drive("%s aller (%s)" % [route, mode], "Refuge", pts, sprint,
				_capture_dir != "" and not sprint and route in ["direct", "couverte"])
			var back_pts: Array = pts.duplicate()
			back_pts.reverse()
			back_pts.append(REFUGE_IN)
			var start := "Eau" if route == "detour_eau" else "Nourriture"
			if start == "Eau":
				# The Eau spawn faces the water spot: start the return from it
				# rather than walking to it and turning back.
				back_pts.pop_front()
			var back := await _drive("%s retour (%s)" % [route, mode], start, back_pts, sprint, false)
			_results["%s/%s" % [route, mode]] = [out, back]
	if _results.has("direct/marche"):
		await _check_panel()
	if not (_results.has("direct/marche") and _results.has("couverte/marche")):
		return
	_section("comparaison des routes (marche, aller)")
	var direct: Dictionary = _results["direct/marche"][0]
	var covered: Dictionary = _results["couverte/marche"][0]
	print("  direct %.1f s / %.2f m, couverte %.1f s / %.2f m" % [direct.time, direct.length, covered.time, covered.length])
	_check(direct.time < covered.time * 0.75, "le raccourci est au moins 25 % plus court en temps")


func _check_panel() -> void:
	_section("panneau de diagnostic")
	# The last direct return ended in the refuge: its trip was recorded.
	print("  dernier trajet enregistré : %s" % _panel.last_trip)
	_check(_panel.last_trip.begins_with("retour"), "le panneau enregistre le trajet retour")
	_panel.go_to("Refuge")
	await _ticks(5)
	Input.action_press(&"move_forward")
	await _ticks(90)
	get_tree().paused = true
	var frozen: float = _panel._trip_time
	await _ticks(60)
	_check(_panel._trip_time == frozen, "le chronomètre ne tourne pas en pause")
	get_tree().paused = false
	Input.action_release(&"move_forward")
	var was: bool = _panel.visible
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = KEY_F3
		e.pressed = pressed
		Input.parse_input_event(e)
		await frame_done
		await frame_done
	_check(_panel.visible != was, "F3 masque le panneau")
	_panel.visible = was


## Follows `pts` from spawn `start`; returns time, length and counters.
func _drive(label: String, start: String, pts: Array, sprint: bool, capture: bool) -> Dictionary:
	_panel.go_to(start)
	_rig.pitch = deg_to_rad(-20.0)
	await _ticks(15)
	var speed := _player.sprint_speed if sprint else _player.walk_speed
	var length := _path_length(pts, start)
	var max_ticks := int(length / speed * 60.0 * 2.0) + 120
	var i := 0
	var ticks := 0
	var travelled := 0.0
	var stuck := 0
	var window: Array[Vector3] = []
	var cam_bad := 0
	var vis_hits := 0
	var max_cam_step := 0.0
	var prev_cam := _rig.current_distance
	var prev := _player.global_position
	Input.action_press(&"move_forward")
	if sprint:
		Input.action_press(&"sprint")
	while i < pts.size() and ticks < max_ticks:
		var p := _player.global_position
		var to: Vector2 = pts[i] - Vector2(p.x, p.z)
		if to.length() < 0.012:
			i += 1
			continue
		_rig.yaw = atan2(-to.x, -to.y)
		await tick_done
		await frame_done
		ticks += 1
		var now := _player.global_position
		travelled += Vector2(now.x - prev.x, now.z - prev.z).length()
		prev = now
		# Blocked = less than 30 % of the expected progress over 0.5 s
		# (a U-turn at a waypoint still progresses over that window).
		window.append(now)
		if window.size() > 30:
			window.pop_front()
			if window[0].distance_to(now) < speed * 0.5 * 0.3:
				stuck += 1
		if not _clear(_rig.camera.global_position):
			cam_bad += 1
			print("    camera contact tick %d: player %s camera %s dist %.4f free %.4f yaw %.0f° hit %s" % [
				ticks, _player.global_position, _rig.camera.global_position, _rig.current_distance,
				_rig.get_free_distance(), rad_to_deg(_rig.yaw), _hit_name(_rig.camera.global_position)])
		vis_hits += int(_visual_overlaps())
		var cam_step := absf(_rig.current_distance - prev_cam)
		if cam_step > 0.02:
			print("    camera pull-in %.1f mm at player (%.2f, %.2f), obstacle %s" % [cam_step * 1000, now.x, now.z, _arm_hit()])
		max_cam_step = maxf(max_cam_step, cam_step)
		prev_cam = _rig.current_distance
		if capture and ticks % 20 == 0:
			await _save("route_%s_%04d" % [label.split(" ")[0], ticks])
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	var reached := i >= pts.size()
	var r := {"time": ticks / 60.0, "length": travelled}
	print("  %-28s %s  %5.1f s  %.2f m  bloqué %d  caméra %d  visuel %d/%d (%.0f %%)  saut caméra max %.1f mm" % [
		label, "OK " if reached else "ÉCHEC", r.time, travelled, stuck, cam_bad, vis_hits, ticks,
		100.0 * vis_hits / maxf(ticks, 1), max_cam_step * 1000])
	_check(reached, "%s : arrivé" % label)
	_check(stuck == 0, "%s : jamais bloqué" % label)
	_check(cam_bad == 0, "%s : caméra jamais dans le décor" % label)
	return r


func _path_length(pts: Array, start: String) -> float:
	var s: Node3D = _scene.get_node("Spawns/" + start)
	var prev := Vector2(s.global_position.x, s.global_position.z)
	var total := 0.0
	for p in pts:
		total += prev.distance_to(p)
		prev = p
	return total


func _visual_overlaps() -> bool:
	var body: MeshInstance3D = _player.get_node("Visual/Body")
	var shape := BoxShape3D.new()
	# The visual body, 1 mm thinner at the bottom so resting on the floor
	# does not count.
	shape.size = Vector3(0.012, 0.005, 0.03)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = body.global_transform.translated(Vector3(0, 0.0005, 0))
	return not _scene.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Name of what the camera arm would hit at the current orientation.
func _arm_hit() -> String:
	var from := _rig.global_position
	var to := _rig.to_global(_rig.get_node("Pitch").transform * Vector3(0, 0, _rig.desired_distance))
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := _scene.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.collider.name if hit else "?"


func _hit_name(at: Vector3) -> String:
	var shape := SphereShape3D.new()
	shape.radius = NEAR_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), at)
	var hits := _scene.get_world_3d().direct_space_state.intersect_shape(q, 4)
	return ", ".join(hits.map(func(h): return h.collider.name))


func _clear(at: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = NEAR_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), at)
	return _scene.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _overview(dir: String) -> void:
	_capture_dir = dir
	var panel: Control = _panel
	panel.visible = false
	# Eye-level views: [name, spawn, player pos (x, z) or null, yaw deg, pitch deg]
	var views := [
		["01_refuge_depart", "Refuge", null, -90.0, -15.0],
		["02_sortie_refuge", "Refuge", Vector2(0.05, 0.91), -90.0, -12.0],
		["03_route_directe_milieu", "Refuge", Vector2(0.75, 0.78), -99.0, -12.0],
		["04_sous_meuble", "Refuge", Vector2(0.5, 0.30), -90.0, -15.0],
		["05_breche_milieu_vers_ouvert", "Refuge", Vector2(0.75, 0.40), 180.0, -12.0],
		["06_nourriture_vers_refuge", "Nourriture", null, 90.0, -12.0],
		["07_eau", "Eau", null, 0.0, -15.0],
		["08_bord_chaise", "Refuge", Vector2(0.62, 0.80), -90.0, -12.0],
	]
	for v in views:
		_panel.go_to(v[1])
		if v[2] != null:
			var t := Transform3D(Basis(), Vector3(v[2].x, 0.0, v[2].y))
			_player.reset_to(t.rotated_local(Vector3.UP, deg_to_rad(v[3])))
		_player.visual.rotation.y = deg_to_rad(v[3])
		_rig.snap_to_target(deg_to_rad(v[3]))
		_rig.pitch = deg_to_rad(v[4])
		await _ticks(30)
		await _save(v[0])
	# Top-down orthographic plan.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	cam.near = 0.1
	cam.far = 10.0
	_scene.add_child(cam)
	cam.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0.95, 3.0, 0.72))
	cam.make_current()
	_player.reset_to(Transform3D(Basis(), Vector3(-0.04, 0, 0.91)))
	await _ticks(10)
	await _save("00_plan_dessus")
	for name in ["Refuge", "FutureFood", "FutureWater"]:
		var n: Node3D = _scene.get_node("Spawns/Refuge") if name == "Refuge" else _scene.get_node("ReservedSpots/" + name)
		print("PIXEL %s %s" % [name, cam.unproject_position(n.global_position)])
	for route in ROUTES:
		var line := "PATH %s" % route
		for p in ROUTES[route]:
			var px := cam.unproject_position(Vector3(p.x, 0, p.y))
			line += " %d,%d" % [px.x, px.y]
		print(line)
	var px0 := cam.unproject_position(Vector3(0, 0, 0))
	var px1 := cam.unproject_position(Vector3(1, 0, 0))
	print("SCALE px_per_m %.1f origin %s" % [px1.x - px0.x, px0])
	# Oblique overview (the island is hidden: it would mask the floor).
	_scene.get_node("Level/IslandBody").visible = false
	_scene.get_node("Level/IslandPlinth").visible = false
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 50.0
	cam.near = 0.01
	cam.global_position = Vector3(1.3, 1.5, 2.1)
	cam.look_at(Vector3(0.75, 0.0, 0.62))
	await _ticks(5)
	await _save("09_vue_ensemble")


func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_capture_dir, shot])


func _ticks(n: int) -> void:
	for i in n:
		await tick_done


func _section(title: String) -> void:
	print("-- ", title)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
