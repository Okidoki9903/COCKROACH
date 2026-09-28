class_name PlayerInteractor
extends Node
## Picks at most one Interactable near the player's body and runs it on the
## existing `interact` signal of PlayerInput; `drop` asks the CarrySlot.
##
## Reach is measured from the body envelope (collision radius) to the
## target's radius, horizontally. A target behind an obstacle (a ray at
## floor level hits collision layer 1) is ignored. Among valid targets the
## closest wins; ties (within 0.1 mm) go to the smaller node path, so the
## choice is stable. A target's own collision bodies (its descendants) never
## block its line of sight.
##
## Pausable: PlayerInput emits nothing while paused, and the target is not
## refreshed either.

signal target_changed(target: Interactable)

@export var player: PlayerMotor
@export var player_input: PlayerInput
@export var carry: CarrySlot
## Metres from the body envelope to the target's edge.
@export var reach := 0.02
## Height of the line-of-sight ray above the floor.
@export var sight_height := 0.004
@export_flags_3d_physics var sight_mask := 1

var target: Interactable = null
var prompt := ""

var _body_radius := 0.01


func _ready() -> void:
	var shape: Shape3D = player.get_node("Collision").shape
	if "radius" in shape:
		_body_radius = shape.radius
	player_input.interact_pressed.connect(_on_interact)
	player_input.drop_pressed.connect(_on_drop)


func _physics_process(_delta: float) -> void:
	refresh()


## Recomputes the target now.
func refresh() -> void:
	var best: Interactable = null
	var best_d := INF
	var best_path := ""
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var it := node as Interactable
		if it == null or not it.is_inside_tree() or it.get_prompt(self) == "":
			continue
		var d := edge_distance(it)
		if d > reach or not _in_sight(it):
			continue
		var path := String(it.get_path())
		if d < best_d - 0.0001 or (absf(d - best_d) <= 0.0001 and path < best_path):
			best = it
			best_d = d
			best_path = path
	var new_prompt := best.get_prompt(self) if best else ""
	if best != target:
		target = best
		target_changed.emit(target)
	prompt = new_prompt


## Horizontal gap between the body envelope and the target's edge.
func edge_distance(it: Interactable) -> float:
	var a := player.global_position
	var b := it.global_position
	return Vector2(b.x - a.x, b.z - a.z).length() - _body_radius - it.target_radius


func _in_sight(it: Interactable) -> bool:
	var from := player.global_position + Vector3.UP * sight_height
	var to := it.global_position
	to.y = from.y
	var exclude: Array[RID] = [player.get_rid()]
	for n in it.find_children("*", "CollisionObject3D", true, false):
		exclude.append((n as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, sight_mask, exclude)
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _on_interact() -> void:
	refresh()
	if target:
		target.interact(self)
		refresh()


func _on_drop() -> void:
	carry.try_drop()
	refresh()
