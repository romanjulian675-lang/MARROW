class_name ChainIK
extends RefCounted

# Stage 5 of the generic locomotion plan: GENERIC CHAIN IK.
#
# Bend a limb so its tip reaches a target, solving by TOPOLOGY (TDD §8):
#   1 segment  -> point it at the target (hinge / direct).
#   2 segments -> analytical two-bone IK with a pole target (deterministic).
#   3+ segments-> FABRIK (position-based iterative), pole-seeded.
#
# This is pure math on world-space points and segment lengths — it knows NOTHING
# about BodyGraph, so it is trivially unit-testable and the BodyGraph stays
# authoritative. A caller feeds `base` (the limb's root attachment), the ordered
# segment `lengths`, a world `target` for the tip, and a `pole` (a world point the
# interior joints bend toward), and gets back the solved joint positions:
# `lengths.size() + 1` points — [base, joint1, ..., tip] — to place rigid parts
# between (each part spans one consecutive pair; TDD §4.4).
#
# Reachability (TDD §8.2): a target beyond a+b straightens the chain toward it
# (tip at max reach); a target closer than the innermost fold folds as far as it
# can. We never stretch a segment.


static func solve(base: Vector3, lengths: Array, target: Vector3, pole: Vector3) -> PackedVector3Array:
	var n: int = lengths.size()
	if n == 0:
		return PackedVector3Array([base])
	if n == 1:
		return _solve_hinge(base, lengths[0], target)
	if n == 2:
		return _solve_two_bone(base, lengths[0], lengths[1], target, pole)
	return _solve_fabrik(base, lengths, target, pole)


# Distance from the solved tip to the target — 0 when the target was reachable.
static func reach_error(points: PackedVector3Array, target: Vector3) -> float:
	if points.is_empty():
		return INF
	return points[points.size() - 1].distance_to(target)


static func _solve_hinge(base: Vector3, length: float, target: Vector3) -> PackedVector3Array:
	var dir: Vector3 = target - base
	dir = dir.normalized() if dir.length() > 1e-6 else Vector3.DOWN
	return PackedVector3Array([base, base + dir * length])


# Two-bone analytical IK. The knee lies in the plane through (base, target) that
# leans toward the pole; the law of cosines fixes the hip angle so |base→knee| = a
# and |knee→tip| = b exactly.
static func _solve_two_bone(base: Vector3, a: float, b: float, target: Vector3, pole: Vector3) -> PackedVector3Array:
	var to_target: Vector3 = target - base
	var d: float = clampf(to_target.length(), absf(a - b) + 1e-5, a + b - 1e-5)
	var u: Vector3 = to_target.normalized() if to_target.length() > 1e-6 else Vector3.DOWN

	# Bend axis: the component of the pole direction perpendicular to u.
	var pole_dir: Vector3 = pole - base
	var v: Vector3 = pole_dir - u * pole_dir.dot(u)
	if v.length() < 1e-6:
		v = u.cross(Vector3.RIGHT)
		if v.length() < 1e-6:
			v = u.cross(Vector3.FORWARD)
	v = v.normalized()

	var cos_hip: float = clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_hip: float = sqrt(maxf(0.0, 1.0 - cos_hip * cos_hip))
	var knee: Vector3 = base + (u * cos_hip + v * sin_hip) * a
	var tip: Vector3 = base + u * d
	return PackedVector3Array([base, knee, tip])


# FABRIK for 3+ segments. Seeded bent toward the pole so the solution resolves on
# the intended side, then forward/backward reaching passes until the tip meets the
# target (or the chain is straight because the target is out of reach).
static func _solve_fabrik(base: Vector3, lengths: Array, target: Vector3, pole: Vector3, iterations: int = 16) -> PackedVector3Array:
	var n: int = lengths.size()
	var total: float = 0.0
	for l in lengths:
		total += l

	var to_target: Vector3 = target - base
	var u: Vector3 = to_target.normalized() if to_target.length() > 1e-6 else Vector3.DOWN
	var pole_dir: Vector3 = pole - base
	var v: Vector3 = pole_dir - u * pole_dir.dot(u)
	v = v.normalized() if v.length() > 1e-6 else Vector3.ZERO

	# Seed: straight toward the target, bowed toward the pole at the middle.
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(base)
	var acc: float = 0.0
	for i in range(n):
		acc += lengths[i]
		var t: float = acc / total
		var bow: float = sin(t * PI) * total * 0.15
		pts.append(base + u * acc + v * bow)

	if base.distance_to(target) >= total:
		# Out of reach: straighten toward the target.
		pts[0] = base
		for i in range(n):
			pts[i + 1] = pts[i] + u * lengths[i]
		return pts

	for _it in range(iterations):
		pts[n] = target
		for i in range(n - 1, -1, -1):
			var dir_b: Vector3 = (pts[i] - pts[i + 1]).normalized()
			pts[i] = pts[i + 1] + dir_b * lengths[i]
		pts[0] = base
		for i in range(n):
			var dir_f: Vector3 = (pts[i + 1] - pts[i]).normalized()
			pts[i + 1] = pts[i] + dir_f * lengths[i]
		if pts[n].distance_to(target) < 1e-4:
			break
	return pts
