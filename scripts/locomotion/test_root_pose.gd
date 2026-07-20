extends SceneTree

# Stage 9 / M6 test: RootPoseSolver tilts the torso to match the contacts —
# level on flat ground, nose-up when the front feet are higher, rolled when one
# side is higher, and riding at the mean contact height.
#   <godot> --headless --path . --script res://scripts/locomotion/test_root_pose.gd

var _fail := 0


func _initialize() -> void:
	var up := 0.6

	var flat := [Vector3(0.3, 0, 0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, -0.3)]
	var pf := RootPoseSolver.solve(flat, up)
	_check("flat ground -> torso level (forward stays +Z)",
		((pf.basis * Vector3.BACK) as Vector3).distance_to(Vector3.BACK) < 1e-3)
	_check("flat ground -> up stays +Y", ((pf.basis * Vector3.UP) as Vector3).distance_to(Vector3.UP) < 1e-3)
	_check("height rides mean contact + up_height", absf(pf.origin.y - up) < 1e-4)

	# Front feet 0.3 higher -> nose up.
	var frontup := [Vector3(0.3, 0.3, 0.4), Vector3(-0.3, 0.3, 0.4), Vector3(0.3, 0, -0.4), Vector3(-0.3, 0, -0.4)]
	var pn := RootPoseSolver.solve(frontup, up)
	_check("front higher -> nose up (forward tilts +Y)", ((pn.basis * Vector3.BACK) as Vector3).y > 0.1)
	_check("uphill torso rides mean (0.15 + up)", absf(pn.origin.y - (0.15 + up)) < 1e-4)
	_check("no roll when both sides even", absf(((pn.basis * Vector3.RIGHT) as Vector3).y) < 1e-3)

	# Right feet 0.3 higher -> right side up.
	var rightup := [Vector3(0.4, 0.3, 0.3), Vector3(-0.4, 0, 0.3), Vector3(0.4, 0.3, -0.3), Vector3(-0.4, 0, -0.3)]
	var pr := RootPoseSolver.solve(rightup, up)
	_check("right higher -> right side up (+X tilts +Y)", ((pr.basis * Vector3.RIGHT) as Vector3).y > 0.1)
	_check("no pitch when front/rear even", absf(((pr.basis * Vector3.BACK) as Vector3).y) < 1e-3)

	if _fail == 0:
		print("ROOT_POSE_TEST: ALL PASS")
	else:
		print("ROOT_POSE_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1
