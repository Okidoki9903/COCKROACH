extends PanelContainer
## Diagnostic panel for the camera test: live camera readout and one
## button per test position. Buttons only teleport the target; they are
## not a movement controller. Usable while paused (mouse released).

@export var rig: CameraRig
@export var target: Node3D
@export var positions_root: Node3D

var current_position := ""

@onready var _label: Label = $VBox/Readout
@onready var _buttons: VBoxContainer = $VBox/Buttons


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for marker: Node3D in positions_root.get_children():
		var button := Button.new()
		button.text = marker.name
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(go_to.bind(marker.name))
		_buttons.add_child(button)
	if positions_root.get_child_count() > 0:
		go_to(positions_root.get_child(0).name)


## Moves the target onto a test position and resets the camera there.
func go_to(position_name: String) -> void:
	var marker: Node3D = positions_root.get_node(position_name)
	target.global_transform = marker.global_transform
	rig.snap_to_target(marker.global_rotation.y)
	current_position = position_name


func _process(_delta: float) -> void:
	var mode := "captured" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "visible"
	_label.text = "position  %s\nyaw  %.1f°   pitch  %.1f°\ndistance  %.3f / free %.3f / desired %.3f m\nmouse  %s   %s\n[Échap] pause : souris libre, boutons actifs" % [
		current_position,
		rad_to_deg(rig.yaw), rad_to_deg(rig.pitch),
		rig.current_distance, rig.get_free_distance(), rig.desired_distance,
		mode, "PAUSED" if get_tree().paused else "running",
	]
