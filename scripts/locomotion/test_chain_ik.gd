extends SceneTree

# Stage-5 test: generic chain IK. Pure solver — reachable targets are hit exactly,
# out-of-reach targets straighten, segment lengths never stretch, and the pole
# controls the bend side.
#   <godot> --headless --path . --script res://scripts/locomotion/test_chain_ik.gd

var _fail := 0


func _initialize() -> void:
	_test_two_bone_reachable()
	_test_two_bone_limits()
	_test_pole_controls_bend()
	_test_one_segment()
	_test_fabrik_three()
	if _fail == 0:
		print("CHAIN_IK_TEST: ALL PASS")
	else:
		print("CHAIN_IK_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


func _segments_preserved(pts: PackedVector3Array, lengths: Array) -> bool:
	if pts.size() != lengths.size() + 1:
		return false
	for i in range(lengths.size()):
		if absf(pts[i].distance_to(pts[i + 1]) - float(lengths[i])) > 1e-4:
			return false
	return true


func _test_two_bone_reachable() -> void:
	print("[two-bone reachable] — tip hits target, bones keep their length")
	var base := Vector3.ZERO
	var lengths := [0.5, 0.5]
	var target := Vector3(0.0, -0.7, 0.0)          # dist 0.7 < 1.0
	var pole := Vector3(0.0, -0.35, 1.0)           # forward
	var pts := ChainIK.solve(base, lengths, target, pole)
	_check("returns base + 2 joints", pts.size() == 3)
	_check("tip reaches the target", ChainIK.reach_error(pts, target) < 1e-4)
	_check("both bones keep exact length", _segments_preserved(pts, lengths))
	_check("knee actually bends off the straight line (not colinear)",
		absf(pts[1].z) > 0.05)


func _test_two_bone_limits() -> void:
	print("[two-bone limits] — straight at full reach, clamped past it")
	var base := Vector3.ZERO
	var lengths := [0.5, 0.5]
	var pole := Vector3(0, 0, 1)

	# Exactly at full reach -> straight line, knee at the midpoint.
	var straight := ChainIK.solve(base, lengths, Vector3(0, -1.0, 0), pole)
	_check("full-reach knee sits ~on the line", absf(straight[1].z) < 0.02 and absf(straight[1].y + 0.5) < 0.02)
	_check("full-reach bones keep length", _segments_preserved(straight, lengths))

	# Beyond reach -> straighten toward target, tip at max reach (~1.0 away).
	var far := ChainIK.solve(base, lengths, Vector3(0, -2.0, 0), pole)
	_check("unreachable target: chain straightens", _segments_preserved(far, lengths))
	_check("unreachable tip sits at max reach from base",
		absf(base.distance_to(far[2]) - 1.0) < 1e-3)
	_check("unreachable tip points toward the target", far[2].y < -0.99)


func _test_pole_controls_bend() -> void:
	print("[pole] — flipping the pole flips the knee to the other side")
	var base := Vector3.ZERO
	var lengths := [0.5, 0.5]
	var target := Vector3(0, -0.7, 0)
	var front := ChainIK.solve(base, lengths, target, Vector3(0, -0.35, 1))
	var back := ChainIK.solve(base, lengths, target, Vector3(0, -0.35, -1))
	_check("front pole -> knee forward (+z)", front[1].z > 0.05)
	_check("back pole -> knee backward (-z)", back[1].z < -0.05)
	_check("bend is mirror-symmetric", absf(front[1].z + back[1].z) < 1e-4)


func _test_one_segment() -> void:
	print("[one segment] — hinge points at the target")
	var base := Vector3(0, 1, 0)
	var pts := ChainIK.solve(base, [0.5], Vector3(0, 1, 3), Vector3.ZERO)
	_check("returns base + tip", pts.size() == 2)
	_check("tip is one segment length from base", absf(base.distance_to(pts[1]) - 0.5) < 1e-4)
	_check("tip points along the target direction (+z)", pts[1].z > base.z + 0.4)


func _test_fabrik_three() -> void:
	print("[FABRIK] — 3-segment chain reaches a target and keeps its lengths")
	var base := Vector3.ZERO
	var lengths := [0.4, 0.4, 0.4]                 # total 1.2
	var target := Vector3(0.5, -0.6, 0.2)          # dist ~0.81 < 1.2
	var pole := Vector3(0.5, -0.3, 1.0)
	var pts := ChainIK.solve(base, lengths, target, pole)
	_check("returns base + 3 joints", pts.size() == 4)
	_check("tip reaches the target", ChainIK.reach_error(pts, target) < 1e-3)
	_check("all three segments keep length", _segments_preserved(pts, lengths))
