extends CanvasLayer
## AI diagnostics, shown only while the level diagnostic panel is shown
## (F3). Internal information: state, visibility, confirmation, last known
## position (also as a marker in the world), search time, capture zone.
## Everything disappears when hidden.

@export var human: HumanBrain
@export var level_panel: Control

var _label: Label
var _lkp_marker: MeshInstance3D


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_label = Label.new()
	_label.offset_left = 12.0
	_label.offset_top = 170.0
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	_lkp_marker = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.004
	mesh.bottom_radius = 0.004
	mesh.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.8)
	mesh.material = mat
	_lkp_marker.mesh = mesh
	_lkp_marker.top_level = true
	_lkp_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	human.add_child(_lkp_marker)


func is_shown() -> bool:
	return level_panel.visible


func _process(_delta: float) -> void:
	var shown := is_shown()
	_label.visible = shown
	_lkp_marker.visible = shown and human.has_last_known
	if not shown:
		return
	_lkp_marker.global_position = human.last_known + Vector3.UP * 0.04
	var t: HumanTuning = human.tuning
	var zone := "—"
	if human.state == HumanBrain.State.CAPTURE_WINDUP:
		zone = "(%.2f, %.2f) r %.3f, reste %.2f s" % [human.capture_point.x, human.capture_point.z, t.capture_radius, human.windup_left]
	_label.text = "HUMAIN  %s\nvu %s (%d/3 points)   confirmation %.0f %%\ndernière position connue %s\nrecherche %.1f / %.1f s (total %.1f / %.1f)\nzone de capture %s   recharge %.1f s" % [
		HumanBrain.State.keys()[human.state],
		"OUI" if human.perception.player_visible else "non", human.perception.visible_samples,
		human.confirmation * 100.0,
		"(%.2f, %.2f)" % [human.last_known.x, human.last_known.z] if human.has_last_known else "—",
		human.search_time, t.search_duration, human.search_total, t.search_max,
		zone, human.cooldown_left,
	]
