extends Node
## Keeps the player's camera out of the human's shoes and legs. The human
## is not on the camera arm's collision mask (it would make the arm jump
## at every step), and physics bodies attached to the moving feet lagged
## behind the visible feet. So after CameraRig places the camera each
## frame, this checks the camera point against the visible shoe and leg
## boxes and, if inside, moves the camera toward the cockroach until it is
## out; the rig's usual smoothing then brings it back. If even the pivot is
## inside a part (a shoe over the cockroach), that part is hidden.

@export var rig: CameraRig
@export var human: Node3D
## Visible parts to keep the camera out of (paths under the human).
@export var parts: Array[NodePath] = [^"Visual/FootL/Shoe", ^"Visual/FootR/Shoe", ^"Visual/LegL", ^"Visual/LegR"]
@export var margin := 0.004

var corrections := 0

var _parts: Array[MeshInstance3D] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After CameraRig._process (priority 0).
	process_priority = 10


func _ready() -> void:
	for p in parts:
		_parts.append(human.get_node(p))


## Parts hidden this frame because even the pivot is inside them.
var hidden_parts := 0


func _process(_delta: float) -> void:
	var d := rig.current_distance
	if d > 0.0 and _inside(rig.camera.global_position):
		# Step toward the pivot until the camera point is clear of every part.
		var step := 0.004
		while d > 0.0 and _inside(_camera_point(d)):
			d = maxf(d - step, 0.0)
		rig.current_distance = d
		rig.camera.position = Vector3(0.0, 0.0, d)
		corrections += 1
	# A shoe can pass over the cockroach itself (no capture on contact):
	# then no camera distance is clear, and the part is hidden instead.
	hidden_parts = 0
	var cam := rig.camera.global_position
	for m in _parts:
		var inside := m.get_aabb().grow(margin).has_point(m.global_transform.affine_inverse() * cam)
		m.visible = not inside
		hidden_parts += int(inside)


func _camera_point(d: float) -> Vector3:
	return rig.camera.get_parent().to_global(Vector3(0.0, 0.0, d))


func _inside(p: Vector3) -> bool:
	for m in _parts:
		var local := m.global_transform.affine_inverse() * p
		if m.get_aabb().grow(margin).has_point(local):
			return true
	return false
