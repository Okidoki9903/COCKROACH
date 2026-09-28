class_name WaterPoint
extends Interactable
## Drinking is an instant interaction that records a session event. It can
## be repeated; the session counts the objective once. Possible while
## carrying. The Flash node lights up briefly as confirmation.

signal drunk

@export var session: SessionState
@export var flash: Node3D
@export var flash_time := 0.5

var _flash_left := 0.0


func get_prompt(_interactor: PlayerInteractor) -> String:
	return "Boire"


func interact(_interactor: PlayerInteractor) -> bool:
	session.record_drink()
	drunk.emit()
	_flash_left = flash_time
	if flash:
		flash.visible = true
	return true


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and flash:
			flash.visible = false
