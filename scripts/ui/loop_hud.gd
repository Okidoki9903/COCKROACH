extends CanvasLayer
## Minimal HUD for the resource loop. It only observes: contextual action,
## load, the two objectives, success and short messages. While paused it
## offers the session reset. F3 does not affect it (that is the level
## diagnostic panel).

@export var interactor: PlayerInteractor
@export var carry: CarrySlot
@export var session: SessionState
@export var water: WaterPoint
@export var deposit: RefugeDeposit
@export var loop_root: KitchenLoop
@export var message_time := 1.6

var _prompt: Label
var _load: Label
var _objectives: Label
var _message: Label
var _success: Label
var _pause_box: VBoxContainer
var _message_left := 0.0
var _interact_key := ""
var _drop_key := ""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_interact_key = _key(&"interact")
	_drop_key = _key(&"drop")
	_prompt = _label(Vector2(0.5, 0.82), 22)
	_load = _label(Vector2(0.5, 0.89), 16)
	_message = _label(Vector2(0.5, 0.74), 18)
	_success = _label(Vector2(0.5, 0.2), 30)
	_success.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5))
	_objectives = Label.new()
	_objectives.anchor_left = 1.0
	_objectives.anchor_right = 1.0
	_objectives.offset_left = -300.0
	_objectives.offset_right = -16.0
	_objectives.offset_top = 16.0
	_style(_objectives, 16)
	add_child(_objectives)
	_pause_box = VBoxContainer.new()
	_pause_box.set_anchors_preset(Control.PRESET_CENTER)
	var title := Label.new()
	title.text = "Pause"
	_style(title, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var reset := Button.new()
	reset.text = "Réinitialiser la session"
	reset.pressed.connect(func() -> void: loop_root.reset_session())
	_pause_box.add_child(title)
	_pause_box.add_child(reset)
	add_child(_pause_box)
	carry.drop_failed.connect(func() -> void: _flash("Pas de place pour lâcher ici"))
	carry.dropped.connect(func() -> void: _flash("Miette lâchée"))
	water.drunk.connect(func() -> void: _flash("Tu as bu."))
	deposit.deposited.connect(func() -> void: _flash("Miette déposée au refuge"))
	session.succeeded.connect(func() -> void: _flash("Sortie réussie !"))


func _process(delta: float) -> void:
	var paused := get_tree().paused
	if paused and not _pause_box.visible and PlayerInput.using_gamepad:
		_focus_pause_menu.call_deferred()
	_pause_box.visible = paused
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message.text = ""
	var interact_key := "A" if PlayerInput.using_gamepad else _interact_key
	var drop_key := "B" if PlayerInput.using_gamepad else _drop_key
	_prompt.text = "" if paused or interactor.prompt == "" else "[%s] %s" % [interact_key, interactor.prompt]
	if carry.has_item():
		_load.text = "Charge : une miette — marche seulement · [%s] lâcher" % drop_key
	else:
		_load.text = "Charge : aucune"
	_objectives.text = "Objectifs\n%s Boire\n%s Rapporter une miette au refuge" % [
		"☑" if session.drank else "☐", "☑" if session.reserve > 0 else "☐"]
	_success.text = "Sortie réussie" if session.success else ""


## Gamepad only, when no other menu took the focus (kitchen_loop alone):
## the reset button, so the D-pad and A work in the pause menu.
func _focus_pause_menu() -> void:
	if _pause_box.visible and get_viewport().gui_get_focus_owner() == null:
		for c in _pause_box.get_children():
			if c is Button:
				c.grab_focus()


func _flash(text: String) -> void:
	_message.text = text
	_message_left = message_time


## Key label for an action on the current keyboard layout (A for drop on
## AZERTY). Without a real display server, the physical (QWERTY) name.
func _key(action: StringName) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: Key = KEY_NONE
			if DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode)
			return OS.get_keycode_string(code if code != KEY_NONE else e.physical_keycode)
	return "?"


func _label(anchor: Vector2, size: int) -> Label:
	var l := Label.new()
	l.anchor_left = anchor.x
	l.anchor_right = anchor.x
	l.anchor_top = anchor.y
	l.anchor_bottom = anchor.y
	l.offset_left = -400.0
	l.offset_right = 400.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(l, size)
	add_child(l)
	return l


func _style(l: Label, size: int) -> void:
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 5)
