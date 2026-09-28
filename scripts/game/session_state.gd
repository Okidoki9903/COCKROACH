class_name SessionState
extends Node
## Objectives of one outing, kept in memory only (nothing is saved).
## Success = drank at the water point AND deposited a crumb, in any order;
## it is emitted once. Only interactions call these methods; positions
## alone never change the session.

signal changed
signal succeeded

var drank := false
## Crumbs deposited in the refuge during this session.
var reserve := 0
var success := false
## Confirmations, for diagnostics: repeated drinks do not add rewards.
var drink_events := 0


func record_drink() -> void:
	drink_events += 1
	if not drank:
		drank = true
		changed.emit()
		_check()


func record_deposit() -> void:
	reserve += 1
	changed.emit()
	_check()


func _check() -> void:
	if not success and drank and reserve > 0:
		success = true
		succeeded.emit()
