extends SceneTree

# Stage-3 test: discover a stationary stance by searching for the widest stable
# base. Same generator, biped and quadruped.
#   <godot> --headless --path . --script res://scripts/locomotion/test_stance_generator.gd

var _fail := 0


func _initialize() -> void:
	var biped_margin: float = _test_biped()
	var quad_margin: float = _test_quadruped()
	_check("quadruped base is more stable than biped (%.3f > %.3f)" % [quad_margin, biped_margin],
		quad_margin > biped_margin)
	_test_no_stance()
	_test_offcenter_instability()
	_test_stance_width()
	if _fail == 0:
		print("STANCE_TEST: ALL PASS")
	else:
		print("STANCE_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


# stance_width and reach_fraction are independent: at the SAME reach_fraction,
# a wider stance_width splays the feet farther without changing the torso height.
func _test_stance_width() -> void:
	print("[stance width] — width and height are independent knobs")
	var g := LocomotionZoo.quadruped()
	var narrow := StanceGenerator.new(g).generate({"reach_fraction": 0.8, "stance_width": 0.2})
	var wide := StanceGenerator.new(g).generate({"reach_fraction": 0.8, "stance_width": 0.9})
	_check("narrow and wide both found a stance", not narrow.is_empty() and not wide.is_empty())
	_check("wider stance_width splays the feet farther (%.2f -> %.2f)" % [_spread(narrow), _spread(wide)],
		_spread(wide) > _spread(narrow) + 0.1)
	_check("torso height stays set by reach_fraction (Δ %.3f)" % absf(narrow["torso_height"] - wide["torso_height"]),
		absf(narrow["torso_height"] - wide["torso_height"]) < 0.05)
	_check("both stay stable", narrow.get("stable", false) and wide.get("stable", false))


func _spread(st: Dictionary) -> float:
	var m := 0.0
	for ct in st["contacts"]:
		var p: Vector3 = ct["pos"]
		m = maxf(m, Vector2(p.x, p.z).length())
	return m


func _leg(id: String, length: float, mass: float) -> BodyPart:
	var leg := BodyPart.new(id, Vector3(0.18, length, 0.18), mass)
	leg.center_offset = Vector3(0, -length * 0.5, 0)
	leg.add_socket("root", Vector3.ZERO)
	leg.add_socket("tip", Vector3(0, -length, 0))
	leg.mark_endpoint("tip")
	return leg


func _test_biped() -> float:
	print("[biped stance]")
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.7, 0.4), 10.0)
	torso.add_socket("hip_r", Vector3(0.16, -0.35, 0))
	torso.add_socket("hip_l", Vector3(-0.16, -0.35, 0))
	torso.add_socket("neck", Vector3(0, 0.35, 0))
	g.add_part(torso); g.set_root("torso")
	g.add_part(_leg("leg_r", 0.62, 3.0)); g.add_part(_leg("leg_l", 0.62, 3.0))
	g.join("torso", "hip_r", "leg_r", "root"); g.join("torso", "hip_l", "leg_l", "root")
	var head := BodyPart.new("head", Vector3(0.32, 0.32, 0.32), 0.7)
	head.add_socket("root", Vector3(0, -0.16, 0)); g.add_part(head); g.join("torso", "neck", "head", "root")

	var st := StanceGenerator.new(g).generate()
	print(StanceGenerator.describe(st))
	_check("biped found a stance", not st.is_empty())
	_check("biped stance is stable (margin > 0)", st.get("stable", false))
	_check("biped has 2 contacts", (st.get("contacts", []) as Array).size() == 2)
	var cs: Array = st["contacts"]
	_check("feet symmetric about the centreline",
		absf((cs[0]["pos"] as Vector3).x + (cs[1]["pos"] as Vector3).x) < 0.01)
	_check("feet at natural hip width, not splayed to the reach limit",
		absf((cs[0]["pos"] as Vector3).x) < 0.30)
	_check("feet on the ground (y~0)", absf((cs[0]["pos"] as Vector3).y) < 0.001)
	_check("torso height within reach", st["torso_height"] > 0.3 and st["torso_height"] < 0.97)
	return st["margin"]


func _test_quadruped() -> float:
	print("[quadruped stance]")
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.4, 1.0), 14.0)
	for corner in ["fr", "fl", "br", "bl"]:
		var zc: float = 0.35 if corner.begins_with("f") else -0.35
		var xc: float = 0.16 if corner.ends_with("r") else -0.16
		torso.add_socket("hip_" + corner, Vector3(xc, -0.2, zc))
	g.add_part(torso); g.set_root("torso")
	for corner in ["fr", "fl", "br", "bl"]:
		g.add_part(_leg("leg_" + corner, 0.5, 2.0))
		g.join("torso", "hip_" + corner, "leg_" + corner, "root")

	var st := StanceGenerator.new(g).generate()
	print(StanceGenerator.describe(st))
	_check("quadruped found a stance", not st.is_empty())
	_check("quadruped stable", st.get("stable", false))
	_check("quadruped has 4 contacts", (st.get("contacts", []) as Array).size() == 4)
	_check("quadruped base has real area (2D polygon)", st.get("area", 0.0) > 0.1)
	return st["margin"]


func _test_no_stance() -> void:
	print("[no stance] — legs too short to reach the ground")
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.7, 0.4), 10.0)
	torso.add_socket("hip_r", Vector3(0.16, -0.35, 0))
	torso.add_socket("hip_l", Vector3(-0.16, -0.35, 0))
	g.add_part(torso); g.set_root("torso")
	g.add_part(_leg("leg_r", 0.01, 1.0)); g.add_part(_leg("leg_l", 0.01, 1.0))
	g.join("torso", "hip_r", "leg_r", "root"); g.join("torso", "hip_l", "leg_l", "root")
	var st := StanceGenerator.new(g).generate()
	_check("stub legs -> no stance found", st.is_empty())


func _test_offcenter_instability() -> void:
	print("[off-centre] — a heavy weight far to one side must read unstable")
	var g := BodyGraph.new()
	var torso := BodyPart.new("torso", Vector3(0.5, 0.7, 0.4), 4.0)
	torso.add_socket("hip_r", Vector3(0.16, -0.35, 0))
	torso.add_socket("hip_l", Vector3(-0.16, -0.35, 0))
	torso.add_socket("boom", Vector3(1.4, 0.0, 0.0))   # a long arm to hang weight off
	g.add_part(torso); g.set_root("torso")
	g.add_part(_leg("leg_r", 0.62, 2.0)); g.add_part(_leg("leg_l", 0.62, 2.0))
	g.join("torso", "hip_r", "leg_r", "root"); g.join("torso", "hip_l", "leg_l", "root")
	var weight := BodyPart.new("weight", Vector3(0.3, 0.3, 0.3), 40.0)  # heavy, far +x
	weight.add_socket("root", Vector3.ZERO)
	g.add_part(weight); g.join("torso", "boom", "weight", "root")
	var st := StanceGenerator.new(g).generate()
	print(StanceGenerator.describe(st))
	_check("off-centre CoM detected outside the base (unstable)", not st.get("stable", true))
	_check("margin is negative", st.get("margin", 0.0) < 0.0)
