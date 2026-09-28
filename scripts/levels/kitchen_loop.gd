class_name KitchenLoop
extends Node3D
## Root of the playable kitchen session: the kitchen blockout plus the
## resource loop. reset_session() rebuilds everything from the scene file
## (new crumb, empty objectives, player in the refuge). Nothing persists.

signal session_reset(fresh: KitchenLoop)
## Emitted instead of resetting when an enclosing scene owns the reset.
signal reset_requested

## Set by an enclosing scene (e.g. kitchen_threat) that must rebuild more
## than this loop; reset_session() then only asks it to.
var external_reset := false


func reset_session() -> void:
	if external_reset:
		reset_requested.emit()
		return
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()
		return
	# Instanced under something else (tests): swap in a fresh copy.
	var fresh: KitchenLoop = load(scene_file_path).instantiate()
	fresh.process_mode = process_mode
	get_parent().add_child(fresh)
	session_reset.emit(fresh)
	queue_free()
