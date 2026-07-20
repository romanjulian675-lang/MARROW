class_name GaitPattern
extends RefCounted

# Stage 7-8 / TDD M6 (§6.4, §7.4): pick a gait FAMILY for a body and emit the
# per-limb phase offsets + duty an oscillator needs. Coupled offsets are the ONLY
# difference between a biped walk, a quadruped walk, a diagonal trot, and a
# hexapod tripod — no per-creature code, just a classification of where each leg
# sits and a footfall schedule.

# Classify each contact by side and column from its ground position, relative to
# the body's own spread. Returns key -> { left:bool, col:int (+1 front, 0 mid,
# -1 rear), x, z }.
static func classify(contacts: Array) -> Dictionary:
	var max_z := 0.0
	for ct in contacts:
		max_z = maxf(max_z, absf((ct["pos"] as Vector3).z))
	var band := max_z * 0.34
	var out: Dictionary = {}
	for ct in contacts:
		var p: Vector3 = ct["pos"]
		var col := 0
		if p.z > band:
			col = 1
		elif p.z < -band:
			col = -1
		out["%s.%s" % [ct["part"], ct["socket"]]] = {"left": p.x < 0.0, "col": col, "x": p.x, "z": p.z}
	return out


# { offsets, duty } for a named family, or a sensible default for the leg count.
static func for_family(family: String, contacts: Array) -> Dictionary:
	var cls: Dictionary = classify(contacts)
	var keys: Array = cls.keys()
	match family:
		"biped_walk":
			return _biped_walk(cls, keys)
		"quadruped_walk":
			return _quadruped_walk(cls, keys)
		"quadruped_trot":
			return _quadruped_trot(cls, keys)
		"tripod":
			return _tripod(cls, keys)
		"wave":
			return _wave(cls, keys)
	return recommend(contacts)


# Default family by leg count: 2 -> walk, 4 -> statically-stable walk, 6 -> tripod.
static func recommend(contacts: Array) -> Dictionary:
	var cls: Dictionary = classify(contacts)
	var keys: Array = cls.keys()
	match keys.size():
		2:
			return _biped_walk(cls, keys)
		4:
			return _quadruped_walk(cls, keys)
		6:
			return _tripod(cls, keys)
	return _wave(cls, keys)


static func _biped_walk(cls: Dictionary, keys: Array) -> Dictionary:
	var offsets: Dictionary = {}
	for k in keys:
		offsets[k] = 0.0 if cls[k]["left"] else 0.5
	return {"offsets": offsets, "duty": 0.6}


# Lateral-sequence walk (LH, RF, RH, LF spaced 0.25 apart) with duty 0.78 so
# exactly one foot swings at a time -> three feet always down (statically stable).
static func _quadruped_walk(cls: Dictionary, keys: Array) -> Dictionary:
	var offsets: Dictionary = {}
	for k in keys:
		var c: Dictionary = cls[k]
		var off := 0.0
		if c["left"] and c["col"] < 0:
			off = 0.0                                  # left hind
		elif not c["left"] and c["col"] >= 0:
			off = 0.25                                 # right fore
		elif not c["left"] and c["col"] < 0:
			off = 0.5                                  # right hind
		else:
			off = 0.75                                 # left fore
		offsets[k] = off
	return {"offsets": offsets, "duty": 0.78}


# Trot: diagonal pairs move together (front-left+rear-right vs front-right+rear-left).
static func _quadruped_trot(cls: Dictionary, keys: Array) -> Dictionary:
	var offsets: Dictionary = {}
	for k in keys:
		var c: Dictionary = cls[k]
		var diag_a: bool = (c["left"] and c["col"] >= 0) or (not c["left"] and c["col"] < 0)
		offsets[k] = 0.0 if diag_a else 0.5
	return {"offsets": offsets, "duty": 0.55}


# Alternating tripod: (front-left, mid-right, rear-left) vs (front-right, mid-left,
# rear-right) — the classic insect gait. Duty 0.55 leaves a brief all-six overlap.
static func _tripod(cls: Dictionary, keys: Array) -> Dictionary:
	var offsets: Dictionary = {}
	for k in keys:
		var c: Dictionary = cls[k]
		var tripod_a: bool = (c["left"] and c["col"] != 0) or (not c["left"] and c["col"] == 0)
		offsets[k] = 0.0 if tripod_a else 0.5
	return {"offsets": offsets, "duty": 0.55}


# Metachronal wave for any leg count: order rear->front, one leg swinging at a
# time (duty (n-1)/n), so n-1 legs always support. Stable for any n.
static func _wave(cls: Dictionary, keys: Array) -> Dictionary:
	var ordered: Array = keys.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool:
		return float(cls[a]["z"]) < float(cls[b]["z"]))
	var n: int = ordered.size()
	var offsets: Dictionary = {}
	for i in range(n):
		offsets[ordered[i]] = float(i) / float(maxi(1, n))
	return {"offsets": offsets, "duty": clampf(1.0 - 1.0 / float(maxi(2, n)) - 0.02, 0.5, 0.95)}
