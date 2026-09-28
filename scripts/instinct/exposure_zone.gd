class_name ExposureZone
extends Node3D
## Gameplay approximation of "standing in the light", not a measure of
## brightness: two explicit levels. INCREASED when the zone is active and
## at least one point of the cockroach's body (the same 3 points the human
## looks at) is inside the lit disc (centre = this node, on the floor) AND
## has a clear line to the lamp. Anything of the level in between (a
## cabinet, the chair seat) keeps the cockroach at BASE.
## Only its controller (ExposureLight) switches it on and off.

enum Level { BASE, INCREASED }

@export var player: PlayerMotor
## The lamp: occlusion rays start here.
@export var light_origin: Node3D
## Radius of the useful lit disc on the floor, metres.
@export var radius := 0.3
@export_flags_3d_physics var occlusion_mask := 1

## Set by ExposureLight only.
var active := false
## Body points lit on the last evaluation (diagnostic).
var lit_samples := 0

var _frame := -1
var _cached := false


func level() -> Level:
	return Level.INCREASED if is_player_exposed() else Level.BASE


## Evaluated at most once per physics tick (the human asks for it while
## deciding); cached for the display.
func is_player_exposed() -> bool:
	var f := Engine.get_physics_frames()
	if f != _frame:
		_frame = f
		_cached = _evaluate()
	return _cached


func invalidate() -> void:
	_frame = -1


func _evaluate() -> bool:
	lit_samples = 0
	if not active or player == null or light_origin == null:
		return false
	var space := get_world_3d().direct_space_state
	var c := global_position
	for p in HumanPerception.body_samples(player):
		if Vector2(p.x - c.x, p.z - c.z).length() > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(light_origin.global_position, p, occlusion_mask)
		if space.intersect_ray(q).is_empty():
			lit_samples += 1
	return lit_samples > 0
