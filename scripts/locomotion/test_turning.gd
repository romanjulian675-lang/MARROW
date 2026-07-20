extends SceneTree

# Stage / M5 finish: turning. A walking quadruped given a turn rate curves its
# path — the heading rotates, the torso yaws to face it, the feet still don't
# slide, and it stays supported and in reach.
#   <godot> --headless --path . --script res://scripts/locomotion/test_turning.gd

var _fail := 0


func _initialize() -> void:
	var g := LocomotionZoo.quadruped()
	var stance := StanceGenerator.new(g).generate({"reach_fraction": 0.72})
	var pat := GaitPattern.for_family("quadruped_walk", stance["contacts"])
	pat["stride_ratio"] = 0.28
	pat["balance_gain"] = 0.08
	var gait := GaitController.new(g, stance, pat)
	var turn := 0.35                                # rad/s
	gait.set_intent(0.45, turn)                     # walk forward AND turn left

	var dt := 1.0 / 60.0
	var steps := 300                                # 5 s
	var start := gait.root_transform.origin
	var min_support := 99
	var no_slide := true
	var reachable := true
	var prev := {}
	var prevp := {}
	for key in gait.limbs():
		prev[key] = gait.foot_position(key)
		prevp[key] = gait.is_planted(key)

	for _i in range(steps):
		gait.step(dt)
		min_support = mini(min_support, gait.planted_count())
		for key in gait.limbs():
			if gait.is_planted(key) and prevp[key]:
				if (gait.foot_position(key) as Vector3).distance_to(prev[key]) > 1e-6:
					no_slide = false
			if gait.reach_strain(key) > 1.001:
				reachable = false
			prev[key] = gait.foot_position(key)
			prevp[key] = gait.is_planted(key)

	var expected_heading: float = turn * steps * dt
	var torso_forward: Vector3 = gait.root_transform.basis * Vector3(0, 0, 1)
	var torso_heading: float = atan2(torso_forward.x, torso_forward.z)
	var disp: Vector3 = gait.root_transform.origin - start
	print("  heading %.2f rad (expected %.2f), displaced (%.2f, %.2f), min support %d" %
		[gait.heading(), expected_heading, disp.x, disp.z, min_support])

	_check("heading advanced by turn_rate*time", absf(gait.heading() - expected_heading) < 0.05)
	_check("torso yaws to face the heading", absf(torso_heading - expected_heading) < 0.1)
	_check("the path curves (moved sideways, not just forward)", absf(disp.x) > 0.4)
	_check("planted feet never slide while turning", no_slide)
	_check("stays statically stable (3+ feet) while turning, min %d" % min_support, min_support >= 3)
	_check("no foot leaves reach while turning", reachable)

	if _fail == 0:
		print("TURNING_TEST: ALL PASS")
	else:
		print("TURNING_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1
