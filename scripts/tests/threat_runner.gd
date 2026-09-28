extends Node
## Scenarios for the human on kitchen_threat.tscn, with the real perception
## rays and collision. Setup may place the player (diagnostic reset) or
## pin the human in place for pure perception checks; the full outing at
## the end uses only player commands, no teleport, no invulnerability.
## Run: godot --headless --fixed-fps 60 --path . res://scenes/tests/threat_runner.tscn
## User arg --capture=<dir> (needs rendering): spotted → flee → hidden →
## search → routine, from an overview camera and the player's camera.

const THREAT := preload("res://scenes/levels/kitchen_threat.tscn")
const WATCHDOG_SECONDS := 900.0
const TICK := 1.0 / 60.0
const HIDDEN_UNDER_CABINET := Vector2(0.5, 0.30)

signal tick_done
signal frame_done

var _failures := 0
var _checks := 0
var _threat: KitchenThreat
var _human: HumanBrain
var _player: PlayerMotor
var _rig: CameraRig
var _session: SessionState
var _cues
var _debug
var _outcomes: Array[String] = []
var _fresh: KitchenThreat = null
var _capture := ""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000
	process_priority = 1000


func _physics_process(_d: float) -> void:
	tick_done.emit()


func _process(_d: float) -> void:
	frame_done.emit()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture = a.trim_prefix("--capture=")
	var t := THREAT.instantiate()
	t.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(t)
	_bind(t)
	await _ticks(5)
	if _capture != "":
		await _sequence()
		get_tree().quit(0)
		return
	await _run()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _bind(t: KitchenThreat) -> void:
	_threat = t
	_human = t.get_node("Human")
	_player = t.get_node("Loop/Kitchen/Player")
	_rig = t.get_node("Loop/Kitchen/CameraRig")
	_session = t.get_node("Loop/Session")
	_cues = t.get_node("ThreatCues")
	_debug = t.get_node("ThreatDebug")
	t.get_node("Loop/Kitchen/PauseController").capture_mouse = false
	_outcomes.clear()
	t.outcome.connect(func(k: String) -> void: _outcomes.append(k))


func _reset() -> void:
	_fresh = null
	_threat.session_reset.connect(func(f: KitchenThreat) -> void: _fresh = f)
	_threat.reset_session()
	await _ticks(5)
	_bind(_fresh)
	await _ticks(5)


func _run() -> void:
	_section("routine")
	var start_pos := _human.global_position
	var states := {}
	var outside := 0
	var t0 := -1
	var left_first := false
	for i in 60 * 34:
		await tick_done
		states[_human.state] = true
		if not _human.is_accessible(_human.global_position):
			outside += 1
		if _human._waypoint != 0:
			left_first = true
		elif left_first and t0 < 0 and _human._pause_left > 0.0:
			t0 = i
	print("  retour au premier point après %.1f s" % [t0 / 60.0])
	_check(states.size() == 1 and states.has(HumanBrain.State.ROUTINE), "joueur au fond du refuge : jamais repéré sur deux cycles")
	_check(outside == 0, "l'humain reste dans ses zones de passage")
	_check(t0 > 0 and absf(t0 / 60.0 - 16.0) < 0.5, "cycle reproductible (≈ 16 s)")

	_section("perception (humain immobilisé)")
	# Human at the sink looking west along the aisle.
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(Vector2(0.4, 0.85))
	await _ticks(2)
	_check(_human.perception.player_visible, "visible en face, à découvert (0,41 m)")
	_place(Vector2(1.2, 0.85))
	await _ticks(2)
	_check(not _human.perception.player_visible, "invisible dans le dos")
	_place(Vector2(0.8, 0.30))
	await _ticks(2)
	_check(not _human.perception.player_visible, "invisible sous les meubles (juste à côté de l'humain)")
	await _pin(Vector2(0.8, 0.72), deg_to_rad(-90.0))
	_place(Vector2(1.4, 0.8))
	await _ticks(2)
	var open_ok: bool = _human.perception.player_visible
	_place(Vector2(1.37, 1.0))
	await _ticks(2)
	_check(open_ok and not _human.perception.player_visible, "visible à découvert, caché derrière la poubelle")
	await _pin(Vector2(1.7, 0.9), deg_to_rad(90.0))
	_place(Vector2(0.03, 1.0))
	await _ticks(2)
	var far := not _human.perception.player_visible
	var t: HumanTuning = _human.tuning
	var saved := t.view_range
	t.view_range = 3.0
	await _ticks(2)
	var with_range: bool = _human.perception.player_visible
	t.view_range = saved
	_check(far and with_range, "hors de portée à 1,67 m (visible si la portée augmente : ce n'est pas un obstacle)")
	await _pin(Vector2(0.4, 0.72), deg_to_rad(90.0))
	_place(Vector2(0.0, 0.91))
	await _ticks(2)
	var mouth: bool = _human.perception.player_visible
	_place(Vector2(-0.11, 0.91))
	await _ticks(2)
	_check(not _human.perception.player_visible, "fond du refuge invisible (entrée : %s)" % ("visible" if mouth else "invisible"))

	_section("exposition brève puis prolongée")
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(HIDDEN_UNDER_CABINET)
	await _ticks(30)
	_place(Vector2(0.4, 0.85))
	await _ticks(24)   # 0.4 s
	var peak := _human.confirmation
	_place(HIDDEN_UNDER_CABINET)
	var back := -1
	for i in 180:
		await tick_done
		if back < 0 and _human.state == HumanBrain.State.ROUTINE:
			back = i
	print("  0,4 s vu : confirmation %.0f %%, retour à la routine après %.2f s" % [peak * 100, back / 60.0])
	_check(peak > 0.3 and peak < 1.0 and back > 0, "exposition brève : doute sans confirmation, puis oubli")
	_place(Vector2(0.4, 0.85))
	var confirm_at := -1
	for i in 120:
		await tick_done
		if confirm_at < 0 and _human.state == HumanBrain.State.CONFIRMED:
			confirm_at = i + 1
	print("  exposition continue : confirmé après %.2f s" % [confirm_at / 60.0])
	_check(confirm_at > 0 and absf(confirm_at / 60.0 - t.confirm_time) <= 2.0 / 60.0, "confirmation après ≈ %.1f s de vue continue" % t.confirm_time)

	_section("déplacement caché : dernière position connue figée")
	var lk := _human.last_known
	_place(Vector2(0.45, 0.30))
	var drift := 0.0
	_hold(Vector2(1, 0), false)
	for i in 120:
		await tick_done
		drift = maxf(drift, _human.last_known.distance_to(lk))
	_release()
	print("  joueur déplacé de %.2f m sous les meubles, dernière position connue bougée de %.4f m" % [_player.global_position.distance_to(Vector3(0.45, 0, 0.30)), drift])
	_check(drift == 0.0 and not _human.perception.player_visible, "l'humain ne suit pas le déplacement caché")

	_section("recherche à la dernière position connue, puis abandon")
	_human.pinned = false
	var search_seen := false
	var positions_ok := true
	var arrived_near := INF
	var end_routine := -1
	for i in 60 * 16:
		await tick_done
		if _human.state == HumanBrain.State.SEARCH:
			search_seen = true
			arrived_near = minf(arrived_near, Vector2(_human.global_position.x - lk.x, _human.global_position.z - 0.725).length())
		positions_ok = positions_ok and _human.is_accessible(_human.global_position) and _human.last_known == lk
		if search_seen and _human.state == HumanBrain.State.ROUTINE:
			end_routine = i
			break
	print("  recherche : plus proche de la position mémorisée %.2f m (projection dans l'allée), fin après %.1f s" % [arrived_near, end_routine / 60.0])
	_check(search_seen and arrived_near < 0.06, "l'humain va inspecter la position mémorisée")
	_check(end_routine > 0 and end_routine / 60.0 <= t.search_max + t.lose_time + 0.5, "la recherche se termine alors que le joueur reste caché")
	_check(positions_ok, "pendant la recherche : allée seulement, position mémorisée inchangée")

	_section("cible inaccessible")
	await _pin(Vector2(0.8, 0.72), deg_to_rad(135.0))
	_place(Vector2(0.4, 1.15))
	await _ticks(70)
	_check(_human.state == HumanBrain.State.CONFIRMED, "repéré entre la chaise et l'îlot")
	var target := _human.last_known
	_place(HIDDEN_UNDER_CABINET)
	_human.pinned = false
	var max_z := 0.0
	var closest := INF
	for i in 60 * 6:
		await tick_done
		max_z = maxf(max_z, _human.global_position.z)
		closest = minf(closest, _flat(_human.global_position, _human.accessible_point(target)))
	print("  cible (%.2f, %.2f) ; point d'inspection %s ; z max de l'humain %.3f" % [target.x, target.z, _human.accessible_point(target), max_z])
	_check(not _human.is_accessible(target) and closest < 0.05 and max_z < 0.75, "inspecte depuis l'allée, sans traverser la chaise")
	await _reset()

	_section("capture : immobile à découvert")
	_place(Vector2(0.5, 0.85))
	var windup_seen := false
	var frozen := Vector3.ZERO
	var frozen_ok := true
	var windup_ticks := 0
	for i in 60 * 20:
		await tick_done
		if _human.state == HumanBrain.State.CAPTURE_WINDUP and _human.active:
			if not windup_seen:
				frozen = _human.capture_point
			windup_seen = true
			windup_ticks += 1
			frozen_ok = frozen_ok and _human.capture_point == frozen and _human.capture_zone.visible
		if not _outcomes.is_empty():
			break
	print("  annonce %.2f s, résultat %s" % [windup_ticks / 60.0, _outcomes])
	_check(windup_seen and frozen_ok and absf(windup_ticks / 60.0 - _human.tuning.windup_time) < 0.05, "annonce ≈ 0,7 s, zone visible et figée")
	_check(_outcomes == ["capture"] and _threat.result == "capture", "capturé : un seul résultat")
	var pos := _player.global_position
	_hold(Vector2(0, 1), true)
	await _ticks(30)
	_release()
	_session.record_drink()
	_session.record_deposit()
	await _ticks(5)
	_check(_player.global_position == pos and _outcomes.size() == 1 and not _human.active, "après la capture : plus de déplacement, pas de second résultat")

	_section("réinitialisation après capture")
	await _reset()
	_check(_threat.result == "" and _human.state == HumanBrain.State.ROUTINE and _human.active, "humain neuf, en routine")
	_check(not _session.drank and _session.reserve == 0, "session neuve")
	_check(_player.global_position.distance_to(KitchenThreat.START) < 0.001 and not get_tree().paused, "joueur au fond du refuge, jeu non pausé")

	_section("capture esquivée")
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	var resolved := []
	_human.capture_resolved.connect(func(ok: bool) -> void: resolved.append(ok))
	_rig.yaw = _yaw_away(_human.global_position)
	_hold(Vector2(0, 1), false)
	for i in 60:
		await tick_done
		if not resolved.is_empty():
			break
	_release()
	print("  esquive en marchant : %s, écart au point visé %.3f m" % [resolved, _flat(_player.global_position, _human.capture_point)])
	_check(resolved == [false] and _outcomes.is_empty(), "s'éloigner à la marche pendant l'annonce fait échouer la capture")
	_check(_human.cooldown_left > 0.0, "délai avant une nouvelle tentative")
	await _reset()

	_section("capture bloquée par un obstacle (assise de la chaise)")
	_place(Vector2(0.75, 0.83))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	resolved = []
	_human.capture_resolved.connect(func(ok: bool) -> void: resolved.append(ok))
	# Step 1.5 cm south, just under the seat edge (z 0.84), still in the zone.
	_rig.yaw = PI
	_hold(Vector2(0, 1), false)
	await _ticks(18)
	_release()
	for i in 60:
		if not resolved.is_empty():
			break
		await tick_done
	var under := _player.global_position
	print("  joueur en (%.3f, %.3f), à %.3f m du point visé (rayon %.3f)" % [under.x, under.z, _flat(under, _human.capture_point), _human.tuning.capture_radius])
	_check(_flat(under, _human.capture_point) <= _human.tuning.capture_radius and under.z > 0.84, "encore dans la zone, mais sous l'assise")
	_check(resolved == [false] and _outcomes.is_empty(), "la capture ne traverse pas l'assise")
	await _reset()

	_section("pause pendant la confirmation, la recherche et l'annonce")
	_place(Vector2(0.5, 0.85))
	for i in 600:
		await tick_done
		if _human.confirmation > 0.3 and _human.state == HumanBrain.State.DOUBT:
			break
	await _pause_check("confirmation", func() -> float: return _human.confirmation)
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	await _ticks(10)
	await _pause_check("annonce", func() -> float: return _human.windup_left)
	await _reset()
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CONFIRMED, 60 * 20)
	_place(HIDDEN_UNDER_CABINET)
	await _wait_state(HumanBrain.State.SEARCH, 60 * 5)
	await _ticks(90)
	await _pause_check("recherche", func() -> float: return _human.search_total)
	await _reset()

	_section("indice de pas pour le joueur")
	# Record every footstep with its distance, and whether it was felt.
	var steps := []
	var felt_now := [-1.0]
	_cues.felt.connect(func(s: float) -> void: felt_now[0] = s)
	_human.footstep.connect(func(at: Vector3, _s: float) -> void:
		steps.append([_flat(at, _player.global_position), felt_now]))
	_place(Vector2(0.8, 0.45))
	var log := []
	for i in 60 * 16:
		felt_now[0] = -1.0
		var n := steps.size()
		await tick_done
		if steps.size() > n:
			log.append([steps[-1][0], felt_now[0]])
	var rule_ok := true
	var near_n := 0
	var far_n := 0
	for e in log:
		var d: float = e[0]
		var s: float = e[1]
		if d < _human.tuning.cue_range:
			near_n += 1
			rule_ok = rule_ok and absf(s - (1.0 - d / _human.tuning.cue_range)) < 0.001
		else:
			far_n += 1
			rule_ok = rule_ok and s < 0.0
	print("  %d pas sur un cycle : %d ressentis (< %.1f m), %d non ressentis" % [log.size(), near_n, _human.tuning.cue_range, far_n])
	_check(rule_ok and near_n > 0 and far_n > 0, "ressenti si et seulement si le pas est proche ; force décroissante avec la distance")
	_check(not _debug._label.visible and not _debug._lkp_marker.visible, "diagnostic masqué par défaut")
	_threat.get_node("Loop/Kitchen/DebugLayer/LevelDebugPanel").visible = true
	await frame_done
	await frame_done
	_check(_debug._label.visible, "F3 (panneau du niveau) affiche le diagnostic de l'IA")
	_threat.get_node("Loop/Kitchen/DebugLayer/LevelDebugPanel").visible = false
	await _reset()

	_section("caméra et pieds de l'humain")
	# Spotted in the open, the player flees into the plinth recess; the
	# human then searches with its toes near the cockroach.
	_place(Vector2(0.62, 0.85))
	var guard = _threat.get_node("HumanCameraGuard")
	var in_part := 0
	var fled := false
	for i in 60 * 14:
		await tick_done
		if not fled and _human.state == HumanBrain.State.CONFIRMED:
			fled = true
			_rig.yaw = 0.0
			_hold(Vector2(0, 1), true)
		if fled and _player.global_position.z < 0.4:
			_release()
		await frame_done
		var c := _rig.camera.global_position
		for n in ["Visual/FootL/Shoe", "Visual/FootR/Shoe", "Visual/LegL", "Visual/LegR"]:
			var m: MeshInstance3D = _human.get_node(n)
			if m.is_visible_in_tree() and m.get_aabb().has_point(m.global_transform.affine_inverse() * c):
				in_part += 1
	_release()
	print("  corrections de la garde : %d ; images avec la caméra dans une chaussure ou une jambe visible : %d" % [guard.corrections, in_part])
	_check(guard.corrections > 0 and in_part == 0, "la caméra n'entre jamais dans un pied ou une jambe visible")
	await _reset()

	_section("sortie complète par les commandes : boire → prendre → éviter → déposer")
	var result := await _full_outing()
	_check(result == "reussite" and _outcomes == ["reussite"], "sortie réussie sans téléportation (%s)" % result)
	var interactor: PlayerInteractor = _threat.get_node("Loop/Interactor")
	_check(interactor.process_mode == Node.PROCESS_MODE_DISABLED and not _human.active, "après la réussite : interactions et humain arrêtés")


## Player-only outing. The bot watches the human the way a player would
## (where it is, where it walks, when it stops) to time its crossings.
var _outing_states := {}
var _outing_min_dist := INF


func _watch_outing() -> void:
	while _threat.result == "":
		await tick_done
		var k: String = HumanBrain.State.keys()[_human.state]
		_outing_states[k] = _outing_states.get(k, 0) + 1
		_outing_min_dist = minf(_outing_min_dist, _flat(_human.global_position, _player.global_position))


func _full_outing() -> String:
	_watch_outing()
	# 1. Leave while the human is at the fridge, sprint to the west gap.
	await _until(func() -> bool: return _human._waypoint == 5 and _human._pause_left > 0.0, 60 * 40)
	await _walk([Vector2(0.06, 0.91), Vector2(0.2, 0.66), Vector2(0.2, 0.45), Vector2(0.2, 0.30), Vector2(0.8, 0.30), Vector2(0.8, 0.15)], true)
	await _approach(Vector2(0.8, 0.095))
	await _key(KEY_E)
	print("  a bu : %s (humain %s)" % [_session.drank, HumanBrain.State.keys()[_human.state]])
	# 2. Under the cabinets to the east gap, wait for the human to walk west.
	await _walk([Vector2(0.8, 0.30), Vector2(1.4, 0.30), Vector2(1.4, 0.45)], true)
	await _until(func() -> bool: return _human._waypoint == 1 and _human._pause_left <= 0.0 and _human.state == HumanBrain.State.ROUTINE, 60 * 40)
	await _walk([Vector2(1.4, 0.64), Vector2(1.52, 0.66)], true)
	await _approach(Vector2(1.5525, 0.6625))
	await _key(KEY_E)
	var carrying: bool = _threat.get_node("Loop/CarrySlot").has_item()
	await _walk([Vector2(1.4, 0.64), Vector2(1.4, 0.30), Vector2(0.2, 0.30), Vector2(0.2, 0.45)], false)
	print("  miette prise : %s (humain %s)" % [carrying, HumanBrain.State.keys()[_human.state]])
	# 3. Cross to the refuge while the human walks east.
	await _until(func() -> bool: return _human._waypoint == 3 and _human._pause_left <= 0.0 and _human.state == HumanBrain.State.ROUTINE, 60 * 40)
	await _walk([Vector2(0.2, 0.66), Vector2(0.06, 0.91), Vector2(-0.08, 0.91)], false)
	await _key(KEY_E)
	await _ticks(10)
	print("  états de l'humain pendant la sortie (ticks) : %s ; distance minimale humain-cafard %.2f m" % [_outing_states, _outing_min_dist])
	return _threat.result


func _sequence() -> void:
	var over := Camera3D.new()
	_threat.add_child(over)
	# Diagnostic top view (render only): the human's upper body, the
	# worktop, the cabinet body and the chair seat are hidden so the feet,
	# the cockroach (cyan ring), the last known position (magenta) and the
	# capture zone (red) can be read.
	for path in ["Human/Visual/Torso", "Human/Visual/Head", "Human/Visual/LegL", "Human/Visual/LegR",
			"Loop/Kitchen/Level/Worktop/Mesh", "Loop/Kitchen/Level/CabinetBody/Mesh", "Loop/Kitchen/Level/ChairSeat/Mesh"]:
		(_threat.get_node(path) as Node3D).visible = false
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.025
	torus.outer_radius = 0.035
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.1, 0.95, 1.0)
	torus.material = ring_mat
	ring.mesh = torus
	_player.add_child(ring)
	ring.position = Vector3(0, 0.01, 0)
	over.projection = Camera3D.PROJECTION_ORTHOGONAL
	over.size = 1.3
	over.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0.85, 3.0, 0.62))
	over.fov = 50.0
	_threat.get_node("Loop/Kitchen/DebugLayer/LevelDebugPanel").visible = true
	_place(Vector2(0.62, 0.85))
	var n := 0
	var fled := false
	for i in 60 * 16:
		await tick_done
		if not fled and _human.state == HumanBrain.State.CONFIRMED:
			fled = true
			_rig.yaw = 0.0
			_hold(Vector2(0, 1), true)
		if fled and _player.global_position.z < 0.40:
			_release()
		if i % 45 == 0:
			for cam in [over, _rig.camera]:
				# Diagnostics only on the overview; the player's view is clean.
				var diag: bool = cam == over
				ring.visible = diag
				_threat.get_node("Loop/Kitchen/DebugLayer/LevelDebugPanel").visible = diag
				cam.make_current()
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s/%03d_%s_%s.png" % [_capture, n, "vue" if cam == over else "cafard", HumanBrain.State.keys()[_human.state]])
			_rig.camera.make_current()
			n += 1
		if fled and _human.state == HumanBrain.State.ROUTINE and i > 60 * 12:
			break


# --- helpers -----------------------------------------------------------------

func _pin(at: Vector2, yaw: float) -> void:
	_human.pinned = true
	_human.global_position = Vector3(at.x, 0.0, at.y)
	_human.rotation.y = yaw
	_human.state = HumanBrain.State.ROUTINE
	_human.confirmation = 0.0
	_human._pause_left = 1000.0
	await _ticks(2)


func _place(at: Vector2) -> void:
	_player.reset_to(Transform3D(Basis(), Vector3(at.x, 0.0, at.y)))
	_rig.snap_to_target(_rig.yaw)


func _pause_check(label: String, value: Callable) -> void:
	var before: float = value.call()
	var st := _human.state
	var hp := _human.global_position
	get_tree().paused = true
	await _ticks(60)
	var same: bool = value.call() == before and _human.state == st and _human.global_position == hp
	get_tree().paused = false
	await _ticks(3)
	var moved_on: bool = value.call() != before or _human.state != st
	_check(same and moved_on, "pause pendant %s : figé, puis reprend (%.2f)" % [label, before])


func _wait_state(s: HumanBrain.State, max_ticks: int) -> void:
	for i in max_ticks:
		if _human.state == s:
			return
		await tick_done
	_check(false, "état %s jamais atteint" % HumanBrain.State.keys()[s])


func _until(cond: Callable, max_ticks: int) -> void:
	for i in max_ticks:
		if cond.call():
			return
		await tick_done
	print("  (attente expirée)")


func _yaw_away(from: Vector3) -> float:
	var away := Vector2(_player.global_position.x - from.x, _player.global_position.z - from.z)
	var side := Vector2(-away.y, away.x)
	return atan2(-side.x, -side.y)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _walk(pts: Array, sprint: bool) -> void:
	var i := 0
	var ticks := 0
	_hold(Vector2(0, 1), sprint)
	while i < pts.size() and ticks < 60 * 60 and _threat.result == "":
		var p := _player.global_position
		var to: Vector2 = pts[i] - Vector2(p.x, p.z)
		if to.length() < 0.012:
			i += 1
			continue
		_rig.yaw = atan2(-to.x, -to.y)
		await tick_done
		ticks += 1
	_release()
	await _ticks(10)


func _approach(point: Vector2) -> void:
	var interactor: PlayerInteractor = _threat.get_node("Loop/Interactor")
	_hold(Vector2(0, 1), false)
	for i in 600:
		var p := _player.global_position
		var to := point - Vector2(p.x, p.z)
		if interactor.target != null and interactor.edge_distance(interactor.target) < interactor.reach * 0.6:
			break
		_rig.yaw = atan2(-to.x, -to.y)
		await tick_done
	_release()
	await _ticks(10)


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


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = key
		e.pressed = pressed
		Input.parse_input_event(e)
		await tick_done
		await frame_done


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
