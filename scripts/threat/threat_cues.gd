extends CanvasLayer
## Instinct cues: what the cockroach senses of the human, drawn on screen.
## Presentation only: it listens to events that already exist (footstep,
## inspecting, capture_started, capture_resolved, the attempt's outcome)
## and never reads or changes the AI state.
##
##   footstep within cue_range     -> brief wave at an approximate
##                                    direction (8 sectors, relative to the
##                                    look), strength from proximity; the
##                                    direction is frozen at the event, never
##                                    updated from the human between steps
##   inspecting within inspect_range -> distinct "search" mark, same rules
##   capture_started               -> on-screen warning with a draining bar
##                                    (visible even if the ground zone is
##                                    off screen) and a filling disc inside
##                                    the ground zone
##   capture_resolved(false)       -> "ESQUIVÉ" ; attempt ended during the
##                                    announce -> "ANNULÉE"
##   exposure (optional zone)      -> "exposed to the light" badge, which
##                                    never means "spotted"
##
## Symbols and words tell the cues apart, never colour alone. Settings:
## InstinctSettings (intensity, reduced motion, reinforced for no sound).
## Pausable: nothing progresses while paused, and no event is produced then.

## A footstep felt, with its strength (0..1), as before task J.
signal felt(strength: float)
## Every cue actually shown: kind (&"pas", &"fouille", &"attaque",
## &"esquive", &"annulee"), sector (0 = ahead, clockwise; -1 if none).
signal shown(kind: StringName, sector: int, strength: float)

@export var human: HumanBrain
@export var player: PlayerMotor
@export var rig: CameraRig
@export var threat: KitchenThreat
## Optional (kitchen_instinct): shows the exposure badge.
@export var exposure: ExposureZone

@export_group("Cues")
## Inspection felt within this distance of the human's body.
@export var inspect_range := 0.8
@export var sectors := 8
## Seconds on screen (x1.5 when reinforced).
@export var step_time := 0.6
@export var inspect_time := 1.2
@export var result_time := 1.2

## Last footstep strength (0..1), decaying; for tests and display.
var pulse := 0.0
## Active direction cues: {kind, sector, strength, age, life}.
var cues: Array[Dictionary] = []
## "" | "attaque" | "esquive" | "annulee"
var warning := ""
var warning_left := 0.0
var warning_total := 0.0
var capture_point := Vector3.ZERO
var finished := false

var _canvas: Control
var _fill: MeshInstance3D
var _exposed_badge: Label


func _ready() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_cues)
	add_child(_canvas)
	_exposed_badge = Label.new()
	_exposed_badge.text = "☀ Exposé à la lumière"
	_exposed_badge.offset_left = 16.0
	_exposed_badge.offset_top = 60.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	box.set_content_margin_all(6.0)
	_exposed_badge.add_theme_stylebox_override(&"normal", box)
	_exposed_badge.add_theme_font_size_override(&"font_size", 22)
	_exposed_badge.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.7))
	_exposed_badge.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_exposed_badge.add_theme_constant_override(&"outline_size", 5)
	_exposed_badge.visible = false
	add_child(_exposed_badge)
	_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.0006
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.0, 0.0, 0.75)
	disc.material = mat
	_fill.mesh = disc
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill.top_level = true
	_fill.visible = false
	human.add_child(_fill)
	human.footstep.connect(_on_footstep)
	human.inspecting.connect(_on_inspecting)
	human.capture_started.connect(_on_capture_started)
	human.capture_resolved.connect(_on_capture_resolved)
	if threat:
		threat.outcome.connect(_on_outcome)


# --- events -------------------------------------------------------------------

func _on_footstep(at: Vector3, strength: float) -> void:
	if finished:
		return
	var d := _flat(at, player.global_position)
	var r: float = human.tuning.cue_range
	if d >= r:
		return
	var s := strength * (1.0 - d / r)
	pulse = maxf(pulse, s)
	felt.emit(s)
	_add(&"pas", sector_of(at), s, step_time)


func _on_inspecting(_point: Vector3) -> void:
	if finished:
		return
	var body := human.global_position
	var d := _flat(body, player.global_position)
	if d >= inspect_range:
		return
	_add(&"fouille", sector_of(body), 1.0 - d / inspect_range, inspect_time)


func _on_capture_started(point: Vector3, radius: float, duration: float) -> void:
	if finished:
		return
	capture_point = point
	warning = "attaque"
	warning_total = duration
	warning_left = duration
	_fill.global_position = point + Vector3.UP * 0.002
	_fill.scale = Vector3(0.0001, 1.0, 0.0001)
	_fill.set_meta(&"radius", radius)
	_fill.visible = true
	shown.emit(&"attaque", sector_of(point), 1.0)


func _on_capture_resolved(success: bool) -> void:
	_fill.visible = false
	if finished or success:
		return
	_set_result("esquive")


func _on_outcome(_kind: String) -> void:
	var interrupted := warning == "attaque" and human.state == HumanBrain.State.CAPTURE_WINDUP
	finished = true
	cues.clear()
	pulse = 0.0
	_fill.visible = false
	warning = ""
	# An announce still running when the attempt ends another way (the
	# outing succeeded) is shown as cancelled; a capture's own result is
	# the end screen.
	if interrupted and _kind != "capture":
		_set_result("annulee")


func _set_result(kind: String) -> void:
	warning = kind
	warning_total = result_time * _life_scale()
	warning_left = warning_total
	shown.emit(StringName(kind), -1, 1.0)


func _add(kind: StringName, sector: int, strength: float, life: float) -> void:
	cues.append({"kind": kind, "sector": sector, "strength": clampf(strength, 0.0, 1.0), "age": 0.0, "life": life * _life_scale()})
	shown.emit(kind, sector, strength)


## Approximate direction of a world point, relative to the look: 0 is
## ahead, then clockwise (2 = right with 8 sectors, 4 = behind).
func sector_of(at: Vector3) -> int:
	var v := Vector2(at.x - player.global_position.x, at.z - player.global_position.z)
	var fwd := Vector2(-sin(rig.yaw), -cos(rig.yaw))
	var right := Vector2(cos(rig.yaw), -sin(rig.yaw))
	var a := atan2(v.dot(right), v.dot(fwd))
	return posmod(roundi(a / TAU * sectors), sectors)


func _life_scale() -> float:
	return 1.5 if InstinctSettings.reinforced else 1.0


# --- progression ------------------------------------------------------------------

func _process(delta: float) -> void:
	# Only runs when the game runs (pausable): nothing ages in pause.
	pulse = maxf(pulse - delta * 2.5, 0.0)
	for c in cues:
		c.age += delta
	cues = cues.filter(func(c: Dictionary) -> bool: return c.age < c.life)
	if warning != "":
		warning_left -= delta
		if warning == "attaque" and _fill.visible:
			var k := clampf(1.0 - warning_left / warning_total, 0.0, 1.0)
			var r: float = _fill.get_meta(&"radius", 0.035) * k
			_fill.scale = Vector3(maxf(r, 0.0001), 1.0, maxf(r, 0.0001))
		if warning_left <= 0.0 and warning != "attaque":
			warning = ""
	if exposure:
		_exposed_badge.visible = not finished and exposure.is_player_exposed()
	_canvas.queue_redraw()


# --- drawing ----------------------------------------------------------------------

func _draw_cues() -> void:
	var size := _canvas.size
	var centre := size * 0.5
	var font := ThemeDB.fallback_font
	var big := InstinctSettings.reinforced
	for c in cues:
		var a := TAU * float(c.sector) / sectors
		var out := Vector2(sin(a), -cos(a))
		var pos := centre + Vector2(out.x * size.x * 0.36, out.y * size.y * 0.34)
		var look := cue_look(c)
		var alpha := look.x
		var sc := look.y
		var ang := out.angle()
		if c.kind == &"pas":
			var col := Color(1.0, 0.85, 0.55, alpha)
			for i in 3:
				_canvas.draw_arc(pos, (15.0 + 12.0 * i) * sc, ang - 0.7, ang + 0.7, 12, col, 4.5 * sc)
			_label(font, pos + Vector2(0, 46 * sc), "〰 pas", col, big)
		else:
			var col := Color(0.6, 0.95, 1.0, alpha)
			for i in 8:
				var s := TAU * i / 8.0
				_canvas.draw_arc(pos, 27.0 * sc, s, s + 0.4, 4, col, 4.5 * sc)
			_canvas.draw_string_outline(font, pos + Vector2(-9, 11) * sc, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * sc), 4, Color(0, 0, 0, col.a))
			_canvas.draw_string(font, pos + Vector2(-9, 11) * sc, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * sc), col)
			_label(font, pos + Vector2(0, 50 * sc), "fouille", col, big)
	if warning != "":
		_draw_warning(font, size)


## (opacity, scale) of a cue now. Opacity is bounded by proximity (never
## invisible, never blinding) and by the intensity setting. Normal: fades
## and grows once over its life (one pulse, no repeat). Reduced motion:
## constant until it disappears.
func cue_look(c: Dictionary) -> Vector2:
	var k: float = c.age / c.life
	var alpha := (0.35 + 0.65 * float(c.strength)) * lerpf(0.4, 1.0, InstinctSettings.intensity)
	var grow := 1.0
	if not InstinctSettings.reduced_motion:
		alpha *= 1.0 - k
		grow = 1.0 + 0.3 * k
	if InstinctSettings.reinforced:
		alpha = maxf(alpha, 0.6)
	return Vector2(alpha, (1.4 if InstinctSettings.reinforced else 1.0) * lerpf(0.7, 1.0, InstinctSettings.intensity) * grow)


func _draw_warning(font: Font, size: Vector2) -> void:
	var w := 420.0
	var top := Vector2(size.x * 0.5 - w * 0.5, 8.0)
	var fs := 30 if InstinctSettings.reinforced else 26
	var text := ""
	var col := Color.WHITE
	match warning:
		"attaque":
			text = "⚠ ATTAQUE — BOUGE !"
			col = Color(1.0, 0.45, 0.35)
		"esquive":
			text = "✓ ESQUIVÉ"
			col = Color(0.75, 1.0, 0.75)
		"annulee":
			text = "— ATTAQUE ANNULÉE"
			col = Color(0.85, 0.85, 0.85)
	_canvas.draw_rect(Rect2(top, Vector2(w, 64)), Color(0, 0, 0, 0.55))
	_canvas.draw_string_outline(font, top + Vector2(0, 32), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 5, Color.BLACK)
	_canvas.draw_string(font, top + Vector2(0, 32), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
	if warning == "attaque":
		# Remaining time of the announce: a bar that empties (not a blink).
		var k := clampf(warning_left / warning_total, 0.0, 1.0)
		_canvas.draw_rect(Rect2(top + Vector2(20, 44), Vector2(w - 40, 10)), Color(1, 1, 1, 0.25))
		_canvas.draw_rect(Rect2(top + Vector2(20, 44), Vector2((w - 40) * k, 10)), col)
		if not zone_on_screen():
			_label(font, top + Vector2(w * 0.5, 84), "zone hors champ : " + ["devant", "devant-droite", "à droite", "derrière-droite", "derrière", "derrière-gauche", "à gauche", "devant-gauche"][sector_of(capture_point) * 8 / sectors], col, true)


## The ground zone is in front of the camera and inside its frame.
func zone_on_screen() -> bool:
	var cam := rig.camera
	return cam.is_position_in_frustum(capture_point)


func _label(font: Font, at: Vector2, text: String, col: Color, big: bool) -> void:
	var fs := 22 if big else 18
	_canvas.draw_string_outline(font, at - Vector2(100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, fs, 4, Color(0, 0, 0, col.a))
	_canvas.draw_string(font, at - Vector2(100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, fs, col)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
