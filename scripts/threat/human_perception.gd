class_name HumanPerception
extends Node
## What the human actually sees of the player this tick. Rays go from the
## eyes to a few points on the cockroach's real body (centre, head, tail)
## and are occluded by the level's collision (layer 1). Range and view cone
## are horizontal, from the body centre and facing. No light, no suspicion:
## the sensitivity is constant (see HumanTuning).

@export_flags_3d_physics var occlusion_mask := 1

var player_visible := false
## Player position on the last tick it was visible (feet).
var seen_position := Vector3.ZERO
## Samples that passed on the last update, for diagnostics.
var visible_samples := 0

var _human: Node3D
var _tuning: HumanTuning
var _player: PlayerMotor


func setup(human: Node3D, tuning: HumanTuning, player: PlayerMotor) -> void:
	_human = human
	_tuning = tuning
	_player = player


func update() -> void:
	visible_samples = 0
	for p in _samples():
		if can_see(p):
			visible_samples += 1
	player_visible = visible_samples > 0
	if player_visible:
		seen_position = _player.global_position


func eye_position() -> Vector3:
	return _human.global_position + Vector3.UP * _tuning.eye_height + _facing() * 0.08


## True if the world point is in range, in the cone and not occluded.
func can_see(point: Vector3) -> bool:
	var centre := _human.global_position
	var flat := Vector2(point.x - centre.x, point.z - centre.z)
	var d := flat.length()
	if d > _tuning.view_range or d < _tuning.near_blind:
		return false
	var f := _facing()
	if flat.normalized().dot(Vector2(f.x, f.z)) < cos(deg_to_rad(_tuning.view_half_angle)):
		return false
	var q := PhysicsRayQueryParameters3D.create(eye_position(), point, occlusion_mask)
	return _human.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _facing() -> Vector3:
	var f := -_human.global_basis.z
	f.y = 0.0
	return f.normalized()


## Points on the cockroach's body: centre, and 13 mm forward and back
## along its visual (the 3 cm body), a few mm above the floor.
func _samples() -> Array[Vector3]:
	var base := _player.global_position
	var along := -_player.visual.global_basis.z
	along.y = 0.0
	along = along.normalized() * 0.013
	var up := Vector3.UP * 0.004
	return [base + up, base + along + up, base - along + up]
