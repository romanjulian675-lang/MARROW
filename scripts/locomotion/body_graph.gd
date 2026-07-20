class_name BodyGraph
extends RefCounted

# Stage 1 of the generic locomotion plan: assemble arbitrary rigid parts through
# sockets into one creature.
#
# The graph is a set of BodyParts plus a set of JOINTS. A joint pins a child
# part's mount socket onto a parent part's socket; assembling walks the tree from
# the root and hands back a world Transform3D for every part. Because a part and
# a joint carry no notion of "arm" or "leg", the SAME assembler produces a biped,
# a quadruped, or anything else — the topology is data, not code. Later stages
# (measure, stance discovery, gait) read this graph and never touch part names.
#
# It is a tree today (one parent per part). Closed loops (a hand gripping a foot)
# are a later concern; `validate()` rejects them so nothing downstream has to
# cope with a cycle yet.

var parts: Dictionary = {}     # id -> BodyPart
var root_id: String = ""

# Each joint: { "parent": id, "parent_socket": name, "child": id, "child_socket": name,
#               "dof": Array }.
# The child's child_socket frame is made to coincide with the parent's
# parent_socket frame, so: child_world = parent_world * parentSocket * childSocket^-1.
#
# `dof` is the joint's rotational freedom, expressed in the parent-socket frame —
# an Array of { "axis": Vector3, "min": float, "max": float } (radians), one entry
# per axis. [] = a rigid weld (stage 1's default). A hinge is one entry, a ball
# three. assemble() ignores it (rest pose = all angles 0); it is METADATA that
# stage 2 measures and stage 5's IK will drive within [min,max].
var joints: Array = []


# A rotational DOF descriptor. Helpers keep the test/author code readable.
static func hinge(axis: Vector3, min_rad: float, max_rad: float) -> Array:
	return [{"axis": axis.normalized(), "min": min_rad, "max": max_rad}]


static func ball(cone_rad: float, twist_rad: float) -> Array:
	return [
		{"axis": Vector3.RIGHT, "min": -cone_rad, "max": cone_rad},
		{"axis": Vector3.UP, "min": -twist_rad, "max": twist_rad},
		{"axis": Vector3.FORWARD, "min": -cone_rad, "max": cone_rad},
	]


func add_part(part: BodyPart) -> void:
	parts[part.id] = part
	if root_id == "":
		root_id = part.id


func set_root(id: String) -> void:
	root_id = id


# Pin child.child_socket onto parent.parent_socket. Returns false (and adds
# nothing) if either part or socket is unknown, so a typo can't silently create a
# floating part.
func join(parent_id: String, parent_socket: String, child_id: String, child_socket: String, dof: Array = []) -> bool:
	if not parts.has(parent_id) or not parts.has(child_id):
		return false
	if not (parts[parent_id] as BodyPart).has_socket(parent_socket):
		return false
	if not (parts[child_id] as BodyPart).has_socket(child_socket):
		return false
	joints.append({
		"parent": parent_id, "parent_socket": parent_socket,
		"child": child_id, "child_socket": child_socket,
		"dof": dof,
	})
	return true


# World transform of every part, keyed by id. `root_transform` places the root
# part in the world. Unreachable parts are omitted (validate() flags them). A
# missing socket resolves to IDENTITY rather than crashing the walk.
func assemble(root_transform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var out: Dictionary = {}
	if root_id == "" or not parts.has(root_id):
		return out
	out[root_id] = root_transform
	# Children indexed by parent for an explicit BFS (so depth is bounded by the
	# tree, and a cycle simply never re-enqueues an already-placed part).
	var kids: Dictionary = _children_by_parent()
	var queue: Array = [root_id]
	while not queue.is_empty():
		var pid: String = queue.pop_front()
		var parent_world: Transform3D = out[pid]
		for j in kids.get(pid, []):
			var cid: String = j["child"]
			if out.has(cid):
				continue  # already placed — a second parent or a loop; validate() reports it
			var ps: Transform3D = (parts[pid] as BodyPart).socket(j["parent_socket"])
			var cs: Transform3D = (parts[cid] as BodyPart).socket(j["child_socket"])
			out[cid] = parent_world * ps * cs.affine_inverse()
			queue.append(cid)
	return out


# World position of a named socket on a part, given an assembly. Endpoint sockets
# (a foot's "tip") are what stages 2+ measure and plant.
func socket_world(assembly: Dictionary, part_id: String, socket_name: String) -> Vector3:
	if not assembly.has(part_id) or not parts.has(part_id):
		return Vector3.ZERO
	return ((assembly[part_id] as Transform3D) * (parts[part_id] as BodyPart).socket(socket_name)).origin


# Structural checks. Returns a list of human-readable problems; empty == sound.
# Catches the failure modes the assembler assumes away: no/unknown root, a part
# with two parents, an orphan (unreachable from root), a cycle, and any joint
# naming a socket the part does not have.
func validate() -> Array:
	var errors: Array = []
	if root_id == "":
		errors.append("no root set")
		return errors
	if not parts.has(root_id):
		errors.append("root '%s' is not a part" % root_id)
		return errors

	var parent_count: Dictionary = {}   # child id -> how many joints target it
	for j in joints:
		for key in ["parent", "child"]:
			if not parts.has(j[key]):
				errors.append("joint references unknown part '%s'" % j[key])
		if parts.has(j["parent"]) and not (parts[j["parent"]] as BodyPart).has_socket(j["parent_socket"]):
			errors.append("part '%s' has no socket '%s'" % [j["parent"], j["parent_socket"]])
		if parts.has(j["child"]) and not (parts[j["child"]] as BodyPart).has_socket(j["child_socket"]):
			errors.append("part '%s' has no socket '%s'" % [j["child"], j["child_socket"]])
		parent_count[j["child"]] = int(parent_count.get(j["child"], 0)) + 1

	for cid in parent_count:
		if int(parent_count[cid]) > 1:
			errors.append("part '%s' has %d parents (tree only)" % [cid, parent_count[cid]])
	if parent_count.has(root_id):
		errors.append("root '%s' also has a parent" % root_id)

	# Reachability: assemble() places exactly the parts reachable from the root
	# without revisiting, so anything missing is an orphan or trapped behind a loop.
	var reached: Dictionary = assemble()
	for pid in parts:
		if not reached.has(pid):
			errors.append("part '%s' is not reachable from root '%s' (orphan or cycle)" % [pid, root_id])
	return errors


func is_valid() -> bool:
	return validate().is_empty()


func part_count() -> int:
	return parts.size()


func _children_by_parent() -> Dictionary:
	var kids: Dictionary = {}
	for j in joints:
		kids.get_or_add(j["parent"], []).append(j)
	return kids


# --- topology queries stage 2+ read (chain tracing) ---------------------------

# The joint that attaches `id` to its parent, or {} if `id` is the root/orphan.
func parent_joint_of(id: String) -> Dictionary:
	for j in joints:
		if j["child"] == id:
			return j
	return {}


# Parts with no children — the tips of the tree (feet, head, hands live here).
func leaves() -> Array:
	var has_child: Dictionary = {}
	for j in joints:
		has_child[j["parent"]] = true
	var out: Array = []
	for pid in parts:
		if not has_child.has(pid):
			out.append(pid)
	return out


# Ordered joints from the root down to `id` (root-side first). Empty for the root.
# Returns [] if `id` is unreachable (an orphan) rather than looping forever.
func joints_to(id: String) -> Array:
	var rev: Array = []
	var cur: String = id
	var guard: int = 0
	while cur != root_id and guard < parts.size() + 1:
		var j: Dictionary = parent_joint_of(cur)
		if j.is_empty():
			return []  # not reachable from root
		rev.append(j)
		cur = j["parent"]
		guard += 1
	rev.reverse()
	return rev


# Every contact endpoint in the body: {part, socket, world_pos}. What stage 3 plants.
func endpoints_world(assembly: Dictionary) -> Array:
	var out: Array = []
	for pid in parts:
		for sname in (parts[pid] as BodyPart).endpoints:
			out.append({"part": pid, "socket": sname, "world": socket_world(assembly, pid, sname)})
	return out


# Every MANIPULATION effector (a hand) in the body: {part, socket, world}. What
# stage-9 attacks reach with — the analogue of endpoints_world for support.
func manipulators_world(assembly: Dictionary) -> Array:
	var out: Array = []
	for pid in parts:
		for sname in (parts[pid] as BodyPart).manipulators:
			out.append({"part": pid, "socket": sname, "world": socket_world(assembly, pid, sname)})
	return out


# --- M7: connected components & sub-graphs (for detachment) -------------------

# Connected components of the parts (joints are undirected attachments), with an
# optional joint index treated as CUT. Returns an Array of Arrays of part ids —
# one component per surviving connected group. A tree with one joint cut yields
# exactly two components.
func connected_components(cut_joint: int = -1) -> Array:
	var adj: Dictionary = {}
	for pid in parts:
		adj[pid] = []
	for i in range(joints.size()):
		if i == cut_joint:
			continue
		var j: Dictionary = joints[i]
		if parts.has(j["parent"]) and parts.has(j["child"]):
			(adj[j["parent"]] as Array).append(j["child"])
			(adj[j["child"]] as Array).append(j["parent"])
	var seen: Dictionary = {}
	var comps: Array = []
	for pid in parts:
		if seen.has(pid):
			continue
		var comp: Array = []
		var queue: Array = [pid]
		seen[pid] = true
		while not queue.is_empty():
			var cur: String = queue.pop_back()
			comp.append(cur)
			for n in adj[cur]:
				if not seen.has(n):
					seen[n] = true
					queue.append(n)
		comps.append(comp)
	return comps


# The component (Array of part ids) that contains `part_id`, optionally after a cut.
func component_containing(part_id: String, cut_joint: int = -1) -> Array:
	for comp in connected_components(cut_joint):
		if part_id in comp:
			return comp
	return []


# Build a NEW BodyGraph from a subset of parts, rooted at `root_id`. Parts are
# duplicated (the original graph is untouched); only joints with both ends inside
# the subset — and not the cut one — are kept. Used to recompile a severed body.
func subgraph(part_ids: Array, root_id: String, cut_joint: int = -1) -> BodyGraph:
	var idset: Dictionary = {}
	for p in part_ids:
		idset[p] = true
	var g := BodyGraph.new()
	for p in part_ids:
		if parts.has(p):
			g.add_part((parts[p] as BodyPart).duplicate_part())
	if idset.has(root_id):
		g.set_root(root_id)
	for i in range(joints.size()):
		if i == cut_joint:
			continue
		var j: Dictionary = joints[i]
		if idset.has(j["parent"]) and idset.has(j["child"]):
			g.join(j["parent"], j["parent_socket"], j["child"], j["child_socket"], j.get("dof", []))
	return g
