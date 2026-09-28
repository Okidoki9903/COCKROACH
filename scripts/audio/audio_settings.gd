class_name AudioSettings
extends CanvasLayer
## Volume of the three buses, shown only while the game is paused (below
## the pause menu). 0-100 % of each bus's nominal level: never above
## 0 dB, so the headroom stays. The values live in the AudioServer for the
## session: kept across restarts, not saved to disk.

const BUSES: Array[Array] = [
	[&"Master", "Général"],
	[&"Threat", "Humain"],
	[&"Ambience", "Ambiance"],
]

## Bus name -> HSlider.
var sliders := {}

var _box: VBoxContainer


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.offset_left = 0.0
	_box.offset_top = 90.0
	add_child(_box)
	var title := Label.new()
	title.text = "Volume"
	_style(title)
	_box.add_child(title)
	for b in BUSES:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = b[1]
		name_label.custom_minimum_size.x = 90.0
		_style(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 5.0
		slider.custom_minimum_size.x = 180.0
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 50.0
		_style(value_label)
		var bus := AudioServer.get_bus_index(b[0])
		slider.value = 0.0 if AudioServer.is_bus_mute(bus) else roundf(db_to_linear(AudioServer.get_bus_volume_db(bus)) * 100.0)
		value_label.text = "%d %%" % slider.value
		slider.value_changed.connect(func(v: float) -> void:
			set_volume(b[0], v)
			value_label.text = "%d %%" % v)
		row.add_child(name_label)
		row.add_child(slider)
		row.add_child(value_label)
		_box.add_child(row)
		sliders[b[0]] = slider
	_box.visible = false


func _process(_delta: float) -> void:
	_box.visible = get_tree().paused


## percent: 0..100 of the bus's nominal level (0 dB); 0 mutes.
static func set_volume(bus_name: StringName, percent: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(bus, percent <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(percent, 0.01, 100.0) / 100.0))


func _style(l: Label) -> void:
	l.add_theme_font_size_override(&"font_size", 16)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 5)
