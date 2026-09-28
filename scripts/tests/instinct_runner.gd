extends Node
## Instinct cues and light exposure (task J), on kitchen_instinct.tscn and,
## for the historical behaviour, kitchen_threat.tscn.
##   godot --headless --fixed-fps 60 --path . res://scenes/tests/instinct_runner.tscn
## --clip=<dir> (needs rendering, movie writer): approach -> inspection ->
## light -> announced capture, diagnostics hidden. Add --silent for the
## version without sound (Master muted, reinforced cues).

const INSTINCT := preload("res://scenes/levels/kitchen_instinct.tscn")
const THREAT := preload("res://scenes/levels/kitchen_threat.tscn")
const WATCHDOG_SECONDS := 600.0
const HIDDEN_UNDER_CABINET := Vector2(0.5, 0.30)
## Open floor inside the lit disc (centre 0.45, 0.95; radius 0.3).
const OPEN_LIT := Vector2(0.40, 0.85)
## Under the chair seat, still inside the lit disc.
const UNDER_SEAT := Vector2(0.62, 0.95)

signal tick_done
signal frame_done

var _failures := 0
var _checks := 0
var _scene: KitchenThreat
var _human: HumanBrain
var _player: PlayerMotor
var _rig: CameraRig
var _cues
var _light: ExposureLight
var _fresh: KitchenThreat = null
var _shown: Array = []
var _tick := 0
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
	var clip := ""
	var shots := ""
	var silent := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.trim_prefix("--clip=")
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		if a == "--silent":
			silent = true
	InstinctSettings.reset()
	if clip != "":
		if silent:
			AudioServer.set_bus_mute(0, true)
			InstinctSettings.reinforced = true
		_spawn(INSTINCT)
		await _ticks(5)
		await _clip()
		var f := FileAccess.open(clip.path_join("markers%s.json" % ("_sans_son" if silent else "")), FileAccess.WRITE)
		f.store_string(JSON.stringify(_markers, "  "))
		f.close()
		get_tree().quit(0)
		return
	if shots != "":
		_spawn(INSTINCT)
		await _ticks(5)
		await _shots(shots)
		get_tree().quit(0)
		return
	await _historical()
	_spawn(INSTINCT)
	await _ticks(5)
	await _run()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _spawn(scene: PackedScene) -> void:
	var t: KitchenThreat = scene.instantiate()
	t.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(t)
	_bind(t)


func _bind(t: KitchenThreat) -> void:
	_scene = t
	_human = t.get_node("Human")
	_player = t.get_node("Loop/Kitchen/Player")
	_rig = t.get_node("Loop/Kitchen/CameraRig")
	_cues = t.get_node("ThreatCues")
	_light = t.get_node_or_null("ExposureLight")
	t.get_node("Loop/Kitchen/PauseController").capture_mouse = false
	_shown.clear()
	_cues.shown.connect(func(kind: StringName, sector: int, strength: float) -> void:
		_shown.append([kind, sector, strength, _tick])
		_markers.append({"t": _time, "cue": String(kind), "sector": sector}))


func _reset() -> void:
	_fresh = null
	_scene.session_reset.connect(func(f: KitchenThreat) -> void: _fresh = f)
	_scene.reset_session()
	await _ticks(5)
	_bind(_fresh)
	await _ticks(5)


func _count(kind: StringName) -> int:
	var n := 0
	for e in _shown:
		if e[0] == kind:
			n += 1
	return n


## Ticks of continuous sight, human pinned at the sink looking west, until
## CONFIRMED.
func _confirm_ticks(at: Vector2) -> int:
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(HIDDEN_UNDER_CABINET)
	await _ticks(3)
	_place(at)
	for i in 180:
		await tick_done
		if _human.state == HumanBrain.State.CONFIRMED:
			return i + 1
	return -1


# --- historical scene -------------------------------------------------------------

func _historical() -> void:
	_section("scène historique (kitchen_threat, sans zone d'exposition)")
	_spawn(THREAT)
	await _ticks(5)
	_check(_light == null and _human.exposure == null and is_equal_approx(_human.confirm_rate_multiplier(), 1.0), "pas de lumière ni de zone : multiplicateur 1")
	var n := await _confirm_ticks(OPEN_LIT)
	print("  confirmé après %d ticks" % n)
	_check(n == 48, "confirmation en 0,8 s (48 ticks), comme avant")
	_scene.queue_free()
	await _ticks(3)


func _run() -> void:
	_section("lumière : rendu et état logique ensemble")
	var zone: ExposureZone = _light.zone
	var together := true
	for on in [true, false, true]:
		_light.set_on(on)
		together = together and _light.lamp.visible == on and zone.active == on
	_check(together and _light.on, "lampe visible ⇔ zone active (3 bascules)")
	_check(_light.lamp is SpotLight3D and (-_light.lamp.global_basis.z).distance_to(Vector3.DOWN) < 1e-4, "lampe au-dessus de la zone, dirigée vers le sol")
	var t: HumanTuning = _human.tuning
	_check(t.lit_confirm_multiplier == 1.5 and t.capture_radius == 0.035 and t.capture_reach == 0.4 and t.lead == 0.6 and t.windup_time == 0.7 and t.view_range == 1.6 and t.view_half_angle == 60.0, "multiplicateur ×1,5 centralisé ; capture et vue inchangées")

	_section("exposition : découvert, couverture, hors zone")
	_place(OPEN_LIT)
	await _ticks(2)
	var open_on := zone.is_player_exposed()
	var open_samples := zone.lit_samples
	_light.set_on(false)
	await _ticks(2)
	var open_off := zone.is_player_exposed()
	_light.set_on(true)
	_place(UNDER_SEAT)
	await _ticks(2)
	var seat := zone.is_player_exposed()
	_place(Vector2(0.9, 0.80))
	await _ticks(2)
	var outside := zone.is_player_exposed()
	print("  découvert allumé %s (%d/3 points) ; éteint %s ; sous l'assise %s ; hors du disque %s" % [open_on, open_samples, open_off, seat, outside])
	_check(open_on and open_samples == 3 and not open_off, "à découvert : exposé si allumé, pas si éteint")
	_check(not seat, "sous l'assise de la chaise, dans le disque : l'assise bloque la lumière")
	_check(not outside, "hors du disque : exposition de base")

	_section("exposition et confirmation")
	_light.set_on(false)
	var off_ticks := await _confirm_ticks(OPEN_LIT)
	_light.set_on(true)
	var on_ticks := await _confirm_ticks(OPEN_LIT)
	var seat_ticks := await _confirm_ticks(UNDER_SEAT)
	print("  confirmation : éteint %d ticks, allumé %d ticks, sous l'assise allumé %d ticks" % [off_ticks, on_ticks, seat_ticks])
	_check(off_ticks == 48, "éteint : vitesse historique (0,8 s), le cafard n'est pas invisible")
	_check(on_ticks == 32, "allumé et exposé : ×1,5 (0,53 s)")
	_check(seat_ticks == -1 or seat_ticks == 48, "sous l'assise : jamais accéléré (vu : 0,8 s ; sinon pas de confirmation)")
	# A light never lets the human see through an obstacle.
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	# 40 cm screen between the human and the player: cuts the line of
	# sight (it dives from 1.6 m), not the near-vertical light ray.
	var wall := _box(Vector3(0.5, 0.2, 0.85), Vector3(0.01, 0.4, 0.2))
	_place(Vector2(0.44, 0.85))
	await _ticks(60)
	print("  derrière un obstacle, dans la lumière : exposé %s, vu %s, confirmation %.2f" % [zone.is_player_exposed(), _human.perception.player_visible, _human.confirmation])
	_check(zone.is_player_exposed() and not _human.perception.player_visible and _human.confirmation == 0.0, "exposé derrière un obstacle : toujours invisible, confirmation nulle")
	wall.queue_free()
	await _ticks(2)

	_section("bascule pendant une confirmation")
	_light.set_on(false)
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(HIDDEN_UNDER_CABINET)
	await _ticks(3)
	_place(OPEN_LIT)
	await _ticks(20)
	var before := _human.confirmation
	_light.set_on(true)
	var after_toggle := _human.confirmation
	var total := 20
	var monotonic := true
	var prev := before
	for i in 120:
		await tick_done
		total += 1
		monotonic = monotonic and _human.confirmation >= prev
		prev = _human.confirmation
		if _human.state == HumanBrain.State.CONFIRMED:
			break
	print("  %.3f avant la bascule, %.3f juste après ; confirmé après %d ticks au total" % [before, after_toggle, total])
	_check(after_toggle == before and monotonic, "le doute engagé est conservé (pas de remise à zéro)")
	_check(total >= 38 and total <= 40, "puis confirmé plus vite : 20 ticks à ×1 + ≈ 19 à ×1,5")
	await _reset()

	_section("pas : proche, lointain, absent ; direction")
	_light.set_on(false)
	await _pin(Vector2(1.3, 0.72), 0.0)
	_place(Vector2(0.5, 0.85))
	_rig.yaw = 0.0
	await _ticks(2)
	var n0 := _count(&"pas")
	_human.footstep.emit(Vector3(0.8, 0.0, 0.85), 1.0)     # 0.3 m east
	var e_right: Array = _shown[-1]
	_human.footstep.emit(Vector3(0.5, 0.0, 0.55), 1.0)     # 0.3 m north
	var e_ahead: Array = _shown[-1]
	_human.footstep.emit(Vector3(1.5, 0.0, 0.85), 1.0)     # 1.0 m: too far
	var far_ignored := _count(&"pas") == n0 + 2
	_rig.yaw = PI
	_human.footstep.emit(Vector3(0.8, 0.0, 0.85), 1.0)     # east, looking south
	var e_left: Array = _shown[-1]
	print("  est regard nord : secteur %d (force %.2f) ; nord : %d ; est regard sud : %d" % [e_right[1], e_right[2], e_ahead[1], e_left[1]])
	_check(e_right[1] == 2 and e_ahead[1] == 0 and e_left[1] == 6, "direction relative au regard : droite 2, devant 0, gauche 6 après demi-tour")
	_check(far_ignored and absf(e_right[2] - (1.0 - 0.3 / t.cue_range)) < 0.01, "lointain (1 m) ignoré ; force bornée 1 − d / 0,8 m")
	await _ticks(60)
	var still := _count(&"pas")
	_human.global_position = Vector3(0.6, 0.0, 0.74)
	await _ticks(60)
	_check(_cues.cues.is_empty() and _count(&"pas") == still, "sans nouveau pas : aucun indice, même si l'humain se déplace tout près")

	_section("pas réels sur un cycle de routine")
	await _reset()
	_light.set_on(false)
	var felt := [0]
	var events := [0]
	_cues.felt.connect(func(_s: float) -> void: felt[0] += 1)
	_human.footstep.connect(func(_a: Vector3, _s: float) -> void: events[0] += 1)
	_place(Vector2(0.8, 0.45))
	var sector_stable := true
	for i in 60 * 16:
		await tick_done
		for c in _cues.cues:
			sector_stable = sector_stable and c.has("sector")
	print("  %d pas, %d ressentis, %d indices de pas" % [events[0], felt[0], _count(&"pas")])
	_check(events[0] > 0 and felt[0] > 0 and felt[0] < events[0] and _count(&"pas") == felt[0], "un indice par pas proche, aucun pour les pas lointains")

	_section("inspection sans pas")
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(Vector2(0.4, 0.85))
	await _wait_state(HumanBrain.State.CONFIRMED, 120)
	_place(HIDDEN_UNDER_CABINET)
	_human.pinned = false
	var insp := [0]
	_human.inspecting.connect(func(_p: Vector3) -> void: insp[0] += 1)
	var step_during := 0
	var start_f := _count(&"fouille")
	for i in 60 * 14:
		var ns := _count(&"pas")
		await tick_done
		if _human.state == HumanBrain.State.SEARCH and _human.velocity == Vector3.ZERO:
			step_during += _count(&"pas") - ns
		if _human.state == HumanBrain.State.ROUTINE:
			break
	var fouilles := _count(&"fouille") - start_f
	print("  %d inspections, %d indices de fouille, %d indices de pas pendant l'inspection" % [insp[0], fouilles, step_during])
	_check(insp[0] == 3 and fouilles == 3 and step_during == 0, "fouille proche : un indice distinct par inspection, sans pas")
	await _pin(Vector2(1.6, 0.9), 0.0)
	var nf := _count(&"fouille")
	_human.inspecting.emit(Vector3.ZERO)
	_check(_count(&"fouille") == nf, "inspection lointaine (> 0,8 m) : pas d'indice")
	await _ticks(90)
	_check(_cues.cues.is_empty(), "humain immobile sans événement : aucun indice continu")

	_section("capture : hors champ, résolue, annulée")
	await _reset()
	_light.set_on(false)
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	await tick_done
	var fill_start: float = _cues._fill.scale.x
	await _ticks(20)
	var fill_mid: float = _cues._fill.scale.x
	var bar_mid: float = _cues.warning_left
	_check(_cues.warning == "attaque" and _cues._fill.visible and fill_mid > fill_start and bar_mid < 0.7 and bar_mid > 0.2, "annonce : avertissement à l'écran, disque qui se remplit, temps restant %.2f s" % bar_mid)
	await _until(func() -> bool: return _scene.result != "", 60 * 2)
	await tick_done
	_check(_scene.result == "capture" and _cues.warning == "" and _cues.cues.is_empty() and not _cues._fill.visible, "capture : effets transitoires nettoyés, écran de fin")
	await _reset()
	_light.set_on(false)
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	_rig.yaw = _yaw_away(_human.global_position)
	_hold(Vector2(0, 1))
	await _until(func() -> bool: return _human.state != HumanBrain.State.CAPTURE_WINDUP, 60 * 2)
	_release()
	await tick_done
	_check(_cues.warning == "esquive" and _count(&"esquive") == 1 and not _cues._fill.visible, "esquive : « ✓ ESQUIVÉ », distinct du début")
	await _ticks(90)
	_check(_cues.warning == "" or _cues.warning == "attaque", "le résultat disparaît de lui-même")
	await _reset()
	_light.set_on(false)
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	var session: SessionState = _scene.get_node("Loop/Session")
	session.record_drink()
	session.record_deposit()
	await _ticks(2)
	_check(_scene.result == "reussite" and _cues.warning == "annulee" and _count(&"annulee") == 1, "tentative finie pendant l'annonce : « ATTAQUE ANNULÉE »")
	await _reset()
	# Off screen: the camera looks away from a zone behind it (synthetic
	# event, the AI is untouched): the warning does not depend on the view.
	_light.set_on(false)
	await _pin(Vector2(1.3, 0.72), 0.0)
	_place(Vector2(0.5, 0.85))
	_rig.yaw = 0.0
	await frame_done
	_human.capture_started.emit(Vector3(0.5, 0.0, 1.0), 0.035, 0.7)
	await frame_done
	_check(_cues.warning == "attaque" and not _cues.zone_on_screen() and _cues.sector_of(_cues.capture_point) == 4, "zone derrière la caméra : avertissement affiché, direction « derrière »")
	await _reset()

	_section("son coupé, mouvement réduit, renforcé")
	_light.set_on(false)
	AudioServer.set_bus_mute(0, true)
	InstinctSettings.reduced_motion = true
	await _pin(Vector2(1.3, 0.72), 0.0)
	_place(Vector2(0.5, 0.85))
	_human.footstep.emit(Vector3(0.8, 0.0, 0.85), 1.0)
	var c: Dictionary = _cues.cues[-1]
	var look0: Vector2 = _cues.cue_look(c)
	await _ticks(20)
	var look1: Vector2 = _cues.cue_look(c)
	await _ticks(30)
	var gone: bool = _cues.cues.is_empty()
	print("  mouvement réduit : opacité %.2f → %.2f, échelle %.2f → %.2f, disparu à 0,6 s : %s" % [look0.x, look1.x, look0.y, look1.y, gone])
	_check(look0 == look1 and gone, "mouvement réduit : indicateur fixe puis retiré, sans pulsation")
	InstinctSettings.reduced_motion = false
	_human.footstep.emit(Vector3(0.8, 0.0, 0.85), 1.0)
	c = _cues.cues[-1]
	look0 = _cues.cue_look(c)
	await _ticks(20)
	look1 = _cues.cue_look(c)
	_check(look1.x < look0.x and look1.y > look0.y, "mode normal : une seule impulsion (s'estompe et grandit)")
	InstinctSettings.reinforced = true
	InstinctSettings.reduced_motion = true
	_human.footstep.emit(Vector3(0.8, 0.0, 0.85), 1.0)
	c = _cues.cues[-1]
	_check(is_equal_approx(c.life, 0.9) and _cues.cue_look(c).x >= 0.6 and _cues.cue_look(c).y > 1.3, "renforcé : plus grand, plus opaque, 1,5× plus long")
	InstinctSettings.intensity = 0.25
	var faint: Vector2 = _cues.cue_look(c)
	InstinctSettings.reinforced = false
	var faint_plain: Vector2 = _cues.cue_look(c)
	_check(faint_plain.x > 0.0 and faint_plain.x < look0.x and faint.x >= 0.6, "intensité 25 % : plus discret mais visible ; le renforcé garde un plancher")
	InstinctSettings.intensity = 1.0
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	await _ticks(10)
	_check(_cues.warning == "attaque" and _cues._fill.visible, "son coupé + mouvement réduit : l'annonce reste affichée avec sa barre")
	AudioServer.set_bus_mute(0, false)
	InstinctSettings.reset()
	await _reset()

	_section("pause et reprise")
	_light.set_on(false)
	await _pin(Vector2(1.3, 0.72), 0.0)
	_place(Vector2(0.5, 0.85))
	_human.footstep.emit(Vector3(0.8, 0.0, 0.85), 1.0)
	await _ticks(5)
	var age: float = _cues.cues[-1].age
	var n_before := _shown.size()
	get_tree().paused = true
	await _ticks(60)
	var frozen: bool = _cues.cues[-1].age == age
	get_tree().paused = false
	await _ticks(5)
	_check(frozen and _shown.size() == n_before, "pause : l'indice ne vieillit pas ; reprise sans rejouer d'événement")
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(Vector2(0.5, 0.85))
	await _wait_state(HumanBrain.State.CAPTURE_WINDUP, 60 * 20)
	await _ticks(10)
	var left: float = _cues.warning_left
	get_tree().paused = true
	await _ticks(60)
	var frozen_w: bool = _cues.warning_left == left
	get_tree().paused = false
	await _ticks(2)
	_check(frozen_w and _cues.warning_left < left, "pause pendant l'annonce : barre figée, reprend ensuite")
	await _reset()

	_section("manette : jeu, menu de pause, fin de tentative")
	_light.set_on(false)
	await _pin(Vector2(1.7, 0.9), 0.0)
	_place(Vector2(0.4, 0.85))
	await _joy_button(JOY_BUTTON_A, false)
	var p0 := _player.global_position
	var yaw0 := _rig.yaw
	await _joy_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _joy_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _ticks(30)
	await _joy_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	var moved := _flat(p0, _player.global_position)
	print("  stick gauche 0,5 s : %.3f m ; stick droit : lacet %.2f → %.2f rad" % [moved, yaw0, _rig.yaw])
	_check(moved > 0.025 and _rig.yaw < yaw0 - 0.5, "sticks : le cafard avance et la caméra tourne (vers la droite)")
	var hud_prompt: Label = _scene.get_node("Loop/Hud")._prompt
	await _joy_button(JOY_BUTTON_START, true)
	await _joy_button(JOY_BUTTON_START, false)
	await frame_done
	var master: HSlider = _scene.get_node("AudioSettings").sliders[&"Master"]
	var focus0 := get_viewport().gui_get_focus_owner()
	_check(get_tree().paused and focus0 == master, "Start : pause, focus sur le premier curseur de volume (pas sur « Réinitialiser »)")
	await _joy_button(JOY_BUTTON_DPAD_LEFT, true)
	await _joy_button(JOY_BUTTON_DPAD_LEFT, false)
	var lowered := master.value
	await _joy_button(JOY_BUTTON_DPAD_RIGHT, true)
	await _joy_button(JOY_BUTTON_DPAD_RIGHT, false)
	await _joy_button(JOY_BUTTON_DPAD_DOWN, true)
	await _joy_button(JOY_BUTTON_DPAD_DOWN, false)
	var focus1 := get_viewport().gui_get_focus_owner()
	print("  croix gauche : volume %d %% ; croix bas : focus sur %s" % [lowered, focus1.get_path() if focus1 else "rien"])
	_check(lowered == 95.0 and master.value == 100.0 and focus1 != null and focus1 != master, "croix : règle le curseur, puis passe au contrôle suivant")
	await _joy_button(JOY_BUTTON_START, true)
	await _joy_button(JOY_BUTTON_START, false)
	await frame_done
	_check(not get_tree().paused and get_viewport().gui_get_focus_owner() == null and _scene.result == "", "Start : reprise, plus de focus de menu, rien réinitialisé")
	_check(hud_prompt.text == "" or hud_prompt.text.begins_with("[A]"), "invite d'action à la manette : [A]")
	await _pin(Vector2(0.8, 0.72), deg_to_rad(90.0))
	_place(Vector2(0.5, 0.85))
	await _until(func() -> bool: return _scene.result != "", 60 * 20)
	await frame_done
	var restart: Button = _scene.get_node("Outcome/Box/Restart")
	_check(_scene.result == "capture" and get_viewport().gui_get_focus_owner() == restart, "capture : focus sur « Recommencer »")
	_fresh = null
	_scene.session_reset.connect(func(f: KitchenThreat) -> void: _fresh = f)
	await _joy_button(JOY_BUTTON_A, true)
	await _joy_button(JOY_BUTTON_A, false)
	await _ticks(5)
	_check(_fresh != null, "A sur « Recommencer » : nouvelle tentative")
	if _fresh:
		_bind(_fresh)
		await _ticks(5)
	PlayerInput.using_gamepad = false

	_section("recommencer plusieurs fois")
	var base := _links()
	for k in 4:
		await _reset()
	_check(_links() == base, "après 4 redémarrages : %s (inchangé)" % [base])
	_check(_human.exposure == _light.zone and _cues.exposure == _light.zone, "la nouvelle tentative a sa lumière et sa zone")
	_check(_scene.get_node("InstinctSettings") != null and InstinctSettings.intensity == 1.0, "réglages d'instinct dans la pause")


## Connections and nodes that must never be duplicated.
func _links() -> Array:
	var discs := 0
	for ch in _human.get_children():
		if ch is MeshInstance3D and ch.top_level and ch != _human.capture_zone:
			discs += 1
	return [_human.footstep.get_connections().size(), _human.inspecting.get_connections().size(),
		_human.capture_started.get_connections().size(), _scene.outcome.get_connections().size(),
		get_tree().root.find_children("ExposureLight", "", true, false).size(), discs]


func _joy_button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	await frame_done
	await frame_done


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await frame_done


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	_scene.add_child(b)
	b.global_position = at
	return b


# --- light shots --------------------------------------------------------------------

## Top view (diagnostic: logical disc outlined in cyan, seat hidden only
## from the camera's view of the worktop) light off / on, and the
## cockroach's view in the open and under the seat, light on.
func _shots(dir: String) -> void:
	_human.stop()
	_human.global_position = Vector3(1.7, 0.0, 0.9)
	var over := Camera3D.new()
	_scene.add_child(over)
	over.projection = Camera3D.PROJECTION_ORTHOGONAL
	over.size = 0.9
	over.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0.5, 3.0, 0.95))
	for path in ["Loop/Kitchen/Level/Worktop/Mesh", "Loop/Kitchen/Level/CabinetBody/Mesh"]:
		(_scene.get_node(path) as Node3D).visible = false
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = _light.zone.radius - 0.004
	torus.outer_radius = _light.zone.radius
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.1, 0.9, 1.0)
	torus.material = mat
	ring.mesh = torus
	_scene.add_child(ring)
	ring.global_position = _light.zone.global_position + Vector3.UP * 0.002
	for spec in [["dessus_eteinte", false, over, OPEN_LIT], ["dessus_allumee", true, over, OPEN_LIT],
			["cafard_decouvert_allumee", true, _rig.camera, OPEN_LIT], ["cafard_sous_assise_allumee", true, _rig.camera, UNDER_SEAT]]:
		_light.set_on(spec[1])
		_place(spec[3])
		_rig.yaw = PI
		ring.visible = spec[2] == over
		(spec[2] as Camera3D).make_current()
		for i in 20:
			await frame_done
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("%s.png" % spec[0]))
		print("  %s : exposé %s" % [spec[0], _light.zone.is_player_exposed()])


# --- clip ------------------------------------------------------------------------

## Approach -> inspection -> light -> announced capture, from the
## cockroach's camera, diagnostics hidden.
func _clip() -> void:
	_light.set_on(false)
	_place(Vector2(0.75, 0.40))
	_rig.snap_to_target(0.0)
	_mark("caché sous les meubles, lumière éteinte")
	await _until(func() -> bool: return _human._waypoint == 5 and _human._pause_left > 0.0, 60 * 20)
	_mark("sortie")
	await _walk([Vector2(0.75, 0.62), Vector2(0.62, 0.85)], true)
	_rig.yaw = -PI / 2.0
	await _until(func() -> bool: return _human.state == HumanBrain.State.CONFIRMED, 60 * 20)
	_mark("repéré : fuite vers le retrait de plinthe")
	_rig.yaw = 0.0
	_hold(Vector2(0, 1), true)
	await _seconds(2.0)
	_release()
	_rig.yaw = PI
	await _until(func() -> bool: return _human.state == HumanBrain.State.ROUTINE, 60 * 15)
	_mark("recherche finie")
	await _seconds(1.0)
	_light.set_on(true)
	_mark("lumière allumée (diagnostic), cafard encore couvert")
	await _until(func() -> bool: return _human._waypoint == 5 and _human._pause_left > 0.0, 60 * 20)
	await _walk([Vector2(0.55, 0.80), Vector2(0.42, 0.88)], true)
	_rig.yaw = -PI / 2.0
	_mark("immobile à découvert, dans le disque éclairé")
	await _until(func() -> bool: return _scene.result != "", 60 * 30)
	await _seconds(2.0)
	_mark("fin")


func _mark(label: String) -> void:
	print("  %6.2f s  %s" % [_time, label])
	_markers.append({"t": _time, "label": label})


func _walk(pts: Array, sprint: bool) -> void:
	var i := 0
	var ticks := 0
	_hold(Vector2(0, 1), sprint)
	while i < pts.size() and ticks < 60 * 30 and _scene.result == "":
		var p := _player.global_position
		var to: Vector2 = pts[i] - Vector2(p.x, p.z)
		if to.length() < 0.012:
			i += 1
			continue
		_rig.yaw = atan2(-to.x, -to.y)
		await tick_done
		ticks += 1
	_release()


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


func _hold(v: Vector2, sprint := false) -> void:
	_release()
	if v.y > 0: Input.action_press(&"move_forward", v.y)
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
