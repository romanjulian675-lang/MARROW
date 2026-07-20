extends SceneTree

# Stage-1 test harness for BodyGraph / BodyPart. Re-runnable, no scene needed:
#   <godot> --headless --path . --script res://scripts/locomotion/test_body_graph.gd
# Proves the SAME assembler builds a biped and a quadruped, and that validate()
# catches every structural failure mode the assembler assumes away.

var _fail := 0


func _initialize() -> void:
	_test_biped()
	_test_quadruped()
	_test_validation()
	_test_socket_orientation()
	if _fail == 0:
		print("BODY_GRAPH_TEST: ALL PASS")
	else:
		print("BODY_GRAPH_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_fail += 1
		print("  FAIL ", label)


func _near(label: String, got: Vector3, want: Vector3, eps := 0.001) -> void:
	_check("%s (got %s want %s)" % [label, got, want], got.distance_to(want) < eps)


# A leg whose ORIGIN is its top mount; box hangs down `length`; "tip" is the foot.
func _make_leg(id: String, length: float) -> BodyPart:
	var leg := BodyPart.new(id, Vector3(0.18, length, 0.18), 3.0)
	leg.center_offset = Vector3(0, -length * 0.5, 0)
	leg.add_socket("root", Vector3.ZERO)
	leg.add_socket("tip", Vector3(0, -length, 0))
	return leg


func _torso(sockets: Dictionary) -> BodyPart:
	var t := BodyPart.new("torso", Vector3(0.5, 0.7, 0.4), 10.0)
	for name in sockets:
		t.add_socket(name, sockets[name])
	return t


func _test_biped() -> void:
	print("[biped]")
	var g := BodyGraph.new()
	g.add_part(_torso({
		"hip_r": Vector3(0.16, -0.35, 0.0),
		"hip_l": Vector3(-0.16, -0.35, 0.0),
		"neck": Vector3(0.0, 0.35, 0.0),
	}))
	g.set_root("torso")
	g.add_part(_make_leg("leg_r", 0.62))
	g.add_part(_make_leg("leg_l", 0.62))
	var head := BodyPart.new("head", Vector3(0.32, 0.32, 0.32), 0.7)
	head.add_socket("root", Vector3(0, -0.16, 0))
	g.add_part(head)
	_check("join leg_r", g.join("torso", "hip_r", "leg_r", "root"))
	_check("join leg_l", g.join("torso", "hip_l", "leg_l", "root"))
	_check("join head", g.join("torso", "neck", "head", "root"))
	_check("join with bad socket returns false", not g.join("torso", "nope", "head", "root"))
	_check("biped valid", g.is_valid())

	var a := g.assemble()  # torso at origin
	_near("foot_r under hip_r", g.socket_world(a, "leg_r", "tip"), Vector3(0.16, -0.97, 0.0))
	_near("foot_l under hip_l", g.socket_world(a, "leg_l", "tip"), Vector3(-0.16, -0.97, 0.0))
	# head origin sits so its "root" (at -0.16) meets the neck (at +0.35): origin +0.51
	_near("head placed on neck", (a["head"] as Transform3D).origin, Vector3(0.0, 0.51, 0.0))
	_check("2 feet on the ground plane (same Y)",
		absf(g.socket_world(a, "leg_r", "tip").y - g.socket_world(a, "leg_l", "tip").y) < 0.001)


func _test_quadruped() -> void:
	print("[quadruped] — same assembler, different topology")
	var g := BodyGraph.new()
	g.add_part(_torso({
		"hip_fr": Vector3(0.16, -0.20, 0.30),
		"hip_fl": Vector3(-0.16, -0.20, 0.30),
		"hip_br": Vector3(0.16, -0.20, -0.30),
		"hip_bl": Vector3(-0.16, -0.20, -0.30),
	}))
	g.set_root("torso")
	for corner in ["fr", "fl", "br", "bl"]:
		g.add_part(_make_leg("leg_" + corner, 0.5))
		_check("join leg_" + corner, g.join("torso", "hip_" + corner, "leg_" + corner, "root"))
	_check("quadruped valid", g.is_valid())
	_check("quadruped has 5 parts", g.part_count() == 5)

	var a := g.assemble()
	var feet := []
	for corner in ["fr", "fl", "br", "bl"]:
		feet.append(g.socket_world(a, "leg_" + corner, "tip"))
	# all four feet at the same height (a flat stance) and at the four corners
	var y0: float = feet[0].y
	var flat := true
	for f in feet:
		if absf(f.y - y0) > 0.001:
			flat = false
	_check("4 feet coplanar (flat quadruped stance)", flat)
	_near("front-right foot", feet[0], Vector3(0.16, -0.70, 0.30))
	_near("back-left foot", feet[3], Vector3(-0.16, -0.70, -0.30))


func _test_validation() -> void:
	print("[validation]")
	# orphan
	var g1 := BodyGraph.new()
	g1.add_part(_torso({"hip_r": Vector3(0.16, -0.35, 0)}))
	g1.set_root("torso")
	g1.add_part(_make_leg("floating", 0.6))  # never joined
	_check("orphan detected", not g1.is_valid())

	# two parents
	var g2 := BodyGraph.new()
	g2.add_part(_torso({"hip_r": Vector3(0.16, -0.35, 0), "hip_l": Vector3(-0.16, -0.35, 0)}))
	g2.set_root("torso")
	g2.add_part(_make_leg("leg", 0.6))
	g2.join("torso", "hip_r", "leg", "root")
	g2.join("torso", "hip_l", "leg", "root")
	_check("two-parents detected", not g2.is_valid())

	# cycle (a<->b)
	var g3 := BodyGraph.new()
	var a := BodyPart.new("a", Vector3.ONE, 1.0); a.add_socket("s", Vector3(0, 1, 0))
	var b := BodyPart.new("b", Vector3.ONE, 1.0); b.add_socket("s", Vector3(0, 1, 0))
	g3.add_part(a); g3.add_part(b); g3.set_root("a")
	g3.join("a", "s", "b", "s")
	g3.join("b", "s", "a", "s")
	_check("cycle detected", not g3.is_valid())

	# a clean single-part graph is valid
	var g4 := BodyGraph.new()
	g4.add_part(_torso({}))
	_check("lone root is valid", g4.is_valid())


func _test_socket_orientation() -> void:
	print("[socket orientation] — a rotated socket rotates the child")
	var g := BodyGraph.new()
	var base := BodyPart.new("base", Vector3.ONE, 1.0)
	# a socket that faces +X (yaw 90°) at height 1
	base.add_socket("out", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 1, 0)))
	g.add_part(base); g.set_root("base")
	var arm := _make_leg("arm", 1.0)  # extends down -Y from its root
	g.add_part(arm)
	g.join("base", "out", "arm", "root")
	var a := g.assemble()
	# arm's -Y tip, rotated by the socket's +Y 90° yaw, stays -Y (yaw doesn't move -Y),
	# so the tip lands 1 below the socket at (0,0,0). Verify the arm BASIS rotated.
	var arm_x: Vector3 = (a["arm"] as Transform3D).basis.x
	_check("child inherits socket rotation (local +X now world -Z)", arm_x.distance_to(Vector3(0, 0, -1)) < 0.01)
	_near("rotated socket still places tip below it", g.socket_world(a, "arm", "tip"), Vector3(0, 0, 0))
