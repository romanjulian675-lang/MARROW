extends SceneTree

# Stage-2 test: measure reach / mass / joint limits / centre of mass, generically.
#   <godot> --headless --path . --script res://scripts/locomotion/test_body_measure.gd
# Uses 2-SEGMENT legs (thigh + shin + knee) so multi-joint reach is exercised, and
# a deliberately BENT leg so rest reach < fully-extended reach.

var _fail := 0


func _initialize() -> void:
	_test_biped_measure()
	_test_bent_reach()
	_test_quadruped_measure_and_display()
	if _fail == 0:
		print("BODY_MEASURE_TEST: ALL PASS")
	else:
		print("BODY_MEASURE_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


func _approx(label: String, got: float, want: float, eps := 0.005) -> void:
	_check("%s (got %.4f want %.4f)" % [label, got, want], absf(got - want) < eps)


# thigh/shin: origin at top mount, box hangs down, sockets root(top)/end(bottom).
func _segment(id: String, length: float, mass: float, knee_bend := 0.0) -> BodyPart:
	var s := BodyPart.new(id, Vector3(0.16, length, 0.16), mass)
	s.center_offset = Vector3(0, -length * 0.5, 0)
	s.add_socket("root", Vector3.ZERO)
	# a bent knee socket tilts whatever mounts below it, costing reach at rest
	s.add_socket("end", Transform3D(Basis(Vector3.RIGHT, knee_bend), Vector3(0, -length, 0)))
	return s


func _biped(knee_bend := 0.0) -> BodyGraph:
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.7, 0.4), 10.0)
	torso.add_socket("hip_r", Vector3(0.16, -0.35, 0))
	torso.add_socket("hip_l", Vector3(-0.16, -0.35, 0))
	torso.add_socket("neck", Vector3(0, 0.35, 0))
	g.add_part(torso); g.set_root("torso")
	for side in ["r", "l"]:
		var thigh := _segment("thigh_" + side, 0.31, 3.0, knee_bend)
		var shin := _segment("shin_" + side, 0.31, 2.0)
		shin.mark_endpoint("end")  # the foot/contact tip
		g.add_part(thigh); g.add_part(shin)
		g.join("torso", "hip_" + side, "thigh_" + side, "root", BodyGraph.ball(deg_to_rad(70), deg_to_rad(30)))
		g.join("thigh_" + side, "end", "shin_" + side, "root", BodyGraph.hinge(Vector3.RIGHT, deg_to_rad(-140), 0.0))
	var head := BodyPart.new("head", Vector3(0.32, 0.32, 0.32), 0.7)
	head.add_socket("root", Vector3(0, -0.16, 0))
	g.add_part(head); g.join("torso", "neck", "head", "root")
	return g


func _test_biped_measure() -> void:
	print("[biped measure]")
	var g := _biped()
	_check("valid", g.is_valid())
	var m := BodyMeasure.new(g)
	_approx("total mass", m.total_mass(), 10.0 + 2 * (3.0 + 2.0) + 0.7)
	var com := m.center_of_mass()
	_check("CoM on the sagittal centreline (x~0)", absf(com.x) < 0.001)
	_check("CoM centred fore-aft (z~0)", absf(com.z) < 0.001)

	var chains := m.chains()
	_check("2 contact chains (two feet)", chains.size() == 2)
	var leg = chains[0]
	_approx("straight leg reach_max = thigh+shin", leg["reach_max"], 0.62)
	_approx("straight leg reach_rest ~= reach_max", leg["reach_rest"], leg["reach_max"])
	_approx("limb mass = thigh+shin", leg["limb_mass"], 5.0)
	_check("chain has 2 joints (hip + knee)", leg["joints"].size() == 2)
	_check("hip joint is a 3-DOF ball", int(leg["joints"][0]["dof_count"]) == 3)
	_check("knee joint is a 1-DOF hinge", int(leg["joints"][1]["dof_count"]) == 1)


func _test_bent_reach() -> void:
	print("[bent reach] — a bent knee at rest reaches less than fully extended")
	var g := _biped(deg_to_rad(50))  # 50° knee bend at rest
	var m := BodyMeasure.new(g)
	var leg = m.chains()[0]
	_approx("reach_max unchanged (segment lengths are rigid)", leg["reach_max"], 0.62)
	_check("reach_rest < reach_max when bent (%.3f < %.3f)" % [leg["reach_rest"], leg["reach_max"]],
		leg["reach_rest"] < leg["reach_max"] - 0.02)


func _test_quadruped_measure_and_display() -> void:
	print("[quadruped measure + DISPLAY]")
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.4, 1.0), 14.0)
	for corner in ["fr", "fl", "br", "bl"]:
		var zc: float = 0.35 if corner.begins_with("f") else -0.35
		var xc: float = 0.16 if corner.ends_with("r") else -0.16
		torso.add_socket("hip_" + corner, Vector3(xc, -0.2, zc))
	g.add_part(torso); g.set_root("torso")
	for corner in ["fr", "fl", "br", "bl"]:
		var thigh := _segment("thigh_" + corner, 0.26, 2.0)
		var shin := _segment("shin_" + corner, 0.26, 1.5)
		shin.mark_endpoint("end")
		g.add_part(thigh); g.add_part(shin)
		g.join("torso", "hip_" + corner, "thigh_" + corner, "root", BodyGraph.ball(deg_to_rad(60), deg_to_rad(20)))
		g.join("thigh_" + corner, "end", "shin_" + corner, "root", BodyGraph.hinge(Vector3.RIGHT, deg_to_rad(-130), 0.0))
	var m := BodyMeasure.new(g)
	_check("4 contact chains", m.chains().size() == 4)
	_approx("each leg reach_max = 0.52", m.chains()[0]["reach_max"], 0.52)
	print("---- describe() ----")
	for line in m.describe().split("\n"):
		print(line)
	print("--------------------")
