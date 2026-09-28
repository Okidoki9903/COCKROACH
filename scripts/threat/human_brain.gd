class_name HumanBrain
extends CharacterBody3D
## The human: waypoint routine, sight-based doubt and confirmation, search
## at the last position actually seen, and an announced capture.
##
##   ROUTINE --player seen--> DOUBT --sight for confirm_time--> CONFIRMED
##   DOUBT --doubt faded (unseen)--> ROUTINE
##   CONFIRMED --unseen for lose_time--> SEARCH --seen long enough--> CONFIRMED
##   SEARCH --searched search_duration at the spot, or search_max--> ROUTINE
##   CONFIRMED --player seen within capture_reach, cooldown over--> CAPTURE_WINDUP
##   CAPTURE_WINDUP --after windup_time--> captured (terminal) | CONFIRMED | SEARCH
##
## The last known position changes only on ticks where the player is seen.
## The human moves only inside walk_areas (x/z rectangles of the aisle);
## a target outside them is inspected from the nearest point inside.
## It is on its own collision layer: it never pushes the player, and the
## furniture (layer 1) blocks it. Pausable with the rest of the game.

signal state_changed(state: State)
## For the player's cues and the audio: each stride.
signal footstep(position: Vector3, strength: float)
## An inspection movement during a search: on arriving at the spot, then
## at each reversal of the sweep (the human turns to look elsewhere).
## `point` is the inspected position. For the audio (cloth rustle).
signal inspecting(point: Vector3)
signal capture_started(point: Vector3, radius: float, duration: float)
signal capture_resolved(success: bool)
signal captured

enum State { ROUTINE, DOUBT, CONFIRMED, SEARCH, CAPTURE_WINDUP }

const FOOT_REST_Z := 0.03

@export var tuning: HumanTuning
@export var player: PlayerMotor
## Marker3D children: position, facing while paused (rotation), and
## metadata "pause" (seconds).
@export var route_root: Node3D
## Rectangles (x, z, width, depth) the human may stand in.
@export var walk_areas: Array[Rect2] = []
## Crossing point between walk areas: moves between two areas pass here
## instead of cutting across furniture (straight lines only, no navmesh).
@export var junction := Vector3(1.47, 0.0, 0.745)
## Tests only: no translation or rotation, everything else runs.
@export var pinned := false

var state := State.ROUTINE
## 0..1: sight accumulated toward a confirmation.
var confirmation := 0.0
var has_last_known := false
var last_known := Vector3.ZERO
var unseen_time := 0.0
var search_time := 0.0
var search_total := 0.0
var capture_point := Vector3.ZERO
var windup_left := 0.0
var cooldown_left := 0.0
## False after a terminal outcome: the human stops entirely.
var active := true

var _waypoint := 0
var _pause_left := 0.0
var _stride := 0.0
var _left_foot := true
var _search_base_yaw := 0.0

@onready var perception: HumanPerception = $Perception
@onready var capture_zone: Node3D = $CaptureZone
@onready var _foot_l: Node3D = $Visual/FootL
@onready var _foot_r: Node3D = $Visual/FootR


func _ready() -> void:
	perception.setup(self, tuning, player)
	capture_zone.top_level = true
	capture_zone.visible = false
	if route_root and route_root.get_child_count() > 0:
		var first: Node3D = route_root.get_child(0)
		global_position = Vector3(first.global_position.x, 0.0, first.global_position.z)
		rotation.y = first.global_rotation.y
		_pause_left = _pause_of(first)


func stop() -> void:
	active = false
	velocity = Vector3.ZERO
	capture_zone.visible = false


func _physics_process(delta: float) -> void:
	if not active:
		return
	perception.update()
	var seen := perception.player_visible
	if seen:
		last_known = perception.seen_position
		has_last_known = true
		unseen_time = 0.0
	else:
		unseen_time += delta
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	match state:
		State.ROUTINE:
			if seen:
				_accumulate(true, delta)
				_set_state(State.DOUBT)
			else:
				_accumulate(false, delta)
				_patrol(delta)
		State.DOUBT:
			velocity = Vector3.ZERO
			_accumulate(seen, delta)
			_face_point(last_known, delta)
			if confirmation >= 1.0:
				_set_state(State.CONFIRMED)
			elif confirmation <= 0.0:
				_set_state(State.ROUTINE)
		State.CONFIRMED:
			if seen and _can_start_capture():
				_start_capture()
			elif not seen and unseen_time > tuning.lose_time:
				search_time = 0.0
				search_total = 0.0
				_set_state(State.SEARCH)
			else:
				_approach(delta)
		State.SEARCH:
			_accumulate(seen, delta)
			if confirmation >= 1.0:
				_set_state(State.CONFIRMED)
			else:
				_search(delta)
		State.CAPTURE_WINDUP:
			windup_left -= delta
			_face_point(capture_point, delta)
			if windup_left <= 0.0:
				_resolve_capture()


# --- states -----------------------------------------------------------------

func _accumulate(seen: bool, delta: float) -> void:
	if seen:
		confirmation = minf(confirmation + delta / tuning.confirm_time, 1.0)
	else:
		confirmation = maxf(confirmation - delta / tuning.forget_time, 0.0)


func _patrol(delta: float) -> void:
	if route_root == null or route_root.get_child_count() == 0:
		return
	var wp: Node3D = route_root.get_child(_waypoint)
	if _pause_left > 0.0:
		velocity = Vector3.ZERO
		_pause_left -= delta
		_turn_to(wp.global_rotation.y, delta)
		if _pause_left <= 0.0:
			_waypoint = (_waypoint + 1) % route_root.get_child_count()
		return
	if _move_to(wp.global_position, tuning.walk_speed, delta):
		_pause_left = maxf(_pause_of(wp), 0.001)


func _approach(delta: float) -> void:
	var goal := accessible_point(last_known)
	var flat := Vector2(last_known.x - global_position.x, last_known.z - global_position.z)
	if flat.length() > tuning.capture_reach * 0.8:
		_move_to(goal, tuning.approach_speed, delta)
	_face_point(last_known, delta)


func _search(delta: float) -> void:
	search_total += delta
	var goal := accessible_point(last_known)
	if _flat_distance(global_position, goal) > tuning.arrive_distance:
		_move_to(goal, tuning.walk_speed, delta)
		_search_base_yaw = _yaw_to(last_known)
	else:
		velocity = Vector3.ZERO
		var before := search_time
		search_time += delta
		if before == 0.0 or _sweep_half(before) != _sweep_half(search_time):
			inspecting.emit(last_known)
		var sweep := deg_to_rad(tuning.search_sweep) * sin(search_time / tuning.search_duration * TAU)
		_turn_to(_search_base_yaw + sweep, delta)
	if search_time >= tuning.search_duration or search_total >= tuning.search_max:
		confirmation = 0.0
		_waypoint = _nearest_waypoint()
		_pause_left = 0.0
		_set_state(State.ROUTINE)


## Index of the sweep half in progress: changes when sin() turns back
## (search_time = 1/4 and 3/4 of search_duration).
func _sweep_half(t: float) -> int:
	return floori(t / tuning.search_duration * 2.0 - 0.5)


func _can_start_capture() -> bool:
	return cooldown_left <= 0.0 and _flat_distance(global_position, player.global_position) <= tuning.capture_reach


func _start_capture() -> void:
	var v := Vector3(player.velocity.x, 0.0, player.velocity.z)
	# Frozen at the start: where the player is, plus part of the move it is
	# making now. It is never updated during the gesture.
	capture_point = player.global_position + v * tuning.windup_time * tuning.lead
	capture_point.y = player.global_position.y
	windup_left = tuning.windup_time
	velocity = Vector3.ZERO
	capture_zone.global_position = capture_point + Vector3.UP * 0.0015
	capture_zone.scale = Vector3(tuning.capture_radius, 1.0, tuning.capture_radius) / 0.05
	capture_zone.visible = true
	_set_state(State.CAPTURE_WINDUP)
	capture_started.emit(capture_point, tuning.capture_radius, tuning.windup_time)


func _resolve_capture() -> void:
	capture_zone.visible = false
	var p := player.global_position
	var in_zone := _flat_distance(p, capture_point) <= tuning.capture_radius
	var in_reach := _flat_distance(global_position, capture_point) <= tuning.capture_reach + tuning.capture_radius
	var success := in_zone and in_reach and _open_from_above(capture_point) and _open_from_above(p)
	capture_resolved.emit(success)
	if success:
		stop()
		captured.emit()
		return
	cooldown_left = tuning.capture_cooldown
	_set_state(State.CONFIRMED if perception.player_visible else State.SEARCH)


## Nothing between a hand coming from above and the floor point.
func _open_from_above(point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.6, point + Vector3.UP * 0.003, perception.occlusion_mask)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- movement -----------------------------------------------------------------

## Nearest point inside walk_areas (y = 0).
func accessible_point(p: Vector3) -> Vector3:
	var best := Vector3(p.x, 0.0, p.z)
	var best_d := INF
	for r in walk_areas:
		var c := Vector3(clampf(p.x, r.position.x, r.end.x), 0.0, clampf(p.z, r.position.y, r.end.y))
		var d := _flat_distance(c, p)
		if d < best_d:
			best_d = d
			best = c
	return best


func is_accessible(p: Vector3) -> bool:
	return _flat_distance(accessible_point(p), p) < 0.001


func _move_to(goal: Vector3, speed: float, delta: float) -> bool:
	var final_goal := goal
	goal = _via_junction(goal)
	var to := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	# The junction is only a way point: reach it exactly (the step below
	# never overshoots), never "arrive" there.
	if to.length() <= tuning.arrive_distance and goal == final_goal:
		velocity = Vector3.ZERO
		return true
	if pinned:
		return false
	var step := minf(speed, to.length() / delta)
	velocity = to.normalized() * step
	var before := global_position
	move_and_slide()
	_turn_to(_yaw_of(to), delta)
	_step_feet(_flat_distance(before, global_position))
	return false


## Goes through the junction when current position and goal are in
## different walk areas. Once inside the junction's own area it heads
## straight for the goal (a distance threshold here made the human
## oscillate at the edge of the arrival radius).
func _via_junction(goal: Vector3) -> Vector3:
	var here := _area_index(global_position)
	var there := _area_index(goal)
	if here >= 0 and there >= 0 and here != there and here != _area_index(junction):
		return junction
	return goal


func _area_index(p: Vector3) -> int:
	for i in walk_areas.size():
		var r := walk_areas[i].grow(0.005)
		if r.has_point(Vector2(p.x, p.z)):
			return i
	return -1


func _step_feet(moved: float) -> void:
	_stride += moved
	var phase := _stride / tuning.stride_length
	var swing := sin(phase * PI) * 0.09
	# Feet rest 3 cm behind the body centre: standing at the counter, the
	# toes stop at the cabinet front instead of entering the plinth recess.
	_foot_l.position.z = FOOT_REST_Z + (-swing if _left_foot else swing * 0.3)
	_foot_r.position.z = FOOT_REST_Z + (swing * 0.3 if _left_foot else -swing)
	if _stride >= tuning.stride_length:
		_stride -= tuning.stride_length
		var foot := _foot_l if _left_foot else _foot_r
		footstep.emit(foot.global_position, 1.0)
		_left_foot = not _left_foot


func _face_point(p: Vector3, delta: float) -> void:
	if _flat_distance(p, global_position) > 0.01:
		_turn_to(_yaw_to(p), delta)


func _turn_to(yaw: float, delta: float) -> void:
	if not pinned:
		rotation.y = rotate_toward(rotation.y, yaw, tuning.turn_speed * delta)


func _yaw_to(p: Vector3) -> float:
	return _yaw_of(p - global_position)


func _yaw_of(v: Vector3) -> float:
	return atan2(-v.x, -v.z)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _nearest_waypoint() -> int:
	var best := 0
	var best_d := INF
	for i in route_root.get_child_count():
		var d := _flat_distance((route_root.get_child(i) as Node3D).global_position, global_position)
		if d < best_d:
			best_d = d
			best = i
	return best


func _pause_of(n: Node) -> float:
	return float(n.get_meta(&"pause", 0.0))


func _set_state(s: State) -> void:
	if s != state:
		state = s
		state_changed.emit(s)
