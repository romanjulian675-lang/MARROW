extends SceneTree

# Stage / M5 refinement test: terrain-following. A quadruped walks up a ramp — its
# planted feet sit on the slope, it climbs, and the torso pitches nose-up to match
# (activating the RootPoseSolver built in M6), all without sliding.
#   <godot> --headless --path . --script res://scripts/locomotion/test_terrain.gd

const SLOPE := 0.12

var _fail := 0


func _ramp(p: Vector3) -> float:
	return SLOPE * p.z                      # a constant incline rising toward +Z


func _initialize() -> void:
	var g := LocomotionZoo.quadruped()
	var stance := StanceGenerator.new(g).generate({"reach_fraction": 0.72})
	var pat := GaitPattern.for_family("quadruped_walk", stance["contacts"])
	pat["stride_ratio"] = 0.28
	pat["balance_gain"] = 0.08
	var gait := GaitController.new(g, stance, pat)
	gait.set_ground(Callable(self, "_ramp"))
	gait.set_velocity(Vector3(0, 0, 0.5))

	var dt := 1.0 / 60.0
	var start := gait.root_transform.origin
	var min_support := 99
	var no_slide := true
	var reachable := true
	var feet_on_terrain := true
	var max_pitch := 0.0
	var prev := {}
	var prevp := {}
	for key in gait.limbs():
		prev[key] = gait.foot_position(key)
		prevp[key] = gait.is_planted(key)

	for _i in range(360):                    # 6 s
		gait.step(dt)
		min_support = mini(min_support, gait.planted_count())
		max_pitch = maxf(max_pitch, ((gait.root_transform.basis * Vector3.BACK) as Vector3).y)
		for key in gait.limbs():
			var foot: Vector3 = gait.foot_position(key)
			if gait.is_planted(key):
				if absf(foot.y - _ramp(foot)) > 1e-6:
					feet_on_terrain = false
				if prevp[key] and (foot as Vector3).distance_to(prev[key]) > 1e-6:
					no_slide = false
			if gait.reach_strain(key) > 1.001:
				reachable = false
			prev[key] = foot
			prevp[key] = gait.is_planted(key)

	var climbed: float = gait.root_transform.origin.y - start.y
	var advanced: float = gait.root_transform.origin.z - start.z
	print("  climbed %.2f m, advanced %.2f m, max nose-up %.3f" % [climbed, advanced, max_pitch])

	_check("planted feet sit exactly on the terrain", feet_on_terrain)
	_check("stays statically stable (3+ feet) up the slope, min %d" % min_support, min_support >= 3)
	_check("planted feet never slide on the slope", no_slide)
	_check("no foot leaves reach while climbing", reachable)
	_check("the body climbs the ramp (%.2f m up)" % climbed, climbed > 0.2)
	_check("the body advances up-slope (%.2f m)" % advanced, advanced > 2.0)
	_check("the torso pitches nose-up on the incline (%.3f)" % max_pitch, max_pitch > 0.05)

	if _fail == 0:
		print("TERRAIN_TEST: ALL PASS")
	else:
		print("TERRAIN_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1
