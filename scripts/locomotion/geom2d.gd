class_name Geom2d
extends RefCounted

# Small 2D helpers on the ground plane (XZ mapped to Vector2). Used from stage 3
# for the support polygon and the static-balance margin; the gait stages reuse
# them for the same job while moving.

# Convex hull, counter-clockwise, of a point set (Andrew's monotone chain).
# Returns the input's unique extreme points; 0/1/2 points pass through as-is
# (a degenerate hull the margin function handles).
static func convex_hull(points: Array) -> Array:
	var pts: Array = []
	for p in points:
		pts.append(p as Vector2)
	if pts.size() <= 2:
		return _dedup(pts)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	pts = _dedup(pts)
	if pts.size() <= 2:
		return pts
	var lower: Array = []
	for p in pts:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array = []
	for i in range(pts.size() - 1, -1, -1):
		var p: Vector2 = pts[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


# Signed distance from `p` to a CONVEX CCW polygon: positive INSIDE (distance to
# the nearest edge), negative outside (−distance to the polygon). This is the
# static-balance margin when `p` is the CoM ground projection.
#   - 0 points  -> -INF (no support)
#   - 1 point   -> -distance to it (only balanced dead on the point)
#   - 2 points  -> -distance to the segment (a line has no interior)
static func signed_margin(hull: Array, p: Vector2) -> float:
	var n: int = hull.size()
	if n == 0:
		return -INF
	if n == 1:
		return -(p.distance_to(hull[0]))
	if n == 2:
		return -_dist_to_segment(p, hull[0], hull[1])

	var inside := true
	var min_edge_dist := INF
	for i in range(n):
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % n]
		# CCW hull: interior is to the LEFT of a->b (cross > 0).
		if _cross(a, b, p) < 0.0:
			inside = false
		min_edge_dist = minf(min_edge_dist, _dist_to_segment(p, a, b))
	return min_edge_dist if inside else -min_edge_dist


# Area of a convex hull (0 for degenerate). Used to prefer bigger bases when the
# margin ties.
static func area(hull: Array) -> float:
	if hull.size() < 3:
		return 0.0
	var a := 0.0
	for i in range(hull.size()):
		var p: Vector2 = hull[i]
		var q: Vector2 = hull[(i + 1) % hull.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func centroid(pts: Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in pts:
		acc += p as Vector2
	return acc / float(pts.size())


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 1e-9:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _dedup(pts: Array) -> Array:
	var out: Array = []
	for p in pts:
		var dup := false
		for q in out:
			if (p as Vector2).distance_to(q) < 1e-6:
				dup = true
				break
		if not dup:
			out.append(p)
	return out
