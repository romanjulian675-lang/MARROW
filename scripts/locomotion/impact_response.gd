class_name ImpactResponse
extends RefCounted

# Procedural action–reaction from a CONTACT POINT.
#
# An impulse applied at a world point kicks a spring-damper that offsets a body's
# root: LINEAR knockback from the impulse itself, and ANGULAR tilt/twist from the
# torque `r × F` taken about the centre of mass — so *where* you land the hit is
# what shapes the reaction:
#   • high on the torso  -> it pitches away from you
#   • off to one side    -> it rolls / spins
#   • straight through the CoM -> pure knockback, no rotation
# The offset then decays back to neutral: the flinch and the recovery.
#
# Newton's third law is the whole point of "action AND reaction": feed the SAME
# contact point and the NEGATED impulse to the attacker's own ImpactResponse and
# you get the recoil for free, scaled by the attacker's own mass and inertia.
#
# Pure math on a root offset — it composes on top of whatever the gait/stance is
# already doing, and knows nothing about scenes.

var stiffness := 55.0            # linear spring back to neutral
var damping := 8.5
var ang_stiffness := 65.0        # angular spring
var ang_damping := 9.5
var knockback_scale := 1.0       # tuning on the linear kick
var torque_scale := 1.0          # tuning on the rotational kick
var max_tilt := 0.9              # radians, clamp so a big hit can't spin it inside out
var max_shift := 1.2             # metres, clamp on knockback

var _lin := Vector3.ZERO
var _lin_vel := Vector3.ZERO
var _ang := Vector3.ZERO         # axis-angle vector (direction = axis, length = radians)
var _ang_vel := Vector3.ZERO


# Kick the response. `contact` and `impulse` are world-space; `com` is the body's
# centre of mass; `mass`/`inertia` come from BodyMeasure so the reaction scales
# with the morphology (a heavy, spread-out body barely budges).
func apply_impulse(contact: Vector3, impulse: Vector3, com: Vector3, mass: float, inertia: float) -> void:
	_lin_vel += impulse / maxf(mass, 0.001) * knockback_scale
	var r: Vector3 = contact - com
	_ang_vel += r.cross(impulse) / maxf(inertia, 0.001) * torque_scale


func step(dt: float) -> void:
	_lin_vel += (-_lin * stiffness - _lin_vel * damping) * dt
	_lin += _lin_vel * dt
	_ang_vel += (-_ang * ang_stiffness - _ang_vel * ang_damping) * dt
	_ang += _ang_vel * dt
	if _lin.length() > max_shift:
		_lin = _lin.normalized() * max_shift
	if _ang.length() > max_tilt:
		_ang = _ang.normalized() * max_tilt


# The offset to compose onto the body's root transform.
func offset() -> Transform3D:
	var b := Basis.IDENTITY
	var a: float = _ang.length()
	if a > 1e-6:
		b = Basis(_ang / a, a)
	return Transform3D(b, _lin)


func displacement() -> Vector3:
	return _lin


func tilt() -> Vector3:
	return _ang


func is_settled() -> bool:
	return _lin.length() < 1e-3 and _ang.length() < 1e-3 \
		and _lin_vel.length() < 1e-2 and _ang_vel.length() < 1e-2


func reset() -> void:
	_lin = Vector3.ZERO
	_lin_vel = Vector3.ZERO
	_ang = Vector3.ZERO
	_ang_vel = Vector3.ZERO


func configure(p: Dictionary) -> void:
	stiffness = p.get("stiffness", stiffness)
	damping = p.get("damping", damping)
	ang_stiffness = p.get("ang_stiffness", ang_stiffness)
	ang_damping = p.get("ang_damping", ang_damping)
	knockback_scale = p.get("knockback_scale", knockback_scale)
	torque_scale = p.get("torque_scale", torque_scale)
	max_tilt = p.get("max_tilt", max_tilt)
	max_shift = p.get("max_shift", max_shift)
