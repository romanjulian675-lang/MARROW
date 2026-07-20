extends SceneTree

# Headless smoke test for the gallery's DATA layer: every creature in the zoo
# must assemble, validate, and produce the stance the gallery will draw (with
# the expected stability). The rendering itself is verified by eye in
# scenes/locomotion_gallery.tscn.
#   <godot> --headless --path . --script res://scripts/locomotion/test_gallery.gd

var _fail := 0


func _initialize() -> void:
	var expect_stable := {
		"Biped": true, "Quadruped": true, "Hexapod": true, "Snake": true, "Off-centre load": false,
	}
	for entry in LocomotionZoo.catalog():
		var nm: String = entry["name"]
		var g: BodyGraph = entry["graph"]
		print("[%s]" % nm)
		_check("%s: graph valid" % nm, g.is_valid())
		var resting: bool = entry.get("mode", "stance") == "rest"
		var st := StanceGenerator.resting_stance(g) if resting else StanceGenerator.new(g).generate()
		_check("%s: stance found" % nm, not st.is_empty())
		if st.is_empty():
			continue
		var want: bool = expect_stable.get(nm, true)
		_check("%s: stable == %s (margin %+.3f)" % [nm, want, st.get("margin", 0.0)],
			st.get("stable", false) == want)
		_check("%s: contacts == graph endpoints" % nm,
			(st["contacts"] as Array).size() == g.endpoints_world(g.assemble()).size())
		if not resting:
			_check("%s: stage-5 IK solves every leg to its planted foot" % nm, _ik_reaches(g, st))
		print("  " + StanceGenerator.describe(st).replace("\n", "\n  "))
	if _fail == 0:
		print("GALLERY_TEST: ALL PASS")
	else:
		print("GALLERY_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


# Every planted foot must be reachable by bending its chain from the raised hip.
func _ik_reaches(g: BodyGraph, st: Dictionary) -> bool:
	var measure := BodyMeasure.new(g)
	var chain_by_key := {}
	for c in measure.chains():
		chain_by_key["%s.%s" % [c["part"], c["socket"]]] = c
	var H: float = st["torso_height"]
	for ct in st["contacts"]:
		var c: Dictionary = chain_by_key["%s.%s" % [ct["part"], ct["socket"]]]
		var hip: Vector3 = (c["base"] as Vector3) + Vector3(0, H, 0)
		var pts := ChainIK.solve(hip, c["segments"], ct["pos"], hip + Vector3(0, 0, 1))
		if ChainIK.reach_error(pts, ct["pos"]) > 1e-3:
			return false
	return true
