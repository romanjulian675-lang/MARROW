extends Node3D

# Stage-6 / M5 demo: watch assembled creatures WALK. Each is driven by the same
# GaitController — a gait oscillator schedules stance/swing per leg, planted feet
# stay world-locked, swing feet arc forward, the root advances and sways for
# balance, and ChainIK poses every leg from hip to foot. A biped WALK and a
# quadruped TROT come out of the SAME controller, differing only in phase offsets.
#
# Open scenes/locomotion_walk.tscn and press F6. Side view; the camera tracks the
# walkers as they cross the striped ground. Swing feet glow, planted feet are dim.

const PLANTED := Color(0.85, 0.62, 0.2)
const SWINGING := Color(0.55, 0.85, 0.55)

var _walkers: Array = []
var _cam: Camera3D
var _center_x := 0.15


func _ready() -> void:
	_setup_environment()
	_ground()
	_walkers.append(_make_walker(LocomotionZoo.biped(), -2.8, 0.7,
		{"family": "biped_walk", "reach_fraction": 0.9}, "biped walk"))
	_walkers.append(_make_walker(LocomotionZoo.quadruped(), 0.2, 0.45,
		{"family": "quadruped_walk", "reach_fraction": 0.80, "stance_width": 0.40,
		"stride_ratio": 0.75, "step_ratio": 0.28}, "quadruped walk"))
	_walkers.append(_make_walker(LocomotionZoo.hexapod(), 3.4, 0.45,
		{"family": "tripod", "reach_fraction": 0.80, "stance_width": 0.40,
		"stride_ratio": 0.75, "step_ratio": 0.28}, "hexapod tripod"))
	_center_x = 0.2
	_cam = Camera3D.new()
	_cam.fov = 62.0
	add_child(_cam)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif key.keycode == KEY_R:
		get_tree().reload_current_scene()


func _process(dt: float) -> void:
	var avg_z := 0.0
	for w in _walkers:
		(w["gait"] as GaitController).step(dt)
		_update_walker(w)
		avg_z += (w["gait"] as GaitController).root_transform.origin.z
	avg_z /= float(maxi(1, _walkers.size()))
	if _cam != null:
		_cam.position = Vector3(_center_x + 8.5, 2.4, avg_z - 0.3)
		_cam.look_at(Vector3(_center_x, 0.7, avg_z + 0.4), Vector3.UP)


# ---- build one walker -----------------------------------------------------

func _make_walker(g: BodyGraph, x_off: float, speed: float, cfg: Dictionary, label: String) -> Dictionary:
	var measure := BodyMeasure.new(g)
	var sopts := {"reach_fraction": cfg.get("reach_fraction", 0.9)}
	if cfg.has("stance_width"):
		sopts["stance_width"] = cfg["stance_width"]
	var stance := StanceGenerator.new(g, measure).generate(sopts)

	# GaitPattern picks the footfall schedule for the family; the per-creature step
	# ratios set stride length and lift. Reining in `stance_width` leaves fore-aft
	# room for a LONG stride — which is what keeps cadence low enough that the swing
	# is actually visible instead of a 4-frame blur.
	var pat: Dictionary = GaitPattern.for_family(cfg.get("family", "biped_walk"), stance["contacts"])
	for k in ["stride_ratio", "step_ratio", "balance_gain"]:
		if cfg.has(k):
			pat[k] = cfg[k]

	var gait := GaitController.new(g, stance, pat)
	gait.set_velocity(Vector3(0, 0, speed))

	var lane := Node3D.new()
	lane.position = Vector3(x_off, 0, 0)
	add_child(lane)

	# Which parts are legs (drawn by IK) vs. body (drawn as boxes)?
	var limb_ids: Dictionary = {}
	var seg_by_key: Dictionary = {}
	for c in measure.chains():
		var key: String = "%s.%s" % [c["part"], c["socket"]]
		seg_by_key[key] = c["segments"]
		for pid in c["limb_parts"]:
			limb_ids[pid] = true

	var body_boxes: Dictionary = {}
	for pid in g.parts:
		if limb_ids.has(pid):
			continue
		var part: BodyPart = g.parts[pid]
		body_boxes[pid] = _box(lane, part.size, Color(0.74, 0.77, 0.85))

	var legs: Dictionary = {}
	for key in seg_by_key:
		var segs: Array = seg_by_key[key]
		legs[key] = {
			"thigh": _cyl(lane, 0.05, segs[0], Color(0.53, 0.6, 0.82)),
			"shin": _cyl(lane, 0.045, segs[1], Color(0.53, 0.6, 0.82)),
			"knee": _ball(lane, 0.05, Color(0.64, 0.7, 0.86)),
			"foot": _ball(lane, 0.06, PLANTED),
		}

	_label(lane, Vector3(0, float(stance["torso_height"]) + 0.7, 0), label)
	return {"gait": gait, "graph": g, "lane": lane, "body_boxes": body_boxes, "legs": legs}


# ---- per-frame update -----------------------------------------------------

func _update_walker(w: Dictionary) -> void:
	var gait: GaitController = w["gait"]
	var g: BodyGraph = w["graph"]
	var asm: Dictionary = g.assemble(gait.root_transform)
	for pid in w["body_boxes"]:
		var part: BodyPart = g.parts[pid]
		(w["body_boxes"][pid] as MeshInstance3D).transform = \
			(asm[pid] as Transform3D) * Transform3D(Basis.IDENTITY, part.local_center_of_mass())
	for key in w["legs"]:
		var pts: PackedVector3Array = gait.leg_points(key)
		var nodes: Dictionary = w["legs"][key]
		_orient(nodes["thigh"], pts[0], pts[1])
		_orient(nodes["shin"], pts[1], pts[2])
		(nodes["knee"] as MeshInstance3D).position = pts[1]
		var foot: MeshInstance3D = nodes["foot"]
		foot.position = pts[2]
		(foot.material_override as StandardMaterial3D).albedo_color = \
			PLANTED if gait.is_planted(key) else SWINGING


# ---- primitives -----------------------------------------------------------

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
	m.radial_segments = 12
	m.rings = 7
	mi.mesh = m
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _orient(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 1e-5:
		return
	mi.transform = Transform3D(_basis_from_up(d / length), (a + b) * 0.5)


func _basis_from_up(dir: Vector3) -> Basis:
	var dot: float = Vector3.UP.dot(dir)
	if dot > 0.9999:
		return Basis.IDENTITY
	if dot < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir))


func _label(parent: Node3D, pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.outline_size = 10
	l.pixel_size = 0.006
	l.no_depth_test = true
	parent.add_child(l)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	return mat


func _ground() -> void:
	var plane := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(60, 0.1, 160)
	plane.mesh = pm
	plane.position = Vector3(0, -0.05, 60)
	plane.material_override = _mat(Color(0.17, 0.18, 0.21))
	add_child(plane)
	# Stripes across the path every metre so forward motion reads.
	for i in range(-4, 120):
		var s := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(14, 0.02, 0.05)
		s.mesh = sm
		s.position = Vector3(0, 0.005, float(i))
		s.material_override = _mat(Color(0.28, 0.3, 0.34))
		add_child(s)


func _setup_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -46, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.45, 0.6)
	sky_mat.sky_horizon_color = Color(0.7, 0.75, 0.82)
	sky_mat.ground_bottom_color = Color(0.18, 0.19, 0.22)
	sky_mat.ground_horizon_color = Color(0.55, 0.57, 0.6)
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
