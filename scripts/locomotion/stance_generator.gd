class_name StanceGenerator
extends RefCounted

# Stage 3 of the generic locomotion plan: discover a stationary stance by
# SEARCHING for the widest stable base.
#
# The torso stands upright at some height H; each contact endpoint drops to the
# ground within its limb's reach and splays OUTWARD from the body centre by a
# fraction s of the reachable radius. We sweep (H, s), build the support polygon
# from the planted feet, project the centre of mass onto the ground, and keep the
# stance whose CoM sits furthest inside the polygon (the balance margin). No part
# names anywhere — hand it a biped and it discovers a two-foot stand; hand it a
# quadruped and it discovers a four-foot stand, from the same code.
#
# Stance placement only: it outputs WHERE the feet go and how tall the torso is.
# Solving the legs to those targets is stage 5 (IK); this uses straight-leg
# midpoints to approximate the CoM so foot placement still moves it correctly.

var graph: BodyGraph
var _chains: Array          # BodyMeasure.chains(), measured at the H=0 rest assembly
var _total_mass: float
var _nonlimb_mass: float
var _nonlimb_com_xz: Vector2   # torso/head CoM on the ground plane


func _init(g: BodyGraph, measure: BodyMeasure = null) -> void:
	graph = g
	var m: BodyMeasure = measure if measure != null else BodyMeasure.new(g)
	_chains = m.chains()
	_total_mass = m.total_mass()

	# Split mass into limb (moves with the feet) and everything else (torso/head).
	var limb_ids: Dictionary = {}
	for c in _chains:
		for pid in c["limb_parts"]:
			limb_ids[pid] = true
	var nl_mass := 0.0
	var nl_acc := Vector2.ZERO
	var rest: Dictionary = g.assemble()
	for pid in g.parts:
		if limb_ids.has(pid):
			continue
		var part: BodyPart = g.parts[pid]
		var wcom: Vector3 = (rest[pid] as Transform3D) * part.local_center_of_mass()
		nl_acc += Vector2(wcom.x, wcom.z) * part.mass
		nl_mass += part.mass
	_nonlimb_mass = nl_mass
	_nonlimb_com_xz = (nl_acc / nl_mass) if nl_mass > 0.0 else Vector2.ZERO


# Search and return the best stance. `opts`: contact_radius (foot half-patch,
# default 0.08), height_steps, spread_steps, ground_y (default 0).
# Returns {} if NO stable stance exists (e.g. legs too short to reach the ground).
# Otherwise: { torso_height, contacts:[{part,socket,pos}], support_hull:[Vector2],
#              com_xz:Vector2, margin, area, stable:bool }.
func generate(opts: Dictionary = {}) -> Dictionary:
	var foot_r: float = opts.get("contact_radius", 0.08)
	var hsteps: int = opts.get("height_steps", 24)
	var ssteps: int = opts.get("spread_steps", 16)
	var ground_y: float = opts.get("ground_y", 0.0)
	# Fraction of each limb's full reach the stance is allowed to USE. 1.0 plants
	# feet at the reach limit (straight legs); a gait/comfort profile lowers it
	# (e.g. 0.9) so stage-5 IK has slack to stand on a bent knee (TDD §1.1).
	var reach_fraction: float = clampf(opts.get("reach_fraction", 1.0), 0.1, 1.0)
	# Lateral splay as a fraction of the horizontal reach available at the chosen
	# height. < 0 (default) lets the search pick it (the widest stable base); >= 0
	# FIXES it, so height (reach_fraction) and width (stance_width) become
	# independent knobs instead of both riding reach_fraction.
	var stance_width: float = opts.get("stance_width", -1.0)

	# Height window: every foot must be able to reach the ground (base height <=
	# usable reach), and the base must stay above it. Bounded by the shortest limb.
	var h_lo := 0.05
	var h_hi := INF
	for c in _chains:
		var base_y: float = (c["base"] as Vector3).y     # base height at H=0
		# base height at torso height H = base_y + H; need 0 < base_y+H <= reach.
		h_hi = minf(h_hi, (c["reach_max"] as float) * reach_fraction - base_y - 0.001)
		h_lo = maxf(h_lo, -base_y + 0.02)                # keep the base above ground
	if h_hi <= h_lo or _chains.is_empty():
		return {}

	var best: Dictionary = {}
	for hi in range(hsteps + 1):
		var H: float = lerpf(h_lo, h_hi, float(hi) / float(hsteps))
		if stance_width >= 0.0:
			var fixed: Dictionary = _evaluate(H, clampf(stance_width, 0.0, 1.0), foot_r, ground_y, reach_fraction)
			if not fixed.is_empty() and _better(fixed, best):
				best = fixed
		else:
			for si in range(ssteps + 1):
				var s: float = float(si) / float(ssteps)
				var cand: Dictionary = _evaluate(H, s, foot_r, ground_y, reach_fraction)
				if not cand.is_empty() and _better(cand, best):
					best = cand
	return best


# Rank two candidate stances. Priority, in order:
#   1. larger balance MARGIN — the whole point.
#   2. LEAST spread — a biped's margin is foot-radius-capped fore-aft, so every
#      lateral spread ties on margin; without this the search splays to the
#      splits. A quadruped's margin genuinely grows with spread, so margin still
#      drives it wide and this only bites where extra spread is free.
#   3. TALLEST torso — once margin and spread tie, stand as tall as the legs
#      allow. A narrow stance ties on margin across every height, and the tallest
#      one puts the (rigid, single-segment) legs at near-full extension — the
#      physically valid pose. Without it the search picks the lowest height and
#      the creature squats with its hips on the floor. (Bent legs come in stage 5.)
func _better(cand: Dictionary, best: Dictionary) -> bool:
	if best.is_empty():
		return true
	var dm: float = cand["margin"] - best["margin"]
	if absf(dm) > 1e-5:
		return dm > 0.0
	var ds: float = cand["spread"] - best["spread"]
	if absf(ds) > 1e-5:
		return ds < 0.0
	return cand["torso_height"] > best["torso_height"] + 1e-5


func _evaluate(H: float, s: float, foot_r: float, ground_y: float, reach_fraction: float = 1.0) -> Dictionary:
	var contacts: Array = []
	var corners: Array = []      # Vector2, foot-patch corners for the hull
	var com_acc: Vector2 = _nonlimb_com_xz * _nonlimb_mass
	for c in _chains:
		var base: Vector3 = c["base"]
		var base_ground := Vector2(base.x, base.z)
		var base_height: float = base.y + H - ground_y
		if base_height <= 0.0:
			return {}   # base sank below the ground at this height
		var reach: float = (c["reach_max"] as float) * reach_fraction
		var horiz2: float = reach * reach - base_height * base_height
		if horiz2 < 0.0:
			return {}   # leg can't reach the ground at this height
		var horiz: float = sqrt(horiz2) * s
		# Splay outward from the torso CENTRELINE (root ground projection = origin),
		# not from the mass centre — that makes the base widest and symmetric, and
		# keeps the CoM-inside-polygon test an honest balance check even when the
		# mass is off-centre.
		var outward: Vector2 = base_ground
		if outward.length() < 1e-4:
			outward = Vector2(1, 0)      # base on the centreline: pick a default axis
		outward = outward.normalized()
		var foot := base_ground + outward * horiz
		contacts.append({"part": c["part"], "socket": c["socket"], "pos": Vector3(foot.x, ground_y, foot.y)})
		for dx in [-foot_r, foot_r]:
			for dz in [-foot_r, foot_r]:
				corners.append(foot + Vector2(dx, dz))
		# straight-leg CoM: midpoint of hip base and foot, on the ground plane.
		var leg_mid := (base_ground + foot) * 0.5
		com_acc += leg_mid * (c["limb_mass"] as float)

	var com_xz: Vector2 = com_acc / _total_mass
	var hull: Array = Geom2d.convex_hull(corners)
	var margin: float = Geom2d.signed_margin(hull, com_xz)
	return {
		"torso_height": H, "spread": s, "contacts": contacts,
		"support_hull": hull, "com_xz": com_xz,
		"margin": margin, "area": Geom2d.area(hull),
		"stable": margin > 0.0,
	}


# Some bodies don't STAND on legs — a snake, a worm, a felled ragdoll rest their
# contacts (belly points) directly on the ground. There is no torso height to
# search: the body drops until its lowest contacts touch, and the SAME support-
# polygon / CoM-margin math decides whether it balances. The returned dict
# matches generate()'s shape (so a renderer treats both alike), plus:
#   root_offset — the XZ shift that centres the body over its contacts
#   resting     — true, to distinguish it from a legged stance.
# Returns {} if the body has no contact endpoints at all.
static func resting_stance(graph: BodyGraph, measure: BodyMeasure = null) -> Dictionary:
	var m: BodyMeasure = measure if measure != null else BodyMeasure.new(graph)
	var asm: Dictionary = graph.assemble()
	var eps: Array = graph.endpoints_world(asm)
	if eps.is_empty():
		return {}

	var lowest := INF
	for ep in eps:
		lowest = minf(lowest, (ep["world"] as Vector3).y)
	var lift := -lowest

	# The contacts are the endpoints that actually reach the ground once dropped.
	var raw: Array = []
	var pts: Array = []
	for ep in eps:
		var w: Vector3 = ep["world"]
		if w.y + lift <= 0.06:
			raw.append({"part": ep["part"], "socket": ep["socket"], "xz": Vector2(w.x, w.z)})
			pts.append(Vector2(w.x, w.z))

	var cen: Vector2 = Geom2d.centroid(pts)
	var com: Vector3 = m.center_of_mass()
	var com_xz: Vector2 = Vector2(com.x, com.z) - cen

	var contacts: Array = []
	var cpts: Array = []
	for r in raw:
		var p: Vector2 = (r["xz"] as Vector2) - cen
		contacts.append({"part": r["part"], "socket": r["socket"], "pos": Vector3(p.x, 0.0, p.y)})
		cpts.append(p)

	var hull: Array = Geom2d.convex_hull(cpts)
	var margin: float = Geom2d.signed_margin(hull, com_xz)
	return {
		"torso_height": lift, "spread": 0.0, "contacts": contacts,
		"support_hull": hull, "com_xz": com_xz,
		"margin": margin, "area": Geom2d.area(hull),
		"stable": margin > 0.0, "root_offset": -cen, "resting": true,
	}


static func describe(stance: Dictionary) -> String:
	if stance.is_empty():
		return "stance: NONE (no stable configuration found)"
	var lines: Array = []
	lines.append("stance: torso_height %.3f  margin %+.3f (%s)  base area %.3f  CoM_xz (%.2f, %.2f)" % [
		stance["torso_height"], stance["margin"],
		("STABLE" if stance["stable"] else "unstable"), stance["area"],
		(stance["com_xz"] as Vector2).x, (stance["com_xz"] as Vector2).y])
	for ct in stance["contacts"]:
		var pos: Vector3 = ct["pos"]
		lines.append("  contact %s.%s at (%.2f, %.2f, %.2f)" % [ct["part"], ct["socket"], pos.x, pos.y, pos.z])
	return "\n".join(lines)
