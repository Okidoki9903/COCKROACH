extends Node
## Integration scenarios for the resource loop on kitchen_loop.tscn.
## Everything goes through commands: E and the drop key as key events,
## movement through the move actions with camera steering, and the
## interactor's own target selection. Player teleports (the diagnostic
## reset) are used only to set up positions.
## Run: godot --headless --fixed-fps 60 --path . res://scenes/tests/resource_loop_runner.tscn
## User arg --capture=<dir> (needs rendering) saves the carry sequence.

const LOOP := preload("res://scenes/levels/kitchen_loop.tscn")
const FAKE := preload("res://scripts/tests/fake_interactable.gd")
const WATCHDOG_SECONDS := 900.0
const EXIT := Vector2(0.06, 0.91)
const REFUGE_IN := Vector2(-0.06, 0.91)
const AT_WATER := Vector2(0.8, 0.15)
const AT_FOOD := Vector2(1.52, 0.66)

signal tick_done
signal frame_done

var _failures := 0
var _checks := 0
var _loop: KitchenLoop
var _player: PlayerMotor
var _rig: CameraRig
var _panel
var _session: SessionState
var _carry: CarrySlot
var _interactor: PlayerInteractor
var _crumb: Crumb
var _source: FoodSource
var _water: WaterPoint
var _deposit: RefugeDeposit
var _hud
var _successes := 0
var _drop_fails := 0
var _capture := ""
var _shot_n := 0
var _carry_ticks := 0
var _carry_overlaps := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000
	process_priority = 1000


func _physics_process(_d: float) -> void:
	tick_done.emit()


func _process(_d: float) -> void:
	frame_done.emit()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("RESULT: watchdog timeout after %d checks" % _checks)
		get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture = a.trim_prefix("--capture=")
	var loop := LOOP.instantiate()
	loop.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(loop)
	_bind(loop)
	await _ticks(10)
	if _capture != "":
		await _sequence()
		get_tree().quit(0)
		return
	await _run()
	print("RESULT: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _bind(loop: KitchenLoop) -> void:
	_loop = loop
	_player = loop.get_node("Kitchen/Player")
	_rig = loop.get_node("Kitchen/CameraRig")
	_panel = loop.get_node("Kitchen/DebugLayer/LevelDebugPanel")
	_session = loop.get_node("Session")
	_carry = loop.get_node("CarrySlot")
	_interactor = loop.get_node("Interactor")
	_crumb = loop.get_node("Resources/Crumb")
	_source = loop.get_node("Resources/FoodSource")
	_water = loop.get_node("Resources/WaterPoint")
	_deposit = loop.get_node("Resources/RefugeDeposit")
	_hud = loop.get_node("Hud")
	loop.get_node("Kitchen/PauseController").capture_mouse = false
	_successes = 0
	_drop_fails = 0
	_session.succeeded.connect(func() -> void: _successes += 1)
	_carry.drop_failed.connect(func() -> void: _drop_fails += 1)


var _fresh: KitchenLoop = null


func _reset() -> void:
	# Lambdas capture locals by value: store the new root in a member.
	_fresh = null
	_loop.session_reset.connect(func(f: KitchenLoop) -> void: _fresh = f)
	_loop.reset_session()
	await _ticks(10)
	_bind(_fresh)
	await _ticks(5)


func _run() -> void:
	_section("session neuve")
	_invariants("départ")
	_check(_crumb.state == Crumb.State.AT_SOURCE and _source.is_available(), "miette disponible à la source")
	_check(not _session.drank and _session.reserve == 0 and not _session.success, "objectifs vides")

	_section("A : refuge → eau → nourriture → refuge")
	await _walk([EXIT, Vector2(0.2, 0.66), Vector2(0.2, 0.30), Vector2(0.8, 0.30), AT_WATER], false)
	await _approach(_xz(_water))
	_check(_interactor.target == _water and _interactor.prompt == "Boire", "l'eau est la cible au bord du point d'eau")
	await _key(KEY_E)
	_check(_session.drank and _session.drink_events == 1, "E boit")
	_check(not _session.success, "boire seul ne réussit pas la sortie")
	await _key(KEY_E)
	await _key_held(KEY_E, 5)
	_check(_session.drank and _session.drink_events == 3 and _successes == 0, "boire encore : confirmé, rien ne s'accumule")
	await _walk([Vector2(0.8, 0.30), Vector2(1.4, 0.30), Vector2(1.4, 0.64), AT_FOOD], false)
	await _approach(_xz(_source))
	_check(_interactor.target == _source and _interactor.prompt == "Prélever une miette", "la source est la cible")
	await _key(KEY_E)
	_check(_carry.item == _crumb and _crumb.state == Crumb.State.CARRIED, "E prélève la miette")
	var dummy := CarrySlot.new()
	dummy.player = _player
	_check(not _crumb.take_from_source(dummy) and not _crumb.pick_up(dummy) and _carry.item == _crumb, "portée : second prélèvement ou reprise refusés")
	dummy.free()
	_check(not _source.is_available() and not _source.available_marker.visible, "source épuisée, halo éteint, biscuit en place")
	# Back to the biscuit: the camera arm must stop on it, not pass through.
	_face(PI / 2.0)
	await _ticks(30)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.0015
	var cq := PhysicsShapeQueryParameters3D.new()
	cq.shape = sphere
	cq.collision_mask = 1
	cq.transform = Transform3D(Basis(), _rig.camera.global_position)
	_check(_loop.get_world_3d().direct_space_state.intersect_shape(cq, 1).is_empty(), "dos au biscuit : caméra hors du biscuit (distance %.3f)" % _rig.current_distance)
	await _key(KEY_E)
	await _key_held(KEY_E, 5)
	_invariants("après E répétés à la source")
	_check(_interactor.target != _source, "une source épuisée n'est plus une cible")
	var r := await _walk([Vector2(1.4, 0.72), EXIT, REFUGE_IN], true)
	_check(r.max_speed <= _player.walk_speed + 1e-6, "sprint maintenu en portant : %.3f m/s au plus" % r.max_speed)
	_check(_interactor.target == _deposit and _interactor.prompt == "Déposer la miette", "le dépôt est la cible au refuge")
	await _key(KEY_E)
	_check(_session.reserve == 1 and _crumb.state == Crumb.State.DEPOSITED and not _carry.has_item(), "E dépose : réserve 1, charge libre")
	_check(_session.success and _successes == 1, "sortie réussie, signalée une fois")
	await _key(KEY_E)
	await _key_held(KEY_E, 8)
	await _ticks(60)
	_check(_session.reserve == 1 and _successes == 1, "rester au refuge et appuyer encore ne compte rien de plus")
	_check(_interactor.target != _crumb and _crumb.get_prompt(_interactor) == "", "une miette déposée ne se reprend pas")
	_invariants("après dépôt")
	_hold_forward(true)
	await _ticks(20)
	_release_all()
	_check(_player.horizontal_speed() > _player.walk_speed + 0.01, "sprint de nouveau possible après le dépôt")

	_section("machine d'états de la miette (appels directs)")
	var st := _crumb.state
	var refused := not _crumb.take_from_source(_carry) and not _crumb.pick_up(_carry) \
		and not _crumb.place_on_ground(_loop.get_node("Resources"), Vector3.ZERO, 0.0) \
		and not _crumb.deposit(_deposit.pile, Vector3.ZERO)
	_check(refused and _crumb.state == st and not _carry.has_item(), "déposée : toute autre transition est refusée")

	_section("réinitialisation de session")
	await _reset()
	_invariants("après réinitialisation")
	_check(_crumb.state == Crumb.State.AT_SOURCE and _source.is_available() and not _carry.has_item(), "miette revenue à la source, charge vide")
	_check(not _session.drank and _session.reserve == 0 and not _session.success, "objectifs remis à zéro")
	_check(_player.global_position.x < 0.0 and not get_tree().paused, "joueur au refuge, jeu non pausé")

	_section("B : nourriture → dépôt, puis eau")
	await _walk([EXIT, AT_FOOD], false)
	await _approach(_xz(_source))
	await _key(KEY_E)
	_check(_carry.item == _crumb, "prélevée")
	await _walk([Vector2(1.4, 0.72), EXIT, REFUGE_IN], false)
	await _key(KEY_E)
	_check(_session.reserve == 1 and not _session.success and _successes == 0, "dépôt sans eau : pas de réussite")
	await _walk([EXIT, Vector2(0.2, 0.66), Vector2(0.2, 0.30), Vector2(0.8, 0.30), AT_WATER], false)
	await _approach(_xz(_water))
	await _key(KEY_E)
	_check(_session.success and _successes == 1, "eau après dépôt : réussite, une fois")

	_section("lâcher et reprendre, sprint, route directe")
	await _reset()
	await _walk([EXIT, AT_FOOD], false)
	await _approach(_xz(_source))
	await _key(KEY_E)
	await _walk([Vector2(1.4, 0.72), Vector2(0.8, 0.79)], false)
	await _key(KEY_Q)
	_check(_crumb.state == Crumb.State.ON_GROUND and not _carry.has_item(), "la touche lâcher pose la miette")
	_check_ground_spot("route directe")
	var spot := Vector2(_crumb.global_position.x, _crumb.global_position.z)
	_hold_forward(true)
	await _ticks(30)
	_check(_player.horizontal_speed() > _player.walk_speed + 0.05, "sprint réautorisé après le lâcher (%.3f m/s)" % _player.horizontal_speed())
	_release_all()
	await _approach(spot)
	_check(_interactor.target == _crumb and _interactor.prompt == "Reprendre la miette", "la miette au sol est la cible")
	await _key(KEY_E)
	_check(_carry.item == _crumb and _crumb.state == Crumb.State.CARRIED, "E reprend la miette")
	_hold_forward(true)
	await _ticks(30)
	_check(_player.horizontal_speed() <= _player.walk_speed + 1e-6, "sprint de nouveau bloqué")
	_release_all()
	_invariants("après reprise, route directe")

	_section("lâcher et reprendre, route couverte")
	await _walk([Vector2(1.4, 0.64), Vector2(1.4, 0.30), Vector2(1.0, 0.30)], false)
	await _key(KEY_Q)
	_check(_crumb.state == Crumb.State.ON_GROUND, "posée sous les meubles")
	_check_ground_spot("sous les meubles")
	spot = Vector2(_crumb.global_position.x, _crumb.global_position.z)
	await _walk([Vector2(1.15, 0.30)], false)
	await _approach(spot)
	await _key(KEY_E)
	_check(_carry.item == _crumb, "reprise sous les meubles")

	_section("lâcher contre un mur")
	_teleport(Vector2(1.1, 0.56), 0.0)
	_hold_forward(false)
	await _ticks(40)
	_release_all()
	await _ticks(10)
	await _key(KEY_Q)
	_check(_crumb.state == Crumb.State.ON_GROUND and _crumb.global_position.z > 0.53 + 0.003, "posée du côté du joueur, pas dans la plinthe (z %.4f)" % _crumb.global_position.z)
	_check_ground_spot("contre la plinthe")
	await _approach(Vector2(_crumb.global_position.x, _crumb.global_position.z))
	await _key(KEY_E)
	_check(_carry.item == _crumb, "reprise contre le mur")

	_section("lâcher près d'un bord (plateau de test de 1 cm)")
	# 1 cm: the floor below stays within the ground ray, so only the
	# same-level rule can refuse the spot beyond the edge.
	var platform := _box(Vector3(0.1, 0.01, 0.1), Vector3(0.3, 0.005, 0.75))
	await _ticks(2)
	_teleport(Vector2(0.3, 0.7152), 0.0, 0.01)
	await _ticks(20)
	await _key(KEY_Q)
	_check(_crumb.state == Crumb.State.ON_GROUND and absf(_crumb.global_position.y - 0.01) < 0.002, "posée sur le plateau, pas en contrebas (y %.4f)" % _crumb.global_position.y)
	_check(_crumb.global_position.z > 0.70, "pas au-delà du bord")
	await _approach(Vector2(_crumb.global_position.x, _crumb.global_position.z))
	await _key(KEY_E)
	_check(_carry.item == _crumb, "reprise sur le plateau")
	platform.queue_free()

	_section("lâcher impossible (enclos de test)")
	var pen: Array[Node] = []
	for w in [[Vector3(0.028, 0.02, 0.002), Vector3(0.35, 0.01, 1.037)], [Vector3(0.028, 0.02, 0.002), Vector3(0.35, 0.01, 1.063)],
			[Vector3(0.002, 0.02, 0.028), Vector3(0.337, 0.01, 1.05)], [Vector3(0.002, 0.02, 0.028), Vector3(0.363, 0.01, 1.05)]]:
		pen.append(_box(w[0], w[1]))
	await _ticks(2)
	_teleport(Vector2(0.35, 1.05), 0.0)
	await _ticks(10)
	var fails := _drop_fails
	await _key(KEY_Q)
	_check(_carry.item == _crumb and _crumb.state == Crumb.State.CARRIED, "aucune place : la charge est conservée")
	_check(_drop_fails == fails + 1, "retour « pas de place » émis")
	_check(_hud._message.text.contains("Pas de place"), "message affiché par l'interface")
	for n in pen:
		n.queue_free()
	await _ticks(2)

	_section("cible derrière un obstacle")
	_teleport(Vector2(1.1, 0.49), PI)
	await _ticks(10)
	await _key(KEY_Q)
	_check(_crumb.state == Crumb.State.ON_GROUND and _crumb.global_position.z < 0.52, "miette posée juste derrière la plinthe (z %.4f)" % _crumb.global_position.z)
	_teleport(Vector2(1.1, 0.545), 0.0)
	await _ticks(10)
	print("  écart corps-miette %.4f m (portée %.3f)" % [_interactor.edge_distance(_crumb), _interactor.reach])
	_check(_interactor.edge_distance(_crumb) <= _interactor.reach, "la miette est à portée en distance")
	_check(_interactor.target == null, "mais la plinthe bloque la sélection")
	await _key(KEY_E)
	_check(_crumb.state == Crumb.State.ON_GROUND, "E à travers la plinthe ne fait rien")
	_teleport(Vector2(1.1, 0.49), PI)
	await _ticks(10)
	await _key(KEY_E)
	_check(_carry.item == _crumb, "reprise du bon côté")

	_section("deux cibles proches")
	await _walk([Vector2(1.4, 0.30), Vector2(0.8, 0.30), AT_WATER], false)
	_face(0.0)
	await _ticks(10)
	await _key(KEY_Q)
	# Step toward the water so both targets are within reach.
	var here := _player.global_position
	_teleport(Vector2(here.x, here.z - 0.012), 0.0)
	await _ticks(10)
	var d_crumb := _interactor.edge_distance(_crumb)
	var d_water := _interactor.edge_distance(_water)
	print("  écarts : miette %.4f, eau %.4f" % [d_crumb, d_water])
	_check(d_crumb <= _interactor.reach and d_water <= _interactor.reach, "les deux cibles sont à portée")
	var expected: Interactable = _crumb if d_crumb < d_water else _water
	var stable := true
	for i in 30:
		await tick_done
		stable = stable and _interactor.target == expected
	_check(stable, "la plus proche est choisie, de façon stable (%s)" % expected.name)
	var a := FAKE.new()
	var b := FAKE.new()
	a.name = "TieB"
	b.name = "TieA"
	a.target_radius = 0.002
	b.target_radius = 0.002
	_loop.get_node("Resources").add_child(a)
	_loop.get_node("Resources").add_child(b)
	var p := _player.global_position
	a.global_position = p + Vector3(0.02, 0, 0.05)
	b.global_position = p + Vector3(-0.02, 0, 0.05)
	_teleport(Vector2(p.x, p.z + 0.035), 0.0)
	await _ticks(5)
	var picks := {}
	for i in 20:
		await tick_done
		picks[_interactor.target.name if _interactor.target else "-"] = true
	print("  égalité : cibles choisies %s" % [picks.keys()])
	_check(picks.size() == 1 and picks.has("TieA"), "égalité départagée par le chemin du nœud, toujours la même")
	a.queue_free()
	b.queue_free()
	await _ticks(2)

	_section("pause pendant une interaction possible")
	_teleport(AT_WATER, 0.0)
	await _ticks(10)
	await _key(KEY_E)
	_check(_carry.item == _crumb or _session.drank, "E sur la cible la plus proche")
	var drinks := _session.drink_events
	var carried := _carry.has_item()
	await _key(KEY_ESCAPE)
	_check(get_tree().paused, "pause")
	await _key(KEY_E)
	await _key(KEY_Q)
	_check(_session.drink_events == drinks and _carry.has_item() == carried, "ni E ni lâcher en pause")
	_check(_hud._prompt.text == "", "pas d'action proposée en pause")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused, "reprise")

	_section("téléportations de diagnostic")
	if not _carry.has_item():
		await _approach(Vector2(_crumb.global_position.x, _crumb.global_position.z))
		await _key(KEY_E)
	var drank_before := _session.drank
	var reserve_before := _session.reserve
	_panel.go_to("Refuge")
	await _ticks(10)
	_check(_carry.item == _crumb and _session.reserve == reserve_before, "retour au refuge : la charge n'est pas déposée")
	_panel.go_to("Eau")
	await _ticks(10)
	_check(_session.drank == drank_before and _session.drink_events == drinks + int(not carried), "téléportation à l'eau : rien n'est validé")
	_invariants("fin")

	_section("miette portée près des murs")
	print("  %d ticks de marche en portant, miette dans le décor : %d" % [_carry_ticks, _carry_overlaps])
	_check(_carry_ticks > 1000 and _carry_overlaps == 0, "la miette portée ne pénètre pas le décor sur les trajets")
	# Worst case: pushing head-first into a wall while carrying.
	if not _carry.has_item():
		await _approach(_xz(_crumb))
		await _key(KEY_E)
	_teleport(Vector2(0.4, 0.60), 0.0)
	_hold_forward(false)
	await _ticks(60)
	_release_all()
	await _ticks(5)
	# At floor level the body passes under the overhang and stops on the
	# plinth, whose face is at z = 0.53.
	var into := 0.53 - (_crumb.global_position.z - CarrySlot.CRUMB_SIZE.z / 2.0)
	print("  poussée tête la première contre la plinthe : corps en z %.4f, miette %.1f mm dans la plinthe" % [_player.global_position.z, into * 1000])


## Short rendered sequence: take, try to sprint, drop, pick up, deposit.
func _sequence() -> void:
	_panel.visible = false
	await _walk([EXIT, AT_FOOD], true)
	await _approach(_xz(_source))
	await _shot("01_devant_la_source")
	await _key(KEY_E)
	await _shot("02_miette_prise")
	_face(PI / 2.0)
	_hold_forward(true)
	for i in 4:
		await _ticks(15)
		await _shot("03_sprint_tente_%d" % i)
	_release_all()
	await _ticks(10)
	await _key(KEY_Q)
	await _ticks(5)
	await _shot("04_lachee")
	_hold_forward(true)
	await _ticks(20)
	await _shot("05_sprint_sans_charge")
	_release_all()
	await _approach(Vector2(_crumb.global_position.x, _crumb.global_position.z))
	await _shot("06_retour_sur_la_miette")
	await _key(KEY_E)
	await _shot("07_reprise")
	await _walk([EXIT, REFUGE_IN], false)
	await _shot("08_au_refuge")
	await _key(KEY_E)
	await _ticks(5)
	await _shot("09_deposee")
	await _walk([EXIT, Vector2(0.2, 0.66), Vector2(0.2, 0.30), Vector2(0.8, 0.30), AT_WATER], true)
	await _approach(_xz(_water))
	await _shot("10_au_point_d_eau")
	await _key(KEY_E)
	await _ticks(5)
	await _shot("11_bu_reussite")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_capture, name])


# --- helpers -----------------------------------------------------------------

func _invariants(where: String) -> void:
	var crumbs := get_tree().get_nodes_in_group(&"interactable").filter(func(n): return n is Crumb)
	var ok: bool = crumbs.size() == 1 and crumbs[0] == _crumb
	match _crumb.state:
		Crumb.State.CARRIED:
			ok = ok and _carry.item == _crumb and _crumb.get_parent() == _player.visual
		Crumb.State.AT_SOURCE, Crumb.State.ON_GROUND:
			ok = ok and _carry.item == null and _crumb.get_parent() == _loop.get_node("Resources")
		Crumb.State.DEPOSITED:
			ok = ok and _carry.item == null and _crumb.get_parent() == _deposit.pile
	ok = ok and _session.reserve <= 1 and _player.sprint_blocked == _carry.has_item()
	_check(ok, "invariants de ressource (%s)" % where)


func _crumb_in_scenery() -> bool:
	var box := BoxShape3D.new()
	box.size = CarrySlot.CRUMB_SIZE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	q.transform = _crumb.global_transform
	return not _loop.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _check_ground_spot(where: String) -> void:
	var c := _crumb.global_position
	var box := BoxShape3D.new()
	box.size = CarrySlot.CRUMB_SIZE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), c + Vector3.UP * 0.0025)
	var free := _loop.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
	var near := Vector2(c.x - _player.global_position.x, c.z - _player.global_position.z).length() < 0.04
	_check(free and absf(c.y - _player.global_position.y) < 0.002 and near, "%s : posée au sol, libre, à côté du joueur" % where)


func _walk(pts: Array, sprint: bool) -> Dictionary:
	var i := 0
	var ticks := 0
	var max_speed := 0.0
	_hold_forward(sprint)
	while i < pts.size() and ticks < 60 * 90:
		var p := _player.global_position
		var to: Vector2 = pts[i] - Vector2(p.x, p.z)
		if to.length() < 0.012:
			i += 1
			continue
		_rig.yaw = atan2(-to.x, -to.y)
		await tick_done
		ticks += 1
		if ticks > 12:
			max_speed = maxf(max_speed, _player.horizontal_speed())
		if _carry.has_item():
			_carry_ticks += 1
			_carry_overlaps += int(_crumb_in_scenery())
	_release_all()
	await _ticks(12)
	if i < pts.size():
		_check(false, "trajet interrompu vers %s" % [pts[i]])
	return {"max_speed": max_speed}


## Walks toward a point until the interactor has a target within reach
## (or the point itself is within reach of the body).
func _approach(point: Vector2) -> void:
	var ticks := 0
	_hold_forward(false)
	while ticks < 600:
		var p := _player.global_position
		var to := point - Vector2(p.x, p.z)
		if to.length() - 0.01 - 0.004 < _interactor.reach * 0.6 or (_interactor.target != null and _interactor.edge_distance(_interactor.target) < _interactor.reach * 0.6 and _xz(_interactor.target).distance_to(point) < 0.001):
			break
		_rig.yaw = atan2(-to.x, -to.y)
		await tick_done
		ticks += 1
	_release_all()
	await _ticks(12)


func _xz(n: Node3D) -> Vector2:
	return Vector2(n.global_position.x, n.global_position.z)


func _teleport(at: Vector2, yaw: float, y := 0.0) -> void:
	_player.reset_to(Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.y)))
	_rig.snap_to_target(yaw)


func _face(yaw: float) -> void:
	_player.visual.rotation.y = yaw
	_rig.yaw = yaw


func _box(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	_loop.add_child(body)
	body.global_position = centre
	return body


func _hold_forward(sprint: bool) -> void:
	Input.action_press(&"move_forward")
	if sprint:
		Input.action_press(&"sprint")


func _release_all() -> void:
	for a in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(a)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = key
		e.pressed = pressed
		Input.parse_input_event(e)
		await tick_done
		await frame_done


## Holds a key with `repeats` key-repeat echoes.
func _key_held(key: Key, repeats: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.pressed = true
	Input.parse_input_event(e)
	await frame_done
	for i in repeats:
		var r := InputEventKey.new()
		r.physical_keycode = key
		r.pressed = true
		r.echo = true
		Input.parse_input_event(r)
		await frame_done
	var up := InputEventKey.new()
	up.physical_keycode = key
	Input.parse_input_event(up)
	await frame_done


func _ticks(n: int) -> void:
	for i in n:
		await tick_done


func _section(title: String) -> void:
	print("-- ", title)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
