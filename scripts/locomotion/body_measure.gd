class_name BodyMeasure
extends RefCounted

# Stage 2 of the generic locomotion plan: measure every chain automatically.
#
# Given a BodyGraph and a rest assembly, derive — with NO part-name knowledge —
# the numbers the later stages need: total mass and whole-body centre of mass,
# and per CONTACT ENDPOINT (a foot/hand tip) the limb's reach (rest and fully-
# extended), its mass and centre of mass, and the DOF/limits of every joint on
# the way from the root. Stage 3 reads reach + endpoints to place stances; the
# gait stages read mass/CoM to balance.

var graph: BodyGraph
var _asm: Dictionary


func _init(g: BodyGraph, assembly: Variant = null) -> void:
	graph = g
	_asm = assembly if assembly is Dictionary else g.assemble()


func total_mass() -> float:
	var m := 0.0
	for pid in graph.parts:
		m += (graph.parts[pid] as BodyPart).mass
	return m


# Whole-body centre of mass in world space (mass-weighted mean of each part's box
# centre). Zero-mass bodies return the root origin rather than divide by zero.
func center_of_mass() -> Vector3:
	var m := 0.0
	var acc := Vector3.ZERO
	for pid in graph.parts:
		var part: BodyPart = graph.parts[pid]
		if not _asm.has(pid):
			continue
		var world_com: Vector3 = (_asm[pid] as Transform3D) * part.local_center_of_mass()
		acc += world_com * part.mass
		m += part.mass
	if m <= 0.0:
		return (_asm.get(graph.root_id, Transform3D.IDENTITY) as Transform3D).origin
	return acc / m


# One metrics dict per contact endpoint in the body. Keys:
#   part, socket, tip (world), base (world, where the limb meets the root),
#   reach_rest, reach_max, limb_mass, limb_com (world), joints (Array of
#   {name, dof, dof_count}).
func chains() -> Array:
	var out: Array = []
	for ep in graph.endpoints_world(_asm):
		out.append(_measure_chain(ep["part"], ep["socket"]))
	return out


# Rotational inertia proxy about the centre of mass: Σ m·r². Not a real inertia
# tensor — a scalar stand-in (TDD §4.3 "inertia hints") that makes hit reactions
# scale with how big and how spread-out a body is, so a long heavy creature twists
# less than a compact light one under the same torque.
func inertia_about_com() -> float:
	var com := center_of_mass()
	var total := 0.0
	for pid in graph.parts:
		if not _asm.has(pid):
			continue
		var part: BodyPart = graph.parts[pid]
		var world_com: Vector3 = (_asm[pid] as Transform3D) * part.local_center_of_mass()
		total += part.mass * world_com.distance_squared_to(com)
	return maxf(total, 0.001)


# One metrics dict per MANIPULATION effector (a hand) — same measurements as
# chains(), but for the reach an attack has, not a support. Stage 9 reads
# `reach_max`, `base` (the shoulder), and `segments` (to bend with IK).
func manipulation_chains() -> Array:
	var out: Array = []
	for mp in graph.manipulators_world(_asm):
		out.append(_measure_chain(mp["part"], mp["socket"]))
	return out


func _measure_chain(part_id: String, socket_name: String) -> Dictionary:
	var chain_joints: Array = graph.joints_to(part_id)
	var tip: Vector3 = graph.socket_world(_asm, part_id, socket_name)

	# Waypoints: the base (limb↔root socket), then each intermediate joint, then
	# the tip. Segment lengths are rigid, so their SUM is the fully-straightened
	# reach; the straight-line base→tip is the rest reach.
	var waypoints: Array = []
	if not chain_joints.is_empty():
		var j0: Dictionary = chain_joints[0]
		waypoints.append(graph.socket_world(_asm, j0["parent"], j0["parent_socket"]))
		for k in range(1, chain_joints.size()):
			var jk: Dictionary = chain_joints[k]
			waypoints.append(graph.socket_world(_asm, jk["parent"], jk["parent_socket"]))
	waypoints.append(tip)

	# Per-segment lengths between consecutive waypoints (thigh, shin, ...) — what
	# stage-5 IK bends. Their sum is the fully-straightened reach.
	var segments: Array = []
	var reach_max := 0.0
	for i in range(waypoints.size() - 1):
		var seg_len: float = (waypoints[i + 1] as Vector3).distance_to(waypoints[i])
		segments.append(seg_len)
		reach_max += seg_len
	var base: Vector3 = waypoints[0]
	var reach_rest: float = base.distance_to(tip)

	# Limb mass/CoM = the parts BELOW the root along the chain (exclude the torso).
	var limb_mass := 0.0
	var limb_acc := Vector3.ZERO
	var joints_info: Array = []
	var limb_parts: Array = []
	for j in chain_joints:
		var cid: String = j["child"]
		limb_parts.append(cid)
		var part: BodyPart = graph.parts[cid]
		var wcom: Vector3 = (_asm[cid] as Transform3D) * part.local_center_of_mass()
		limb_acc += wcom * part.mass
		limb_mass += part.mass
		var dof: Array = j.get("dof", [])
		joints_info.append({"name": "%s→%s" % [j["parent"], cid], "dof": dof, "dof_count": dof.size()})
	var limb_com: Vector3 = (limb_acc / limb_mass) if limb_mass > 0.0 else base

	return {
		"part": part_id, "socket": socket_name,
		"tip": tip, "base": base,
		"reach_rest": reach_rest, "reach_max": reach_max,
		"segments": segments,
		"limb_mass": limb_mass, "limb_com": limb_com,
		"limb_parts": limb_parts,
		"joints": joints_info,
	}


# Human-readable dump — the "display" half of the stage. Degrees for angles.
func describe() -> String:
	var lines: Array = []
	lines.append("body: %d parts, total mass %.2f, CoM %s" % [graph.part_count(), total_mass(), _fmt(center_of_mass())])
	var cs: Array = chains()
	lines.append("contact chains: %d" % cs.size())
	for c in cs:
		lines.append("  %s.%s  reach %.3f rest / %.3f max  mass %.2f  CoM %s" % [
			c["part"], c["socket"], c["reach_rest"], c["reach_max"], c["limb_mass"], _fmt(c["limb_com"])])
		for j in c["joints"]:
			if j["dof_count"] == 0:
				lines.append("    joint %-16s rigid" % j["name"])
			else:
				var ranges: Array = []
				for d in j["dof"]:
					ranges.append("%s[%.0f°,%.0f°]" % [_axis_name(d["axis"]), rad_to_deg(d["min"]), rad_to_deg(d["max"])])
				lines.append("    joint %-16s %d DOF: %s" % [j["name"], j["dof_count"], ", ".join(ranges)])
	return "\n".join(lines)


func _fmt(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _axis_name(a: Vector3) -> String:
	if absf(a.x) > 0.9: return "x"
	if absf(a.y) > 0.9: return "y"
	if absf(a.z) > 0.9: return "z"
	return "(%.1f,%.1f,%.1f)" % [a.x, a.y, a.z]
