class_name KitchenThreat
extends Node3D
## Demonstration attempt: the kitchen loop plus the human. Exactly one
## terminal outcome per attempt (captured, or the loop's success). After
## it, the human, the player and the interactions stop, and "Recommencer"
## rebuilds the whole attempt (human included). Nothing is saved.

signal outcome(kind: String)

## Start deep in the refuge: its first 4 cm (the mouth) can be seen from
## the aisle through the 6 cm opening; from about 8 cm in, the refuge
## ceiling hides the player from every point of the human's route.
const START := Vector3(-0.11, 0.0, 0.91)
signal session_reset(fresh: KitchenThreat)

var result := ""

@onready var loop: KitchenLoop = $Loop
@onready var human: HumanBrain = $Human
@onready var _overlay: CanvasLayer = $Outcome
@onready var _message: Label = $Outcome/Box/Message


func _ready() -> void:
	loop.external_reset = true
	loop.reset_requested.connect(reset_session)
	# Diagnostics start hidden in this scene; F3 shows them.
	loop.get_node("Kitchen/DebugLayer/LevelDebugPanel").visible = false
	human.captured.connect(func() -> void: _finish("capture"))
	loop.get_node("Session").succeeded.connect(func() -> void: _finish("reussite"))
	$Outcome/Box/Restart.pressed.connect(reset_session)
	_overlay.visible = false
	var player: PlayerMotor = loop.get_node("Kitchen/Player")
	var start_yaw := deg_to_rad(-90.0)
	player.reset_to(Transform3D(Basis(Vector3.UP, start_yaw), START))
	loop.get_node("Kitchen/CameraRig").snap_to_target(start_yaw)


func _finish(kind: String) -> void:
	if result != "":
		return
	result = kind
	human.stop()
	var player: PlayerMotor = loop.get_node("Kitchen/Player")
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var interactor: PlayerInteractor = loop.get_node("Interactor")
	interactor.process_mode = Node.PROCESS_MODE_DISABLED
	interactor.prompt = ""
	interactor.target = null
	var pause: PauseController = loop.get_node("Kitchen/PauseController")
	pause.capture_mouse = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_message.text = "Attrapé !" if kind == "capture" else "Sortie réussie : tentative terminée"
	_overlay.visible = true
	outcome.emit(kind)


func reset_session() -> void:
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()
		return
	var fresh: KitchenThreat = load(scene_file_path).instantiate()
	fresh.process_mode = process_mode
	get_parent().add_child(fresh)
	session_reset.emit(fresh)
	queue_free()
