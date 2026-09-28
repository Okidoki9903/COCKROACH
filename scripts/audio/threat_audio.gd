class_name ThreatAudio
extends Node
## Audio presentation of the human, heard from the cockroach. It only
## listens to events that already exist (HumanBrain signals, the attempt's
## outcome) and turns each one into at most one sound; it never reads or
## changes the AI state, and nothing plays between events: a human that
## stands still is silent.
##
##   footstep          -> one step, at the foot that landed
##   inspecting        -> cloth rustle, at the human's legs
##   capture_started   -> the hand coming down, above the aimed point
##   capture_resolved  -> slap on the floor, only for a miss
##   outcome           -> routine sounds stop, one final sound
##
## The listener sits on the cockroach (not on the camera) and turns with
## the look yaw. Pausable: sounds in progress are suspended with the game
## and continue on resume; the ambience goes on during the pause.

## Every sound actually started (for the diagnostic and the tests).
signal emitted(kind: StringName, at: Vector3, volume_db: float, occluded: bool)

const STEPS: Array[AudioStream] = [
	preload("res://assets/audio/step_a.wav"),
	preload("res://assets/audio/step_b.wav"),
	preload("res://assets/audio/step_c.wav"),
]
const RUSTLE := preload("res://assets/audio/rustle.wav")
const ANNOUNCE := preload("res://assets/audio/capture_announce.wav")
const MISS := preload("res://assets/audio/capture_miss.wav")
const CAUGHT := preload("res://assets/audio/capture_caught.wav")
const SUCCESS := preload("res://assets/audio/outing_success.wav")
const HUM := preload("res://assets/audio/kitchen_hum.wav")

@export var human: HumanBrain
@export var player: PlayerMotor
@export var rig: CameraRig
@export var threat: KitchenThreat

@export_group("Listener")
## Ears above the cockroach's origin (the camera pivot height).
@export var ear_height := 0.012

@export_group("Attenuation")
## Inverse-distance model: full level at unit_size, -6 dB per doubling,
## silent beyond max_distance.
@export var step_unit_size := 0.3
@export var body_unit_size := 0.4
@export var max_distance := 2.6
## Something of the level (layer 1) between the ears and the source:
## fixed attenuation and low-pass, never a mute.
## Stereo spread of the positional sounds (multiplies the project's
## 3D panning strength, 0.5): 2.0 would pan fully to one side.
@export var panning_strength := 1.5
@export var occlusion_db := -6.0
@export var occlusion_cutoff_hz := 2500.0
@export_flags_3d_physics var occlusion_mask := 1
## Trouser legs, for the rustle; the hand, above the aimed point, for the
## announce.
@export var cloth_height := 0.5
@export var hand_height := 0.25

@export_group("Levels")
@export var step_db := 0.0
@export var rustle_db := 0.0
@export var announce_db := 0.0
@export var resolve_db := 0.0
@export var final_db := 0.0
@export var ambience_db := -16.0

@export_group("Variation")
## Light random pitch and volume on repeated sounds. Seeded: runs repeat.
@export var variation := true
@export var pitch_variation := 0.06
@export var volume_variation_db := 1.5
@export var random_seed := 7

var listener: AudioListener3D
var ambience: AudioStreamPlayer
## Count of sounds started, and the recent ones for the diagnostic.
var emissions := 0
var recent: Array[String] = []
var finished := false

var _steps: Array[AudioStreamPlayer3D] = []
var _next_step := 0
var _rustle: AudioStreamPlayer3D
var _announce: AudioStreamPlayer3D
var _resolve: AudioStreamPlayer3D
var _final_3d: AudioStreamPlayer3D
var _final_ui: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


func _init() -> void:
	process_physics_priority = 10
	process_priority = 10


func _ready() -> void:
	_rng.seed = random_seed
	listener = AudioListener3D.new()
	listener.name = "Listener"
	add_child(listener)
	listener.make_current()
	_place_listener()
	for i in 2:
		_steps.append(_player3d("Step%d" % i, step_unit_size))
	_rustle = _player3d("Rustle", body_unit_size)
	_announce = _player3d("Announce", body_unit_size)
	_resolve = _player3d("Resolve", body_unit_size)
	_final_3d = _player3d("FinalCaught", body_unit_size)
	_final_ui = AudioStreamPlayer.new()
	_final_ui.name = "FinalSuccess"
	_final_ui.stream = SUCCESS
	_final_ui.bus = &"Threat"
	_final_ui.volume_db = final_db
	add_child(_final_ui)
	ambience = AudioStreamPlayer.new()
	ambience.name = "Ambience"
	ambience.stream = HUM
	ambience.bus = &"Ambience"
	ambience.volume_db = ambience_db
	ambience.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ambience)
	ambience.play()
	human.footstep.connect(_on_footstep)
	human.inspecting.connect(_on_inspecting)
	human.capture_started.connect(_on_capture_started)
	human.capture_resolved.connect(_on_capture_resolved)
	threat.outcome.connect(_on_outcome)


func _physics_process(delta: float) -> void:
	_clock += delta
	_place_listener()


func _process(_delta: float) -> void:
	_place_listener()


## On the cockroach, turned with the look (yaw only). The camera's distance
## and pitch play no part.
func _place_listener() -> void:
	listener.global_transform = Transform3D(Basis(Vector3.UP, rig.yaw), player.global_position + Vector3.UP * ear_height)


func ear_position() -> Vector3:
	return listener.global_position


## All the positional players (tests: no duplicate after restarts).
func sources() -> Array[AudioStreamPlayer3D]:
	var all: Array[AudioStreamPlayer3D] = []
	all.append_array(_steps)
	all.append_array([_rustle, _announce, _resolve, _final_3d])
	return all


# --- events -------------------------------------------------------------------

func _on_footstep(at: Vector3, strength: float) -> void:
	if finished:
		return
	var p := _steps[_next_step]
	_next_step = (_next_step + 1) % _steps.size()
	# Source on the shoe, not in the floor.
	_start(p, &"pas", STEPS[_rng.randi() % STEPS.size()], at + Vector3.UP * 0.035, step_db + linear_to_db(maxf(strength, 0.01)), true)


func _on_inspecting(_point: Vector3) -> void:
	if finished:
		return
	var legs := Vector3(human.global_position.x, cloth_height, human.global_position.z)
	_start(_rustle, &"fouille", RUSTLE, legs, rustle_db, true)


func _on_capture_started(point: Vector3, _radius: float, _duration: float) -> void:
	if finished:
		return
	_start(_announce, &"annonce", ANNOUNCE, point + Vector3.UP * hand_height, announce_db, false)


func _on_capture_resolved(success: bool) -> void:
	# A success ends the attempt: its sound is the final one (outcome).
	if finished or success:
		return
	_start(_resolve, &"raté", MISS, human.capture_point + Vector3.UP * 0.01, resolve_db, true)


func _on_outcome(kind: String) -> void:
	if finished:
		return
	finished = true
	for p in sources():
		p.stop()
	if kind == "capture":
		_start(_final_3d, &"attrapé", CAUGHT, human.capture_point + Vector3.UP * 0.01, final_db, false)
	else:
		_final_ui.play()
		_log(&"réussite", player.global_position, final_db, false)


# --- playback -----------------------------------------------------------------

func _player3d(node_name: String, unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.bus = &"Threat"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = unit_size
	p.max_db = 0.0
	p.max_distance = max_distance
	p.panning_strength = panning_strength
	p.attenuation_filter_cutoff_hz = 20500.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.top_level = true
	add_child(p)
	return p


func _start(p: AudioStreamPlayer3D, kind: StringName, stream: AudioStream, at: Vector3, db: float, vary: bool) -> void:
	var occluded := is_occluded(at)
	p.stream = stream
	p.global_position = at
	p.volume_db = db + (occlusion_db if occluded else 0.0)
	p.pitch_scale = 1.0
	if variation and vary:
		p.volume_db += _rng.randf_range(-volume_variation_db, volume_variation_db)
		p.pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	p.attenuation_filter_cutoff_hz = occlusion_cutoff_hz if occluded else 20500.0
	p.play()
	_log(kind, at, p.volume_db, occluded)


## A straight line from the ears to the source crosses the level.
func is_occluded(at: Vector3) -> bool:
	var space := listener.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ear_position(), at, occlusion_mask)
	return not space.intersect_ray(q).is_empty()


func _log(kind: StringName, at: Vector3, db: float, occluded: bool) -> void:
	emissions += 1
	var d := at.distance_to(ear_position())
	recent.append("%6.1f s  %-8s %.2f m  %+.1f dB%s" % [_clock, kind, d, db, "  occulté" if occluded else ""])
	if recent.size() > 6:
		recent.pop_front()
	emitted.emit(kind, at, db, occluded)
