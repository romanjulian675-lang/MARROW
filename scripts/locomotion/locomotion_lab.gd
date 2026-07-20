extends Node3D

# Locomotion Lab — a live tuning bench for EVERY variable the M2–M6 pipeline
# exposes. One creature walks; the menu (top-right) drives it in real time and the
# readout (top-left) shows the consequences (measured reach/mass, the chosen
# stance's height/margin, and the live support count / reach strain), so you can
# judge which knobs actually matter and whether any should be added or dropped.
#
# The whole variable set is the SPEC array below — the single source of truth.
# Tab hides/shows the menu; Esc returns to the main menu; R resets position.

# stage | name | kind | (range: min,max,step,default) | (enum: values, default)
const SPEC := [
	{"stage": "M2 · morphology", "name": "creature", "kind": "enum",
		"values": ["quadruped", "biped", "hexapod"], "default": "quadruped"},
	{"stage": "M2 · morphology", "name": "leg_length", "min": 0.30, "max": 0.90, "step": 0.02, "default": 0.50},
	{"stage": "M3 · stance", "name": "reach_fraction", "min": 0.50, "max": 1.00, "step": 0.01, "default": 0.80},
	{"stage": "M3 · stance", "name": "stance_width", "min": 0.0, "max": 1.0, "step": 0.02, "default": 0.40},
	{"stage": "M3 · stance", "name": "contact_radius", "min": 0.02, "max": 0.20, "step": 0.005, "default": 0.08},
	{"stage": "M5 · gait", "name": "speed", "min": 0.0, "max": 1.5, "step": 0.02, "default": 0.45},
	{"stage": "M5 · gait", "name": "turn_rate", "min": -1.0, "max": 1.0, "step": 0.02, "default": 0.0},
	{"stage": "M5 · gait", "name": "stride_ratio", "min": 0.10, "max": 0.90, "step": 0.01, "default": 0.75},
	{"stage": "M5 · gait", "name": "step_ratio", "min": 0.05, "max": 0.40, "step": 0.01, "default": 0.28},
	{"stage": "M5 · gait", "name": "duty", "min": 0.40, "max": 0.92, "step": 0.01, "default": 0.78},
	{"stage": "M6 · pattern", "name": "family", "kind": "enum",
		"values": ["auto", "quadruped_walk", "quadruped_trot", "tripod", "wave", "biped_walk"], "default": "auto"},
	{"stage": "M6 · terrain", "name": "slope", "min": 0.0, "max": 0.30, "step": 0.01, "default": 0.0},
]

const LIVE := ["speed", "turn_rate"]     # applied every frame, no rebuild

var _params: Dictionary = {}
var _value_labels: Dictionary = {}
var _readout: Label
var _menu: Control
var _cam: Camera3D
var _ground_node: MeshInstance3D

var _graph: BodyGraph
var _measure: BodyMeasure
var _stance: Dictionary = {}
var _gait: GaitController
var _creature: Node3D
var _body_boxes: Dictionary = {}
var _legs: Dictionary = {}
var _seg_by_key: Dictionary = {}
var _status := ""
var _min_support := 99
var _max_strain := 0.0


func _ready() -> void:
	for e in SPEC:
		_params[e["name"]] = e["default"]
	_setup_environment()
	_build_ui()
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_rebuild()


func _terrain(p: Vector3) -> float:
	return float(_params["slope"]) * p.z


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_TAB:
		_menu.visible = not _menu.visible
	elif key.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif key.keycode == KEY_R:
		_rebuild(true)


# ---- (re)build the creature from the current params ------------------------

func _rebuild(reset := false) -> void:
	var carry_travel := Vector3.ZERO
	var carry_head := 0.0
	if _gait != null and not reset:
		carry_travel = _gait.root_transform.origin
		carry_head = _gait.heading()
	if _creature != null:
		_creature.queue_free()
	_creature = Node3D.new()
	add_child(_creature)
	_body_boxes = {}
	_legs = {}
	_seg_by_key = {}
	_min_support = 99
	_max_strain = 0.0

	_graph = _build_creature()
	_measure = BodyMeasure.new(_graph)
	_stance = StanceGenerator.new(_graph, _measure).generate({
		"reach_fraction": _params["reach_fraction"], "stance_width": _params["stance_width"],
		"contact_radius": _params["contact_radius"]})
	_build_ground()

	if _stance.is_empty():
		_gait = null
		_status = "NO STABLE STANCE at these settings"
		_spawn_static()
		_update_readout()
		return

	_status = ""
	var fam: String = _params["family"]
	var pat: Dictionary = GaitPattern.recommend(_stance["contacts"]) if fam == "auto" \
		else GaitPattern.for_family(fam, _stance["contacts"])
	pat["duty"] = _params["duty"]
	pat["stride_ratio"] = _params["stride_ratio"]
	pat["step_ratio"] = _params["step_ratio"]
	_gait = GaitController.new(_graph, _stance, pat)   # balance is now automatic
	if float(_params["slope"]) > 0.001:
		_gait.set_ground(Callable(self, "_terrain"))
	_gait.set_intent(_params["speed"], _params["turn_rate"])
	_gait.adopt_motion(carry_travel, carry_head)

	_spawn_render()
	_update_readout()


func _build_creature() -> BodyGraph:
	var l: float = _params["leg_length"]
	match _params["creature"]:
		"biped":
			return LocomotionZoo.biped(l)
		"hexapod":
			return LocomotionZoo.hexapod(l)
		_:
			return LocomotionZoo.quadruped(l)


func _process(dt: float) -> void:
	if _gait != null:
		_gait.set_intent(_params["speed"], _params["turn_rate"])
		_gait.step(dt)
		_update_render()
		_min_support = mini(_min_support, _gait.planted_count())
		for key in _gait.limbs():
			_max_strain = maxf(_max_strain, _gait.reach_strain(key))
	_update_camera()
	_update_readout()


# ---- rendering -------------------------------------------------------------

func _spawn_render() -> void:
	var limb_ids: Dictionary = {}
	for c in _measure.chains():
		var key: String = "%s.%s" % [c["part"], c["socket"]]
		_seg_by_key[key] = c["segments"]
		for pid in c["limb_parts"]:
			limb_ids[pid] = true
	for pid in _graph.parts:
		if limb_ids.has(pid):
			continue
		_body_boxes[pid] = _box((_graph.parts[pid] as BodyPart).size, Color(0.74, 0.77, 0.85))
	for key in _seg_by_key:
		var segs: Array = _seg_by_key[key]
		_legs[key] = {
			"thigh": _cyl(0.05, segs[0], Color(0.53, 0.6, 0.82)),
			"shin": _cyl(0.045, segs[1], Color(0.53, 0.6, 0.82)),
			"knee": _ball(0.05, Color(0.64, 0.7, 0.86)),
			"foot": _ball(0.06, Color(0.85, 0.62, 0.2)),
		}


func _spawn_static() -> void:
	# No viable stance — just show the rest assembly standing at reach height.
	var h: float = float(_params["leg_length"]) + 0.35
	var asm := _graph.assemble(Transform3D(Basis.IDENTITY, Vector3(0, h, 0)))
	for pid in _graph.parts:
		var part: BodyPart = _graph.parts[pid]
		var mi := _box(part.size, Color(0.7, 0.45, 0.45))
		mi.transform = (asm[pid] as Transform3D) * Transform3D(Basis.IDENTITY, part.local_center_of_mass())


func _update_render() -> void:
	var asm: Dictionary = _graph.assemble(_gait.root_transform)
	for pid in _body_boxes:
		var part: BodyPart = _graph.parts[pid]
		(_body_boxes[pid] as MeshInstance3D).transform = \
			(asm[pid] as Transform3D) * Transform3D(Basis.IDENTITY, part.local_center_of_mass())
	for key in _legs:
		var pts: PackedVector3Array = _gait.leg_points(key)
		var n: Dictionary = _legs[key]
		_orient(n["thigh"], pts[0], pts[1])
		_orient(n["shin"], pts[1], pts[2])
		(n["knee"] as MeshInstance3D).position = pts[1]
		var foot: MeshInstance3D = n["foot"]
		foot.position = pts[2]
		(foot.material_override as StandardMaterial3D).albedo_color = \
			Color(0.85, 0.62, 0.2) if _gait.is_planted(key) else Color(0.55, 0.85, 0.55)


func _update_camera() -> void:
	var focus := Vector3(0, 0.6, 0)
	if _gait != null:
		focus = _gait.root_transform.origin
	var facing := 0.0 if _gait == null else _gait.heading()
	var back := Basis(Vector3.UP, facing) * Vector3(4.5, 0, -5.5)
	_cam.position = focus + back + Vector3(0, 2.6, 0)
	_cam.look_at(focus + Vector3(0, 0.2, 0), Vector3.UP)


# ---- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)

	# readout (top-left)
	var rpanel := PanelContainer.new()
	rpanel.anchor_left = 0.0
	rpanel.anchor_top = 0.0
	rpanel.offset_left = 12
	rpanel.offset_top = 12
	layer.add_child(rpanel)
	var rmargin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		rmargin.add_theme_constant_override("margin_" + s, 10)
	rpanel.add_child(rmargin)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 13)
	rmargin.add_child(_readout)

	# menu (top-right)
	_menu = PanelContainer.new()
	_menu.anchor_left = 1.0
	_menu.anchor_right = 1.0
	_menu.anchor_top = 0.0
	_menu.anchor_bottom = 1.0
	_menu.offset_left = -346
	_menu.offset_right = -12
	_menu.offset_top = 12
	_menu.offset_bottom = -12
	layer.add_child(_menu)
	var scroll := ScrollContainer.new()
	_menu.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(316, 0)
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Locomotion lab — M2–M6 variables"
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "Tab: hide · Esc: menu · R: reset"
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	var stage := ""
	for e in SPEC:
		if e["stage"] != stage:
			stage = e["stage"]
			var sh := Label.new()
			sh.text = "  " + stage
			sh.add_theme_font_size_override("font_size", 13)
			sh.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95))
			vbox.add_child(sh)
		if e.get("kind", "range") == "enum":
			vbox.add_child(_enum_row(e))
		else:
			vbox.add_child(_slider_row(e))


func _slider_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = e["name"]
	name_lbl.custom_minimum_size = Vector2(112, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(name_lbl)
	var slider := HSlider.new()
	slider.min_value = e["min"]
	slider.max_value = e["max"]
	slider.step = e["step"]
	slider.value = e["default"]
	slider.custom_minimum_size = Vector2(140, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var val := Label.new()
	val.custom_minimum_size = Vector2(46, 0)
	val.add_theme_font_size_override("font_size", 12)
	val.text = _fmt(e["default"])
	row.add_child(val)
	_value_labels[e["name"]] = val
	slider.value_changed.connect(_on_slider.bind(e["name"]))
	return row


func _enum_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = e["name"]
	name_lbl.custom_minimum_size = Vector2(112, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(name_lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range((e["values"] as Array).size()):
		opt.add_item(e["values"][i], i)
		if e["values"][i] == e["default"]:
			opt.select(i)
	row.add_child(opt)
	opt.item_selected.connect(_on_enum.bind(e))
	return row


func _on_slider(value: float, pname: String) -> void:
	_params[pname] = value
	if _value_labels.has(pname):
		(_value_labels[pname] as Label).text = _fmt(value)
	if pname in LIVE:
		return                                # applied live in _process
	_rebuild()


func _on_enum(idx: int, e: Dictionary) -> void:
	_params[e["name"]] = e["values"][idx]
	_rebuild()


func _update_readout() -> void:
	if _readout == null:
		return
	var lines: Array = []
	var reach := 0.0
	for c in _measure.chains():
		reach = maxf(reach, c["reach_max"])
	lines.append("M2  parts %d   reach %.2f m   mass %.1f" % [_graph.part_count(), reach, _measure.total_mass()])
	if _stance.is_empty():
		lines.append("M3  %s" % _status)
	else:
		lines.append("M3  height %.2f   margin %+.3f   feet %d   %s" % [
			_stance["torso_height"], _stance["margin"], (_stance["contacts"] as Array).size(),
			("STABLE" if _stance.get("stable", false) else "unstable")])
	if _gait != null:
		lines.append("M5  stride %.2f   step %.2f   duty %.2f" % [_gait.stride, _gait.step_height, _gait.osc.duty])
		lines.append("live  support(min) %d   strain(max) %.2f   heading %d°" % [
			(_min_support if _min_support < 99 else _gait.planted_count()),
			_max_strain, int(rad_to_deg(_gait.heading()))])
	_readout.text = "\n".join(lines)


func _fmt(v: float) -> String:
	return "%.2f" % v


# ---- primitives ------------------------------------------------------------

func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _mat(color)
	_creature.add_child(mi)
	return mi


func _cyl(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 10
	mi.mesh = m
	mi.material_override = _mat(color)
	_creature.add_child(mi)
	return mi


func _ball(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	mi.mesh = m
	mi.material_override = _mat(color)
	_creature.add_child(mi)
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


func _build_ground() -> void:
	if _ground_node != null:
		_ground_node.queue_free()
	_ground_node = MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(60, 0.1, 200)
	_ground_node.mesh = m
	_ground_node.rotation.x = -atan(float(_params["slope"]))   # tilt to match the ramp
	_ground_node.position = Vector3(0, -0.05, 80)
	_ground_node.material_override = _mat(Color(0.17, 0.18, 0.21))
	add_child(_ground_node)


func _setup_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -46, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.45, 0.6)
	sky_mat.sky_horizon_color = Color(0.7, 0.75, 0.82)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
