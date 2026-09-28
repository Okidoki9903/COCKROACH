class_name Interactable
extends Node3D
## Something PlayerInteractor can target. The node origin is the target
## point on the floor; target_radius is its size for the reach test.
## Subclasses override get_prompt() and interact(); an empty prompt means
## "not available now", and such a target is never selected.

@export var target_radius := 0.01


func _enter_tree() -> void:
	add_to_group(&"interactable")


func get_prompt(_interactor: PlayerInteractor) -> String:
	return ""


## Returns true when the interaction happened.
func interact(_interactor: PlayerInteractor) -> bool:
	return false
