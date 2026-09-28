class_name KitchenLoop
extends Node3D
## Root of the playable kitchen session: the kitchen blockout plus the
## resource loop. reset_session() rebuilds everything from the scene file
## (new crumb, empty objectives, player in the refuge). Nothing persists.

signal session_reset(fresh: KitchenLoop)


func reset_session() -> void:
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
