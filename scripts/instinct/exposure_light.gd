class_name ExposureLight
extends Node3D
## The one switch of a gameplay light: the rendered lamp (child Lamp) and
## the logical exposure zone (child Zone) always change together.

signal toggled(on: bool)

@export var start_on := true

var on := false

@onready var lamp: Light3D = $Lamp
@onready var zone: ExposureZone = $Zone


func _ready() -> void:
	set_on(start_on)


func set_on(value: bool) -> void:
	on = value
	lamp.visible = value
	zone.active = value
	zone.invalidate()
	toggled.emit(value)


func toggle() -> void:
	set_on(not on)
