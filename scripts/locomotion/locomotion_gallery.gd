extends Node3D

# Visual gallery for stages 1–3 of the generic locomotion system. For every
# creature in LocomotionZoo it runs the real StanceGenerator and draws, on its
# own ground tile:
#   • torso / head / loads as their true rigid-part boxes (stage-1 assembly)
#   • each leg as one bone from its hip to the planted foot (stage-3 target)
#   • the support polygon (translucent), a disc per planted foot, and the
#     centre-of-mass plumb line + marker — GREEN when the CoM sits inside the
#     base (stable), RED when it falls outside (the body would tip).
#
# Nothing is hardcoded per creature: the SAME code renders 2, 4 or 6 legs.
#
# View it: open scenes/locomotion_gallery.tscn in Godot and press F6 (Play
# Scene). The camera slowly orbits so the fore-aft spread of the wider stances
# reads in 3D. Data-layer smoke test (headless):
#   <godot> --headless --path . --script res://scripts/locomotion/test_gallery.gd

const SPACING := 3.2
const FOOT_R := 0.08          # must match StanceGenerator's contact_radius

var _camera: Camera3D
var _orbit_center := Vector3(0.0, 0.55, 0.0)
var _orbit_radius := 10.0
var _orbit_height := 3.2
var _orbit_t := 0.0


func _ready() -> void:
	_setup_environment()
	var zoo: Array = LocomotionZoo.catalog()
	var span := SPACING * float(zoo.size() - 1)
	var x := -span * 0.5
	for entry in zoo:
		_spawn(entry, Vector3(x, 0.0, 0.0))
		x += SPACING
	_orbit_radius = span * 0.6 + 5.0
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)


func _process(delta: float) -> void:
	if _camera == null:
		return
	_orbit_t += delta * 0.1
	_camera.position = _orbit_center + Vector3(
		sin(_orbit_t) * _orbit_radius, _orbit_height, cos(_orbit_t) * _orbit_radius)
	_camera.look_at(_orbit_center, Vector3.UP)


func _spawn(entry: Dictionary, offset: Vector3) -> void:
	var graph: BodyGraph = entry["graph"]
	var measure := BodyMeasure.new(graph)
	var resting: bool = entry.get("mode", "stance") == "rest"
	# Stand at 90% of full reach so stage-5 IK has slack to bend the knees.
	var stance: Dictionary = StanceGenerator.resting_stance(graph, measure) if resting \
		else StanceGenerator.new(graph, measure).generate({"reach_fraction": 0.9})
	var chains: Array = measure.chains()

	var H: float = stance.get("torso_height", 0.9)
	var stable: bool = stance.get("stable", false)
	var off: Vector2 = stance.get("root_offset", Vector2.ZERO)

	var root := Node3D.new()
	root.name = entry["name"]
	root.position = offset
	add_child(root)
	_ground_tile(root)

	# Assemble the rigid body at the stance height — and, for a resting body,
	# recentred over its contacts. Every stance coordinate shares this frame, so
	# `root.position` alone places the whole exhibit.
	var asm: Dictionary = graph.assemble(Transform3D(Basis.IDENTITY, Vector3(off.x, H, off.y)))

	# A legged body draws its limb parts as bones-to-the-foot and everything else
	# as boxes; a resting body has no legs, so every part is drawn as its box.
	var limb_ids: Dictionary = {}
	if not resting:
		for c in chains:
			for pid in c["limb_parts"]:
				limb_ids[pid] = true

	for pid in graph.parts:
		if limb_ids.has(pid):
			continue
		var part: BodyPart = graph.parts[pid]
		var box_xf: Transform3D = (asm[pid] as Transform3D) * Transform3D(Basis.IDENTITY, part.local_center_of_mass())
		_box(root, box_xf, part.size, Color(0.74, 0.77, 0.85))

	if stance.is_empty():
		_label(root, Vector3(0, H + 0.7, 0), "%s\n(no stance found)" % entry["name"])
		return

	if resting:
		for ct in stance["contacts"]:
			_foot_dot(root, ct["pos"])
	else:
		# Solve each leg with stage-5 IK: bend the chain from its hip (raised to the
		# stance height) to the planted foot, knee toward a forward pole, and draw
		# one rigid bone per solved segment (TDD §4.4) plus a knee joint marker.
		var chain_by_key: Dictionary = {}
		for c in chains:
			chain_by_key["%s.%s" % [c["part"], c["socket"]]] = c
		for ct in stance["contacts"]:
			var c: Dictionary = chain_by_key["%s.%s" % [ct["part"], ct["socket"]]]
			var hip: Vector3 = (c["base"] as Vector3) + Vector3(0, H, 0)
			var foot: Vector3 = ct["pos"]
			var pole: Vector3 = hip + Vector3(0, 0, 1.0)          # knee bends forward (+z)
			var pts: PackedVector3Array = ChainIK.solve(hip, c["segments"], foot, pole)
			for i in range(pts.size() - 1):
				_bone(root, pts[i], pts[i + 1], 0.05, Color(0.53, 0.6, 0.82))
			for i in range(1, pts.size() - 1):                    # interior joints = knees
				_sphere(root, pts[i], 0.045, Color(0.64, 0.7, 0.86))
			_foot_dot(root, foot)

	_support_polygon(root, stance["support_hull"], stable)

	var com: Vector2 = stance["com_xz"]
	var com_ground := Vector3(com.x, 0.02, com.y)
	var com_color := Color(0.2, 0.85, 0.35) if stable else Color(0.95, 0.28, 0.22)
	_sphere(root, com_ground, 0.07, com_color)
	_bone(root, Vector3(com.x, H + 0.15, com.y), com_ground, 0.012, com_color)   # plumb line

	var tag := "STABLE" if stable else "UNSTABLE"
	_label(root, Vector3(0, H + 0.75, 0),
		"%s\n%s\nmargin %+.2f · %s" % [entry["name"], entry["blurb"], stance["margin"], tag])


# ---- primitives ----------------------------------------------------------

func _ground_tile(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(2.6, 0.04, 2.6)
	mi.mesh = m
	mi.position = Vector3(0, -0.02, 0)
	mi.material_override = _mat(Color(0.16, 0.17, 0.2))
	parent.add_child(mi)


func _box(parent: Node3D, xf: Transform3D, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.transform = xf
	mi.material_override = _mat(color)
	parent.add_child(mi)


func _bone(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-5:
		return
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = 10
	mi.mesh = m
	mi.transform = Transform3D(_basis_from_up(d / length), (a + b) * 0.5)
	mi.material_override = _mat(color)
	parent.add_child(mi)


# Rotate the cylinder's +Y axis onto `dir` (unit).
func _basis_from_up(dir: Vector3) -> Basis:
	var dot := Vector3.UP.dot(dir)
	if dot > 0.9999:
		return Basis.IDENTITY
	if dot < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	var axis := Vector3.UP.cross(dir).normalized()
	return Basis(axis, Vector3.UP.angle_to(dir))


func _sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 14
	m.rings = 8
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)


func _foot_dot(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = FOOT_R
	m.bottom_radius = FOOT_R
	m.height = 0.02
	m.radial_segments = 16
	mi.mesh = m
	mi.position = Vector3(pos.x, 0.012, pos.z)
	mi.material_override = _mat(Color(0.92, 0.76, 0.22))
	parent.add_child(mi)


func _support_polygon(parent: Node3D, hull: Array, stable: bool) -> void:
	if hull.size() < 3:
		return
	var y := 0.008
	var c := Geom2d.centroid(hull)
	var center := Vector3(c.x, y, c.y)
	var verts := PackedVector3Array()
	var n := hull.size()
	for i in range(n):
		var p0: Vector2 = hull[i]
		var p1: Vector2 = hull[(i + 1) % n]
		verts.append(center)
		verts.append(Vector3(p0.x, y, p0.y))
		verts.append(Vector3(p1.x, y, p1.y))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var col := Color(0.2, 0.72, 0.36, 0.33) if stable else Color(0.92, 0.3, 0.24, 0.33)
	var mat := _mat(col)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	parent.add_child(mi)


func _label(parent: Node3D, pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 44
	l.outline_size = 12
	l.pixel_size = 0.006
	l.no_depth_test = true
	parent.add_child(l)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.75
	return mat


func _setup_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -40, 0)
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
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
