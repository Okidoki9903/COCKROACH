class_name CarrySlot
extends Node
## Holds zero or one crumb. While it holds one, the player may only walk
## (PlayerMotor.sprint_blocked). Dropping searches a nearby free spot on
## walkable ground at the player's level with physics queries; the crumb is
## placed there statically. If no spot is valid, the crumb stays carried
## and drop_failed is emitted.

signal changed(has_item: bool)
signal dropped
signal drop_failed

@export var player: PlayerMotor
## Parent for crumbs lying on the ground.
@export var level: Node3D
## Distances from the body centre tried for a drop, in metres.
@export var drop_distances: PackedFloat32Array = [0.026, 0.034]
## Angles from the facing direction tried in order, in degrees.
@export var drop_angles: PackedFloat32Array = [0, 35, -35, 70, -70, 110, -110, 180]
@export var max_floor_angle_deg := 35.0
@export_flags_3d_physics var collision_mask := 1

## Crumb footprint used for the free-space test (metres).
const CRUMB_SIZE := Vector3(0.006, 0.004, 0.006)

var item: Crumb = null


func has_item() -> bool:
	return item != null


## Called by Crumb when it becomes carried.
func hold(crumb: Crumb) -> void:
	item = crumb
	_changed()


## Empties the slot and returns what it held.
func release() -> Crumb:
	var c := item
	item = null
	_changed()
	return c


## Tries to put the carried crumb down near the player.
func try_drop() -> bool:
	if item == null:
		return false
	var spot: Variant = find_drop_spot()
	if spot == null:
		drop_failed.emit()
		return false
	var crumb := item
	release()
	crumb.place_on_ground(level, spot, player.visual.global_rotation.y)
	dropped.emit()
	return true


## First valid spot around the player, or null.
func find_drop_spot() -> Variant:
	var space := player.get_world_3d().direct_space_state
	var origin := player.global_position
	var facing := -player.visual.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	for angle in drop_angles:
		var dir := facing.rotated(Vector3.UP, deg_to_rad(angle))
		for d in drop_distances:
			var spot: Variant = _check_spot(space, origin, origin + dir * d)
			if spot != null:
				return spot
	return null


func _check_spot(space: PhysicsDirectSpaceState3D, origin: Vector3, p: Vector3) -> Variant:
	# Ground under the spot, at the player's level (no ledge, no void).
	var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.02, p + Vector3.DOWN * 0.02, collision_mask)
	var hit := space.intersect_ray(down)
	if hit.is_empty():
		return null
	if hit.normal.y < cos(deg_to_rad(max_floor_angle_deg)):
		return null
	if absf(hit.position.y - origin.y) > 0.005:
		return null
	var ground: Vector3 = hit.position
	# Room for the crumb (a ray started inside a wall does not see it).
	var box := BoxShape3D.new()
	box.size = CRUMB_SIZE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = collision_mask
	q.transform = Transform3D(Basis(), ground + Vector3.UP * (CRUMB_SIZE.y / 2.0 + 0.0005))
	if not space.intersect_shape(q, 1).is_empty():
		return null
	# Nothing between the body and the spot.
	var sight := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.004, ground + Vector3.UP * 0.003, collision_mask, [player.get_rid()])
	if not space.intersect_ray(sight).is_empty():
		return null
	return ground


func _changed() -> void:
	if player:
		player.sprint_blocked = item != null
	changed.emit(item != null)
