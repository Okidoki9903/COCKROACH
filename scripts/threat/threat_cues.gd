extends CanvasLayer
## Player-facing approach cue: a short "vibration" pulse when one of the
## human's footsteps lands near the cockroach. Strength falls off with
## distance; no direction, no position, nothing through walls beyond what
## a floor vibration would carry. The same footstep events will feed the
## audio task later.

signal felt(strength: float)

@export var human: HumanBrain
@export var player: PlayerMotor

## Last pulse strength (0..1), decaying; for tests and display.
var pulse := 0.0

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 24.0
	_label.offset_top = -70.0
	_label.text = "〰 vibrations 〰"
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.6))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.modulate.a = 0.0
	add_child(_label)
	human.footstep.connect(_on_footstep)


func _on_footstep(at: Vector3, strength: float) -> void:
	var d := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
	var r: float = human.tuning.cue_range
	if d >= r:
		return
	var s := strength * (1.0 - d / r)
	pulse = maxf(pulse, s)
	felt.emit(s)


func _process(delta: float) -> void:
	if not get_tree().paused:
		pulse = maxf(pulse - delta * 2.5, 0.0)
	_label.modulate.a = clampf(pulse * 1.5, 0.0, 1.0)
	_label.scale = Vector2.ONE * (1.0 + pulse * 0.3)
