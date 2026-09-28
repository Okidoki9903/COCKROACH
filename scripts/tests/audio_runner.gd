extends Node
## Audio presentation checks on kitchen_threat.tscn: loading, routing,
## listener, one sound per event, pause, terminal outcome, restarts.
## These are checks of events and of the audio graph, not listening.
##   godot --headless --fixed-fps 60 --path . res://scenes/tests/audio_runner.tscn
## Signal modes (need rendering; the movie writer mixes the audio frame by
## frame and saves it; markers go to <dir>/markers.json):
##   --probe=<dir>  calibrated emissions: near/far, left/right, rotation,
##                  camera distance, occlusion, every sound once
##   --clip=<dir>   threat scenario from the cockroach's camera: approach
##                  out of view, close pass, search next to the hideout,
##                  missed capture, capture
##   godot --fixed-fps 30 --resolution 480x270 --write-movie <dir>/x.avi --path . res://scenes/tests/audio_runner.tscn -- --clip=<dir>

const THREAT := preload("res://scenes/levels/kitchen_threat.tscn")
const WATCHDOG_SECONDS := 600.0
const HIDDEN_UNDER_CABINET := Vector2(0.5, 0.30)

signal tick_done
signal frame_done

var _failures := 0
var _checks := 0
var _threat: KitchenThreat
var _human: HumanBrain
var _player: PlayerMotor
var _rig: CameraRig
var _audio: ThreatAudio
var _fresh: KitchenThreat = null
## [kind, tick] of every sound started, for the current attempt.
var _events: Array = []
var _tick := 0
## Movie time (s), counted on every frame, paused or not.
var _time := 0.0
var _markers: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000
	process_priority = 1000


func _physics_process(_d: float) -> void:
	_tick += 1
	tick_done.emit()


func _process(delta: float) -> void:
	_time += delta
	frame_done.emit()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	var probe := ""
	var clip := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			probe = a.trim_prefix("--probe=")
		if a.begins_with("--clip="):
			clip = a.trim_prefix("--clip=")
	var t := THREAT.instantiate()
	t.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(t)
	_bind(t)
	await _ticks(5)
	if probe != "":
		await _probe()
		_save_markers(probe)
		get_tree().quit(0)
		return
	if clip != "":
		await _clip()
		_save_markers(clip)
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
	_audio = t.get_node("ThreatAudio")
	t.get_node("Loop/Kitchen/PauseController").capture_mouse = false
	_events.clear()
	_audio.emitted.connect(func(kind: StringName, at: Vector3, db: float, occluded: bool) -> void:
		_events.append([kind, _tick])
		_markers.append({"t": _time, "kind": String(kind), "d": at.distance_to(_audio.ear_position()), "db": db, "occluded": occluded}))


func _reset() -> void:
	_fresh = null
	_threat.session_reset.connect(func(f: KitchenThreat) -> void: _fresh = f)
	_threat.reset_session()
	await _ticks(5)
	_bind(_fresh)
	await _ticks(5)


func _count(kind: StringName) -> int:
	var n := 0
	for e in _events:
		if e[0] == kind:
			n += 1
	return n


func _run() -> void:
	_section("chargement et routage")
	var buses := []
	for i in AudioServer.bus_count:
		buses.append(AudioServer.get_bus_name(i))
	_check(buses == ["Master", "Threat", "Ambience"] and AudioServer.get_bus_send(1) == &"Master" and AudioServer.get_bus_send(2) == &"Master", "bus Master, Threat, Ambience ; Threat et Ambience vers Master")
	var lim := AudioServer.get_bus_effect(0, 0) as AudioEffectHardLimiter
	_check(lim != null and AudioServer.is_bus_effect_enabled(0, 0) and lim.ceiling_db <= -1.0, "limiteur sur Master, plafond %.1f dB" % (lim.ceiling_db if lim else 0.0))
	var streams_ok := true
	for s in ThreatAudio.STEPS + [ThreatAudio.RUSTLE, ThreatAudio.ANNOUNCE, ThreatAudio.MISS, ThreatAudio.CAUGHT, ThreatAudio.SUCCESS, ThreatAudio.HUM]:
		streams_ok = streams_ok and s is AudioStreamWAV and s.get_length() > 0.1
	_check(streams_ok, "9 sons chargés")
	var routing := true
	for p in _audio.sources():
		routing = routing and p.bus == &"Threat" and p.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE and p.max_db <= 0.0
	_check(routing and _audio._final_ui.bus == &"Threat" and _audio.ambience.bus == &"Ambience", "sons de l'humain sur Threat (3D, jamais au-dessus de 0 dB), ambiance sur Ambience")
	_check(_audio.ambience.playing and (ThreatAudio.HUM as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambiance en boucle, lancée")

	_section("écouteur sur le cafard")
	var vp := get_viewport()
	_check(vp.get_audio_listener_3d() == _audio.listener, "l'écouteur de la scène est celui du cafard")
	var ear_ok := true
	var cam_min := INF
	var cam_max := 0.0
	# Walk in the open, then under the cabinets (camera pulled in).
	_place(Vector2(0.5, 0.85))
	_rig.yaw = 0.0
	_hold(Vector2(0, 1), false)
	for i in 60 * 8:
		await frame_done
		var d := _rig.camera.global_position.distance_to(_player.global_position)
		cam_min = minf(cam_min, d)
		cam_max = maxf(cam_max, d)
		ear_ok = ear_ok and _audio.ear_position().distance_to(_player.global_position + Vector3.UP * _audio.ear_height) < 1e-5
	_release()
	print("  distance caméra-cafard de %.3f à %.3f m ; écouteur toujours à 12 mm au-dessus du cafard : %s" % [cam_min, cam_max, ear_ok])
	_check(ear_ok and cam_max - cam_min > 0.03, "la distance de la caméra ne déplace pas l'écouteur")
	var turn_ok := true
	for yaw in [0.0, PI / 2.0, PI, -PI / 3.0]:
		_rig.yaw = yaw
		_rig.pitch = deg_to_rad(-60.0)
		await frame_done
		var fwd := -_audio.listener.global_transform.basis.z
		turn_ok = turn_ok and fwd.distance_to(Vector3(-sin(yaw), 0.0, -cos(yaw))) < 1e-4 and _audio.listener.global_transform.basis.y.distance_to(Vector3.UP) < 1e-4
	_rig.pitch = deg_to_rad(-20.0)
	_check(turn_ok, "l'écouteur tourne avec le regard (lacet), pas avec l'inclinaison")
	await _reset()

	_section("pas : un événement, un son ; rien au repos")
	var steps := [0]
	_human.footstep.connect(func(_a: Vector3, _s: float) -> void: steps[0] += 1)
	var one_to_one := true
	var moved_when_emitting := true
	var still_ticks := 0
	var still_emissions := 0
	var prev := _human.global_position
	for i in 60 * 17:
		var n_ev := _count(&"pas")
		var n_st: int = steps[0]
		await tick_done
		var moved := _human.global_position.distance_to(prev) > 0.0
		prev = _human.global_position
		var new_ev := _count(&"pas") - n_ev
		one_to_one = one_to_one and new_ev == steps[0] - n_st and new_ev <= 1
		if new_ev > 0:
			moved_when_emitting = moved_when_emitting and moved
		if not moved:
			still_ticks += 1
			still_emissions += new_ev
	print("  cycle de routine : %d pas, %d sons de pas ; %d ticks immobile, %d sons pendant ces ticks" % [steps[0], _count(&"pas"), still_ticks, still_emissions])
	_check(one_to_one and steps[0] >= 5, "chaque événement de pas donne exactement un son, dans le même tick")
	_check(moved_when_emitting and still_ticks > 60 * 5 and still_emissions == 0, "aucun pas pendant les pauses de la routine")
	_check(_events.size() == _count(&"pas"), "rien d'autre en routine (pas de sonar)")
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(Vector2(0.4, 0.85))
	var before := _events.size()
	await _ticks(40)
	_check(_human.state == HumanBrain.State.DOUBT and _events.size() == before, "humain immobile qui regarde (doute) : silencieux")

	_section("fouille : froissement sur les inspections")
	_place(Vector2(0.4, 0.85))
	await _wait_state(HumanBrain.State.CONFIRMED, 120)
	_place(HIDDEN_UNDER_CABINET)
	_human.pinned = false
	var inspections := [0]
	_human.inspecting.connect(func(_p: Vector3) -> void: inspections[0] += 1)
	var rustle_ok := true
	var start_n := _count(&"fouille")
	var paused_rustle := false
	for i in 60 * 14:
		var n := _count(&"fouille")
		await tick_done
		if _count(&"fouille") > n:
			rustle_ok = rustle_ok and _human.state == HumanBrain.State.SEARCH and _human.velocity == Vector3.ZERO
			if not paused_rustle:
				paused_rustle = true
				await _pause_during_sound("un froissement", _audio._rustle)
		if _human.state == HumanBrain.State.ROUTINE:
			break
	var rustles := _count(&"fouille") - start_n
	print("  %d inspections, %d froissements" % [inspections[0], rustles])
	_check(rustles == inspections[0] and rustles == 3 and rustle_ok, "un froissement à l'arrivée et à chaque retournement du balayage (3), humain arrêté en recherche")
	await _reset()

	_section("annonce et résolution de capture")
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	await tick_done
	var ann_tick := _tick
	_check(_count(&"annonce") == 1, "un son d'annonce au début de l'annonce")
	await _ticks(10)
	await _pause_during_sound("l'annonce", _audio._announce)
	for i in 60 * 2:
		if _threat.result != "":
			break
		await tick_done
	await tick_done
	_check(_count(&"annonce") == 1 and _count(&"attrapé") == 1 and _count(&"raté") == 0, "capture : un seul son final, pas de son d'échec")
	var others_stopped := true
	for p in _audio.sources():
		if p != _audio._final_3d:
			others_stopped = others_stopped and not p.playing
	_check(others_stopped and _audio._final_3d.playing, "fin de tentative : sons de routine arrêtés, retour final joué")
	var n_end := _events.size()
	await _ticks(120)
	_check(_events.size() == n_end, "plus aucun son d'humain après la fin")
	await _reset()
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	_rig.yaw = _yaw_away(_human.global_position)
	_hold(Vector2(0, 1), false)
	for i in 60:
		if _count(&"raté") > 0:
			break
		await tick_done
	_release()
	_check(_count(&"raté") == 1 and _count(&"attrapé") == 0 and _threat.result == "", "capture esquivée : un son d'échec, distinct, la tentative continue")
	await _reset()
	_threat.get_node("Loop/Session").record_drink()
	_threat.get_node("Loop/Session").record_deposit()
	await _ticks(5)
	_check(_audio.finished and _audio._final_ui.playing and _count(&"réussite") == 1, "sortie réussie : un seul retour final")
	await _reset()

	_section("recommencer plusieurs fois")
	var base_players := _players_under(get_tree().root)
	var base_links := _human.footstep.get_connections().size()
	for k in 4:
		await _reset()
	var old := _audio
	await _reset()
	_check(not is_instance_valid(old), "l'ancienne présentation audio est libérée")
	_check(_players_under(get_tree().root) == base_players and _human.footstep.get_connections().size() == base_links, "après 5 redémarrages : %d lecteurs, %d connexions aux pas (inchangés)" % [base_players, base_links])
	_check(get_viewport().get_audio_listener_3d() == _audio.listener, "l'écouteur est celui de la nouvelle tentative")
	var counted := [0]
	_human.footstep.connect(func(_a: Vector3, _s: float) -> void: counted[0] += 1)
	await _ticks(60 * 4)
	_check(counted[0] > 0 and _count(&"pas") == counted[0], "toujours un son par pas (%d / %d)" % [_count(&"pas"), counted[0]])

	_section("occultation bornée")
	_place(HIDDEN_UNDER_CABINET)
	await _ticks(2)
	var foot := Vector3(0.5, 0.035, 0.72)
	var hidden_occ := _audio.is_occluded(foot)
	_place(Vector2(0.5, 0.85))
	await _ticks(2)
	_check(hidden_occ and not _audio.is_occluded(foot), "pas derrière la plinthe : occulté ; à découvert : direct")
	_check(_audio.occlusion_db >= -9.0 and _audio.occlusion_db < 0.0, "occultation bornée (%.0f dB, jamais muet)" % _audio.occlusion_db)


## Pause while a sound plays: it is suspended (playing false, position
## frozen apart from the engine's short fade-out while real time passes,
## ambience going on), no event is produced, nothing bursts on resume.
## The headless run is much faster than real time: the sound is given a
## few real milliseconds to start first.
func _pause_during_sound(label: String, p: AudioStreamPlayer3D) -> void:
	await _ticks(2)
	OS.delay_msec(40)
	var n := _events.size()
	get_tree().paused = true
	await _ticks(2)
	var pos := p.get_playback_position()
	var amb := _audio.ambience.get_playback_position()
	var suspended := p.stream_paused and not p.playing
	OS.delay_msec(250)
	await _ticks(30)
	var drift := p.get_playback_position() - pos
	var amb_moved := _audio.ambience.get_playback_position() - amb
	var silent := _events.size() == n
	get_tree().paused = false
	await _ticks(2)
	var resumed := p.playing and not p.stream_paused
	await _ticks(8)
	var burst := _events.size() - n
	print("  pause pendant %s à %.3f s : suspendu %s, avance pendant 250 ms réelles %.3f s (ambiance %.3f s) ; sons émis en pause %d ; reprise %s, sons dans les 10 ticks après %d" % [label, pos, suspended, drift, amb_moved, _events.size() - n if not silent else 0, resumed, burst])
	_check(suspended and drift < 0.03 and amb_moved > 0.15 and silent and resumed and burst <= 1, "pause pendant %s : suspendu, rien d'accumulé, reprise sans rafale" % label)


func _players_under(n: Node) -> int:
	var c := 1 if (n is AudioStreamPlayer or n is AudioStreamPlayer3D) else 0
	for ch in n.get_children():
		c += _players_under(ch)
	return c


# --- signal modes -----------------------------------------------------------------

func _probe() -> void:
	# Calibrated emissions, no variation, human stopped; player in the open
	# aisle with a clear line along x.
	_human.stop()
	_audio.variation = false
	var at := Vector2(0.7, 0.78)
	_place(at)
	_rig.yaw = 0.0
	await _seconds(1.0)
	_mark("ambiance seule")
	await _seconds(1.5)
	var ear_y := 0.0
	var near_e := Vector3(at.x + 0.3, ear_y, at.y)
	var near_w := Vector3(at.x - 0.3, ear_y, at.y)
	var far_e := Vector3(at.x + 1.2, ear_y, at.y)
	for spec in [
			["pas 0,30 m à droite (est, regard nord)", 0.0, near_e],
			["pas 0,30 m à gauche (ouest, regard nord)", 0.0, near_w],
			["pas 1,20 m à droite (est)", 0.0, far_e],
			["pas 0,30 m est, regard sud (donc à gauche)", PI, near_e],
			["pas 0,30 m devant (est, regard est)", -PI / 2.0, near_e]]:
		_rig.yaw = spec[1]
		await _seconds(0.3)
		_mark(spec[0])
		_audio._on_footstep(spec[2], 1.0)
		await _seconds(1.0)
	# Same step with the camera pulled in to 2 cm, then back.
	_rig.yaw = 0.0
	_rig.desired_distance = 0.02
	await _seconds(0.6)
	_mark("pas 0,30 m à droite, caméra à 2 cm")
	_audio._on_footstep(near_e, 1.0)
	await _seconds(1.0)
	_rig.desired_distance = 0.12
	# Occlusion: under the cabinets, the step 0.3 m away behind the plinth.
	_place(Vector2(0.7, 0.45))
	_rig.yaw = PI / 2.0
	await _seconds(0.6)
	_mark("pas 0,30 m derrière la plinthe (occulté)")
	_audio._on_footstep(Vector3(0.7, 0.0, 0.75), 1.0)
	await _seconds(1.0)
	# Same geometry in the open (west of the chair): source 0.3 m south,
	# looking west, so on the left as above.
	_place(Vector2(0.3, 0.78))
	_rig.yaw = PI / 2.0
	await _seconds(0.6)
	_mark("pas 0,30 m à découvert (même disposition)")
	_audio._on_footstep(Vector3(0.3, 0.0, 1.08), 1.0)
	await _seconds(1.0)
	# Each other sound once, human 0.3 m to the right, levels, clipping.
	_place(at)
	_rig.yaw = 0.0
	await _seconds(0.3)
	_human.global_position = Vector3(at.x + 0.3, 0.0, at.y)
	_human.capture_point = Vector3(at.x + 0.05, 0.0, at.y)
	_audio._on_inspecting(Vector3.ZERO)
	_mark("fouille")
	await _seconds(1.2)
	_mark("annonce")
	_audio._on_capture_started(_human.capture_point, 0.035, 0.7)
	await _seconds(0.7)
	_audio._on_capture_resolved(false)
	await _seconds(1.0)
	_mark("attrapé (final)")
	_audio._on_outcome("capture")
	await _seconds(1.2)
	_audio._final_ui.play()
	_mark("réussite (final, non positionnel)")
	await _seconds(1.2)


## Threat scenario, heard and seen from the cockroach, real AI, player
## commands only (no teleport after the first placement).
func _clip() -> void:
	# 1. Approach out of view and close passes: under the cabinets, facing
	# the wall; the human comes from behind on the right, stops at the
	# sink 0.3 m behind the plinth, goes west, comes back, goes east.
	_place(Vector2(0.75, 0.40))
	_rig.snap_to_target(0.0)
	_mark("caché sous les meubles, face au mur")
	await _until(func() -> bool: return _human._waypoint == 5 and _human._pause_left > 0.0, 60 * 20)
	# 2. Out through the gap while the human is at the fridge; seen when it
	# walks west again, flight to the plinth recess; the human searches
	# right next to it.
	_mark("sortie par la brèche")
	await _walk([Vector2(0.75, 0.62), Vector2(0.62, 0.85)], true)
	_rig.yaw = -PI / 2.0
	await _until(func() -> bool: return _human.state == HumanBrain.State.CONFIRMED, 60 * 20)
	_mark("repéré : fuite vers le retrait de plinthe")
	_rig.yaw = 0.0
	_hold(Vector2(0, 1), true)
	await _seconds(2.0)
	_release()
	_rig.yaw = PI
	await _until(func() -> bool: return _human.state == HumanBrain.State.SEARCH, 60 * 5)
	_mark("recherche à côté de la cachette")
	await _until(func() -> bool: return _human.state == HumanBrain.State.ROUTINE, 60 * 15)
	_mark("recherche abandonnée")
	await _seconds(1.0)
	# 3. Out again while the human is at the fridge, then still in the
	# open, facing it: the capture is announced, then resolved.
	await _until(func() -> bool: return _human._waypoint == 5 and _human._pause_left > 0.0, 60 * 20)
	await _walk([Vector2(0.55, 0.80), Vector2(0.5, 0.85)], false)
	_rig.yaw = -PI / 2.0
	_mark("immobile à découvert")
	await _until(func() -> bool: return _threat.result != "", 60 * 30)
	await _seconds(2.5)
	_mark("fin")


func _walk(pts: Array, sprint: bool) -> void:
	var i := 0
	var ticks := 0
	_hold(Vector2(0, 1), sprint)
	while i < pts.size() and ticks < 60 * 30 and _threat.result == "":
		var p := _player.global_position
		var to: Vector2 = pts[i] - Vector2(p.x, p.z)
		if to.length() < 0.012:
			i += 1
			continue
		_rig.yaw = atan2(-to.x, -to.y)
		await tick_done
		ticks += 1
	_release()


func _mark(label: String) -> void:
	print("  %6.2f s  %s" % [_time, label])
	_markers.append({"t": _time, "label": label})


func _save_markers(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("markers.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_markers, "  "))
	f.close()


func _seconds(s: float) -> void:
	await _ticks(int(round(s * 60.0)))


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


func _yaw_toward(p: Vector3) -> float:
	var to := Vector2(p.x - _player.global_position.x, p.z - _player.global_position.z)
	return atan2(-to.x, -to.y)


func _hold(v: Vector2, sprint: bool) -> void:
	_release()
	if v.y > 0: Input.action_press(&"move_forward", v.y)
	if v.y < 0: Input.action_press(&"move_backward", -v.y)
	if sprint: Input.action_press(&"sprint")


func _release() -> void:
	for a in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(a)


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
