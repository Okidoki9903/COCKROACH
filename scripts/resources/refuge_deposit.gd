class_name RefugeDeposit
extends Interactable
## Drop-off inside the refuge. Available only while a crumb is carried; the
## crumb moves to the reserve pile and the session counts it once (the
## crumb's DEPOSITED state is final, so a second press has nothing to do).

signal deposited

@export var session: SessionState
@export var pile: Node3D


func get_prompt(interactor: PlayerInteractor) -> String:
	if interactor.carry.has_item():
		return "Déposer la miette"
	return ""


func interact(interactor: PlayerInteractor) -> bool:
	var crumb := interactor.carry.item
	if crumb == null or not crumb.deposit(pile, pile.global_position):
		return false
	interactor.carry.release()
	session.record_deposit()
	deposited.emit()
	return true
