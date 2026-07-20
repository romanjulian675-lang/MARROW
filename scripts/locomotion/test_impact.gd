extends SceneTree

# Impact-response test: the reaction is driven by the CONTACT POINT. A high hit
# pitches the body away, a side hit twists it, a hit through the centre of mass is
# pure knockback — and the attacker gets an equal-and-opposite recoil. Everything
# decays back to neutral.
#   <godot> --headless --path . --script res://scripts/locomotion/test_impact.gd

var _fail := 0


func _initialize() -> void:
	var g := LocomotionZoo.biped()
	var m := BodyMeasure.new(g)
	var com := m.center_of_mass()
	var mass := m.total_mass()
	var inertia := m.inertia_about_com()
	var push := Vector3(0, 0, 40.0)          # a shove toward +Z

	# --- high hit: torso should pitch, top going the way of the push
	var high := _kicked(com + Vector3(0, 0.45, 0), push, com, mass, inertia, 12)
	var top_after: Vector3 = high.offset().basis * Vector3.UP
	print("  high hit  tilt %s  top.z %+.3f" % [_v(high.tilt()), top_after.z])
	_check("high hit rotates about the lateral axis (pitch)", absf(high.tilt().x) > 0.05)
	_check("high hit tips the top the WAY OF the push (+Z)", top_after.z > 0.02)

	# --- side hit: should twist (yaw), not pitch
	var side := _kicked(com + Vector3(0.45, 0, 0), push, com, mass, inertia, 12)
	print("  side hit  tilt %s" % _v(side.tilt()))
	_check("side hit rotates about the vertical axis (yaw/twist)",
		absf(side.tilt().y) > absf(side.tilt().x))

	# --- through the centre of mass: pure knockback, no spin
	var centre := _kicked(com, push, com, mass, inertia, 12)
	print("  com hit   tilt %s  shift %s" % [_v(centre.tilt()), _v(centre.displacement())])
	_check("hit through the CoM barely rotates", centre.tilt().length() < 1e-4)
	_check("hit through the CoM still knocks the body back", centre.displacement().z > 0.01)

	# --- morphology: a heavier body is moved less by the same hit
	var heavy := _kicked(com, push, com, mass * 4.0, inertia * 4.0, 12)
	_check("a heavier body is knocked back less (%.3f < %.3f)" %
		[heavy.displacement().length(), centre.displacement().length()],
		heavy.displacement().length() < centre.displacement().length())

	# --- Newton's third law: the attacker recoils the opposite way
	var recoil := _kicked(com, -push, com, mass, inertia, 12)
	_check("attacker recoil is opposite the strike", recoil.displacement().z < -0.01)

	# --- it settles back to neutral
	var settling := _kicked(com + Vector3(0, 0.4, 0), push, com, mass, inertia, 12)
	for _i in range(600):
		settling.step(1.0 / 60.0)
	_check("the reaction decays back to neutral", settling.is_settled())

	if _fail == 0:
		print("IMPACT_TEST: ALL PASS")
	else:
		print("IMPACT_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _kicked(contact: Vector3, impulse: Vector3, com: Vector3, mass: float, inertia: float, frames: int) -> ImpactResponse:
	var r := ImpactResponse.new()
	r.apply_impulse(contact, impulse, com, mass, inertia)
	for _i in range(frames):
		r.step(1.0 / 60.0)
	return r


func _v(v: Vector3) -> String:
	return "(%+.3f, %+.3f, %+.3f)" % [v.x, v.y, v.z]


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1
