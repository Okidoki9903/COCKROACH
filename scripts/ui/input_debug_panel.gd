extends Label
## Diagnostic readout of PlayerInput and pause state. Read-only.

@export var player_input: PlayerInput

var interact_count := 0
var drop_count := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	player_input.interact_pressed.connect(func() -> void: interact_count += 1)
	player_input.drop_pressed.connect(func() -> void: drop_count += 1)


func _process(_delta: float) -> void:
	var v := player_input.move_vector
	text = "move  (%+.2f, %+.2f)  len %.2f\nsprint  %s\ninteract  %d\ndrop  %d\npause  %s" % [
		v.x, v.y, v.length(),
		"ON" if player_input.sprint_held else "off",
		interact_count, drop_count,
		"PAUSED" if get_tree().paused else "running",
	]
