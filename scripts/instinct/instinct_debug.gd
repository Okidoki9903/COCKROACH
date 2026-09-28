extends CanvasLayer
## Diagnostic of the light (kitchen_instinct), shown only with the level
## diagnostic panel (F3): light state, exposure level and body points lit,
## the confirmation multiplier in force, and a button that switches the
## light. No gameplay key.

@export var light: ExposureLight
@export var human: HumanBrain
@export var level_panel: Control

var button: Button
var _label: Label
var _box: VBoxContainer


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_box = VBoxContainer.new()
	_box.anchor_left = 1.0
	_box.anchor_right = 1.0
	_box.offset_left = -330.0
	_box.offset_top = 150.0
	add_child(_box)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	_box.add_child(_label)
	button = Button.new()
	button.text = "Basculer la lumière (diagnostic)"
	button.pressed.connect(light.toggle)
	_box.add_child(button)


func _process(_delta: float) -> void:
	_box.visible = level_panel.visible
	if not _box.visible:
		return
	_label.text = "LUMIÈRE  %s\nexposition %s (%d/3 points éclairés)\nvitesse de confirmation ×%.1f" % [
		"allumée" if light.on else "éteinte",
		"ACCRUE" if light.zone.is_player_exposed() else "de base", light.zone.lit_samples,
		human.confirm_rate_multiplier()]
