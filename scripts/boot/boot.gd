extends Node
## Entry point: immediately hands over to the first playable scene.

const FIRST_SCENE := "res://scenes/tests/scale_test.tscn"


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(FIRST_SCENE)
