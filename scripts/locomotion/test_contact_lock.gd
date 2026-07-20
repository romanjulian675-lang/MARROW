extends SceneTree

# Stage-4 test: contact locking. Plant a biped's feet, then move the torso and
# prove the planted feet DON'T move while the per-limb reach bookkeeping stays
# honest.
#   <godot> --headless --path . --script res://scripts/locomotion/test_contact_lock.gd

var _fail := 0


func _initialize() -> void:
	_test_lock_holds_feet()
	_test_reach_bookkeeping()
	_test_travel_limits()
	_test_rotation_and_replant()
	_test_quadruped_generality()
	if _fail == 0:
		print("CONTACT_LOCK_TEST: ALL PASS")
	else:
		print("CONTACT_LOCK_TEST: %d FAILURE(S)" % _fail)
	quit(_fail)


func _check(label: String, cond: bool) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail += 1


func _biped_lock() -> ContactLock:
	var g := LocomotionZoo.biped()
	var stance := StanceGenerator.new(g).generate()
	return ContactLock.new(g, stance)


# THE property: as the torso translates, feet stay put and hips move by exactly
# the same vector.
func _test_lock_holds_feet() -> void:
	print("[lock holds feet] — translate the torso, feet must not move")
	var lock := _biped_lock()
	var base := lock.evaluate(lock.base_root)
	_check("planted 2 contacts", lock.contact_count() == 2)
	_check("base pose is reachable", base["all_reachable"])

	var delta := Vector3(0.02, -0.05, 0.01)
	var moved := lock.evaluate_shift(delta)
	var feet_fixed := true
	var hips_tracked := true
	for i in range((base["contacts"] as Array).size()):
		var b: Dictionary = base["contacts"][i]
		var m: Dictionary = moved["contacts"][i]
		if (b["foot"] as Vector3).distance_to(m["foot"]) > 1e-6:
			feet_fixed = false
		if ((b["hip"] as Vector3) + delta).distance_to(m["hip"]) > 1e-6:
			hips_tracked = false
	_check("feet stay locked in world space under translation", feet_fixed)
	_check("hips move by exactly the torso translation", hips_tracked)


# Lower the torso -> more reach to spare; raise it past extension -> unreachable.
func _test_reach_bookkeeping() -> void:
	print("[reach bookkeeping] — margin grows crouching, breaks over-extended")
	var lock := _biped_lock()
	var base_margin: float = lock.evaluate(lock.base_root)["min_reach_margin"]
	var crouch := lock.evaluate_shift(Vector3(0, -0.1, 0))
	var reach_up := lock.evaluate_shift(Vector3(0, 0.1, 0))
	_check("crouching leaves more reach margin than standing", crouch["min_reach_margin"] > base_margin + 1e-4)
	_check("crouch keeps every foot reachable", crouch["all_reachable"])
	_check("raising the torso past full extension breaks a lock", not reach_up["all_reachable"])
	_check("strain near 1.0 when standing (legs almost straight)",
		(base_margin < 0.05) and (base_margin >= -1e-6))


# The torso can crouch far but barely rise (it stands near full extension), and
# lateral travel is symmetric.
func _test_travel_limits() -> void:
	print("[travel limits] — support-limited torso mobility")
	var lock := _biped_lock()
	var down := lock.max_travel(Vector3.DOWN)
	var up := lock.max_travel(Vector3.UP)
	var right := lock.max_travel(Vector3.RIGHT)
	var left := lock.max_travel(Vector3.LEFT)
	print("  down %.3f  up %.3f  right %.3f  left %.3f" % [down, up, right, left])
	_check("can crouch a long way (> 0.3)", down > 0.3)
	_check("can barely rise (< 0.05, already standing tall)", up < 0.05)
	_check("crouch room far exceeds rise room", down > up + 0.3)
	_check("lateral travel is finite and positive", right > 1e-3 and right < 3.0)
	_check("lateral travel is symmetric", absf(right - left) < 5e-3)


func _test_rotation_and_replant() -> void:
	print("[rotation + replant] — turning keeps feet planted; a step moves one")
	var lock := _biped_lock()
	var base := lock.evaluate(lock.base_root)
	var turned := lock.evaluate_rotated(Basis(Vector3.UP, deg_to_rad(20.0)))
	var feet_fixed := true
	var hips_moved := true
	for i in range((base["contacts"] as Array).size()):
		var b: Dictionary = base["contacts"][i]
		var t: Dictionary = turned["contacts"][i]
		if (b["foot"] as Vector3).distance_to(t["foot"]) > 1e-6:
			feet_fixed = false
		if (b["hip"] as Vector3).distance_to(t["hip"]) < 1e-3:
			hips_moved = false
	_check("feet stay planted while the torso yaws", feet_fixed)
	_check("hips swing when the torso yaws", hips_moved)

	# Re-plant the right foot forward (a completed step) and confirm it took.
	var key: String = lock.locked_keys()[0]
	var parts: PackedStringArray = key.split(".")
	var new_pos := lock.contact_world(parts[0], parts[1]) + Vector3(0, 0, 0.25)
	lock.set_contact(parts[0], parts[1], new_pos)
	_check("re-planted contact reports its new world position",
		lock.contact_world(parts[0], parts[1]).distance_to(new_pos) < 1e-6)
	var after := lock.evaluate(lock.base_root)
	var found := false
	for c in after["contacts"]:
		if c["key"] == key and (c["foot"] as Vector3).distance_to(new_pos) < 1e-6:
			found = true
	_check("evaluate() uses the re-planted contact", found)


# Contact locking is name-agnostic: a 4-contact body works the same.
func _test_quadruped_generality() -> void:
	print("[quadruped] — same locking with four contacts")
	var g := LocomotionZoo.quadruped()
	var stance := StanceGenerator.new(g).generate()
	var lock := ContactLock.new(g, stance)
	_check("planted 4 contacts", lock.contact_count() == 4)
	var base := lock.evaluate(lock.base_root)
	_check("quadruped base reachable", base["all_reachable"])
	var swayed := lock.evaluate_shift(Vector3(0.03, 0, 0.03))
	var feet_fixed := true
	for i in range((base["contacts"] as Array).size()):
		if (base["contacts"][i]["foot"] as Vector3).distance_to(swayed["contacts"][i]["foot"]) > 1e-6:
			feet_fixed = false
	_check("all four feet stay planted while the torso shifts", feet_fixed)
	print(ContactLock.describe(base).replace("\n", "\n  "))
