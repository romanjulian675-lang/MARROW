extends Node3D

# Combat lab — procedural ACTION and REACTION from the contact point.
#
# An armed biped swings a task-space attack (AttackController) at a receiver. At
# the impact window the hand's world position IS the contact point: the receiver
# takes `impulse` there and the attacker takes the negated impulse (Newton's
# third law), each driving its own ImpactResponse. Because the torque is r × F
# about each body's centre of mass, WHERE the blow lands shapes the motion — aim
# high and the receiver pitches back, aim at the centre and it just gets shoved.
#
# The menu (top-right) tunes the whole exchange live; Save writes a reusable
# PROFILE (json) that regenerates the motion on any body, and Bake optionally
# records the result to a Godot Animation clip for inspection/export.
#
# Keys — Space: strike · A: auto-repeat · Tab: hide menu · Esc: menu · R: reset

const SPEC := [
	{"stage": "aim (contact point)", "name": "target_height", "min": -0.2, "max": 0.9, "step": 0.02, "default": 0.55},
	{"stage": "aim (contact point)", "name": "target_side", "min": -0.5, "max": 0.5, "step": 0.02, "default": 0.0},
	{"stage": "aim (contact point)", "name": "target_distance", "min": 0.6, "max": 2.2, "step": 0.05, "default": 1.05},
	{"stage": "attack", "name": "attack_style", "kind": "enum", "values": ["jab", "overhead"], "default": "jab"},
	{"stage": "attack", "name": "attack_duration", "min": 0.25, "max": 1.60, "step": 0.05, "default": 0.70},
	{"stage": "attack", "name": "impulse", "min": 5.0, "max": 160.0, "step": 5.0, "default": 55.0},
	{"stage": "reaction (receiver)", "name": "knockback_scale", "min": 0.0, "max": 3.0, "step": 0.05, "default": 1.0},
	{"stage": "reaction (receiver)", "name": "torque_scale", "min": 0.0, "max": 3.0, "step": 0.05, "default": 1.0},
	{"stage": "reaction (receiver)", "name": "stiffness", "min": 5.0, "max": 160.0, "step": 5.0, "default": 55.0},
	{"stage": "reaction (receiver)", "name": "damping", "min": 1.0, "max": 30.0, "step": 0.5, "default": 8.5},
	{"stage": "recoil (attacker)", "name": "recoil_scale", "min": 0.0, "max": 1.5, "step": 0.05, "default": 0.45},
]

var _params: Dictionary = {}
var _value_labels: Dictionary = {}
var _readout: Label
var _menu: Control
var _cam: Camera3D
var _status := "press Space to strike"

var _attacker: Dictionary = {}
var _receiver: Dictionary = {}
var _attack: AttackController
var _phase := -1.0                  # <0 = idle
var _auto := false
var _struck := false
var _last_contact := Vector3.ZERO
var _last_impulse := Vector3.ZERO
var _hit_marker: MeshInstance3D

# bake recording
var _recording := false
var _samples: Array = []            # [{t, node_path, pos, rot}]
var _rec_time := 0.0


func _ready() -> void:
	for e in SPEC:
		_params[e["name"]] = e["default"]
	_setup_environment()
	_ground()
	_build_ui()
	_attacker = _make_body(LocomotionZoo.biped_with_arms(0.55), Vector3(0, 0, -1.05), true)
	_receiver = _make_body(LocomotionZoo.biped(0.62), Vector3(0, 0, 0.0), false)
	_hit_marker = _ball(self, 0.09, Color(1.0, 0.35, 0.2))
	_hit_marker.visible = false
	_cam = Camera3D.new()
	_cam.fov = 58.0
	add_child(_cam)
	_place_bodies()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			_strike()
		KEY_A:
			_auto = not _auto
		KEY_TAB:
			_menu.visible = not _menu.visible
		KEY_R:
			_reset()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _strike() -> void:
	_phase = 0.0
	_struck = false
	_recording = true
	_samples.clear()
	_rec_time = 0.0
	_status = "striking…"


func _reset() -> void:
	(_attacker["impact"] as ImpactResponse).reset()
	(_receiver["impact"] as ImpactResponse).reset()
	_phase = -1.0
	_hit_marker.visible = false
	_status = "reset"


# ---- bodies ---------------------------------------------------------------

func _make_body(g: BodyGraph, at: Vector3, is_attacker: bool) -> Dictionary:
	var measure := BodyMeasure.new(g)
	var stance := StanceGenerator.new(g, measure).generate({"reach_fraction": 0.88})
	var holder := Node3D.new()
	holder.name = "Attacker" if is_attacker else "Receiver"
	add_child(holder)

	var body := {
		"graph": g, "measure": measure, "stance": stance, "holder": holder,
		"base": Transform3D(Basis.IDENTITY, at + Vector3(0, stance.get("torso_height", 0.9), 0)),
		"impact": ImpactResponse.new(), "boxes": {}, "legs": {}, "segs": {},
		"arm": {}, "arm_chain": {},
	}

	var limb_ids: Dictionary = {}
	for c in measure.chains():
		var key: String = "%s.%s" % [c["part"], c["socket"]]
		body["segs"][key] = c["segments"]
		for pid in c["limb_parts"]:
			limb_ids[pid] = true
	if is_attacker:
		var arm: Dictionary = AttackController.pick_chain(measure)
		body["arm_chain"] = arm
		for pid in arm.get("limb_parts", []):
			limb_ids[pid] = true

	for pid in g.parts:
		if limb_ids.has(pid):
			continue
		var mi := _box(holder, (g.parts[pid] as BodyPart).size, Color(0.78, 0.6, 0.52) if is_attacker else Color(0.62, 0.7, 0.85))
		mi.name = pid
		body["boxes"][pid] = mi
	for key in body["segs"]:
		var segs: Array = body["segs"][key]
		body["legs"][key] = {
			"a": _cyl(holder, 0.05, segs[0], Color(0.5, 0.55, 0.7)),
			"b": _cyl(holder, 0.045, segs[1], Color(0.5, 0.55, 0.7)),
			"foot": _ball(holder, 0.06, Color(0.85, 0.62, 0.2)),
		}
	if is_attacker and not body["arm_chain"].is_empty():
		var asegs: Array = body["arm_chain"]["segments"]
		body["arm"] = {
			"a": _cyl(holder, 0.045, asegs[0], Color(0.9, 0.5, 0.35)),
			"b": _cyl(holder, 0.04, asegs[1], Color(0.9, 0.5, 0.35)),
			"hand": _ball(holder, 0.055, Color(1.0, 0.75, 0.4)),
		}
	return body


func _place_bodies() -> void:
	var g: BodyGraph = _attacker["graph"]
	var arm: Dictionary = _attacker["arm_chain"]
	if not arm.is_empty():
		_attack = AttackController.new(arm["reach_max"], 0.0, AttackController.preset(_params["attack_style"]))
	_apply_body(_attacker)
	_apply_body(_receiver)


func _target_point() -> Vector3:
	var base: Transform3D = _receiver["base"]
	return Vector3(base.origin.x + float(_params["target_side"]),
		float(_params["target_height"]), base.origin.z)


func _shoulder() -> Vector3:
	var arm: Dictionary = _attacker["arm_chain"]
	if arm.is_empty():
		return (_attacker["base"] as Transform3D).origin
	return _root_of(_attacker) * (arm["base"] as Vector3)


func _root_of(body: Dictionary) -> Transform3D:
	var base: Transform3D = body["base"]
	var off: Transform3D = (body["impact"] as ImpactResponse).offset()
	return Transform3D(off.basis * base.basis, base.origin + off.origin)


func _process(dt: float) -> void:
	# keep the attacker at the tuned distance from the receiver
	var d: float = _params["target_distance"]
	var ab: Transform3D = _attacker["base"]
	_attacker["base"] = Transform3D(ab.basis, Vector3(ab.origin.x, ab.origin.y, -d))
	if _attack != null:
		_attack.defn = AttackController.preset(_params["attack_style"])

	var rr: ImpactResponse = _receiver["impact"]
	var ar: ImpactResponse = _attacker["impact"]
	rr.configure(_params)
	ar.configure({"knockback_scale": float(_params["knockback_scale"]) * float(_params["recoil_scale"]),
		"torque_scale": float(_params["torque_scale"]) * float(_params["recoil_scale"]),
		"stiffness": _params["stiffness"], "damping": _params["damping"]})
	rr.step(dt)
	ar.step(dt)

	if _phase >= 0.0:
		_phase += dt / maxf(float(_params["attack_duration"]), 0.05)
		if _phase >= 1.0:
			_phase = -1.0
			_recording = false
			if _auto:
				await get_tree().create_timer(0.35).timeout
				if _auto:
					_strike()
	_apply_body(_attacker)
	_apply_body(_receiver)
	_update_camera()
	_update_readout()
	if _recording:
		_rec_time += dt
		_record_sample()


func _apply_body(body: Dictionary) -> void:
	var g: BodyGraph = body["graph"]
	var root: Transform3D = _root_of(body)
	var asm: Dictionary = g.assemble(root)
	for pid in body["boxes"]:
		var part: BodyPart = g.parts[pid]
		(body["boxes"][pid] as MeshInstance3D).transform = \
			(asm[pid] as Transform3D) * Transform3D(Basis.IDENTITY, part.local_center_of_mass())
	# legs: IK to their planted stance feet (feet stay on the ground under the body)
	var stance: Dictionary = body["stance"]
	var base: Transform3D = body["base"]
	for ct in stance.get("contacts", []):
		var key: String = "%s.%s" % [ct["part"], ct["socket"]]
		if not body["legs"].has(key):
			continue
		var chain_base: Vector3 = Vector3.ZERO
		for c in (body["measure"] as BodyMeasure).chains():
			if "%s.%s" % [c["part"], c["socket"]] == key:
				chain_base = c["base"]
		var hip: Vector3 = root * chain_base
		var foot: Vector3 = (ct["pos"] as Vector3) + Vector3(base.origin.x, 0, base.origin.z)
		var pts := ChainIK.solve(hip, body["segs"][key], foot, hip + Vector3(0, 0, 1))
		var n: Dictionary = body["legs"][key]
		_orient(n["a"], pts[0], pts[1])
		_orient(n["b"], pts[1], pts[2])
		(n["foot"] as MeshInstance3D).position = pts[2]
	# attacking arm
	if body.get("arm", {}).is_empty() or _attack == null:
		return
	var arm: Dictionary = body["arm_chain"]
	var shoulder: Vector3 = root * (arm["base"] as Vector3)
	var target := _target_point()
	var ph: float = _phase if _phase >= 0.0 else 0.0
	var s: Dictionary = _attack.sample(ph, shoulder, target)
	var hand_target: Vector3 = s["hand_target"]
	var pts2 := ChainIK.solve(shoulder, arm["segments"], hand_target, shoulder + Vector3(0, -0.6, 1))
	_orient(body["arm"]["a"], pts2[0], pts2[1])
	_orient(body["arm"]["b"], pts2[1], pts2[2])
	(body["arm"]["hand"] as MeshInstance3D).position = pts2[2]

	# contact: the hand IS the contact point during the impact window
	if _phase >= 0.0 and not _struck and s["impact_active"]:
		var hand: Vector3 = pts2[2]
		if hand.distance_to(target) < 0.35:
			_land_hit(hand)


func _land_hit(contact: Vector3) -> void:
	_struck = true
	var rm: BodyMeasure = _receiver["measure"]
	var am: BodyMeasure = _attacker["measure"]
	var aim: Vector3 = (_target_point() - _shoulder())
	aim = aim.normalized() if aim.length() > 1e-4 else Vector3(0, 0, 1)
	var impulse: Vector3 = aim * float(_params["impulse"])
	_last_contact = contact
	_last_impulse = impulse

	var r_root: Transform3D = _root_of(_receiver)
	var r_com: Vector3 = r_root * ((_receiver["base"] as Transform3D).affine_inverse() * rm.center_of_mass())
	(_receiver["impact"] as ImpactResponse).apply_impulse(
		contact, impulse, r_com, rm.total_mass(), rm.inertia_about_com())

	var a_root: Transform3D = _root_of(_attacker)
	var a_com: Vector3 = a_root * ((_attacker["base"] as Transform3D).affine_inverse() * am.center_of_mass())
	(_attacker["impact"] as ImpactResponse).apply_impulse(
		contact, -impulse, a_com, am.total_mass(), am.inertia_about_com())

	_hit_marker.position = contact
	_hit_marker.visible = true
	var above := contact.y - r_com.y
	_status = "HIT %.2f m %s the CoM" % [absf(above), ("above" if above > 0.0 else "below")]


func _update_camera() -> void:
	var focus := Vector3(0, 0.7, -0.4)
	_cam.position = focus + Vector3(3.6, 1.4, 2.9)
	_cam.look_at(focus, Vector3.UP)


# ---- save / bake -----------------------------------------------------------

const OUT_DIR := "res://data/locomotion_profiles"


func _save_profile() -> void:
	_ensure_dir()
	var path := "%s/impact_%s.json" % [OUT_DIR, _params["attack_style"]]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status = "save FAILED (%s)" % path
		return
	f.store_string(JSON.stringify(_params, "\t"))
	f.close()
	_status = "saved profile → %s" % path


func _record_sample() -> void:
	for body in [_attacker, _receiver]:
		var holder: Node3D = body["holder"]
		for mi in holder.get_children():
			if mi is MeshInstance3D:
				_samples.append({"t": _rec_time, "path": "%s/%s" % [holder.name, mi.name],
					"pos": (mi as MeshInstance3D).position,
					"rot": (mi as MeshInstance3D).quaternion})


func _bake_clip() -> void:
	if _samples.is_empty():
		_status = "nothing recorded — strike first, then bake"
		return
	_ensure_dir()
	var anim := Animation.new()
	var by_path: Dictionary = {}
	var length := 0.0
	for s in _samples:
		by_path.get_or_add(s["path"], []).append(s)
		length = maxf(length, s["t"])
	anim.length = maxf(length, 0.1)
	for p in by_path:
		var pt := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pt, NodePath(p))
		var rt := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(rt, NodePath(p))
		for s in by_path[p]:
			anim.position_track_insert_key(pt, s["t"], s["pos"])
			anim.rotation_track_insert_key(rt, s["t"], s["rot"])
	var path := "%s/impact_%s_baked.tres" % [OUT_DIR, _params["attack_style"]]
	var err := ResourceSaver.save(anim, path)
	_status = ("baked %d tracks → %s" % [by_path.size(), path]) if err == OK else "bake FAILED (%d)" % err


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)


# ---- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)

	var rp := PanelContainer.new()
	rp.offset_left = 12
	rp.offset_top = 12
	layer.add_child(rp)
	var rm := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		rm.add_theme_constant_override("margin_" + s, 10)
	rp.add_child(rm)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 13)
	rm.add_child(_readout)

	_menu = PanelContainer.new()
	_menu.anchor_left = 1.0
	_menu.anchor_right = 1.0
	_menu.anchor_bottom = 1.0
	_menu.offset_left = -352
	_menu.offset_right = -12
	_menu.offset_top = 12
	_menu.offset_bottom = -12
	layer.add_child(_menu)
	var scroll := ScrollContainer.new()
	_menu.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(322, 0)
	scroll.add_child(vb)

	var title := Label.new()
	title.text = "Combat lab — action & reaction"
	title.add_theme_font_size_override("font_size", 15)
	vb.add_child(title)
	var hint := Label.new()
	hint.text = "Space: strike · A: auto · Tab: hide · R: reset"
	hint.add_theme_font_size_override("font_size", 11)
	vb.add_child(hint)

	var stage := ""
	for e in SPEC:
		if e["stage"] != stage:
			stage = e["stage"]
			var sh := Label.new()
			sh.text = "  " + stage
			sh.add_theme_font_size_override("font_size", 13)
			sh.add_theme_color_override("font_color", Color(0.95, 0.7, 0.55))
			vb.add_child(sh)
		vb.add_child(_enum_row(e) if e.get("kind", "range") == "enum" else _slider_row(e))

	var strike_btn := Button.new()
	strike_btn.text = "Strike  (Space)"
	strike_btn.pressed.connect(_strike)
	vb.add_child(strike_btn)
	var save_btn := Button.new()
	save_btn.text = "Save profile (.json)"
	save_btn.pressed.connect(_save_profile)
	vb.add_child(save_btn)
	var bake_btn := Button.new()
	bake_btn.text = "Bake last strike (.tres)"
	bake_btn.pressed.connect(_bake_clip)
	vb.add_child(bake_btn)


func _slider_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = e["name"]
	lbl.custom_minimum_size = Vector2(126, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = e["min"]
	sl.max_value = e["max"]
	sl.step = e["step"]
	sl.value = e["default"]
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(130, 0)
	row.add_child(sl)
	var val := Label.new()
	val.custom_minimum_size = Vector2(46, 0)
	val.add_theme_font_size_override("font_size", 12)
	val.text = "%.2f" % float(e["default"])
	row.add_child(val)
	_value_labels[e["name"]] = val
	sl.value_changed.connect(_on_slider.bind(e["name"]))
	return row


func _enum_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = e["name"]
	lbl.custom_minimum_size = Vector2(126, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range((e["values"] as Array).size()):
		opt.add_item(e["values"][i], i)
		if e["values"][i] == e["default"]:
			opt.select(i)
	row.add_child(opt)
	opt.item_selected.connect(_on_enum.bind(e))
	return row


func _on_slider(v: float, pname: String) -> void:
	_params[pname] = v
	if _value_labels.has(pname):
		(_value_labels[pname] as Label).text = "%.2f" % v


func _on_enum(idx: int, e: Dictionary) -> void:
	_params[e["name"]] = e["values"][idx]


func _update_readout() -> void:
	if _readout == null:
		return
	var rr: ImpactResponse = _receiver["impact"]
	var ar: ImpactResponse = _attacker["impact"]
	var lines := [
		"%s" % _status,
		"contact  (%.2f, %.2f, %.2f)   impulse %.0f" % [_last_contact.x, _last_contact.y, _last_contact.z, _last_impulse.length()],
		"receiver  shift %.3f m   tilt %.1f°" % [rr.displacement().length(), rad_to_deg(rr.tilt().length())],
		"attacker  recoil %.3f m   tilt %.1f°" % [ar.displacement().length(), rad_to_deg(ar.tilt().length())],
		"phase %s   samples %d" % [("idle" if _phase < 0.0 else "%.2f" % _phase), _samples.size()],
	]
	_readout.text = "\n".join(lines)


# ---- primitives ------------------------------------------------------------

func _box(parent: Node3D, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 10
	mi.mesh = m
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	mi.mesh = m
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _orient(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d: Vector3 = b - a
	if d.length() < 1e-5:
		return
	var dir := d.normalized()
	var basis: Basis
	var dot := Vector3.UP.dot(dir)
	if dot > 0.9999:
		basis = Basis.IDENTITY
	elif dot < -0.9999:
		basis = Basis(Vector3.RIGHT, PI)
	else:
		basis = Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir))
	mi.transform = Transform3D(basis, (a + b) * 0.5)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	return mat


func _ground() -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(24, 0.1, 24)
	mi.mesh = m
	mi.position = Vector3(0, -0.05, 0)
	mi.material_override = _mat(Color(0.17, 0.18, 0.21))
	add_child(mi)


func _setup_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -40, 0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	add_child(light)
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.4, 0.55)
	sm.sky_horizon_color = Color(0.68, 0.72, 0.8)
	var sky := Sky.new()
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
