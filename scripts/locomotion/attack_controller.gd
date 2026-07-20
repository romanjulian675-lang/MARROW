class_name AttackController
extends RefCounted

# Stage / TDD M9 §9: procedural attacks as TASK-SPACE paths, not joint clips.
#
# The hand follows wind-up -> strike -> follow-through in a frame AIMED at the
# target. Reach = the manipulation chain's reach + weapon; if the target is beyond
# it, the attack asks the root to step closer (§9.1 reach policy). Everything
# scales from morphology, so a longer arm swings a wider arc and reaches farther,
# while a short arm has to close the distance. The hand target it produces is fed
# to ChainIK to bend the actual arm — no recorded pose anywhere.

var chain_reach: float
var weapon_reach: float
var defn: Dictionary


func _init(arm_reach: float, weapon: float = 0.0, definition: Variant = null) -> void:
	chain_reach = arm_reach
	weapon_reach = weapon
	defn = definition if definition is Dictionary else preset("jab")


# A named attack shape: wind-up / follow-through offsets (fractions of reach, in
# the aim frame: x forward, y up, z sideways), impact timing and torso lunge.
static func preset(name: String) -> Dictionary:
	match name:
		"overhead":
			return {"windup": Vector3(-0.10, 0.55, 0.0), "follow": Vector3(0.40, -0.45, 0.0),
				"impact_phase": 0.5, "impact_window": 0.10, "torso_lunge": 0.18}
		_:
			return {"windup": Vector3(-0.15, 0.30, 0.10), "follow": Vector3(0.45, -0.10, -0.05),
				"impact_phase": 0.4, "impact_window": 0.10, "torso_lunge": 0.12}


func total_reach() -> float:
	return chain_reach + weapon_reach


# Reach check (§9.1). If the target is beyond reach, `root_step` is how far the
# body must move toward it to connect; `in_reach` says whether it can hit in place.
func plan(shoulder: Vector3, target: Vector3) -> Dictionary:
	var d := shoulder.distance_to(target)
	var reach := total_reach()
	return {
		"distance": d, "reach": reach, "in_reach": d <= reach + 1e-5,
		"root_step": maxf(0.0, d - reach),
		"aim": (target - shoulder).normalized() if d > 1e-4 else Vector3.FORWARD,
	}


# Sample the attack at `phase` in [0,1]. Returns the world hand target (feed to
# ChainIK), whether the impact (hit) window is open, and a forward lunge vector
# for the torso.
func sample(phase: float, shoulder: Vector3, target: Vector3) -> Dictionary:
	var to := target - shoulder
	var dist := to.length()
	var aim := to.normalized() if dist > 1e-4 else Vector3.FORWARD
	var reach := total_reach()
	var strike_dist := minf(dist, reach)
	var up := Vector3.UP
	var side := aim.cross(up)
	side = side.normalized() if side.length() > 1e-4 else Vector3.RIGHT

	var wf: Vector3 = defn.get("windup", Vector3(-0.15, 0.3, 0.1))
	var ff: Vector3 = defn.get("follow", Vector3(0.45, -0.1, -0.05))
	var ip: float = defn.get("impact_phase", 0.4)

	var windup := shoulder + aim * (reach * wf.x) + up * (reach * wf.y) + side * (reach * wf.z)
	var strike := shoulder + aim * strike_dist
	var follow := shoulder + aim * (reach * ff.x) + up * (reach * ff.y) + side * (reach * ff.z)

	var hand: Vector3
	if phase <= ip:
		hand = windup.lerp(strike, smoothstep(0.0, 1.0, phase / maxf(ip, 1e-3)))
	else:
		hand = strike.lerp(follow, smoothstep(0.0, 1.0, (phase - ip) / maxf(1.0 - ip, 1e-3)))

	var window: float = defn.get("impact_window", 0.1)
	var lunge_amt: float = defn.get("torso_lunge", 0.0) * clampf(1.0 - absf(phase - ip) / 0.25, 0.0, 1.0)
	return {
		"phase": phase, "hand_target": hand, "strike": strike,
		"impact_active": absf(phase - ip) <= window,
		"lunge": aim * (reach * lunge_amt),
	}


# The manipulation chain to attack WITH (the longest-reach hand), or {} if the
# body has none — then the attack is unavailable and the caller falls back (§9.2).
static func pick_chain(measure: BodyMeasure) -> Dictionary:
	var best: Dictionary = {}
	for c in measure.manipulation_chains():
		if best.is_empty() or float(c["reach_max"]) > float(best["reach_max"]):
			best = c
	return best
