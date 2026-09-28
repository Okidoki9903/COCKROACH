class_name CameraRig
extends Node3D
## Third-person orbit camera for a centimetre-scale target.
##
## Yaw is this node's rotation, pitch is the Pitch child's. A SpringArm3D
## measures the free distance behind the pivot; the camera moves in at once
## when an obstacle requires it and returns to the desired distance at
## return_speed. The camera is not a child of the arm, so the arm only
## measures and never snaps the camera outward.
##
## Rotation is applied in _physics_process so the arm, which casts during
## the physics step, always measures the current orientation. The camera
## distance is applied in _process, after that step.
##
## Pause is not handled here: PlayerInput returns no look while paused.

@export var target: Node3D:
	set(value):
		target = value
		if is_node_ready():
			_exclude_target()
@export var player_input: PlayerInput

@export_range(-89.0, 0.0) var pitch_min_deg := -70.0
@export_range(0.0, 89.0) var pitch_max_deg := 10.0
## Pivot height above the target origin (the target's feet), in metres.
@export var pivot_height := 0.012
## Distance from pivot to camera when nothing is in the way, in metres.
@export var desired_distance := 0.12:
	set(value):
		desired_distance = value
		if is_node_ready():
			_arm.spring_length = value
## Speed at which the camera moves back out once space frees up, in m/s.
@export var return_speed := 0.3
@export_flags_3d_physics var collision_mask := 1:
	set(value):
		collision_mask = value
		if is_node_ready():
			_arm.collision_mask = value

var yaw := 0.0
var pitch := deg_to_rad(-20.0)
var current_distance := 0.0

var _snap_physics_frame := -1

@onready var _pitch: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/Camera3D


func _init() -> void:
	# Keeps measuring obstacles while paused so a repositioned target is
	# framed correctly; rotation is frozen by PlayerInput, not here.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	top_level = true
	_arm.spring_length = desired_distance
	_arm.collision_mask = collision_mask
	_exclude_target()
	snap_to_target()


## Places the rig on the target immediately, optionally with a new yaw, and
## restarts the distance from the pivot so the camera never sweeps through
## scenery between the old and new position.
func snap_to_target(new_yaw: float = NAN) -> void:
	if not is_nan(new_yaw):
		yaw = new_yaw
	_follow()
	current_distance = 0.0
	camera.position = Vector3.ZERO
	_snap_physics_frame = Engine.get_physics_frames()


## Distance the camera may use, in metres: the arm's measurement minus the
## arm's margin. SpringArm3D applies its margin only to its own children,
## and the camera is not one. The margin also absorbs the shape cast's
## overshoot at this scale (about 2-4 mm, see docs/CAMERA.md).
func get_free_distance() -> float:
	var hit := _arm.get_hit_length()
	if hit >= _arm.spring_length:
		return hit
	return maxf(hit - _arm.margin, 0.0)


func _physics_process(_delta: float) -> void:
	if player_input:
		var look := player_input.consume_look()
		yaw -= look.x
		pitch += look.y
	pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	_follow()


func _process(delta: float) -> void:
	var free := get_free_distance()
	if _snap_physics_frame >= 0:
		# Wait for one physics step at the new position before trusting the arm.
		if Engine.get_physics_frames() <= _snap_physics_frame:
			return
		_snap_physics_frame = -1
		current_distance = free
	elif free < current_distance:
		current_distance = free
	else:
		current_distance = move_toward(current_distance, free, return_speed * delta)
	camera.position = Vector3(0.0, 0.0, current_distance)


func _follow() -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3(0.0, pivot_height, 0.0)
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch.rotation = Vector3(pitch, 0.0, 0.0)


func _exclude_target() -> void:
	_arm.clear_excluded_objects()
	if target == null:
		return
	var stack: Array[Node] = [target]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject3D:
			_arm.add_excluded_object(node.get_rid())
		stack.append_array(node.get_children())
