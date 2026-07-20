class_name Detachment
extends RefCounted

# Stage / TDD M7 §10: sever an attachment and recompile the survivor.
#
# Cutting a joint splits the graph into connected components. The component that
# contains the CORE part (the head — identity lives there, §11) is recompiled: a
# fresh sub-graph, re-measured and re-stanced. If it can still stand it stays
# controllable; if not, it is flagged `collapsed`. Every other component is
# DETACHED — in the scene layer those parts become RigidBody3D debris; here we
# just hand back their sub-graphs.
#
# Pure graph logic, no scene nodes — so it is fully headless-testable. The
# physics hand-off and possession transfer live in the node architecture (later).


# Sever `joint_index` and recompile around `core_id` (the head). Returns:
#   {
#     controlled: { graph, part_ids, stance, standing:bool, collapsed:bool },
#     detached:   Array of { graph, part_ids, root },
#     severed:    the cut joint dict,
#   }
static func sever(graph: BodyGraph, joint_index: int, core_id: String) -> Dictionary:
	var comps: Array = graph.connected_components(joint_index)
	var controlled_ids: Array = []
	var detached_ids: Array = []
	for comp in comps:
		if core_id in comp:
			controlled_ids = comp
		else:
			detached_ids.append(comp)

	var controlled := _recompile(graph, controlled_ids, core_id, joint_index)

	var detached: Array = []
	for comp in detached_ids:
		var droot: String = _detached_root(graph, comp, joint_index)
		detached.append({
			"graph": graph.subgraph(comp, droot, joint_index),
			"part_ids": comp, "root": droot,
		})

	return {"controlled": controlled, "detached": detached, "severed": graph.joints[joint_index]}


# Recompile one component into a controllable body (or a collapsed one).
static func _recompile(graph: BodyGraph, ids: Array, core_id: String, cut_joint: int) -> Dictionary:
	if ids.is_empty():
		return {"graph": null, "part_ids": ids, "stance": {}, "standing": false, "collapsed": true}
	# Keep the original root if it survived; otherwise root at the core part.
	var root_id: String = graph.root_id if (graph.root_id in ids) else core_id
	if not (root_id in ids):
		root_id = ids[0]
	var sub := graph.subgraph(ids, root_id, cut_joint)
	var stance := StanceGenerator.new(sub).generate()
	var standing: bool = (not stance.is_empty()) and stance.get("stable", false)
	return {
		"graph": sub, "part_ids": ids, "stance": stance,
		"standing": standing, "collapsed": not standing,
	}


# A detached component roots at the severed limb's top (the cut joint's child if
# it landed here), so it assembles outward from the break.
static func _detached_root(graph: BodyGraph, comp: Array, joint_index: int) -> String:
	var j: Dictionary = graph.joints[joint_index]
	if j["child"] in comp:
		return j["child"]
	if j["parent"] in comp:
		return j["parent"]
	return comp[0]


# Convenience: find the joint index that attaches `part_id` to its parent, so a
# caller can say "sever this limb" by naming the part rather than a joint number.
static func joint_attaching(graph: BodyGraph, part_id: String) -> int:
	for i in range(graph.joints.size()):
		if graph.joints[i]["child"] == part_id:
			return i
	return -1
