class_name FoodSource
extends Interactable
## Fixed biscuit (a visual of the kitchen blockout) holding the session's
## single crumb. BiscuitBody gives the biscuit the collision the blockout
## visual lacks, so neither the body nor the camera passes through it. The biscuit stays; only the crumb on top leaves. The
## Available node (a pale halo) is shown only while the crumb is here.

@export var crumb: Crumb
@export var available_marker: Node3D


func _ready() -> void:
	crumb.state_changed.connect(func(_s) -> void: _refresh())
	_refresh()


func is_available() -> bool:
	return crumb.state == Crumb.State.AT_SOURCE


func get_prompt(interactor: PlayerInteractor) -> String:
	if is_available() and not interactor.carry.has_item():
		return "Prélever une miette"
	return ""


func interact(interactor: PlayerInteractor) -> bool:
	return crumb.take_from_source(interactor.carry)


func _refresh() -> void:
	if available_marker:
		available_marker.visible = is_available()
