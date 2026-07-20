class_name GaitOscillator
extends RefCounted

# Stage 6 / TDD M5 §7.4: one normalized phase per support limb. A single global
# phase in [0,1) advances with cadence; each limb reads it through its own OFFSET.
# Within its cycle a limb is in STANCE (planted) for `duty` of the phase, then in
# SWING (airborne). Coupled offsets make the gait: a biped walk is two limbs half
# a cycle apart; a quadruped trot is diagonal pairs together; a hexapod tripod is
# two alternating sets of three — all just offsets, no recorded poses.

var phase: float = 0.0
var duty: float = 0.65
var _offsets: Dictionary = {}     # key -> phase offset [0,1)


func _init(limb_offsets: Dictionary, duty_factor: float = 0.65) -> void:
	_offsets = limb_offsets.duplicate()
	duty = clampf(duty_factor, 0.05, 0.95)


func advance(cycles: float) -> void:
	phase = fposmod(phase + cycles, 1.0)


func limb_phase(key: String) -> float:
	return fposmod(phase + float(_offsets.get(key, 0.0)), 1.0)


func is_stance(key: String) -> bool:
	return limb_phase(key) < duty


# 0..1 progress through the current stance (planted) portion.
func stance_t(key: String) -> float:
	return clampf(limb_phase(key) / duty, 0.0, 1.0)


# 0..1 progress through the current swing (airborne) portion.
func swing_t(key: String) -> float:
	var over: float = 1.0 - duty
	if over <= 0.0:
		return 0.0
	return clampf((limb_phase(key) - duty) / over, 0.0, 1.0)


func keys() -> Array:
	return _offsets.keys()
