extends PanelContainer
## Compact locomotion readout and one button per test position.
## A button is a diagnostic reset (position, zero velocity, camera snap),
## not a death or save system. Usable while paused (mouse released).

@export var player: PlayerMotor
@export var rig: CameraRig
@export var positions_root: Node3D

var current_position := ""

@onready var _label: Label = $VBox/Readout
@onready var _buttons: GridContainer = $VBox/Buttons


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for marker: Node3D in positions_root.get_children():
		var button := Button.new()
		button.text = marker.name
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(go_to.bind(marker.name))
		_buttons.add_child(button)
	go_to(positions_root.get_child(0).name)


## Resets the player onto a test position and re-snaps the camera behind it.
func go_to(position_name: String) -> void:
	var marker: Node3D = positions_root.get_node(position_name)
	player.reset_to(marker.global_transform)
	rig.snap_to_target(marker.global_rotation.y)
	current_position = position_name


func _process(_delta: float) -> void:
	var p := player.global_position
	var paused := get_tree().paused
	# While paused nothing moves: show 0 rather than the stored velocity.
	var requested := 0.0 if paused else Vector2(player.requested_velocity.x, player.requested_velocity.z).length()
	var actual := 0.0 if paused else player.horizontal_speed()
	_label.text = "demandé %.3f  réel %.3f m/s\nsol %s   %s\npos (%.3f, %.3f, %.3f)\n[Échap] pause · départ : %s" % [
		requested, actual,
		"OUI" if player.is_on_floor() else "non",
		"PAUSED" if paused else "running",
		p.x, p.y, p.z, current_position,
	]
