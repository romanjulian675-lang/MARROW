class_name GaitController
extends RefCounted

# Stage 6 / TDD M5: drive a standing creature into a WALK on flat ground.
#
# Per frame (TDD §7): the gait oscillator schedules each limb's stance/swing; a
# PLANTED foot is world-locked (the defence against foot sliding, §7.3); a
# SWINGING foot arcs to the next predicted plant ahead of the body; the root
# advances by the desired velocity and shifts toward its support for balance; and
# every leg is posed by ChainIK from its hip to its foot. Every distance is scaled
# from morphology (§7.5), so the same controller walks any leg length.
#
# This is the biped case (two limbs, half a cycle apart) but nothing here is
# limb-count specific — hand it N offsets and it schedules N supports (M6).

var graph: BodyGraph
var osc: GaitOscillator
var root_transform: Transform3D

var stride: float
var step_height: float
var _stance_height: float
var _forward := Vector3(0, 0, 1)
var _velocity := Vector3.ZERO
var _heading := 0.0                    # facing yaw (radians)
var _turn_rate := 0.0                  # radians / second
var _speed := 0.0                      # forward speed (m/s)
var _balance_base: float                # max lateral sway; auto-scaled by support
var _travel := Vector3.ZERO            # ground position advancing purely by velocity
var _ground: Callable                  # Vector3 -> height; unset = flat ground (y=0)

# per limb (key = "part.socket")
var _base_local: Dictionary = {}       # hip position in the root frame
var _segments: Dictionary = {}         # per-segment lengths for IK
var _reach: Dictionary = {}
var _rest_offset: Dictionary = {}      # neutral foot offset under the hip, root frame
var _foot: Dictionary = {}             # current world foot position
var _planted: Dictionary = {}          # world position where the foot last planted
var _liftoff: Dictionary = {}
var _landing: Dictionary = {}
var _was_stance: Dictionary = {}


func _init(g: BodyGraph, stance: Dictionary, opts: Dictionary = {}) -> void:
	graph = g
	var measure := BodyMeasure.new(g)
	_stance_height = stance.get("torso_height", 0.9)
	root_transform = Transform3D(Basis.IDENTITY, Vector3(0, _stance_height, 0))

	var contacts: Array = stance.get("contacts", [])
	var offsets: Dictionary = opts.get("offsets", {})
	if offsets.is_empty():                                   # default: evenly spaced
		for i in range(contacts.size()):
			var ct: Dictionary = contacts[i]
			offsets["%s.%s" % [ct["part"], ct["socket"]]] = float(i) / float(maxi(1, contacts.size()))
	osc = GaitOscillator.new(offsets, opts.get("duty", 0.65))

	var chain_by_key: Dictionary = {}
	for c in measure.chains():
		chain_by_key["%s.%s" % [c["part"], c["socket"]]] = c

	var max_reach := 0.0
	for ct in contacts:
		var key: String = "%s.%s" % [ct["part"], ct["socket"]]
		var c: Dictionary = chain_by_key[key]
		_base_local[key] = c["base"]
		_segments[key] = c["segments"]
		_reach[key] = c["reach_max"]
		max_reach = maxf(max_reach, c["reach_max"])
		var foot: Vector3 = Vector3((ct["pos"] as Vector3).x, 0.0, (ct["pos"] as Vector3).z)
		_rest_offset[key] = foot
		_foot[key] = foot
		_planted[key] = foot
		_liftoff[key] = foot
		_landing[key] = foot
		_was_stance[key] = true

	stride = max_reach * float(opts.get("stride_ratio", 0.45))
	step_height = max_reach * float(opts.get("step_ratio", 0.16))
	_balance_base = float(opts.get("balance_gain", 0.35))


func set_velocity(v: Vector3) -> void:
	var flat := Vector3(v.x, 0, v.z)
	_speed = flat.length()
	if _speed > 1e-4:
		_heading = atan2(flat.x, flat.z)
	_forward = Basis(Vector3.UP, _heading) * Vector3(0, 0, 1)
	_velocity = _forward * _speed


# Walk-where-you-face intent: a forward speed and a turn rate. The heading turns
# over time, so a non-zero turn rate curves the path (radius = speed / turn_rate).
func set_intent(speed: float, turn_rate: float) -> void:
	_speed = speed
	_turn_rate = turn_rate


func set_turn_rate(turn_rate: float) -> void:
	_turn_rate = turn_rate


func heading() -> float:
	return _heading


# Carry position + facing across a rebuild (retune) so the creature doesn't jump.
func adopt_motion(travel: Vector3, head: float) -> void:
	_travel = Vector3(travel.x, 0, travel.z)
	_heading = head
	_forward = Basis(Vector3.UP, head) * Vector3(0, 0, 1)


# Give the controller a terrain height function (Vector3 -> float). Planted feet
# drop to it and the torso rides/tilts to match (via RootPoseSolver). Re-projects
# the current stance onto the terrain so it starts grounded.
func set_ground(height_fn: Callable) -> void:
	_ground = height_fn
	for key in _foot:
		var p: Vector3 = _planted[key]
		p.y = _ground_h(p)
		_planted[key] = p
		_foot[key] = p
		_liftoff[key] = p
		_landing[key] = p


func _ground_h(p: Vector3) -> float:
	return float(_ground.call(p)) if _ground.is_valid() else 0.0


func speed() -> float:
	return _velocity.length()


func step(dt: float) -> void:
	# Turn the heading, then walk where we face.
	_heading += _turn_rate * dt
	var facing := Basis(Vector3.UP, _heading)
	_forward = facing * Vector3(0, 0, 1)
	_velocity = _forward * _speed

	var cadence: float = (_speed / stride) if stride > 1e-4 else 0.0  # cycles / second
	osc.advance(cadence * dt)

	_travel += _velocity * dt
	var root_ground: Vector3 = Vector3(_travel.x, 0, _travel.z)
	var swing_dur: float = ((1.0 - osc.duty) / cadence) if cadence > 1e-4 else 0.0

	for key in osc.keys():
		var stance_now: bool = osc.is_stance(key)
		if stance_now:
			if not _was_stance[key]:
				# Swing -> stance: lock at the PLANNED landing (exactly on the ground),
				# not the last discretely-sampled swing point, which sits slightly high.
				_planted[key] = _landing[key]
			_foot[key] = _planted[key]
		else:
			if _was_stance[key]:                          # stance -> swing: pick a landing
				_liftoff[key] = _planted[key]
				var predicted: Vector3 = root_ground + _velocity * swing_dur
				# The neutral foot offset rotates with the facing, so a turning body
				# plants its feet under the turned hips.
				var land: Vector3 = predicted + facing * (_rest_offset[key] as Vector3) + _forward * (stride * 0.5)
				var lp := Vector3(land.x, 0.0, land.z)
				lp.y = _ground_h(lp)                      # drop the plant onto the terrain
				_landing[key] = lp
			var t: float = osc.swing_t(key)
			var flat: Vector3 = (_liftoff[key] as Vector3).lerp(_landing[key], smoothstep(0.0, 1.0, t))
			_foot[key] = flat + Vector3(0, step_height * sin(PI * t), 0)
		_was_stance[key] = stance_now

	# Root: horizontal position from travel + a lateral sway toward the support
	# (keeps the CoM over the planted feet); HEIGHT and TILT come from the contacts
	# (RootPoseSolver), so on a slope or a step the body rides and matches the
	# ground. On flat ground this is level at the stance height, as before.
	# Only PLANTED feet define the ground — a lifted swing foot must not tilt the
	# torso. Use their locked ground positions.
	var feet_now: Array = []
	for key in osc.keys():
		if osc.is_stance(key):
			feet_now.append(_planted[key])
	var pose: Transform3D = RootPoseSolver.solve(feet_now, _stance_height, _forward)
	var support: Variant = _support_centroid()
	# Auto balance: sway toward the support only when few feet are down. A biped in
	# single support swings fully; a statically-stable body (3+ feet planted) barely
	# sways — so this needs no per-creature tuning and can't push feet out of reach.
	var eff_gain: float = _balance_base * clampf(float(3 - planted_count()) / 2.0, 0.0, 1.0)
	var xz: Vector3 = root_ground
	if support != null:
		xz = root_ground.lerp(Vector3((support as Vector3).x, 0, (support as Vector3).z), eff_gain)
	root_transform = Transform3D(pose.basis, Vector3(xz.x, pose.origin.y, xz.z))


func _support_centroid() -> Variant:
	var acc := Vector3.ZERO
	var n := 0
	for key in osc.keys():
		if osc.is_stance(key):
			acc += _planted[key]
			n += 1
	return (acc / n) if n > 0 else null


# --- accessors for rendering / tests ---

func limbs() -> Array:
	return osc.keys()

func is_planted(key: String) -> bool:
	return osc.is_stance(key)

func planted_count() -> int:
	var n := 0
	for key in osc.keys():
		if osc.is_stance(key):
			n += 1
	return n

func foot_position(key: String) -> Vector3:
	return _foot[key]

func hip_position(key: String) -> Vector3:
	return root_transform * (_base_local[key] as Vector3)

func leg_points(key: String) -> PackedVector3Array:
	var hip: Vector3 = hip_position(key)
	return ChainIK.solve(hip, _segments[key], _foot[key], hip + _forward)

func reach_strain(key: String) -> float:
	var r: float = _reach[key]
	return (hip_position(key).distance_to(_foot[key]) / r) if r > 0.0 else INF
