class_name PlayerMotor
extends CharacterBody3D
## Ground locomotion for the cockroach. Moves relative to the camera's yaw
## only (pitch is ignored), with short linear acceleration and braking.
##
## Runs before CameraRig in the physics step (process_physics_priority -1)
## so the camera follows the position of the current tick, not the last.
## It reads the rig's yaw from the previous tick: one tick of lag on the
## heading only.
##
## The collision shape never rotates; only the Visual child turns toward
## the direction of travel.

@export var player_input: PlayerInput
## Source of the horizontal heading. Without a rig, forward is -Z.
@export var camera_rig: CameraRig

@export_group("Speeds")
## Metres per second.
@export var walk_speed := 0.08
@export var sprint_speed := 0.16
## Seconds to reach the requested speed from rest.
@export var accel_time := 0.1
## Seconds to stop from the current speed once input is released.
@export var stop_time := 0.08

@export_group("Body")
## m/s². Real gravity; the body is small but falls like anything else.
@export var gravity := 9.8
## Radians per second for the visual to face the direction of travel.
@export var turn_speed := 12.0

## Horizontal velocity requested this tick (m/s), for diagnostics.
var requested_velocity := Vector3.ZERO

var _brake_rate := 0.0
var _braking := false

@onready var visual: Node3D = $Visual


func _init() -> void:
	# Explicit: the body must stop while paused even under an ALWAYS parent.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	var sprinting := false
	if player_input:
		input = player_input.move_vector
		sprinting = player_input.sprint_held
	var heading := camera_rig.yaw if camera_rig else 0.0
	# x right, y forward; forward is -Z. Only the yaw is used, so looking
	# down never shortens the horizontal move.
	var wish := Vector3(input.x, 0.0, -input.y).rotated(Vector3.UP, heading)
	var target_speed := sprint_speed if sprinting else walk_speed
	requested_velocity = wish * target_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float
	if wish.is_zero_approx():
		if not _braking:
			_braking = true
			_brake_rate = horizontal.length() / stop_time
		rate = _brake_rate
	else:
		_braking = false
		rate = target_speed / accel_time
	horizontal = horizontal.move_toward(requested_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	_turn_visual(wish, delta)


## Diagnostic reset: puts the body on a transform, clears all motion and
## faces the visual along the transform's yaw.
func reset_to(xform: Transform3D) -> void:
	global_transform = Transform3D(Basis(), xform.origin)
	velocity = Vector3.ZERO
	requested_velocity = Vector3.ZERO
	_braking = false
	_brake_rate = 0.0
	visual.rotation = Vector3(0.0, xform.basis.get_euler().y, 0.0)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _turn_visual(wish: Vector3, delta: float) -> void:
	var moving := Vector3(velocity.x, 0.0, velocity.z)
	if wish.is_zero_approx() or moving.length() < walk_speed * 0.1:
		return
	var target_yaw := atan2(-moving.x, -moving.z)
	visual.rotation.y = rotate_toward(visual.rotation.y, target_yaw, turn_speed * delta)
