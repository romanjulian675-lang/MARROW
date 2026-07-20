extends SceneTree

# Stage-6 / M5 test: walk a biped and check the invariants that make it a real
# walk rather than a slide — planted feet never move, at least one foot is always
# down, swing feet lift, the body advances at the desired speed, and no foot ever
# leaves reach.
#   <godot> --headless --path . --script res://scripts/locomotion/test_gait.gd

var _fail := 0


func _initialize() -> void:
	var g := LocomotionZoo.biped()
	var stance := StanceGenerator.new(g).generate({"reach_fraction": 0.9})
	var keys: Array = []
	for ct in stance["contacts"]:
		keys.append("%s.%s" % [ct["part"], ct["socket"]])
	# right foot leads, left half a cycle later — the classic biped walk.
	var offsets := {keys[0]: 0.0, keys[1]: 0.5}
	var gait := GaitController.new(g, stance, {"offsets": offsets, "duty": 0.65})
	gait.set_velocity(Vector3(0, 0, 0.6))          # 0.6 m/s forward

	var dt := 1.0 / 60.0
	var steps := 300                                # 5 seconds
	var start_z: float = gait.root_transform.origin.z

	var always_supported := true
	var no_slide := true
	var reachable := true
	var feet_on_ground := true
	var max_slide := 0.0
	var max_planted_y := 0.0
	var swing_lift := {keys[0]: 0.0, keys[1]: 0.0}
	var swing_seen := {keys[0]: false, keys[1]: false}
	var prev_foot := {keys[0]: gait.foot_position(keys[0]), keys[1]: gait.foot_position(keys[1])}
	var prev_planted := {keys[0]: true, keys[1]: true}

	for _i in range(steps):
		gait.step(dt)
		if gait.planted_count() < 1:
			always_supported = false
		for key in keys:
			var planted: bool = gait.is_planted(key)
			var foot: Vector3 = gait.foot_position(key)
			if planted:
				max_planted_y = maxf(max_planted_y, absf(foot.y))
				if absf(foot.y) > 1e-6:
					feet_on_ground = false
			if planted and prev_planted[key]:
				var slid: float = (foot as Vector3).distance_to(prev_foot[key])
				max_slide = maxf(max_slide, slid)
				if slid > 1e-6:
					no_slide = false
			if not planted:
				swing_seen[key] = true
				swing_lift[key] = maxf(swing_lift[key], foot.y)
			if gait.reach_strain(key) > 1.001:
				reachable = false
			prev_foot[key] = foot
			prev_planted[key] = planted

	var advanced: float = gait.root_transform.origin.z - start_z
	var expected: float = 0.6 * (steps * dt)

	_check("at least one foot planted at all times (a walk, not a leap)", always_supported)
	print("  (step_height %.4f, max swing lift L %.4f R %.4f)" % [gait.step_height, swing_lift[keys[1]], swing_lift[keys[0]]])
	_check("planted feet never slide (max slip %.6f m)" % max_slide, no_slide)
	_check("both feet take swing steps", swing_seen[keys[0]] and swing_seen[keys[1]])
	_check("planted feet stay on the ground (max y %.6f)" % max_planted_y, feet_on_ground)
	_check("swing feet lift, but no higher than the step height (L %.3f, R %.3f, cap %.3f)" %
		[swing_lift[keys[1]], swing_lift[keys[0]], gait.step_height],
		swing_lift[keys[0]] > gait.step_height * 0.4 and swing_lift[keys[1]] > gait.step_height * 0.4
		and swing_lift[keys[0]] < gait.step_height * 1.05 and swing_lift[keys[1]] < gait.step_height * 1.05)
	_check("body advanced ~%.2f m at the desired speed (got %.2f)" % [expected, advanced],
		absf(advanced - expected) < 0.15)
	_check("no foot ever left reach while walking", reachable)
	_check("stride scaled from morphology (%.3f m)" % gait.stride, gait.stride > 0.15 and gait.stride < 0.45)

	if _fail == 0:
		print("GAIT_TEST: ALL PASS")
	else:
		print("GAIT_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1
