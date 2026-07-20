extends SceneTree

# Stage 7-8 / M6 test: gait patterns keep the body supported, and a quadruped
# actually WALKS (statically stable) from the same GaitController as the biped.
#   <godot> --headless --path . --script res://scripts/locomotion/test_gait_pattern.gd

var _fail := 0


func _initialize() -> void:
	_test_classification()
	_test_pattern_support()
	# Live-walk each family with the demo's exact params (statically stable, no
	# slide, feet in reach, torso level on flat ground).
	_walk_check("quadruped walk", LocomotionZoo.quadruped(), "quadruped_walk",
		{"rf": 0.80, "sw": 0.40, "sr": 0.75, "st": 0.28, "sp": 0.45}, 3)
	_walk_check("hexapod tripod", LocomotionZoo.hexapod(), "tripod",
		{"rf": 0.80, "sw": 0.40, "sr": 0.75, "st": 0.28, "sp": 0.45}, 3)
	if _fail == 0:
		print("GAIT_PATTERN_TEST: ALL PASS")
	else:
		print("GAIT_PATTERN_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


func _contacts(g: BodyGraph) -> Array:
	return StanceGenerator.new(g).generate()["contacts"]


# Sweep a whole cycle and return the fewest feet ever planted at once.
func _min_support(pat: Dictionary) -> int:
	var offsets: Dictionary = pat["offsets"]
	var osc := GaitOscillator.new(offsets, pat["duty"])
	var m: int = offsets.size()
	for i in range(240):
		osc.phase = float(i) / 240.0
		var n := 0
		for k in offsets:
			if osc.is_stance(k):
				n += 1
		m = mini(m, n)
	return m


func _test_classification() -> void:
	print("[classification] — legs sorted by side and column from position")
	var cls := GaitPattern.classify(_contacts(LocomotionZoo.quadruped()))
	_check("front-right leg is right + front",
		cls["leg_fr_shin.tip"]["left"] == false and cls["leg_fr_shin.tip"]["col"] == 1)
	_check("back-left leg is left + rear",
		cls["leg_bl_shin.tip"]["left"] == true and cls["leg_bl_shin.tip"]["col"] == -1)


func _test_pattern_support() -> void:
	print("[support] — each family keeps the right number of feet down")
	var quad := _contacts(LocomotionZoo.quadruped())
	var walk := GaitPattern.for_family("quadruped_walk", quad)
	var trot := GaitPattern.for_family("quadruped_trot", quad)
	_check("quadruped WALK keeps 3+ feet down (statically stable), min %d" % _min_support(walk),
		_min_support(walk) >= 3)
	_check("quadruped walk uses a high duty (%.2f > 0.7)" % walk["duty"], walk["duty"] > 0.7)
	_check("quadruped TROT keeps a diagonal 2 down, min %d" % _min_support(trot),
		_min_support(trot) >= 2)
	_check("trot pairs the diagonal (front-left in phase with rear-right)",
		is_equal_approx(trot["offsets"]["leg_fl_shin.tip"], trot["offsets"]["leg_br_shin.tip"]))
	var tripod := GaitPattern.for_family("tripod", _contacts(LocomotionZoo.hexapod()))
	_check("hexapod TRIPOD keeps 3+ feet down, min %d" % _min_support(tripod),
		_min_support(tripod) >= 3)


func _walk_check(name: String, g: BodyGraph, family: String, cfg: Dictionary, min_supp: int) -> void:
	print("[%s] — walks, stable, no slide, reachable, level, VISIBLE swing" % name)
	# Reining in `stance_width` keeps the feet under the body, which leaves fore-aft
	# room for a long stride — and a long stride is what keeps cadence low enough
	# that the swing is actually visible instead of a few-frame blur.
	var rf: float = cfg.get("rf", 0.80)
	var sw: float = cfg.get("sw", -1.0)
	var speed: float = cfg.get("sp", 0.45)
	var sopts := {"reach_fraction": rf}
	if sw >= 0.0:
		sopts["stance_width"] = sw
	var stance := StanceGenerator.new(g).generate(sopts)
	var pat := GaitPattern.for_family(family, stance["contacts"])
	pat["stride_ratio"] = cfg.get("sr", 0.75)
	pat["step_ratio"] = cfg.get("st", 0.28)
	var gait := GaitController.new(g, stance, pat)
	gait.set_velocity(Vector3(0, 0, speed))
	var max_lift := 0.0

	var dt := 1.0 / 60.0
	var start_z: float = gait.root_transform.origin.z
	var min_support: int = 99
	var no_slide := true
	var reachable := true
	var max_strain := 0.0
	var prev := {}
	var prevp := {}
	for key in gait.limbs():
		prev[key] = gait.foot_position(key)
		prevp[key] = gait.is_planted(key)
	for _i in range(360):
		gait.step(dt)
		min_support = mini(min_support, gait.planted_count())
		for key in gait.limbs():
			if gait.is_planted(key) and prevp[key]:
				if (gait.foot_position(key) as Vector3).distance_to(prev[key]) > 1e-6:
					no_slide = false
			if not gait.is_planted(key):
				max_lift = maxf(max_lift, (gait.foot_position(key) as Vector3).y)
			max_strain = maxf(max_strain, gait.reach_strain(key))
			if gait.reach_strain(key) > 1.001:
				reachable = false
			prev[key] = gait.foot_position(key)
			prevp[key] = gait.is_planted(key)
	var advanced: float = gait.root_transform.origin.z - start_z
	print("  (min support %d, max reach strain %.3f, advanced %.2f m)" % [min_support, max_strain, advanced])
	_check("%s: stays %d+ supported throughout" % [name, min_supp], min_support >= min_supp)
	_check("%s: planted feet never slide" % name, no_slide)
	_check("%s: no foot leaves reach" % name, reachable)
	_check("%s: body advances" % name, advanced > speed * 4.0)
	_check("%s: torso level on flat ground" % name,
		((gait.root_transform.basis * Vector3.BACK) as Vector3).distance_to(Vector3.BACK) < 1e-3)
	# Regression guard: a too-short stride makes cadence so high that each swing
	# lasts a handful of frames and the legs read as GLUED to the ground.
	var cadence: float = speed / maxf(gait.stride, 1e-4)
	var swing_frames: float = ((1.0 - gait.osc.duty) / maxf(cadence, 1e-4)) * 60.0
	print("  (stride %.3f, cadence %.2f Hz, swing %.1f frames, lift %.3f)" %
		[gait.stride, cadence, swing_frames, max_lift])
	_check("%s: swing lasts long enough to SEE (%.1f frames >= 8)" % [name, swing_frames],
		swing_frames >= 8.0)
	_check("%s: swing feet visibly leave the ground (%.3f m)" % [name, max_lift],
		max_lift > gait.step_height * 0.5)
