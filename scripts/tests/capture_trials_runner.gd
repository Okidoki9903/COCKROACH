extends Node
## Capture trials, measured on kitchen_threat.tscn with the real human
## (routine, sight, approach) and the real player commands. They explain
## the escape table of docs/HUMAN_AI.md: what the player was doing when
## the announce started matters, because the aimed point leads a moving
## player. Nothing is tuned here; the checks pin the current rules.
## Run: godot --headless --fixed-fps 60 --path . res://scenes/tests/capture_trials_runner.tscn

const THREAT := preload("res://scenes/levels/kitchen_threat.tscn")
const WATCHDOG_SECONDS := 600.0
const START := Vector2(0.5, 0.85)

signal tick_done

var _failures := 0
var _checks := 0
var _threat: KitchenThreat
var _human: HumanBrain
var _player: PlayerMotor
var _rig: CameraRig
var _fresh: KitchenThreat = null
var _resolved: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000


func _physics_process(_d: float) -> void:
	tick_done.emit()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	var t := THREAT.instantiate()
	t.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(t)
	_bind(t)
	await _ticks(5)
	var t_: HumanTuning = _human.tuning
	print("-- règles : portée %.2f m, rayon %.3f m (diamètre %.1f cm), annonce %.2f s, anticipation %.0f %%, marche %.2f m/s, sprint %.2f m/s" % [
		t_.capture_reach, t_.capture_radius, t_.capture_radius * 200.0, t_.windup_time, t_.lead * 100.0, _player.walk_speed, _player.sprint_speed])
	_check(t_.capture_reach == 0.4 and t_.capture_radius == 0.035 and t_.windup_time == 0.7 and t_.lead == 0.6 and t_.capture_cooldown == 1.0,
		"réglages de capture inchangés (0,40 m ; 3,5 cm ; 0,7 s ; 60 % ; 1 s)")

	# name, walk before the announce, reaction delay (ticks), action during
	# the announce ("perp": 90° to the human->player line, "same": keep
	# going, "stop", "turn": +90° from the current heading, "none")
	var trials := [
		["A0 immobile, part aussitôt", false, 0, "perp", false],
		["A1 immobile, part après 0,20 s", false, 12, "perp", false],
		["A2 immobile, part après 0,30 s", false, 18, "perp", true],
		["B  marche déjà, continue tout droit", true, 0, "same", true],
		["C  marche déjà, s'arrête", true, 0, "stop", true],
		["D  marche déjà, tourne de 90°", true, 0, "turn", false],
	]
	for tr in trials:
		var caught := await _trial(tr[0], tr[1], tr[2], tr[3])
		_check(caught == tr[4], "%s : %s" % [tr[0], "pris" if tr[4] else "s'échappe"])
		await _reset()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _trial(label: String, moving_before: bool, delay: int, action: String) -> bool:
	_place(START)
	var heading := 0.0
	# Wait for the confirmation, then (B, C, D) start walking before the
	# human is in reach, so the player is moving when the announce starts.
	for i in 60 * 30:
		if _human.state == HumanBrain.State.CAPTURE_WINDUP:
			break
		if moving_before and not Input.is_action_pressed(&"move_forward") \
				and _human.state == HumanBrain.State.CONFIRMED and _flat(_human.global_position, _player.global_position) < 0.55:
			heading = _yaw_perp()
			_rig.yaw = heading
			Input.action_press(&"move_forward")
		await tick_done
	if _human.state != HumanBrain.State.CAPTURE_WINDUP:
		_check(false, "%s : annonce jamais lancée" % label)
		return false
	_resolved = []
	_human.capture_resolved.connect(func(ok: bool) -> void: _resolved.append(ok))
	var p0 := _player.global_position
	var h0 := _human.global_position
	var v0 := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var aim := _human.capture_point
	var to_player := Vector2(p0.x - h0.x, p0.z - h0.z).normalized()
	match action:
		"perp":
			heading = _yaw_perp()
		"turn":
			heading += PI / 2.0
		"stop":
			Input.action_release(&"move_forward")
	_rig.yaw = heading
	var moving_during := action != "stop"
	for i in 60:
		if i == delay and moving_during:
			Input.action_press(&"move_forward")
		if not _resolved.is_empty():
			break
		await tick_done
	Input.action_release(&"move_forward")
	var p1 := _player.global_position
	var dir := Vector2(-sin(heading), -cos(heading))
	var caught: bool = _resolved == [true]
	print("  %s\n    départ (%.3f ; %.3f), humain (%.3f ; %.3f) à %.3f m ; vitesse au début %.3f m/s, angle avec humain→cafard %.0f°\n    point visé à %.1f cm du cafard ; pendant l'annonce : %s, direction %.0f° de humain→cafard ; déplacement %.1f cm\n    fin à %.1f cm du point visé (rayon 3,5), dégagé au-dessus : %s → %s" % [
		label, p0.x, p0.z, h0.x, h0.z, _flat(p0, h0), v0.length(),
		rad_to_deg(to_player.angle_to(Vector2(v0.x, v0.z))) if v0.length() > 0.001 else 0.0,
		_flat(aim, p0) * 100.0,
		"arrêt" if action == "stop" else ("marche après %.2f s" % (delay / 60.0)),
		rad_to_deg(to_player.angle_to(dir)), _flat(p1, p0) * 100.0,
		_flat(p1, aim) * 100.0, _human._open_from_above(p1), "PRIS" if caught else "échappé"])
	return caught


func _yaw_perp() -> float:
	var away := Vector2(_player.global_position.x - _human.global_position.x, _player.global_position.z - _human.global_position.z)
	var side := Vector2(-away.y, away.x)
	return atan2(-side.x, -side.y)


# --- helpers -----------------------------------------------------------------

func _bind(t: KitchenThreat) -> void:
	_threat = t
	_human = t.get_node("Human")
	_player = t.get_node("Loop/Kitchen/Player")
	_rig = t.get_node("Loop/Kitchen/CameraRig")
	t.get_node("Loop/Kitchen/PauseController").capture_mouse = false


func _reset() -> void:
	_fresh = null
	_threat.session_reset.connect(func(f: KitchenThreat) -> void: _fresh = f)
	_threat.reset_session()
	await _ticks(5)
	_bind(_fresh)
	await _ticks(5)


func _place(at: Vector2) -> void:
	_player.reset_to(Transform3D(Basis(), Vector3(at.x, 0.0, at.y)))
	_rig.snap_to_target(_rig.yaw)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ticks(n: int) -> void:
	for i in n:
		await tick_done


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
