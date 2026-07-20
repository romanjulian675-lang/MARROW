class_name RootPoseSolver
extends RefCounted

# Stage 9 / TDD §7.6: derive the root (torso) pose from the support contacts.
# The torso rides at `up_height` above the mean contact; its PITCH comes from the
# front vs rear contact groups and its ROLL from the right vs left groups, so on a
# slope or a step the body tilts to match the ground instead of clipping through
# it. On flat ground it is perfectly level. Bodies here are built facing +Z with
# +X to the right, so those are the fore-aft and lateral axes.

# `feet` = current world foot positions; `forward` = the body's facing (horizontal).
# Front/rear and left/right are measured along the FACING, so it works turned. The
# returned basis is the full torso orientation — yaw (to `forward`) + pitch + roll.
# The caller supplies the horizontal position (from travel) and keeps the height +
# orientation from here.
static func solve(feet: Array, up_height: float, forward: Vector3 = Vector3(0, 0, 1)) -> Transform3D:
	if feet.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0, up_height, 0))

	var fwd := Vector3(forward.x, 0, forward.z)
	fwd = fwd.normalized() if fwd.length() > 1e-4 else Vector3(0, 0, 1)
	var right := Vector3.UP.cross(fwd).normalized()      # facing +Z -> right +X

	var centroid := Vector3.ZERO
	var mean_y := 0.0
	for f in feet:
		centroid += f
		mean_y += (f as Vector3).y
	centroid /= float(feet.size())
	mean_y /= float(feet.size())

	var front_y := 0.0
	var front_n := 0
	var rear_y := 0.0
	var rear_n := 0
	var right_y := 0.0
	var right_n := 0
	var left_y := 0.0
	var left_n := 0
	var fore_span := 0.0
	var lat_span := 0.0
	for f in feet:
		var rel: Vector3 = (f as Vector3) - centroid
		var af: float = rel.dot(fwd)                     # along facing (front/rear)
		var al: float = rel.dot(right)                   # across facing (right/left)
		if af >= 0.0:
			front_y += (f as Vector3).y
			front_n += 1
		else:
			rear_y += (f as Vector3).y
			rear_n += 1
		fore_span = maxf(fore_span, absf(af))
		if al >= 0.0:
			right_y += (f as Vector3).y
			right_n += 1
		else:
			left_y += (f as Vector3).y
			left_n += 1
		lat_span = maxf(lat_span, absf(al))

	var pitch := 0.0
	if front_n > 0 and rear_n > 0 and fore_span > 1e-3:
		# front higher -> nose up
		pitch = atan2((front_y / front_n) - (rear_y / rear_n), fore_span * 2.0)
	var roll := 0.0
	if right_n > 0 and left_n > 0 and lat_span > 1e-3:
		roll = atan2((right_y / right_n) - (left_y / left_n), lat_span * 2.0)

	# yaw to face `forward` (local +Z -> forward), then tilt about the resulting
	# local axes: about +X, +Z tips down so nose-up needs -pitch; about +Z (BACK),
	# +X lifts so right-side-up needs +roll.
	var yaw: float = atan2(fwd.x, fwd.z)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(basis, Vector3(centroid.x, mean_y + up_height, centroid.z))
