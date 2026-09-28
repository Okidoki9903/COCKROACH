extends Node
## Automated check of PlayerInput and PauseController.
## Feeds simulated key events through Input.parse_input_event so the engine
## routes them (InputMap matching, echo flag, _unhandled_input dispatch).
## Run: godot --headless --path . res://scenes/tests/input_test_runner.tscn
## Exit code 0 = all checks passed.

const INPUT_TEST := preload("res://scenes/tests/input_test.tscn")
const EPS := 0.001
const WATCHDOG_SECONDS := 60.0

var _failures := 0
var _checks := 0
var _input: PlayerInput
var _pause: PauseController
var _panel: Label
var _interacts := 0
var _drops := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	# Watchdog: a script error must fail the run, not hang it.
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	var scene := INPUT_TEST.instantiate()
	add_child(scene)
	_input = scene.get_node("PlayerInput")
	_pause = scene.get_node("PauseController")
	_panel = scene.get_node("DebugLayer/InputDebugPanel")
	_input.interact_pressed.connect(func() -> void: _interacts += 1)
	_input.drop_pressed.connect(func() -> void: _drops += 1)
	await _frames()
	await _run()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	_section("idle")
	_expect_vec(Vector2.ZERO)
	_check(not _input.sprint_held, "sprint off at start")

	_section("single directions")
	for c in [[KEY_W, Vector2(0, 1)], [KEY_S, Vector2(0, -1)], [KEY_A, Vector2(-1, 0)], [KEY_D, Vector2(1, 0)]]:
		await _key(c[0], true)
		_expect_vec(c[1], OS.get_keycode_string(c[0]))
		await _key(c[0], false)
		_expect_vec(Vector2.ZERO, "release " + OS.get_keycode_string(c[0]))

	_section("diagonals")
	for pair in [[KEY_W, KEY_D], [KEY_W, KEY_A], [KEY_S, KEY_D], [KEY_S, KEY_A]]:
		await _key(pair[0], true)
		await _key(pair[1], true)
		var v := _input.move_vector
		_check(v.length() <= 1.0 + EPS, "diagonal length <= 1 (got %.4f)" % v.length())
		_check(absf(absf(v.x) - absf(v.y)) < EPS and absf(v.x) > 0.7, "diagonal is 45 deg (got %s)" % v)
		await _key(pair[0], false)
		await _key(pair[1], false)
		_expect_vec(Vector2.ZERO, "release diagonal")

	_section("opposites cancel")
	await _key(KEY_W, true)
	await _key(KEY_S, true)
	_expect_vec(Vector2.ZERO, "W+S")
	await _key(KEY_A, true)
	await _key(KEY_D, true)
	_expect_vec(Vector2.ZERO, "W+S+A+D")
	await _key(KEY_S, false)
	await _key(KEY_A, false)
	_expect_vec(Vector2(1, 1).normalized(), "W+D left after releasing S and A")
	await _key(KEY_W, false)
	await _key(KEY_D, false)
	_expect_vec(Vector2.ZERO, "all released")

	_section("physical keys (AZERTY)")
	# On AZERTY the key labelled Z sits at physical W: keycode Z, physical W.
	await _key_raw(KEY_W, KEY_Z, true)
	_expect_vec(Vector2(0, 1), "AZERTY Z (physical W) = forward")
	await _key_raw(KEY_W, KEY_Z, false)
	# The key labelled W on AZERTY sits at physical Z: must do nothing.
	await _key_raw(KEY_Z, KEY_W, true)
	_expect_vec(Vector2.ZERO, "AZERTY W (physical Z) = nothing")
	await _key_raw(KEY_Z, KEY_W, false)
	# AZERTY Q is physical A (move_left); AZERTY A is physical Q (drop).
	await _key_raw(KEY_A, KEY_Q, true)
	_expect_vec(Vector2(-1, 0), "AZERTY Q (physical A) = left")
	_check(_drops == 0, "AZERTY Q does not drop")
	await _key_raw(KEY_A, KEY_Q, false)

	_section("sprint")
	await _key(KEY_SHIFT, true)
	_check(_input.sprint_held, "sprint held")
	await _key(KEY_SHIFT, true, true)
	_check(_input.sprint_held, "sprint still held during key repeat")
	await _key(KEY_W, true)
	_expect_vec(Vector2(0, 1), "forward while sprinting")
	await _key(KEY_W, false)
	await _key(KEY_SHIFT, false)
	_check(not _input.sprint_held, "sprint released")

	_section("interact / drop once per press")
	_interacts = 0
	_drops = 0
	await _key(KEY_E, true)
	for i in 5:
		await _key(KEY_E, true, true)
	await _key(KEY_E, false)
	_check(_interacts == 1, "interact once with 5 repeats (got %d)" % _interacts)
	await _key(KEY_E, true)
	await _key(KEY_E, false)
	_check(_interacts == 2, "second press counted (got %d)" % _interacts)
	await _key(KEY_Q, true)
	for i in 5:
		await _key(KEY_Q, true, true)
	await _key(KEY_Q, false)
	_check(_drops == 1, "drop once with 5 repeats (got %d)" % _drops)
	_check(_interacts == 2, "drop does not trigger interact")
	_expect_vec(Vector2.ZERO, "drop key does not move")

	_section("pause and resume with Escape")
	await _key(KEY_W, true)
	await _key(KEY_SHIFT, true)
	await _key(KEY_ESCAPE, true)
	for i in 3:
		await _key(KEY_ESCAPE, true, true)
	_check(get_tree().paused, "Escape pauses (repeats do not toggle)")
	_expect_vec(Vector2.ZERO, "move neutral while paused")
	_check(not _input.sprint_held, "sprint neutral while paused")
	await _key(KEY_E, true)
	await _key(KEY_E, false)
	await _key(KEY_Q, true)
	await _key(KEY_Q, false)
	_check(_interacts == 2 and _drops == 1, "no interact/drop while paused")
	_check(_panel.text.contains("PAUSED"), "panel updates while paused")
	await _key(KEY_ESCAPE, false)
	await _key(KEY_ESCAPE, true)
	_check(not get_tree().paused, "Escape resumes")
	await _key(KEY_ESCAPE, false)
	_expect_vec(Vector2(0, 1), "still-held W applies again after resume")
	_check(_input.sprint_held, "still-held sprint applies again after resume")
	_check(_panel.text.contains("running"), "panel shows running")
	await _key(KEY_W, false)
	await _key(KEY_SHIFT, false)

	_section("focus loss")
	await _key(KEY_W, true)
	await _key(KEY_D, true)
	await _key(KEY_SHIFT, true)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames()
	_check(get_tree().paused, "focus loss pauses")
	_expect_vec(Vector2.ZERO, "move cleared on focus loss")
	_check(not _input.sprint_held, "sprint cleared on focus loss")
	_check(not Input.is_action_pressed(&"move_forward"), "held keys released on focus loss")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames()
	_check(get_tree().paused, "focus regain does not resume")
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	_check(not get_tree().paused, "Escape resumes after focus regain")
	_expect_vec(Vector2.ZERO, "no stuck movement after resume")
	_check(not _input.sprint_held, "no stuck sprint after resume")

	_section("gamepad (simulated events, standard SDL layout)")
	await _joy_button(JOY_BUTTON_A, true)
	_check(PlayerInput.using_gamepad, "a pad button switches prompts and menus to gamepad")
	await _joy_button(JOY_BUTTON_A, false)
	await _joy_axis(JOY_AXIS_LEFT_Y, -1.0)
	_expect_vec(Vector2(0, 1), "left stick up = forward")
	await _joy_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _joy_axis(JOY_AXIS_LEFT_X, 1.0)
	_expect_vec(Vector2(1, 0), "left stick right")
	await _joy_axis(JOY_AXIS_LEFT_X, 0.5)
	var half := _input.move_vector.x
	_check(half > 0.3 and half < 0.45, "half tilt is partial, after the 0.2 deadzone (got %.3f)" % half)
	await _joy_axis(JOY_AXIS_LEFT_X, 0.1)
	_expect_vec(Vector2.ZERO, "tilt inside the deadzone")
	await _joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await _joy_button(JOY_BUTTON_DPAD_LEFT, true)
	_expect_vec(Vector2(-1, 0), "D-pad left")
	await _joy_button(JOY_BUTTON_DPAD_LEFT, false)
	await _joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	_check(_input.sprint_held, "RB sprints")
	await _joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_check(_input.sprint_held, "right trigger sprints")
	await _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check(not _input.sprint_held, "sprint released")
	_interacts = 0
	_drops = 0
	await _joy_button(JOY_BUTTON_A, true)
	await _frames(10)
	await _joy_button(JOY_BUTTON_A, false)
	await _joy_button(JOY_BUTTON_B, true)
	await _joy_button(JOY_BUTTON_B, false)
	_check(_interacts == 1 and _drops == 1, "A interacts once while held, B drops (got %d, %d)" % [_interacts, _drops])
	# Right stick: a speed, integrated once per physics tick.
	_input.consume_look()
	await _joy_axis(JOY_AXIS_RIGHT_X, 1.0)
	_input.consume_look()
	for i in 60:
		await get_tree().physics_frame
	var turn := _input.consume_look()
	await _joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	print("  right stick full right for 60 ticks: %.3f rad (speed %.1f rad/s)" % [turn.x, _input.stick_look_speed])
	_check(absf(turn.x - _input.stick_look_speed) < 0.1 and absf(turn.y) < EPS, "right stick turns right at stick_look_speed, once per tick")
	await _joy_axis(JOY_AXIS_RIGHT_Y, -1.0)
	_input.consume_look()
	for i in 10:
		await get_tree().physics_frame
	var up := _input.consume_look()
	await _joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_input.consume_look()
	for i in 10:
		await get_tree().physics_frame
	_check(up.y > 0.3 and _input.consume_look() == Vector2.ZERO, "right stick up looks up; at rest nothing accumulates")
	await _joy_button(JOY_BUTTON_START, true)
	await _joy_button(JOY_BUTTON_START, false)
	_check(get_tree().paused, "Start pauses")
	await _joy_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _joy_axis(JOY_AXIS_RIGHT_X, 1.0)
	for i in 10:
		await get_tree().physics_frame
	_check(_input.move_vector == Vector2.ZERO and _input.consume_look() == Vector2.ZERO, "sticks neutral while paused")
	await _joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _joy_button(JOY_BUTTON_START, true)
	await _joy_button(JOY_BUTTON_START, false)
	_check(not get_tree().paused, "Start resumes")
	_expect_vec(Vector2(0, 1), "still-tilted stick applies again after resume")
	await _joy_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _key(KEY_W, true)
	await _key(KEY_W, false)
	_check(not PlayerInput.using_gamepad, "a key switches back to keyboard")

	_section("marker does not move")
	var marker: Node3D = get_node("InputTest/ScaleTest/CockroachMarker")
	_check(marker.position.is_equal_approx(Vector3(0, 0.003, 0)), "CockroachMarker unchanged")


func _key(physical: Key, pressed: bool, echo := false) -> void:
	await _key_raw(physical, physical, pressed, echo)


func _key_raw(physical: Key, logical: Key, pressed: bool, echo := false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = physical
	e.keycode = logical
	e.pressed = pressed
	e.echo = echo
	Input.parse_input_event(e)
	await _frames()


func _joy_button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	await _frames()


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await _frames()


func _frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func _section(title: String) -> void:
	print("-- ", title)


func _expect_vec(expected: Vector2, label := "") -> void:
	var got := _input.move_vector
	_check(got.distance_to(expected) < EPS, "%s move %s (got %s)" % [label, expected, got])


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
