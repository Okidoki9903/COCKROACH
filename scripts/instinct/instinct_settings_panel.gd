class_name InstinctSettingsPanel
extends CanvasLayer
## Accessibility settings of the instinct cues, shown only while paused
## (left of the volume panel). Values live in InstinctSettings for the
## session.

var intensity: HSlider
var reduced: CheckBox
var reinforced: CheckBox

var _box: VBoxContainer


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.offset_left = -380.0
	_box.offset_top = 90.0
	add_child(_box)
	_box.add_child(_text("Indices d'instinct"))
	var row := HBoxContainer.new()
	row.add_child(_text("Intensité"))
	intensity = HSlider.new()
	intensity.min_value = 25.0
	intensity.max_value = 100.0
	intensity.step = 25.0
	intensity.custom_minimum_size.x = 140.0
	intensity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intensity.value = InstinctSettings.intensity * 100.0
	var value := _text("%d %%" % intensity.value)
	intensity.value_changed.connect(func(v: float) -> void:
		InstinctSettings.intensity = v / 100.0
		value.text = "%d %%" % v)
	row.add_child(intensity)
	row.add_child(value)
	_box.add_child(row)
	reduced = _check("Mouvement réduit", InstinctSettings.reduced_motion)
	reduced.toggled.connect(func(on: bool) -> void: InstinctSettings.reduced_motion = on)
	reinforced = _check("Indices renforcés (sans son)", InstinctSettings.reinforced)
	reinforced.toggled.connect(func(on: bool) -> void: InstinctSettings.reinforced = on)
	_box.visible = false


func _process(_delta: float) -> void:
	_box.visible = get_tree().paused


func _check(label: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = on
	c.add_theme_font_size_override(&"font_size", 16)
	_box.add_child(c)
	return c


func _text(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override(&"font_size", 16)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 5)
	return l
