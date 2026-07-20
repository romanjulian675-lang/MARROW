extends SceneTree

# Stage / M9 test: procedural attacks. A hand swings a task-space path (wind-up ->
# strike -> follow), reach is morphology-driven (long arm hits, short arm must
# step), the impact window opens at the strike, and ChainIK bends the arm to the
# path. Manipulator hands never count as support.
#   <godot> --headless --path . --script res://scripts/locomotion/test_attack.gd

var _fail := 0


func _initialize() -> void:
	_test_effectors_and_stance()
	_test_reach_policy()
	_test_swing_path()
	_test_ik_follows_path()
	_test_morphology()
	if _fail == 0:
		print("ATTACK_TEST: ALL PASS")
	else:
		print("ATTACK_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


func _test_effectors_and_stance() -> void:
	print("[effectors] — hands attack, but never bear weight")
	var g := LocomotionZoo.biped_with_arms(0.55)
	var m := BodyMeasure.new(g)
	_check("armed biped exposes 2 manipulation chains (hands)", m.manipulation_chains().size() == 2)
	_check("plain biped has no attack effector (fallback)",
		AttackController.pick_chain(BodyMeasure.new(LocomotionZoo.biped())).is_empty())
	var stance := StanceGenerator.new(g).generate()
	_check("armed biped still stands on its 2 FEET (hands not planted)",
		(stance.get("contacts", []) as Array).size() == 2 and stance.get("stable", false))


func _test_reach_policy() -> void:
	print("[reach policy] — hit in place, or ask the root to step")
	var m := BodyMeasure.new(LocomotionZoo.biped_with_arms(0.55))
	var arm := AttackController.pick_chain(m)
	var shoulder: Vector3 = arm["base"]
	var atk := AttackController.new(arm["reach_max"], 0.0)
	var near := shoulder + Vector3(0, 0, 0.4)
	var far := shoulder + Vector3(0, 0, 1.5)
	var pn := atk.plan(shoulder, near)
	var pf := atk.plan(shoulder, far)
	_check("target within reach -> in reach, no step", pn["in_reach"] and pn["root_step"] < 1e-5)
	_check("target out of reach -> not in reach", not pf["in_reach"])
	_check("root step = distance beyond reach (%.2f)" % pf["root_step"],
		is_equal_approx(pf["root_step"], 1.5 - atk.total_reach()))


func _test_swing_path() -> void:
	print("[swing] — wind-up high & back, strike on target, impact window opens")
	var m := BodyMeasure.new(LocomotionZoo.biped_with_arms(0.55))
	var arm := AttackController.pick_chain(m)
	var shoulder: Vector3 = arm["base"]
	var atk := AttackController.new(arm["reach_max"], 0.0)
	var target := shoulder + Vector3(0, 0, 0.4)

	var s0 := atk.sample(0.0, shoulder, target)
	var si := atk.sample(0.4, shoulder, target)   # impact_phase
	var s1 := atk.sample(1.0, shoulder, target)
	_check("wind-up hand is higher than the strike", (s0["hand_target"] as Vector3).y > (si["hand_target"] as Vector3).y + 0.02)
	_check("wind-up hand is drawn back behind the strike", (s0["hand_target"] as Vector3).z < (si["hand_target"] as Vector3).z)
	_check("at impact the hand lands on the target", (si["hand_target"] as Vector3).distance_to(target) < 1e-3)
	_check("impact window is open only at the strike",
		si["impact_active"] and not s0["impact_active"] and not s1["impact_active"])
	_check("torso lunges forward near impact", (si["lunge"] as Vector3).length() > 0.0)


func _test_ik_follows_path() -> void:
	print("[IK] — the arm bends to reach the hand target all along the swing")
	var m := BodyMeasure.new(LocomotionZoo.biped_with_arms(0.55))
	var arm := AttackController.pick_chain(m)
	var shoulder: Vector3 = arm["base"]
	var segs: Array = arm["segments"]
	var atk := AttackController.new(arm["reach_max"], 0.0)
	var target := shoulder + Vector3(0, 0, 0.42)
	var worst := 0.0
	for i in range(21):
		var s := atk.sample(float(i) / 20.0, shoulder, target)
		var pts := ChainIK.solve(shoulder, segs, s["hand_target"], shoulder + Vector3(0, -1, 1))
		worst = maxf(worst, ChainIK.reach_error(pts, s["hand_target"]))
	_check("arm IK reaches every point on the path (max err %.4f)" % worst, worst < 1e-3)


func _test_morphology() -> void:
	print("[morphology] — a long arm hits what a short arm must step toward")
	var short_arm := AttackController.pick_chain(BodyMeasure.new(LocomotionZoo.biped_with_arms(0.35)))
	var long_arm := AttackController.pick_chain(BodyMeasure.new(LocomotionZoo.biped_with_arms(0.70)))
	var shoulder: Vector3 = short_arm["base"]
	var target := shoulder + Vector3(0, 0, 0.6)
	var short_atk := AttackController.new(short_arm["reach_max"], 0.0)
	var long_atk := AttackController.new(long_arm["reach_max"], 0.0)
	_check("short arm can't reach 0.6 m -> must step", not short_atk.plan(shoulder, target)["in_reach"])
	_check("long arm reaches 0.6 m in place", long_atk.plan(shoulder, target)["in_reach"])
