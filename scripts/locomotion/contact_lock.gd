class_name ContactLock
extends RefCounted

# Stage 4 of the generic locomotion plan: CONTACT LOCKING.
#
# Once a stance plants a creature's endpoints, those world contact points are
# LOCKED — the torso can sway, bob, lean and turn while every planted foot stays
# exactly where it is. This class holds the locked contacts and, for any proposed
# torso (root) transform, reports whether each planted limb can still REACH its
# contact and how much reach it has to spare.
#
# It does NOT bend the legs to the contacts — that is stage 5 (IK). Stage 4 only
# tracks feasibility: the reach margin per limb, and how far the torso can travel
# before a foot must be picked up. That is exactly what the gait scheduler
# (stages 6-8) reads to decide WHEN to lift and step a foot.
#
# The one geometric fact this rests on: a limb's base (where it attaches to the
# root) is a socket on the root part, so its world position is just
# `root_transform * base_local` — no re-assembly needed as the torso moves.

var graph: BodyGraph
var base_root: Transform3D                 # the torso pose the stance was planted at
var _hip_local: Dictionary = {}            # contact key -> base socket position in the root frame
var _reach: Dictionary = {}                # contact key -> reach_max (fully-straightened limb)
var _foot: Dictionary = {}                 # contact key -> locked world position
var _order: Array = []                     # stable contact-key order


# Capture the stance's contacts as locked world points. The stance is expressed
# with the root's horizontal origin at 0 and feet on the ground, standing at
# torso_height H — so the planting pose is a pure lift to (0, H, 0).
func _init(g: BodyGraph, stance: Dictionary, measure: BodyMeasure = null) -> void:
	graph = g
	var m: BodyMeasure = measure if measure != null else BodyMeasure.new(g)
	var height: float = stance.get("torso_height", 0.0)
	base_root = Transform3D(Basis.IDENTITY, Vector3(0, height, 0))
	for c in m.chains():
		var key: String = _key(c["part"], c["socket"])
		_hip_local[key] = c["base"]
		_reach[key] = c["reach_max"]
	for ct in stance.get("contacts", []):
		var key: String = _key(ct["part"], ct["socket"])
		if _reach.has(key):
			_foot[key] = ct["pos"]
			_order.append(key)


static func _key(part: String, socket: String) -> String:
	return "%s.%s" % [part, socket]


# Re-plant one contact at a new world position — a completed step. Keeps the
# lock set current as the gait lifts and puts down feet.
func set_contact(part: String, socket: String, world_pos: Vector3) -> void:
	var key: String = _key(part, socket)
	if not _reach.has(key):
		return
	if not _foot.has(key):
		_order.append(key)
	_foot[key] = world_pos


func locked_keys() -> Array:
	return _order.duplicate()


func contact_count() -> int:
	return _order.size()


func contact_world(part: String, socket: String) -> Vector3:
	return _foot.get(_key(part, socket), Vector3.ZERO)


# Where a limb's hip (its root attachment) sits for a given torso pose.
func hip_world(part: String, socket: String, root_xf: Transform3D) -> Vector3:
	return root_xf * (_hip_local.get(_key(part, socket), Vector3.ZERO) as Vector3)


# Assess a proposed torso pose against the locked contacts. Per contact:
#   key, hip, foot (locked, unchanged), dist, reach_max,
#   margin  = reach_max - dist   (>0 has slack, <0 the foot can no longer stay),
#   strain  = dist / reach_max   (1.0 = limb dead straight),
#   reachable.
# Plus, for the whole body: all_reachable, min_reach_margin, and the worst key.
func evaluate(root_xf: Transform3D) -> Dictionary:
	var contacts: Array = []
	var all_ok := true
	var min_margin := INF
	var worst := ""
	for key in _order:
		var hip: Vector3 = root_xf * (_hip_local[key] as Vector3)
		var foot: Vector3 = _foot[key]
		var dist: float = hip.distance_to(foot)
		var rmax: float = _reach[key]
		var margin: float = rmax - dist
		var reachable: bool = margin >= -1e-6
		all_ok = all_ok and reachable
		if margin < min_margin:
			min_margin = margin
			worst = key
		contacts.append({
			"key": key, "hip": hip, "foot": foot, "dist": dist,
			"reach_max": rmax, "margin": margin,
			"strain": (dist / rmax) if rmax > 0.0 else INF, "reachable": reachable,
		})
	return {
		"root_transform": root_xf, "contacts": contacts,
		"all_reachable": all_ok, "min_reach_margin": min_margin, "worst": worst,
	}


# Convenience: the base pose displaced by a world translation (sway/bob/lean).
func evaluate_shift(delta: Vector3) -> Dictionary:
	return evaluate(Transform3D(base_root.basis, base_root.origin + delta))


# Convenience: the base pose rotated in place about its own origin (turn/lean),
# feet staying planted.
func evaluate_rotated(basis: Basis) -> Dictionary:
	return evaluate(Transform3D(basis * base_root.basis, base_root.origin))


# How far the torso can travel from `start` along `dir` before some locked
# contact can no longer reach — the support-limited mobility in that direction.
# Bisection to `tol`; returns 0 if `start` is already infeasible, or `limit` if
# the whole span stays reachable.
func max_travel(dir: Vector3, start: Transform3D = base_root, limit: float = 3.0, tol: float = 0.001) -> float:
	var d: Vector3 = dir.normalized()
	if not evaluate(start)["all_reachable"]:
		return 0.0
	if evaluate(Transform3D(start.basis, start.origin + d * limit))["all_reachable"]:
		return limit
	var lo := 0.0
	var hi := limit
	while hi - lo > tol:
		var mid := (lo + hi) * 0.5
		if evaluate(Transform3D(start.basis, start.origin + d * mid))["all_reachable"]:
			lo = mid
		else:
			hi = mid
	return lo


static func describe(ev: Dictionary) -> String:
	var lines: Array = []
	lines.append("torso @ %s  %s  min reach margin %+.3f%s" % [
		_fmt((ev["root_transform"] as Transform3D).origin),
		("all reachable" if ev["all_reachable"] else "OUT OF REACH"),
		ev["min_reach_margin"],
		("" if (ev["worst"] as String).is_empty() else "  (tightest: %s)" % ev["worst"])])
	for c in ev["contacts"]:
		lines.append("  %-12s hip %s -> foot %s  dist %.3f/%.3f  strain %.2f%s" % [
			c["key"], _fmt(c["hip"]), _fmt(c["foot"]), c["dist"], c["reach_max"],
			c["strain"], ("" if c["reachable"] else "  UNREACHABLE")])
	return "\n".join(lines)


static func _fmt(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
