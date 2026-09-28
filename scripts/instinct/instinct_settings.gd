class_name InstinctSettings
extends RefCounted
## Accessibility settings of the instinct cues, for the session (static:
## they survive "Recommencer", like the bus volumes; nothing is saved).

## 0.25..1: opacity and size of the footstep and inspection cues. The
## capture warning is essential information and ignores it.
static var intensity := 1.0
## No pulsing, growing or fading: cues appear still, stay for a fixed
## time, then disappear.
static var reduced_motion := false
## Playing without sound: bigger cues, always labelled, shown longer.
static var reinforced := false


static func reset() -> void:
	intensity = 1.0
	reduced_motion = false
	reinforced = false
