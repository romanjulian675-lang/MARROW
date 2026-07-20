class_name BodyPart
extends RefCounted

# Stage 1 of the generic locomotion plan: a single RIGID part in the body graph.
#
# A part is deliberately dumb — a box of a given size and mass, plus a set of
# named SOCKETS. A socket is a frame (Transform3D) fixed to the part's own origin
# where another part can be joined. Nothing here knows "arm" or "leg"; a torso is
# just a part with five sockets, a leg is a part with two. That is what lets one
# assembler build a biped, a quadruped, or a thing with seven legs from the same
# code.
#
# Convention: the part's ORIGIN is its own local (0,0,0); `size` is the full box
# extent centred on `center_offset` from the origin. Sockets and the centre are
# all expressed in this origin frame, so a part is fully self-describing and can
# be reused wherever it is socketed.

var id: String = ""
var size: Vector3 = Vector3.ONE            # full box dimensions (metres)
var mass: float = 1.0                       # kilograms-ish; used from stage 2 (measure)
var center_offset: Vector3 = Vector3.ZERO   # box centre relative to the part origin

# socket_name -> Transform3D, the mount frame in this part's origin space.
var sockets: Dictionary = {}

# Socket names that are SUPPORT endpoints (a foot's tip). Stage 2 measures reach to
# them; stage 3 plants them. Membership here marks a weight-bearing contact.
var endpoints: Array = []

# Socket names that are MANIPULATION effectors (a hand, a jaw, a claw). They do NOT
# bear weight — stage 3 never plants them — but stage-9 attacks reach with them.
var manipulators: Array = []


func _init(part_id: String = "", part_size: Vector3 = Vector3.ONE, part_mass: float = 1.0) -> void:
	id = part_id
	size = part_size
	mass = part_mass


# Add/replace a socket. `xform` is the mount frame in this part's origin space —
# a bare Vector3 position is accepted as shorthand for an axis-aligned frame.
func add_socket(socket_name: String, xform) -> void:
	if xform is Vector3:
		sockets[socket_name] = Transform3D(Basis(), xform)
	else:
		sockets[socket_name] = xform


func has_socket(socket_name: String) -> bool:
	return sockets.has(socket_name)


# Mark an existing socket a SUPPORT contact endpoint (a foot).
func mark_endpoint(socket_name: String) -> void:
	if not endpoints.has(socket_name):
		endpoints.append(socket_name)


# Mark an existing socket a MANIPULATION effector (a hand) — reached by attacks,
# never planted as support.
func mark_manipulator(socket_name: String) -> void:
	if not manipulators.has(socket_name):
		manipulators.append(socket_name)


# The socket frame, or IDENTITY if the socket does not exist (callers that care
# should check has_socket first; the graph validator reports missing sockets).
func socket(socket_name: String) -> Transform3D:
	return sockets.get(socket_name, Transform3D.IDENTITY)


func socket_names() -> Array:
	return sockets.keys()


# The box centre in the part's origin frame — the naive centre of mass of a
# uniform box, which stage 2 aggregates up the graph.
func local_center_of_mass() -> Vector3:
	return center_offset


func duplicate_part() -> BodyPart:
	var p := BodyPart.new(id, size, mass)
	p.center_offset = center_offset
	for k in sockets:
		p.sockets[k] = sockets[k]
	p.endpoints = endpoints.duplicate()
	p.manipulators = manipulators.duplicate()
	return p
