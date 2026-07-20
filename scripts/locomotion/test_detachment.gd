extends SceneTree

# Stage / M7 test: sever a limb, split the graph, recompile the survivor.
#   <godot> --headless --path . --script res://scripts/locomotion/test_detachment.gd

var _fail := 0


func _initialize() -> void:
	_test_components()
	_test_biped_loses_a_leg()
	_test_head_detaches()
	_test_quadruped_loses_a_leg()
	if _fail == 0:
		print("DETACHMENT_TEST: ALL PASS")
	else:
		print("DETACHMENT_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


func _test_components() -> void:
	print("[components] — intact body is one piece; a cut makes two")
	var g := LocomotionZoo.biped()
	_check("intact biped is a single connected component", g.connected_components().size() == 1)
	var cut := Detachment.joint_attaching(g, "leg_r_thigh")
	_check("found the joint attaching the right leg", cut >= 0)
	var comps := g.connected_components(cut)
	_check("cutting the right hip yields 2 components", comps.size() == 2)
	var sizes := [comps[0].size(), comps[1].size()]
	sizes.sort()
	_check("components split 2 (leg) + 4 (body+head)", sizes == [2, 4])


func _test_biped_loses_a_leg() -> void:
	print("[biped loses a leg] — head keeps control; can't stand on one leg")
	var g := LocomotionZoo.biped()
	var cut := Detachment.joint_attaching(g, "leg_r_thigh")
	var r := Detachment.sever(g, cut, "head")
	var ctrl: Dictionary = r["controlled"]
	print("  controlled parts %s  standing=%s" % [ctrl["part_ids"].size(), ctrl["standing"]])
	_check("controlled component keeps the head", "head" in ctrl["part_ids"])
	_check("controlled component is the 4-part body", ctrl["part_ids"].size() == 4)
	_check("recompiled body graph is valid", (ctrl["graph"] as BodyGraph).is_valid())
	_check("exactly one detached piece", (r["detached"] as Array).size() == 1)
	_check("detached piece is the 2-part leg", (r["detached"][0]["part_ids"] as Array).size() == 2)
	_check("detached leg roots at its severed top (thigh)", r["detached"][0]["root"] == "leg_r_thigh")
	_check("one-legged body can't stand -> collapses", ctrl["collapsed"])


func _test_head_detaches() -> void:
	print("[head detaches] — identity follows the head; body goes limp")
	var g := LocomotionZoo.biped()
	var cut := Detachment.joint_attaching(g, "head")
	var r := Detachment.sever(g, cut, "head")
	var ctrl: Dictionary = r["controlled"]
	_check("controlled component is the head alone", ctrl["part_ids"] == ["head"])
	_check("head alone has no stance -> head-only/collapse", ctrl["collapsed"])
	var body: Array = r["detached"][0]["part_ids"]
	_check("the detached body has 5 parts", body.size() == 5)
	_check("the detached body does NOT contain the head", not ("head" in body))


func _test_quadruped_loses_a_leg() -> void:
	print("[quadruped loses a leg] — recompiles the survivor")
	var g := LocomotionZoo.quadruped()
	var cut := Detachment.joint_attaching(g, "leg_fr_thigh")
	var r := Detachment.sever(g, cut, "head")
	var ctrl: Dictionary = r["controlled"]
	var margin: float = (ctrl["stance"] as Dictionary).get("margin", 0.0) if not (ctrl["stance"] as Dictionary).is_empty() else -999.0
	print("  controlled parts %s  standing=%s  margin %+.3f" % [ctrl["part_ids"].size(), ctrl["standing"], margin])
	_check("controlled keeps the head", "head" in ctrl["part_ids"])
	_check("controlled is the 8-part 3-legged body", ctrl["part_ids"].size() == 8)
	_check("recompiled 3-legged graph is valid", (ctrl["graph"] as BodyGraph).is_valid())
	_check("front-right leg detached (2 parts)", (r["detached"][0]["part_ids"] as Array).size() == 2)
	_check("recompiled a fresh stance (found some support)", not (ctrl["stance"] as Dictionary).is_empty())
