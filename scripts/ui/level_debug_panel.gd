extends PanelContainer
## Discreet level diagnostic: position, trip timer and length, and reset
## buttons. F3 (action toggle_debug) hides or shows it. Diagnostic only:
## no gameplay reads it.
##
## Trip timer: starts when the player leaves the refuge (x > 0, the wall
## face), stops within food_radius of the food spot; the same backwards
## for the return. It counts physics time only while the game runs.

@export var player: PlayerMotor
@export var rig: CameraRig
@export var spawns_root: Node3D
@export var food_spot: Node3D
@export var food_radius := 0.06

var last_trip := ""

var _trip := ""
var _trip_time := 0.0
var _trip_length := 0.0
var _last_pos := Vector3.ZERO

@onready var _label: Label = $VBox/Readout
@onready var _buttons: HBoxContainer = $VBox/Buttons


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for marker: Node3D in spawns_root.get_children():
		var button := Button.new()
		button.text = marker.name
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(go_to.bind(marker.name))
		_buttons.add_child(button)
	go_to(spawns_root.get_child(0).name)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		visible = not visible
		get_viewport().set_input_as_handled()


## Diagnostic reset: player on a spawn, zero velocity, camera re-snapped.
func go_to(spawn_name: String) -> void:
	var marker: Node3D = spawns_root.get_node(spawn_name)
	player.reset_to(marker.global_transform)
	rig.snap_to_target(marker.global_rotation.y)
	_trip = ""
	_last_pos = player.global_position


func in_refuge() -> bool:
	return player.global_position.x < 0.0


func at_food() -> bool:
	var d := player.global_position - food_spot.global_position
	return Vector2(d.x, d.z).length() < food_radius


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	var pos := player.global_position
	if _trip == "":
		if in_refuge():
			_trip = "aller?"
		elif at_food():
			_trip = "retour?"
	elif _trip == "aller?" and not in_refuge():
		_start("aller")
	elif _trip == "retour?" and not at_food():
		_start("retour")
	elif _trip == "aller" and at_food():
		_finish("aller")
	elif _trip == "retour" and in_refuge():
		_finish("retour")
	if _trip == "aller" or _trip == "retour":
		_trip_time += delta
		_trip_length += Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos


func _start(kind: String) -> void:
	_trip = kind
	_trip_time = 0.0
	_trip_length = 0.0


func _finish(kind: String) -> void:
	last_trip = "%s : %.1f s, %.2f m" % [kind, _trip_time, _trip_length]
	_trip = ""


func _process(_delta: float) -> void:
	if not visible:
		return
	var p := player.global_position
	var running := ""
	if _trip == "aller" or _trip == "retour":
		running = "%s en cours : %.1f s, %.2f m" % [_trip, _trip_time, _trip_length]
	_label.text = "pos (%.2f, %.2f)  %.3f m/s\n%s\ndernier %s\n[F3] masquer · [Échap] pause" % [
		p.x, p.z, player.horizontal_speed(), running, last_trip if last_trip != "" else "—",
	]
