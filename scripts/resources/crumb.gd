class_name Crumb
extends Interactable
## The one crumb of the session. It owns its state; every transition is
## checked, so it can never be duplicated, taken twice, or picked up again
## once deposited.
##
##   AT_SOURCE --take_from_source--> CARRIED --place_on_ground--> ON_GROUND
##                                   CARRIED <------pick_up------ ON_GROUND
##                                   CARRIED --deposit--> DEPOSITED (final)
##
## While carried the node is reparented under the player's visual, in front
## of the head. It never has a physics body.

signal state_changed(state: State)

enum State { AT_SOURCE, CARRIED, ON_GROUND, DEPOSITED }

## Local position under the player's Visual node while carried: resting on
## top of the head, so it reads from behind and never reaches further
## forward than the head itself (the head already overhangs the collision
## cylinder; a crumb in front of it went 10.5 mm into a wall).
const CARRY_OFFSET := Vector3(0.0, 0.0075, -0.012)

var state := State.AT_SOURCE


func get_prompt(interactor: PlayerInteractor) -> String:
	if state == State.ON_GROUND and not interactor.carry.has_item():
		return "Reprendre la miette"
	return ""


func interact(interactor: PlayerInteractor) -> bool:
	return pick_up(interactor.carry)


func take_from_source(slot: CarrySlot) -> bool:
	return _to_carried(slot, State.AT_SOURCE)


func pick_up(slot: CarrySlot) -> bool:
	return _to_carried(slot, State.ON_GROUND)


func place_on_ground(level: Node, point: Vector3, yaw: float) -> bool:
	if state != State.CARRIED:
		return false
	reparent(level, false)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), point)
	_set_state(State.ON_GROUND)
	return true


func deposit(level: Node, point: Vector3) -> bool:
	if state != State.CARRIED:
		return false
	reparent(level, false)
	global_transform = Transform3D(Basis(), point)
	_set_state(State.DEPOSITED)
	return true


func _to_carried(slot: CarrySlot, from: State) -> bool:
	if state != from or slot.has_item():
		return false
	reparent(slot.player.visual, false)
	transform = Transform3D(Basis(), CARRY_OFFSET)
	_set_state(State.CARRIED)
	slot.hold(self)
	return true


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)
