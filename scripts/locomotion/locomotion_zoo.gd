class_name LocomotionZoo
extends RefCounted

# A small catalogue of demo creatures for the generic locomotion system, built
# ONLY from BodyPart/BodyGraph — no "arm"/"leg" logic anywhere. Shared by the
# visual gallery (locomotion_gallery.gd) and its headless smoke test so both
# show the exact same bodies.
#
# Every creature uses SINGLE-SEGMENT legs, so stage 3's foot target sits exactly
# one leg-length from the hip and the gallery can draw each leg as one straight
# bone. Bent, multi-segment legs wait for stage-5 IK.


# Each entry: { name, graph, blurb }. Order = left-to-right in the gallery.
static func catalog() -> Array:
	return [
		{"name": "Biped", "graph": biped(), "blurb": "2 legs · hip-width stand"},
		{"name": "Quadruped", "graph": quadruped(), "blurb": "4 legs · wide base"},
		{"name": "Hexapod", "graph": hexapod(), "blurb": "6 legs · same code"},
		{"name": "Snake", "graph": snake(), "blurb": "10 segments · rests on its belly", "mode": "rest"},
		{"name": "Off-centre load", "graph": offcenter_load(), "blurb": "heavy boom · tips over"},
	]


# One rigid box leg: mount at the hip (root) and a contact tip one length down.
# Add a TWO-segment leg (thigh + shin, hinged knee) whose tip is a contact
# endpoint, mounted on `parent_socket` of `parent_id`. Two segments give stage-5
# IK a knee to bend; `reach_max` (thigh + shin) is unchanged from a one-box leg,
# so the stance search behaves the same.
static func add_leg(g: BodyGraph, parent_id: String, parent_socket: String, id: String, total_len: float, mass: float) -> void:
	var half := total_len * 0.5
	var thigh := BodyPart.new(id + "_thigh", Vector3(0.16, half, 0.18), mass * 0.55)
	thigh.center_offset = Vector3(0, -half * 0.5, 0)
	thigh.add_socket("root", Vector3.ZERO)
	thigh.add_socket("knee", Vector3(0, -half, 0))
	var shin := BodyPart.new(id + "_shin", Vector3(0.13, half, 0.15), mass * 0.45)
	shin.center_offset = Vector3(0, -half * 0.5, 0)
	shin.add_socket("root", Vector3.ZERO)
	shin.add_socket("tip", Vector3(0, -half, 0))
	shin.mark_endpoint("tip")
	g.add_part(thigh)
	g.add_part(shin)
	g.join(parent_id, parent_socket, id + "_thigh", "root", BodyGraph.hinge(Vector3.RIGHT, -2.4, 0.3))
	g.join(id + "_thigh", "knee", id + "_shin", "root", BodyGraph.hinge(Vector3.RIGHT, 0.0, 2.6))


static func biped(leg_len: float = 0.62) -> BodyGraph:
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.7, 0.4), 10.0)
	torso.add_socket("hip_r", Vector3(0.16, -0.35, 0))
	torso.add_socket("hip_l", Vector3(-0.16, -0.35, 0))
	torso.add_socket("neck", Vector3(0, 0.35, 0))
	g.add_part(torso)
	g.set_root("torso")
	add_leg(g, "torso", "hip_r", "leg_r", leg_len, 3.0)
	add_leg(g, "torso", "hip_l", "leg_l", leg_len, 3.0)
	var head := BodyPart.new("head", Vector3(0.32, 0.32, 0.32), 0.7)
	head.add_socket("root", Vector3(0, -0.16, 0))
	g.add_part(head)
	g.join("torso", "neck", "head", "root")
	return g


static func quadruped(leg_len: float = 0.5) -> BodyGraph:
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.4, 1.0), 14.0)
	for corner in ["fr", "fl", "br", "bl"]:
		var zc: float = 0.35 if corner.begins_with("f") else -0.35
		var xc: float = 0.16 if corner.ends_with("r") else -0.16
		torso.add_socket("hip_" + corner, Vector3(xc, -0.2, zc))
	torso.add_socket("neck", Vector3(0, 0.1, 0.5))
	g.add_part(torso)
	g.set_root("torso")
	for corner in ["fr", "fl", "br", "bl"]:
		add_leg(g, "torso", "hip_" + corner, "leg_" + corner, leg_len, 2.0)
	var head := BodyPart.new("head", Vector3(0.28, 0.28, 0.34), 1.2)
	head.add_socket("root", Vector3(0, 0, -0.17))
	g.add_part(head)
	g.join("torso", "neck", "head", "root")
	return g


static func hexapod(leg_len: float = 0.5) -> BodyGraph:
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.35, 1.6), 16.0)
	var zs := [0.6, 0.0, -0.6]
	for i in range(zs.size()):
		for side in ["r", "l"]:
			var xc: float = 0.2 if side == "r" else -0.2
			torso.add_socket("hip_%d%s" % [i, side], Vector3(xc, -0.17, zs[i]))
	g.add_part(torso)
	g.set_root("torso")
	for i in range(zs.size()):
		for side in ["r", "l"]:
			add_leg(g, "torso", "hip_%d%s" % [i, side], "leg_%d%s" % [i, side], leg_len, 1.6)
	return g


# Add a TWO-segment arm (upper + fore, ball shoulder + hinge elbow) whose tip is a
# MANIPULATION effector (a hand) — reached by attacks, never planted as support.
static func add_arm(g: BodyGraph, parent_id: String, parent_socket: String, id: String, total_len: float, mass: float) -> void:
	var half := total_len * 0.5
	var upper := BodyPart.new(id + "_upper", Vector3(0.13, half, 0.14), mass * 0.55)
	upper.center_offset = Vector3(0, -half * 0.5, 0)
	upper.add_socket("root", Vector3.ZERO)
	upper.add_socket("elbow", Vector3(0, -half, 0))
	var fore := BodyPart.new(id + "_fore", Vector3(0.11, half, 0.12), mass * 0.45)
	fore.center_offset = Vector3(0, -half * 0.5, 0)
	fore.add_socket("root", Vector3.ZERO)
	fore.add_socket("hand", Vector3(0, -half, 0))
	fore.mark_manipulator("hand")
	g.add_part(upper)
	g.add_part(fore)
	g.join(parent_id, parent_socket, id + "_upper", "root", BodyGraph.ball(2.0, 1.0))
	g.join(id + "_upper", "elbow", id + "_fore", "root", BodyGraph.hinge(Vector3.RIGHT, -2.6, 0.0))


# A biped with two arms — the arms are manipulation chains (hands), so stage 3
# still stands it on its two feet while stage-9 attacks reach with a hand.
static func biped_with_arms(arm_len: float = 0.55) -> BodyGraph:
	var g := biped()
	var torso: BodyPart = g.parts["torso"]
	torso.add_socket("sh_r", Vector3(0.28, 0.2, 0))
	torso.add_socket("sh_l", Vector3(-0.28, 0.2, 0))
	add_arm(g, "torso", "sh_r", "arm_r", arm_len, 2.0)
	add_arm(g, "torso", "sh_l", "arm_l", arm_len, 2.0)
	return g


# A limbless slider: a long chain of segments curved in the ground plane via
# ROTATED joint sockets (a stage-1 feature), with a belly contact under each
# segment. It has no legs to stand on, so the gallery rests it on its belly
# (StanceGenerator.resting_stance) instead of searching for a legged stance —
# the balance check is the same Geom2d support-polygon / CoM-margin math.
static func snake() -> BodyGraph:
	var g := BodyGraph.new()
	var seg_count := 10
	var seg_len := 0.30
	var yaw := deg_to_rad(16.0)
	for i in range(seg_count):
		var t := float(i) / float(seg_count - 1)
		var w := lerpf(0.24, 0.10, t)            # taper the width toward the tail
		var seg := BodyPart.new("seg%d" % i, Vector3(w, 0.17, seg_len), lerpf(2.0, 0.5, t))
		seg.add_socket("back", Vector3(0, 0, seg_len * 0.5))
		seg.add_socket("front", Transform3D(Basis(Vector3.UP, yaw), Vector3(0, 0, -seg_len * 0.5)))
		seg.add_socket("belly", Vector3(0, -0.085, 0))
		seg.mark_endpoint("belly")
		g.add_part(seg)
		if i == 0:
			g.set_root("seg0")
		else:
			g.join("seg%d" % (i - 1), "front", "seg%d" % i, "back")
	return g


# A biped carrying a heavy weight on a long boom — its centre of mass falls
# outside the two-foot base, so stage 3 must report it UNSTABLE.
static func offcenter_load() -> BodyGraph:
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.7, 0.4), 4.0)
	torso.add_socket("hip_r", Vector3(0.16, -0.35, 0))
	torso.add_socket("hip_l", Vector3(-0.16, -0.35, 0))
	torso.add_socket("boom", Vector3(1.2, 0.0, 0.0))
	g.add_part(torso)
	g.set_root("torso")
	add_leg(g, "torso", "hip_r", "leg_r", 0.62, 2.0)
	add_leg(g, "torso", "hip_l", "leg_l", 0.62, 2.0)
	var weight := BodyPart.new("weight", Vector3(0.35, 0.35, 0.35), 40.0)
	weight.add_socket("root", Vector3.ZERO)
	g.add_part(weight)
	g.join("torso", "boom", "weight", "root")
	return g
