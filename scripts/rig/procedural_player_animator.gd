class_name ProceduralPlayerAnimator
extends Node3D

# Velocity-driven procedural animation (Marrow rigging brief, Phases B/D/E/F).
# Reads ACTUAL velocity (not raw input) so it reacts to slopes, knockback, and
# speed bonuses, and moves the rig's sockets. Bones parented to sockets follow.

@export var rig: ModularSkeletonRig
@export var turn_target: Node3D            # usually VisualRoot; rotates toward facing
@export var player_body_progression_enabled := false

# --- Tuning (from the brief's suggested values) -------------------------------
@export var walk_cycle_speed := 9.0
@export var body_bob_amount := 0.12
@export var body_sway_amount := 0.05
@export var torso_lean_amount := 0.14
@export var arm_swing_amount := 0.75
@export var leg_swing_amount := 0.6
@export var turn_smoothing := 12.0
@export var idle_breath_amount := 0.025
@export var speed_smoothing := 12.0
@export var heavy_weight_swing_slowdown := 0.65

@export_group("Crawl")
@export var crawl_mode := false
@export var crawl_body_drop := 0.46
@export var crawl_body_pitch := 1.08
@export var crawl_pull_amount := 1.35
@export var crawl_arm_drop := 0.42
@export var crawl_head_lift := 0.48
@export var crawl_forward_offset := 0.18
@export var crawl_arm_reach := 0.18
@export var crawl_leg_tuck := 0.72
@export var crawl_shoulder_roll := 0.42
@export var lizard_torso_flex_amount := 0.12
@export var lizard_wall_climb_lift := 0.18
@export var lizard_wall_climb_pitch := 0.42
@export var lizard_wall_climb_head_lift := 0.16
@export var lizard_wall_climb_limb_reach := 0.34
@export var head_only_hop_amount := 0.0
@export var head_only_roll_amount := 0.24
@export var head_only_roll_radius := 0.16
@export var head_only_roll_speed_scale := 0.85
@export var head_only_ground_socket_y := -0.85
@export var torso_spring_hop_amount := 0.34
@export var torso_spring_compress_amount := 0.16
@export var torso_spring_forward_offset := 0.18
@export var torso_spring_tilt_amount := 0.24
@export var torso_spring_ground_socket_y := -0.58
@export var torso_spring_head_offset := Vector3(0.0, 0.42, 0.0)
@export var torso_spring_head_pop_amount := 0.28
@export var torso_spring_head_pop_delay := 0.38

# Bend at the limb mid-joint (elbow/knee) so limbs flex instead of staying stiff.
@export var joint_bend_base := 0.12    # radians always bent a little (never a stick)
@export var joint_bend_swing := 0.7    # extra bend through the walk cycle

# Loose-skeleton wobble: each bone jiggles and slides in/out of its socket, so it
# rattles like a skeleton (always on, even standing still).
@export_group("Skeleton wobble")
@export var wobble_enabled := true
@export var wobble_rotation := 0.035   # radians of GENTLE idle jiggle
@export var wobble_slide := 0.012      # meters the bone slides in/out of its socket
@export var wobble_speed := 2.5        # slow, coherent sway (not chaotic)

# Environment reaction: the figure leans to match the floor slope and tips away
# from nearby objects/walls.
@export_group("Environment reaction")
@export var env_reaction_enabled := true
@export var slope_influence := 0.7
@export var object_lean := 0.15
@export var object_range := 1.2
@export var env_smoothing := 8.0

@export_group("Attack overlay")
# A melee swing takes this long.
#
# CEILING, do not raise alone: the finisher and arm-sword steps run 1.15x, so this
# must satisfy duration * 1.15 < Player.attack_cooldown. Normal melee has no
# anti-stacking gate (that is head-launch only), so a swing longer than the cooldown
# lets the next click restart the pose mid-swing — you would see the windup over and
# over and never the hit. Raising this means raising attack_cooldown too.
# At 0.70: 0.70 * 1.15 = 0.805 < 0.85.
@export var attack_overlay_duration := 0.70
@export var attack_overlay_blend_speed := 18.0

# Shape of the swing: wind back, strike, follow through. Impact comes from the
# CONTRAST between a slow wind-back and a fast strike, which is why these are
# fractions of the duration rather than seconds — retiming the swing keeps the feel.
@export var attack_windup_portion := 0.38    # fraction spent winding back
@export var attack_strike_portion := 0.13    # fraction spent striking. Short = snappy.
# Fraction HELD at full extension after the strike. Without this the pose spikes
# through its peak in a couple of frames and the hit is over before it reads — snap
# and readability pull opposite ways, and this is what buys both.
@export var attack_strike_hold := 0.16
@export var attack_anticipation := 0.35      # how far BACK the windup pulls, as -strength

# Overlapping action. Every joint driven by the same value on the same frame is
# what reads as ROBOTIC — a real limb drags: the torso leads, the shoulder follows
# it, the hand trails last. These are phase offsets: a joint samples the swing
# curve EARLIER, so it lags.
@export var attack_overlap_arm := 0.07       # phase the shoulder trails the torso
@export var attack_overlap_elbow := 0.13     # extra phase the elbow trails the shoulder
# Radians the elbow cocks on the windup and whips straight through the strike.
# Without it the arm is one rigid stick: _animate_joints only ever gives the elbow
# the WALK bend, so it ignores the swing entirely.
@export var attack_elbow_whip := 0.9
@export var attack_arm_forward := 1.1       # radians the right arm swings forward
@export var attack_torso_twist := 0.35      # radians the torso twists into the swing
@export var attack_lunge := 0.22            # radians the body leans into the swing
@export var head_only_attack_duration := 0.34
@export var head_only_attack_charge_portion := 0.28
@export var head_only_attack_lunge := 0.85
@export var head_only_attack_arc := 0.92
@export var head_only_attack_charge_squash := 0.22
@export var head_only_attack_roll := 1.4
# Fraction of the jump over which the charge compression unwinds. Lower is a
# snappier spring; 0 would restore the old one-frame snap.
@export var head_only_attack_release_portion := 0.25
# How much of the rolling spin survives while the head is airborne mid-attack.
# 1.0 restores the old behaviour (attack roll buried under locomotion spin).
@export var head_only_attack_roll_damping := 0.2
@export var head_only_hit_recoil_duration := 0.58
@export var head_only_hit_recoil_hold := 0.14
@export var head_only_hit_recoil_arc := 0.64
@export var head_only_hit_recoil_lift := 0.46
@export var head_only_hit_recoil_horizontal_push := 0.18
@export var head_only_hit_recoil_roll := 0.95
@export var head_only_hit_recoil_settle := 0.16
@export var torso_head_attack_duration := 0.56
@export var torso_head_attack_charge_portion := 0.34
@export var torso_head_attack_lunge := 1.05
@export var torso_head_attack_arc := 0.42
@export var torso_head_attack_coil := 0.24
@export var torso_head_attack_recoil_duration := 0.66
@export var torso_head_attack_recoil_arc := 1.25
@export var torso_head_attack_recoil_pullback := 0.18
@export var torso_head_attack_roll := 1.15
@export var detached_head_landing_duration := 0.18
@export var detached_head_landing_bounce := 0.03
@export var detached_head_landing_roll := 0.25
@export var detached_head_mode_blend_duration := 0.08
@export var detached_head_reattach_tornado_duration := 0.78
@export var detached_head_reattach_tornado_radius := 0.82
@export var detached_head_reattach_tornado_turns := 2.1
@export var detached_head_reattach_tornado_lift := 0.36
@export var detached_head_reattach_finish_blend_duration := 0.18
# Combo step 4: the right arm tears the LEFT arm off and swings it like a sword.
# Purely a pose — the left_arm slot stays equipped throughout, so stats, the paper
# doll and the bow (which needs both arms) are untouched. The arm rides the
# attack's strength curve, so it tears free and snaps back on its own.
const COMBO_STEP_ARM_SWORD := 4
@export var arm_sword_swing := 1.5          # radians the swinging arm carves through
@export var arm_sword_torso_twist := 0.45
@export var arm_sword_lunge := 0.30
# Radians the torn-off arm is levelled to, from hanging (0) to blade-forward.
@export var arm_sword_blade_pitch := -1.57
# Swings the arm stays off for before it goes back on.
@export var arm_sword_swing_count := 3
@export var arm_sword_hold_speed := 14.0    # how fast it tears free / snaps home
# Let go if no further swing lands within this long, so stopping mid-combo does
# not leave the arm off forever.
@export var arm_sword_hold_timeout := 1.6

# Swings taken since the arm came off. 0 == the arm is on.
var _arm_sword_swings := 0
# 0..1 blend of "in the hand". Its own state, NOT the per-attack strength: strength
# falls to 0 between swings, and the arm must stay off across all three.
var _arm_sword_hold := 0.0
var _arm_sword_idle_timer := 0.0

@export var combo_left_arm_forward := 1.0
@export var combo_finisher_arm_forward := 0.85
@export var combo_finisher_torso_twist := 0.5
@export var combo_finisher_lunge := 0.34

@export_group("Animation demo")
# A/B harness: keys 2 and 3 play the SAME head lunge, authored two different ways.
# Both read the head_only_attack_* tuning above, so retuning moves them together
# and any difference you see is the authoring style, not the numbers.
@export var demo_settle_time := 0.12

@export_group("Waist")
# The chest leans at the waist and the head/arms come with it, giving a
# two-segment spine instead of a rigid plank. Set waist_bend_lean to 0 to switch
# the whole feature off at runtime.
#
# NOT routed through _animate_joints: that writer was built for elbows and knees.
# It ASSIGNS rotation (stomping any other writer), its joint_bend_base 0.12 +
# joint_bend_swing 0.7 would give the chest a permanent 0.12-0.82 rad flex every
# step, and its bend_sign keys off the substring "arm". A waist is not an elbow.
# RUNNING ARCH (author-directed 2026-07-16: "waist a little more vertical than
# the chest so there is an arch, when moving/running"). This is the steady
# chest-relative-to-waist pitch while moving — the waist joint IS that
# differential (the body socket holds the vertical abdomen, the waist_joint holds
# the chest). POSITIVE = chest forward over the upright waist, the sprinter's
# forward arch. Supersedes the old waist_bend_lean back-tilt (now 0). Split-player
# only — enemies have no waist joint.
@export var run_arch_deg := 20.0
@export var waist_bend_lean := 0.0        # legacy steady lean; the arch replaced it
@export var waist_bend_step := 0.025      # slight pump at twice the stride
@export var waist_bend_breath := 0.015    # idle only
@export var waist_bend_limit := 0.55      # ~31 deg — the arch needs headroom past 20
@export var waist_response := 12.0        # smoothing rate

# --- Idle combat stance (author-directed): standing still is a READY pose, not a
# neutral stand — legs spread, CHEST (not the waist) pitched forward and breathing,
# both arms up in a low guard. All of it fades out with speed_ratio, so it belongs
# to the idle only and never fights the gait. Split player only: every value is
# routed through _idle_stance_blend(), which is 0 unless the IK gate is on.
@export_group("Idle combat stance")
@export var idle_stance_enabled := true
@export var idle_stance_width := 0.10       # legs spread while still (per foot, outboard)
# Forward (+Z) offset of the STANDING feet from under the hips. NEGATIVE sets
# them BEHIND the hip points: the torso's forward tilt shifts the visible mass
# forward, so feet under the hip POINTS still read as forward of the BODY —
# biasing them back makes them look planted under it (author-directed). Blends
# to the socket's natural gait offset with speed, so moving is unchanged.
@export var idle_foot_forward := -0.10
@export var idle_chest_lean_deg := 14.0     # CHEST pitches forward — not a waist fold
@export var idle_chest_breath_deg := 2.2    # chest lean oscillates: breathing
@export var idle_breath_speed := 1.8
@export var idle_guard_arm_raise_deg := 42.0  # shoulders forward — guard DOWN, not high
@export var idle_guard_arm_tuck_deg := 13.0   # elbows drawn in toward the ribs
@export var idle_guard_elbow_deg := 68.0      # forearms up into the guard
@export var idle_guard_blend_speed := 9.0

@export_group("Whole body")
# Rotates the entire visible rig — every socket rides along — as a posture
# offset on top of facing. Live-tunable from the F3 tuning menu. Large angles
# also tilt the IK's solve frame: the feet still reach their world plants, but
# extreme values will read strangely. Defaults ZERO, so enemies are untouched.
@export var whole_body_rotation_deg := Vector3.ZERO

@export_group("Aim overlay")
@export var aim_overlay_blend_speed := 14.0
@export var aim_right_arm_forward := 0.82
@export var aim_left_arm_forward := 1.18
@export var aim_right_arm_draw := 0.38
@export var aim_left_arm_brace := 0.26
@export var aim_torso_lean := 0.12
@export var aim_head_dip := 0.08

# Feet are planted in WORLD space and the legs are solved to reach them, inverting
# the FK walk cycle (which rotates the hip and drags the foot along). Only the
# split player rig has the knee socket this needs — see _ik_active().
@export_group("Foot IK")
@export var ik_feet_enabled := true
# CARTOON MAGNET FEET (author-directed): instead of nailing the foot to a fixed
# world plant and dragging it when the body overruns (which skated), the foot is
# a SPRING pulled toward its target like a magnet. It reaches the target when the
# target is still and in range, but lags and overshoots in motion — a loose,
# bouncy, cartoonish foot. When the target is out of reach (the body has bounced
# up), the foot just stretches toward it to the leg's limit instead of dragging:
# the reach problem becomes the cartoon look. Set false for the rigid-plant gait.
@export var ik_foot_magnet := true
@export var ik_magnet_stiffness := 500.0   # spring pull; higher = snappier to target
@export var ik_magnet_damping := 20.0      # MOVING damping; lower = bouncier/looser (cartoon)
@export var ik_magnet_damping_idle := 46.0 # NEAR-REST / mid-TRANSITION damping. The moving spring
										   # is underdamped (bouncy), so a brake/turn/reversal
										   # overshoots the target that just jumped — the "feet
										   # adjust too much". Blending to ~critical damping when
										   # slow OR mid-transition kills it while the walk keeps
										   # its bounce.
@export var ik_magnet_transition_thresh := 0.10 # move-velocity change/frame for full transition damp
@export var ik_magnet_transition_decay := 7.0   # how long the damp holds after a change (lower=longer)
@export var ik_foot_max_speed := 6.0            # m/s ceiling on how fast a foot may travel. A
												# turn/reversal whips the target across; capping the
												# spring's speed keeps the foot from snapping — it
                                                # slides to the new spot at a walk-step pace instead.
                                                # A normal swing sits under this, so it is untouched.
# THE LEG RESTS AT 99.9% EXTENSION (hip->ankle 0.586 against a 0.587 reach), so a
# standing pose has ~0.5 mm of slack and a foot more than ~6 cm from under its hip
# is out of reach. Lowering the pelvis is what buys the knees room to bend; every
# other tunable here is downstream of it. 0 disables stepping in all but name.
@export var ik_hip_drop := 0.05           # STANDING crouch — near-straight legs, a normal stand
# MOVING crouch. THE load-bearing number for a gait with a real stance, and pure
# geometry: a planted foot 0.36 m from its hip on a 0.59 m leg forces the hip
# below 0.455 m (sqrt(0.36² + h²) ≤ 0.58), yet a straight-legged rig stands at
# 0.53 and the leap lift pushes it higher still — so every planted frame the foot
# was out of reach and got dragged (measured 35%+ skate the moment a real stance
# existed; the old zero-stance gait hid it by never planting). Real legs solve
# this by being BENT: crouch, then extend the planted leg to push off. The value
# is a HIP-HEIGHT vs SKATE trade — with the stride fixed by the 3-steps/m cap the
# hips only rise ~2-3 cm before the planted legs straighten to their reach limit
# and drag: 0.20 → hipY 0.428 / 0.3% skate, 0.17 → 0.447 (+2 cm) / 3.7%, 0.15 →
# 0.458 (+3 cm) / 5.7% (author asked for higher hips, so 0.17 with more airtime).
# Blended in by speed (see _ik_hip_drop_now) so standing stays tall.
@export var ik_hip_drop_moving := 0.05
@export var ik_step_trigger := 0.18       # world distance from the anchor before a step fires
@export var ik_idle_step_trigger := 0.14  # settle deadzone at a standstill — with the settle
										  # SLIDE below this can stay loose (no fussy steps)
@export var ik_idle_settle_enabled := true
@export var ik_idle_settle_speed := 0.22  # below this speed_ratio, planted feet slide (not step)
@export var ik_idle_settle_rate := 5.0    # how fast the slide settles; lower = gentler brake
@export var ik_step_duration := 0.48      # ceiling; the live duration adapts to speed.
										  # Raised with the 1.4 walk so slow steps stay <=3/m
# The longest stride one step may cover. THE LOAD-BEARING COUPLING: each step
# must not let the capsule advance further than this, or the plants fall behind
# faster than the legs can recover and the gait collapses into a trailing glide —
# so the live step duration is ik_step_reach / speed. Faster body, quicker steps;
# LONGER REACH, SLOWER FEET. The standing envelope is only ~0.24 m; anything
# above that is bought by ik_stride_dip lowering the pelvis when the legs
# scissor apart. 0.32 measured cleanest (0.5% skate at 2.5 m/s); 0.34 costs ~3%
# visible plant slide — the sweep table is in docs/rig_notes.md.
@export var ik_step_reach := 0.34
@export var ik_step_duration_min := 0.06  # cadence floor: past ~4 m/s the feet scurry
# Fraction of a swing still remaining when the NEXT swing may launch. Strict
# one-at-a-time forced every swing to fit inside stride/speed — 8 frames at a
# walk, 4 at a sprint, which read as the feet teleporting. Overlap stretches
# every swing's airtime by 1/(1-overlap) at the same ground coverage; the launch
# order is still strictly alternating. THE SMOOTH-vs-GROUNDED KNOB (measured at
# 2.5 m/s): 0.15 -> punchier surge; 0.25 -> balanced; 0.35 -> smoothest, with
# real double-flight windows — which the leap gait's pelvis arc and chest cycle
# deliberately sell as a jump, so 0.35 is the default. 0 = one-foot-at-a-time.
# Each foot's planted fraction is (1 - 2*overlap) of its swing, so 0.5 is a
# ZERO-STANCE degenerate: measured 0% planted frames, BOTH feet airborne 100% of
# the time — the figure never plants, it just cycles its legs in the air, and no
# leg can stay behind the hip while the body passes over it (author-reported).
# It is the theoretical floor for foot speed, but a gait with no stance is not a
# walk. 0.4 leaves each foot planted ~25% of its cycle: a real stance the body
# rides over, with more swing airtime than 0.3 (author asked for more airtime for
# smoothness) at a small cost to the planted fraction. 0 = strict alternation.
@export var ik_step_overlap := 0.4

# Mid-swing forward REACH (author-directed: "exaggerate the extension of the
# legs when moving forward, really noticeable"). The swing foot bulges FORWARD
# past its landing spot at mid-flight — the leg extends dramatically out front —
# then draws back down to the same plant. It touches only the AIRBORNE arc, not
# the plant, so it costs zero skate and cannot collapse the stride (cranking the
# plant lead did both). Metres of overshoot at the peak; 0 = off. Big values
# push the swing leg past its own reach, which just straightens it fully forward
# — the maximal reach pose, and exactly the exaggeration asked for.
@export var ik_stride_reach_boost := 0.34

# Lateral STANCE WIDTH: pushes each foot's target OUTWARD from under its hip, so
# the feet plant well apart instead of stacked under the pelvis (author: "both
# legs separated / good distance between them, targets not under the hips").
# Metres added to each foot's outboard offset — hips sit ±0.12, so 0.12 here
# plants the feet ~0.48 apart. Widening also costs leg reach (the foot is
# farther from its hip), which the stride dip pays for.
@export var ik_stance_width := 0.08

# --- Leap gait (author-directed): each stride is a little jump, feet strictly
# one after the other. The NEWEST swing drives a whole-body cycle: at push-off
# the pelvis arcs up and the chest pitches UP ~25 deg; as the foot comes down
# the chest and waist COMPRESS — the pitch eases through to slightly looking
# down at touchdown. The capsule is untouched; this is the visible body.
@export_group("Leap gait")
@export var ik_leap_height := 0.10          # pelvis lift at the top of each stride
@export var ik_leap_pitch_up_deg := 20.0    # push-off chest bounce; gentled from 32 so the
											# steady run_arch_deg forward lean reads through it
@export var ik_leap_pitch_down_deg := 0.0   # settle to LEVEL at touchdown — the cycle
											# never dips forward; the torso stays back
# How quickly the chest follows the cycle. At walking cadence (~4 steps/s) the
# smoothing deliberately softens the full up/down sweep into a held-up posture
# with a nod into each landing — the complete 25->-7 sweep would bobblehead at
# that frequency. The full range plays out at slower strides. Raise for snappier.
@export var ik_leap_pitch_response := 14.0
# Extra pelvis drop the stride may pull IN ADDITION to ik_hip_drop, engaged only
# when a leg would otherwise be out of reach and released between strides. This
# is the weight-transfer bob that makes long strides physically possible on
# these leg proportions; without it any reach above ~0.24 just clamps.
@export var ik_stride_dip := 0.06
@export var ik_step_height := 0.20        # knee lifts forward+up at the top of the swing
# Where a step lands, in units of ONE STEP'S capsule travel, measured ahead of
# the under-hip anchor at launch time. 1.5 makes the plants STRADDLE the moving
# capsule (land ~half a stride ahead, leave ~half a stride behind) instead of
# permanently trailing it — that centring is what lets the body ride the feet
# raw, without a bias filter eating the motion.
@export var ik_stride_lead := 1.7
@export var ik_run_lean := 0.07           # hips lean forward into the movement (rig faces +Z)
# The body rides the MEAN OF THE FEET horizontally, not just vertically. The
# capsule still owns gameplay motion (constant glide); this offset makes the
# VISIBLE body stall while both feet are planted and surge when a step lands —
# without it the torso slides at constant speed and the gait reads hip-led no
# matter what the legs do.
@export var ik_body_follow := 1.0         # 0 = old constant glide, 1 = full feet-driven
# How hard the SWINGING foot drags the body: 0 = even mean of both feet, 1 = the
# body rides the stepping foot alone. An even mean moves at EXACTLY capsule speed
# whenever the stepping is continuous (measured: body speed dead-constant 2.50 at
# a 2.5 m/s walk), which is indistinguishable from hip-led glide. Weighting the
# swing foot makes the body load back as the knee lifts and get pulled forward by
# the extending leg — a per-step surge even with no pause between steps.
@export var ik_step_drive := 0.85
@export var ik_body_follow_max := 0.45    # rig-local clamp so the art never tears off the capsule
@export var ik_body_follow_response := 22.0
# Slow safety baseline only. With the plants centred on the capsule by
# ik_stride_lead the raw feet offset has (near) zero steady component, so the
# body can ride the feet RAW — the full stall-and-surge, not a filtered pulse.
# This very slow tracker just bleeds off whatever small bias survives (slopes,
# turns, the cadence floor at a sprint) so it never accumulates into the clamp.
@export var ik_body_follow_recenter := 0.8
@export var ik_probe_radius := 0.05       # spherecast radius
@export var ik_probe_up := 0.7
@export var ik_probe_down := 1.2
@export var ik_max_drop := 0.16           # how far uneven ground may sink the pelvis
@export var ik_pelvis_response := 10.0
@export var ik_foot_response := 14.0
@export var ik_align_to_normal := true

var walk_time := 0.0
var _time := 0.0
var speed_ratio := 0.0
var total_equipped_weight := 1.0

var _attack_timer := 0.0
var _attack_blend := 0.0
var _attack_duration_current := 0.16
var _attack_combo_step := 1
var _head_only_attack_contacted := true
var _head_only_attack_landed := true
var _head_only_base_world_offset := Vector3.ZERO
var _head_only_attack_world_offset := Vector3.ZERO
var _head_only_attack_direction := Vector3.FORWARD
var _head_only_last_facing_direction := Vector3.FORWARD
var _head_only_hit_recoil_timer := 0.0
var _head_only_hit_recoil_start_offset := Vector3.ZERO
var _head_only_hit_recoil_end_offset := Vector3.ZERO
var _head_only_hit_recoil_start_local_position := Vector3.ZERO
var _head_only_hit_recoil_end_local_position := Vector3.ZERO
var _torso_head_attack_contacted := true
var _torso_head_attack_landed := true
var _torso_head_attack_world_offset := Vector3.ZERO
var _torso_head_attack_direction := Vector3.FORWARD
var _torso_head_recoil_timer := 0.0
var _torso_head_recoil_start_local_position := Vector3.ZERO
var _torso_head_recoil_end_local_position := Vector3.ZERO
var _torso_head_socket_local_position := Vector3.ZERO
var _torso_head_socket_offset := Vector3(0.0, 0.42, 0.0)
var _torso_head_miss_detach_requested := false
var _torso_head_detach_world_offset := Vector3.ZERO
var _torso_head_miss_fall_active := false
var _torso_head_miss_fall_timer := 0.0
var _torso_head_miss_fall_start_position := Vector3.ZERO
var _torso_head_miss_fall_start_rotation := Vector3.ZERO
var _torso_head_miss_fall_start_scale := Vector3.ONE
var _torso_head_miss_body_hold_global_transform := Transform3D.IDENTITY
var _torso_head_detach_body_global_transform := Transform3D.IDENTITY
var _torso_head_miss_body_hold_transform_ready := false
var _detached_head_landing_timer := 0.0
var _detached_head_landing_start_position := Vector3.ZERO
var _detached_head_landing_start_rotation := Vector3.ZERO
var _detached_head_landing_start_scale := Vector3.ONE
var _reattach_tornado_active := false
var _reattach_tornado_timer := 0.0
var _reattach_tornado_progress := 0.0
var _reattach_tornado_start_position := Vector3.ZERO
var _reattach_tornado_start_rotation := Vector3.ZERO
var _reattach_tornado_body_position := Vector3.ZERO
var _reattach_tornado_body_rotation := Vector3.ZERO
var _reattach_tornado_target_position := Vector3.ZERO
var _reattach_finish_blend_timer := 0.0
var _reattach_finish_blend_duration := 0.0
var _reattach_finish_head_start_position := Vector3.ZERO
var _reattach_finish_head_start_rotation := Vector3.ZERO
var _aim_requested := false
var _aim_blend := 0.0
var _lizard_wall_climb_blend := 0.0
var _head_only_roll_angle := 0.0

var _rest_pos: Dictionary = {}
var _rest_rot: Dictionary = {}
var _captured := false
var _body: Node3D = null

enum DemoMode {OFF, PROCEDURAL, TWEEN}

var _demo_mode: DemoMode = DemoMode.OFF
var _demo_timer := 0.0
var _demo_tween: Tween = null
var _demo_forward := Vector3.FORWARD
var _demo_start_position := Vector3.ZERO
var _demo_start_rotation := Vector3.ZERO
# The demo writes these; _apply_demo_pose() is the single place they reach the
# socket. The Tween cannot touch head.position directly because _animate_body()
# rebuilds it from rest every frame and would overwrite the tween mid-flight.
var _demo_head_position := Vector3.ZERO
var _demo_head_rotation := Vector3.ZERO
var _demo_head_scale := Vector3.ONE
var _demo_target_world_position := Vector3.ZERO
var _demo_target_valid := false

# Auto-aim for head-launch attacks. The Player owns enemy lookup and pushes a
# world-space direction here every frame; the animator just steers the launch.
var _head_launch_aim_direction := Vector3.ZERO
var _head_launch_aim_valid := false

# Pending body displacement from a landed head-only lunge. The Player consumes
# this and moves the capsule, so the head and the body stay together.
var _head_only_body_catch_up_offset := Vector3.ZERO
var _head_only_body_catch_up_requested := false

const ANIMATED_KEYS := ["body", "head", "right_arm", "left_arm", "right_leg", "left_leg"]
const FOOT_KEYS := ["left_foot", "right_foot"]

# foot socket -> the hip socket its chain hangs from. The knee between them is
# "<leg>_lower", which only exists on a split rig.
const IK_LEG_OF_FOOT := {"left_foot": "left_leg", "right_foot": "right_leg"}
# Sockets a real pelvis would parent. Every socket is a child of the RIG (legs and
# body are SIBLINGS), so a pelvis drop has to be applied to each of them by hand —
# the same trick, and the same reason, as _apply_waist_carry below.
const IK_PELVIS_CARRIED := ["body", "head", "right_arm", "left_arm", "right_leg", "left_leg"]

var _ik_plant: Dictionary = {}        # foot key -> world Vector3, the anchor
var _ik_plant_normal: Dictionary = {} # foot key -> world Vector3
var _ik_step_from: Dictionary = {}
var _ik_step_to: Dictionary = {}
var _ik_step_to_normal: Dictionary = {}
var _ik_step_t: Dictionary = {}
var _ik_stepping := ""                # "" or the ONE foot currently in the air
var _ik_next_foot := "right_foot"     # whose turn it is, so the legs alternate
var _ik_foot_pos: Dictionary = {}     # MAGNET: the foot's actual world pos (spring state)
var _ik_foot_vel: Dictionary = {}     # MAGNET: world velocity, for the springy overshoot
var _ik_velocity_prev := Vector3.ZERO # last frame's move velocity, for the transition detector
var _ik_transition := 0.0             # 0..1: how mid-brake/turn/reversal we are (decays)
var _ik_ready := false
var _ik_grounded_prev := false
var _idle_blend := 0.0       # 0..1 smoothed: how much of the ready stance is showing
var _ik_leap_pitch := 0.0    # smoothed chest pitch of the leap cycle (radians)
var _ik_leap_lift := 0.0     # pelvis lift of the current stride's flight
var _ik_pelvis_dy := 0.0
var _ik_pelvis_lean := 0.0   # forward (+Z rig-local) hip offset while moving
var _ik_pelvis_follow := Vector3.ZERO  # rig-local XZ: the applied, recentred pulse
var _ik_follow_fast := Vector3.ZERO    # raw feet offset, fast smoothing
var _ik_follow_slow := Vector3.ZERO    # same signal, slow — the baseline that cancels the DC
var _ik_velocity := Vector3.ZERO
var _ik_probe_shape: SphereShape3D = null


# Called by the player AFTER move_and_slide(), so velocity is the resolved motion.
func update_from_player(delta: float, velocity: Vector3, max_speed: float, facing_direction: Vector3, equipped_defs: Array) -> void:
	if rig == null:
		return
	if not _captured:
		_capture_rest()

	# Whole-body posture offset (F3 tuning menu). Guarded compare so the common
	# zero case (every enemy) never dirties the rig's transform.
	if rig.rotation_degrees != whole_body_rotation_deg:
		rig.rotation_degrees = whole_body_rotation_deg

	_time += delta
	_update_head_only_facing_direction(facing_direction)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_ik_velocity = horizontal
	var target_ratio: float = clamp(horizontal.length() / max(max_speed, 0.001), 0.0, 1.0)
	speed_ratio = lerp(speed_ratio, target_ratio, 1.0 - exp(-speed_smoothing * delta))
	if _is_head_only():
		var roll_radius: float = maxf(head_only_roll_radius, 0.01)
		var roll_scale: float = head_only_roll_speed_scale
		# Mid-lunge the head is off the ground, so it should not keep winding up
		# ground roll on top of the attack's own roll. Without this, attacking at
		# full speed spun the head ~671 degrees in a 0.34 s attack instead of ~189.
		if _head_only_attack_airborne():
			roll_scale *= head_only_attack_roll_damping
		_head_only_roll_angle += (horizontal.length() * delta / roll_radius) * roll_scale
	if _detached_head_landing_timer > 0.0:
		_detached_head_landing_timer = maxf(_detached_head_landing_timer - delta, 0.0)
	if _torso_head_miss_fall_timer > 0.0:
		_torso_head_miss_fall_timer = maxf(_torso_head_miss_fall_timer - delta, 0.0)
	if _reattach_finish_blend_timer > 0.0:
		_reattach_finish_blend_timer = maxf(_reattach_finish_blend_timer - delta, 0.0)

	total_equipped_weight = _calculate_weight(equipped_defs)
	_update_torso_head_socket_offset(equipped_defs)
	var weight_slowdown: float = clamp(1.0 / max(total_equipped_weight, 1.0), heavy_weight_swing_slowdown, 1.0)

	walk_time += delta * walk_cycle_speed * speed_ratio * weight_slowdown
	_animate_facing(delta, facing_direction)

	if crawl_mode:
		_animate_crawl_body()
		_animate_crawl_limbs()
	else:
		_animate_body()
		_animate_limbs()
		_animate_joints()
		# After the limbs' rest pose, before the attack/aim overlays — they must
		# stay free to take the arms out of the guard.
		_update_idle_stance(delta)
		_apply_idle_stance()
	_animate_wobble()
	_apply_lizard_wall_climb_limb_pose()
	_update_aim_overlay(delta)
	_apply_aim_overlay()
	_update_attack_overlay(delta)
	_update_head_launch_attack_aim()
	_head_only_attack_world_offset = Vector3.ZERO
	_torso_head_attack_world_offset = Vector3.ZERO
	_apply_attack_overlay()
	# After every FK writer, because the solve ASSIGNS the hip and knee rotations
	# the walk cycle just wrote — that overwrite IS the FK->IK inversion, so the
	# leg half of _animate_limbs/_animate_joints needs no gate of its own. It has
	# to see the final hip position, though: _animate_wobble slides the hip by up
	# to wobble_slide, and the solver compensates for that instead of fighting it.
	_update_foot_ik(delta)
	# Runs last so the demo wins the head socket for its duration. The tween
	# variant has already advanced its own values by the time we get here.
	if _demo_mode == DemoMode.PROCEDURAL:
		_update_demo_procedural(delta)
	if _demo_mode != DemoMode.OFF:
		_apply_demo_pose()
	# After the attack overlay, so the hand it reads has already swung. Before the
	# waist, so the carry rotates the blade and the arm holding it as one rigid
	# piece and the blade stays in the hand.
	_update_arm_sword(delta)
	# LAST, after every other socket writer, for the same reason the demo is last:
	# _apply_waist_carry stands in for a parent transform, so it has to see the
	# final pose. A writer added below this line would silently escape the carry
	# and its socket would stop following the chest.
	_animate_waist(delta)


# --- Waist ---------------------------------------------------------------------
# The chest bends at the waist and the head/arms follow.
#
# WHY THE HEAD/ARMS ARE NOT REPARENTED UNDER THE CHEST, which is the obvious way
# to make them follow: _capture_rest() stores every socket's PARENT-LOCAL rest
# pose, so reparenting silently redefines what _rest_pos["head"] means, and every
# site that mixes rig space with socket space breaks at once — torso-spring
# (head.position = body.position + offset), the head-only ground constants
# (rig-space -0.85 fused with chest-space rest.x/z), the 12
# _world_horizontal_offset_to_local call sites (rig-basis directions applied in a
# tilted frame), rig.to_local across the player.gd boundary, the doubled crawl
# drops, and — the one nothing warns about — body.scale's squash-and-stretch,
# which would suddenly squash the head and both arms.
#
# So instead of inheriting the chest transform, this ADDS the one transform a real
# hierarchy would have contributed, by hand, after everyone else has written. No
# socket changes parent, so no space changes, and all of the above is structurally
# absent rather than fixed. The cost is order-coupling: this must run last.

# Sockets a real chest parent would carry. The abdomen and legs stay on the pelvis.
const WAIST_CARRIED := ["head", "right_arm", "left_arm"]

var _waist_angle := 0.0


# Zero in every mode that owns the head socket or already pitches the torso — a
# waist bend would fight them. Returning exactly 0.0 lets _apply_waist_carry early
# out, so those modes stay bit-identical to a build without a waist at all.
func _waist_target_angle() -> float:
	if _is_head_only():
		return 0.0            # no torso equipped; nothing to bend
	if _is_torso_spring_only():
		return 0.0            # the hop/squash IS the read here, and body.scale is non-uniform
	if crawl_mode:
		return 0.0            # the body already pitches by crawl_body_pitch
	if _reattach_tornado_active or _reattach_finish_blend_timer > 0.0:
		return 0.0
	if _detached_head_landing_timer > 0.0 or _torso_head_miss_fall_active:
		return 0.0
	if _demo_mode != DemoMode.OFF:
		return 0.0            # the demo owns the head socket

	# The arch: chest pitched FORWARD of the vertical waist, growing with speed.
	var arch: float = deg_to_rad(run_arch_deg) * speed_ratio
	var lean: float = waist_bend_lean * speed_ratio
	var step: float = sin(walk_time * 2.0) * waist_bend_step * speed_ratio
	var breath: float = sin(_time * 1.8) * waist_bend_breath * (1.0 - speed_ratio)
	return clampf(arch + lean + step + breath, -waist_bend_limit, waist_bend_limit)


func _animate_waist(delta: float) -> void:
	if rig == null or not rig.has_method("get_waist_joint"):
		return
	var waist: Node3D = rig.call("get_waist_joint") as Node3D
	if waist == null:
		return  # unsplit rig (every enemy) — no waist exists

	_waist_angle = lerp(_waist_angle, _waist_target_angle(), 1.0 - exp(-waist_response * delta))
	# The leap's chest cycle rides the same joint: pitched UP at push-off,
	# compressing to slightly DOWN as the foot lands. It is exactly zero whenever
	# the IK is inactive, so every special mode stays bit-identical.
	var total_bend: float = _waist_angle + _ik_leap_pitch
	# Plain assign is right here: this node is new and has exactly one writer.
	waist.rotation.x = total_bend
	_apply_waist_carry(total_bend)


# Applies the chest's rotation to the sockets a real hierarchy would carry.
func _apply_waist_carry(angle: float) -> void:
	if is_zero_approx(angle):
		return  # the bit-identical guarantee: zeroed modes never touch a socket

	# Pivot is the waist PLANE at rest, NOT body.position: the head and arms
	# deliberately do not inherit the body's bob/sway today, and this must add the
	# bend and nothing else. The pelvis carry moved that plane, though, so the rest
	# pivot has to follow it down or the bend swings the head about a point the
	# waist no longer occupies.
	var pivot: Vector3 = _get_rest_pos("body") + _ik_pelvis_offset()
	var bend := Basis(Vector3.RIGHT, angle)
	for key in WAIST_CARRIED:
		var socket: Node3D = rig.get_socket(key)
		if socket == null:
			continue
		socket.position = pivot + bend * (socket.position - pivot)
		socket.basis = bend * socket.basis


# --- Animation demo: same lunge, two authoring styles -------------------------
# Key 2 -> trigger_demo_attack_procedural(): per-frame math, easing by hand.
# Key 3 -> trigger_demo_attack_tween(): declarative steps, easing by name.
# Shared beats: charge (squash back) -> rise to apex -> fall to landing ->
# settle back to the start pose so the demo can be replayed from one spot.

func trigger_demo_attack_procedural() -> void:
	var head: Node3D = _demo_begin()
	if head == null:
		return
	_demo_mode = DemoMode.PROCEDURAL


func trigger_demo_attack_tween() -> void:
	var head: Node3D = _demo_begin()
	if head == null:
		return
	_demo_mode = DemoMode.TWEEN

	var k: Dictionary = _demo_keyframes()
	var charge_time: float = _demo_charge_time()
	var air_time: float = _demo_air_time()
	var rise: float = air_time * 0.5
	var fall: float = air_time * 0.5
	var settle: float = maxf(demo_settle_time, 0.01)

	_demo_tween = create_tween()
	# Physics mode keeps the tween stepping in lockstep with update_from_player,
	# which is driven from the player's _physics_process.
	_demo_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	# 1. Charge: squash down and pull back.
	_demo_tween.tween_property(self, "_demo_head_position", k["charge_pos"], charge_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_demo_tween.parallel().tween_property(self, "_demo_head_rotation", k["charge_rot"], charge_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_demo_tween.parallel().tween_property(self, "_demo_head_scale", k["charge_scale"], charge_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# 2. Rise: launch toward the apex, decelerating into it.
	_demo_tween.tween_property(self, "_demo_head_position", k["apex_pos"], rise).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_demo_tween.parallel().tween_property(self, "_demo_head_rotation", k["apex_rot"], rise).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_demo_tween.parallel().tween_property(self, "_demo_head_scale", k["apex_scale"], rise).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3. Fall: accelerate into the landing.
	_demo_tween.tween_property(self, "_demo_head_position", k["land_pos"], fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_demo_tween.parallel().tween_property(self, "_demo_head_rotation", k["land_rot"], fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_demo_tween.parallel().tween_property(self, "_demo_head_scale", Vector3.ONE, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 4. Settle back to the start pose.
	_demo_tween.tween_property(self, "_demo_head_position", _demo_start_position, settle).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_demo_tween.parallel().tween_property(self, "_demo_head_rotation", _demo_start_rotation, settle).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_demo_tween.tween_callback(_demo_on_tween_finished)


# The procedural twin of the tween chain above. Same four beats, but the phase
# bookkeeping and the easing curves are spelled out by hand.
func _update_demo_procedural(delta: float) -> void:
	_demo_timer += delta
	# The one thing the tween cannot do: re-aim at a target that moved after the
	# animation started. Every keyframe below is derived from _demo_forward, so
	# refreshing it here swings the whole trajectory to follow.
	_demo_forward = _demo_local_forward()
	var k: Dictionary = _demo_keyframes()
	var charge_time: float = _demo_charge_time()
	var air_time: float = _demo_air_time()
	var rise: float = air_time * 0.5
	var fall: float = air_time * 0.5
	var settle: float = maxf(demo_settle_time, 0.01)
	var t: float = _demo_timer

	if t < charge_time:
		var p: float = _ease_out_sine(t / charge_time)
		_demo_head_position = _demo_start_position.lerp(k["charge_pos"], p)
		_demo_head_rotation = _demo_start_rotation.lerp(k["charge_rot"], p)
		_demo_head_scale = Vector3.ONE.lerp(k["charge_scale"], p)
		return
	t -= charge_time

	if t < rise:
		var p: float = _ease_out_quad(t / rise)
		_demo_head_position = (k["charge_pos"] as Vector3).lerp(k["apex_pos"], p)
		_demo_head_rotation = (k["charge_rot"] as Vector3).lerp(k["apex_rot"], p)
		_demo_head_scale = (k["charge_scale"] as Vector3).lerp(k["apex_scale"], p)
		return
	t -= rise

	if t < fall:
		var p: float = _ease_in_quad(t / fall)
		_demo_head_position = (k["apex_pos"] as Vector3).lerp(k["land_pos"], p)
		_demo_head_rotation = (k["apex_rot"] as Vector3).lerp(k["land_rot"], p)
		_demo_head_scale = (k["apex_scale"] as Vector3).lerp(Vector3.ONE, p)
		return
	t -= fall

	if t < settle:
		var p: float = _ease_in_out_sine(t / settle)
		_demo_head_position = (k["land_pos"] as Vector3).lerp(_demo_start_position, p)
		_demo_head_rotation = (k["land_rot"] as Vector3).lerp(_demo_start_rotation, p)
		_demo_head_scale = Vector3.ONE
		return

	_demo_stop()


# Both styles converge here: the demo owns the head socket while it runs.
func _apply_demo_pose() -> void:
	if rig == null:
		return
	var head: Node3D = rig.get_socket("head")
	if head == null:
		return
	head.position = _demo_head_position
	head.rotation = _demo_head_rotation
	head.scale = _demo_head_scale


# Targets are baked once at trigger time so the two styles stay comparable. The
# procedural version could recompute these live against a moving target; the
# tween cannot, because its steps are authored up front.
func _demo_keyframes() -> Dictionary:
	var lunge: float = head_only_attack_lunge
	var squash: float = head_only_attack_charge_squash
	var roll: float = head_only_attack_roll
	# Peak stretch matches _apply_head_only_attack_pose()'s arc * 0.12 at apex.
	var stretch: float = 0.12
	return {
		"charge_pos": _demo_start_position - _demo_forward * lunge * 0.14 + Vector3(0.0, -squash, 0.0),
		"charge_rot": _demo_start_rotation + Vector3(-roll * 0.22, 0.0, 0.0),
		"charge_scale": Vector3(1.0 + squash * 0.55, 1.0 - squash * 0.75, 1.0 + squash * 0.45),
		"apex_pos": _demo_start_position + _demo_forward * lunge * 0.5 + Vector3(0.0, head_only_attack_arc, 0.0),
		"apex_rot": _demo_start_rotation + Vector3(roll * 0.5, 0.0, 0.0),
		"apex_scale": Vector3(1.0 - stretch * 0.5, 1.0 + stretch, 1.0 - stretch * 0.35),
		"land_pos": _demo_start_position + _demo_forward * lunge,
		"land_rot": _demo_start_rotation + Vector3(roll, 0.0, 0.0),
	}


func _demo_charge_time() -> float:
	return maxf(head_only_attack_duration * clampf(head_only_attack_charge_portion, 0.05, 0.75), 0.01)


func _demo_air_time() -> float:
	return maxf(head_only_attack_duration - _demo_charge_time(), 0.02)


func _demo_begin() -> Node3D:
	if rig == null:
		return null
	var head: Node3D = rig.get_socket("head")
	if head == null:
		return null
	_demo_stop()
	_demo_start_position = head.position
	_demo_start_rotation = head.rotation
	_demo_head_position = _demo_start_position
	_demo_head_rotation = _demo_start_rotation
	_demo_head_scale = Vector3.ONE
	_demo_forward = _demo_local_forward()
	_demo_timer = 0.0
	return head


# Aims at the demo target when the player supplies one, else at current facing.
func _demo_local_forward() -> Vector3:
	if _demo_target_valid and rig != null:
		var to_target: Vector3 = rig.to_local(_demo_target_world_position) - _demo_start_position
		to_target.y = 0.0
		if to_target.length() > 0.001:
			return to_target.normalized()
	var local: Vector3 = _world_horizontal_offset_to_local(_head_only_last_facing_direction)
	if local.length() > 0.001:
		return local.normalized()
	return Vector3.FORWARD


# The player pushes the orbiting demo target here every frame.
func set_demo_target_world_position(world_position: Vector3) -> void:
	_demo_target_world_position = world_position
	_demo_target_valid = true


# Releases the head socket back to the normal animator on the next frame.
# Cancels an in-flight tween, so it must not be used as the tween's own callback.
func _demo_stop() -> void:
	if _demo_tween != null and _demo_tween.is_valid():
		_demo_tween.kill()
	_demo_tween = null
	_demo_mode = DemoMode.OFF
	_demo_timer = 0.0


# Runs from inside the tween's final step, where killing it would be re-entrant.
func _demo_on_tween_finished() -> void:
	_demo_tween = null
	_demo_mode = DemoMode.OFF
	_demo_timer = 0.0


# Hand-written equivalents of Tween's TRANS_*/EASE_* pairs, so both styles trace
# the exact same curve.
func _ease_out_sine(t: float) -> float:
	return sin(clampf(t, 0.0, 1.0) * PI * 0.5)


func _ease_out_quad(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)


func _ease_in_quad(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c


func _ease_in_out_sine(t: float) -> float:
	return -(cos(PI * clampf(t, 0.0, 1.0)) - 1.0) * 0.5


# True while a head-launch attack is still resolving: in flight, in hit recoil,
# falling after a miss, or waiting for the Player to consume a detach request.
# The Player gates new attacks on this, because `attack_cooldown` alone is shorter
# than these animations and a new trigger would restart the pose mid-air.
func is_head_launch_attack_busy() -> bool:
	if _is_head_only():
		return not _head_only_attack_landed or _head_only_hit_recoil_timer > 0.0
	if _is_torso_spring_only():
		return (
			not _torso_head_attack_landed
			or _torso_head_recoil_timer > 0.0
			or _torso_head_miss_fall_active
			or _torso_head_miss_detach_requested
		)
	return false


# Auto-aim for head-launch attacks, pushed by the Player every frame. Passing
# valid = false (no enemy in range) falls back to the player's facing direction,
# which is the original behaviour.
func set_head_launch_attack_aim(direction: Vector3, valid: bool) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if not valid or flat.length() < 0.001:
		_head_launch_aim_valid = false
		_head_launch_aim_direction = Vector3.ZERO
		return
	_head_launch_aim_valid = true
	_head_launch_aim_direction = flat.normalized()


func _head_launch_aim_or(fallback: Vector3) -> Vector3:
	if _head_launch_aim_valid:
		return _head_launch_aim_direction
	return fallback


# Steers an in-flight launch toward the target. This is the whole reason the
# launch is procedural rather than a baked clip: the direction is re-read every
# frame, so an enemy that moves mid-attack is still tracked. Once the attack has
# landed the direction is frozen, so the landing offset stays consistent with the
# offset the pose actually reached.
func _update_head_launch_attack_aim() -> void:
	if not _head_launch_aim_valid:
		return
	if _is_head_only() and not _head_only_attack_landed:
		_head_only_attack_direction = _head_launch_aim_direction
	elif _is_torso_spring_only() and not _torso_head_attack_landed:
		_torso_head_attack_direction = _head_launch_aim_direction


# The player calls this when an attack fires (Phase E).
#
# allow_head_launch = false plays the plain overlay instead of throwing the head
# off the body. Ranged shots and stealth finishers need this: they only want
# attack FEEDBACK, and a head that leaps 0.85 m forward to fire a projectile both
# reads wrong and (via the body catch-up) physically displaces the player. In
# torso-only it is worse, because a launch that misses detaches the head.
func trigger_attack(combo_step: int = 0, allow_head_launch: bool = true) -> void:
	if combo_step <= 0:
		_attack_combo_step = (_attack_combo_step % 3) + 1
	else:
		_attack_combo_step = clampi(combo_step, 1, COMBO_STEP_ARM_SWORD)
	if _is_head_only() and allow_head_launch:
		_attack_duration_current = head_only_attack_duration
		_head_only_attack_contacted = false
		_head_only_attack_landed = false
		_head_only_attack_direction = _head_launch_aim_or(_head_only_last_facing_direction)
		_head_only_hit_recoil_timer = 0.0
		_torso_head_attack_contacted = true
		_torso_head_attack_landed = true
		_torso_head_recoil_timer = 0.0
		_torso_head_miss_detach_requested = false
		_torso_head_miss_fall_active = false
		_torso_head_miss_fall_timer = 0.0
		_torso_head_miss_body_hold_transform_ready = false
	elif _torso_head_launch_available() and allow_head_launch:
		_attack_duration_current = torso_head_attack_duration
		_head_only_attack_contacted = true
		_head_only_attack_landed = true
		_head_only_hit_recoil_timer = 0.0
		_torso_head_attack_contacted = false
		_torso_head_attack_landed = false
		_torso_head_attack_direction = _head_launch_aim_or(_head_only_last_facing_direction)
		_torso_head_recoil_timer = 0.0
		_torso_head_miss_detach_requested = false
		_torso_head_detach_world_offset = Vector3.ZERO
		_torso_head_miss_fall_active = false
		_torso_head_miss_fall_timer = 0.0
		_torso_head_miss_body_hold_transform_ready = false
	else:
		_attack_duration_current = attack_overlay_duration
		_head_only_attack_contacted = true
		_head_only_attack_landed = true
		_head_only_hit_recoil_timer = 0.0
		_torso_head_attack_contacted = true
		_torso_head_attack_landed = true
		_torso_head_recoil_timer = 0.0
		_torso_head_miss_detach_requested = false
		_torso_head_miss_fall_active = false
		_torso_head_miss_fall_timer = 0.0
		_torso_head_miss_body_hold_transform_ready = false
	if _attack_combo_step == COMBO_STEP_ARM_SWORD and _both_arms_equipped():
		note_arm_sword_swing()
	if _attack_combo_step >= 3 and not _is_head_only() and not _is_torso_spring_only():
		_attack_duration_current *= 1.15
	_attack_timer = _attack_duration_current
	_attack_blend = maxf(_attack_blend, 0.25)


func _capture_torso_head_miss_body_hold_transform() -> void:
	_torso_head_miss_body_hold_transform_ready = false
	if rig == null:
		return
	var body: Node3D = rig.get_socket("body")
	if body == null:
		return
	_torso_head_miss_body_hold_global_transform = body.global_transform
	_torso_head_detach_body_global_transform = _torso_head_miss_body_hold_global_transform
	_torso_head_miss_body_hold_transform_ready = true


func set_aiming(enabled: bool) -> void:
	_aim_requested = enabled


func confirm_head_only_attack_contact() -> void:
	if _is_head_only() and _attack_blend > 0.001:
		_head_only_attack_contacted = true
		_head_only_attack_landed = true
		_head_only_hit_recoil_start_offset = _head_only_base_world_offset + _head_only_attack_world_offset
		_head_only_hit_recoil_end_offset = _head_only_base_world_offset
		_head_only_hit_recoil_start_local_position = _capture_head_only_recoil_start_local_position()
		_head_only_hit_recoil_end_local_position = _get_head_only_grounded_local_position()
		_head_only_hit_recoil_timer = head_only_hit_recoil_duration
	elif _is_torso_spring_only() and _attack_blend > 0.001:
		_torso_head_attack_contacted = true
		_torso_head_attack_landed = true
		_torso_head_miss_detach_requested = false
		_torso_head_miss_fall_active = false
		_torso_head_miss_fall_timer = 0.0
		_torso_head_recoil_start_local_position = _capture_socket_local_position("head")
		_torso_head_recoil_end_local_position = _torso_head_socket_local_position
		_torso_head_recoil_timer = torso_head_attack_recoil_duration


func get_head_only_attack_forward_offset() -> float:
	if not _is_head_only():
		return 0.0
	return get_head_only_attack_world_offset().length()


func get_head_only_attack_world_offset() -> Vector3:
	if not _is_head_only():
		return Vector3.ZERO
	return _head_only_base_world_offset + _head_only_attack_world_offset


func get_head_launch_attack_world_offset() -> Vector3:
	if _is_head_only():
		return _head_only_base_world_offset + _head_only_attack_world_offset
	if _is_torso_spring_only():
		return _torso_head_attack_world_offset
	return Vector3.ZERO


# A landed head-only lunge asks the Player to bring the capsule to the head.
# Consumed the same frame it is raised (see Player._update_procedural_animation).
func has_head_only_body_catch_up_request() -> bool:
	return _head_only_body_catch_up_requested


func consume_head_only_body_catch_up_offset() -> Vector3:
	if not _head_only_body_catch_up_requested:
		return Vector3.ZERO
	_head_only_body_catch_up_requested = false
	var offset: Vector3 = _head_only_body_catch_up_offset
	_head_only_body_catch_up_offset = Vector3.ZERO
	return offset


func has_torso_head_miss_detach_request() -> bool:
	return _torso_head_miss_detach_requested


func consume_torso_head_miss_detach_offset() -> Vector3:
	if not _torso_head_miss_detach_requested:
		return Vector3.ZERO
	_torso_head_miss_detach_requested = false
	return _torso_head_detach_world_offset


func get_torso_head_miss_detach_body_transform() -> Transform3D:
	return _torso_head_detach_body_global_transform


func enter_detached_head_state(start_local_position: Vector3 = Vector3.ZERO, use_start_position: bool = false) -> void:
	_attack_timer = 0.0
	_attack_blend = 0.0
	_head_only_attack_contacted = true
	_head_only_attack_landed = true
	_head_only_base_world_offset = Vector3.ZERO
	_head_only_attack_world_offset = Vector3.ZERO
	_head_only_hit_recoil_timer = 0.0
	_torso_head_attack_contacted = true
	_torso_head_attack_landed = true
	_torso_head_attack_world_offset = Vector3.ZERO
	_torso_head_recoil_timer = 0.0
	_torso_head_miss_detach_requested = false
	_torso_head_detach_world_offset = Vector3.ZERO
	_torso_head_miss_fall_active = false
	_torso_head_miss_fall_timer = 0.0
	if use_start_position:
		_detached_head_landing_start_position = start_local_position
		_detached_head_landing_start_rotation = _capture_socket_local_rotation("head")
		_detached_head_landing_start_scale = _capture_socket_local_scale("head")
		var head: Node3D = null
		if rig != null:
			head = rig.get_socket("head")
		if head != null:
			head.position = start_local_position
		_detached_head_landing_timer = maxf(detached_head_mode_blend_duration, 0.01)
	else:
		_detached_head_landing_timer = 0.0


func start_detached_head_reattach_tornado(body_world_position: Vector3, target_world_position: Vector3, body_world_rotation: Vector3 = Vector3.ZERO) -> void:
	if rig == null:
		return
	var head: Node3D = rig.get_socket("head")
	if head == null:
		return
	_reattach_tornado_active = true
	_reattach_tornado_timer = maxf(detached_head_reattach_tornado_duration, 0.01)
	_reattach_tornado_progress = 0.0
	_reattach_tornado_start_position = head.position
	_reattach_tornado_start_rotation = head.rotation
	_reattach_tornado_body_position = rig.to_local(body_world_position)
	_reattach_tornado_body_rotation = _world_rotation_to_rig_local(body_world_rotation)
	_reattach_tornado_target_position = rig.to_local(target_world_position)
	_detached_head_landing_timer = 0.0


func set_detached_head_reattach_tornado_progress(progress: float, body_world_position: Vector3, target_world_position: Vector3, body_world_rotation: Vector3 = Vector3.ZERO) -> void:
	if rig == null:
		return
	if not _reattach_tornado_active:
		start_detached_head_reattach_tornado(body_world_position, target_world_position, body_world_rotation)
	_reattach_tornado_progress = clampf(progress, 0.0, 1.0)
	_reattach_tornado_body_position = rig.to_local(body_world_position)
	_reattach_tornado_body_rotation = _world_rotation_to_rig_local(body_world_rotation)
	_reattach_tornado_target_position = rig.to_local(target_world_position)


func cancel_detached_head_reattach_tornado_to_ground() -> void:
	if rig == null or not _reattach_tornado_active:
		return
	var head: Node3D = rig.get_socket("head")
	if head == null:
		return
	_reattach_tornado_active = false
	_reattach_tornado_timer = 0.0
	_reattach_tornado_progress = 0.0
	_detached_head_landing_start_position = head.position
	_detached_head_landing_start_rotation = head.rotation
	_detached_head_landing_start_scale = head.scale
	_detached_head_landing_timer = maxf(detached_head_landing_duration, 0.01)


func play_detached_head_reattach_finish_blend() -> void:
	if rig == null:
		return
	var head: Node3D = rig.get_socket("head")
	if head == null:
		return
	_reattach_tornado_active = false
	_reattach_tornado_timer = 0.0
	_reattach_tornado_progress = 1.0
	_reattach_finish_blend_duration = maxf(detached_head_reattach_finish_blend_duration, 0.01)
	_reattach_finish_blend_timer = _reattach_finish_blend_duration
	_reattach_finish_head_start_position = head.position
	_reattach_finish_head_start_rotation = head.rotation
	head.scale = Vector3.ONE


func get_detached_head_reattach_tornado_duration() -> float:
	return maxf(detached_head_reattach_tornado_duration, 0.01)


func get_stable_body_attach_local_position() -> Vector3:
	var rest: Vector3 = _get_rest_pos("body")
	if _is_torso_spring_only():
		return Vector3(rest.x, torso_spring_ground_socket_y, rest.z)
	return rest


func _update_head_only_facing_direction(facing_direction: Vector3) -> void:
	var flat: Vector3 = Vector3(facing_direction.x, 0.0, facing_direction.z)
	if flat.length() > 0.01:
		_head_only_last_facing_direction = flat.normalized()


func _world_horizontal_offset_to_local(world_offset: Vector3) -> Vector3:
	if rig == null:
		return Vector3.ZERO
	var flat: Vector3 = Vector3(world_offset.x, 0.0, world_offset.z)
	var local_offset: Vector3 = rig.global_transform.basis.inverse() * flat
	local_offset.y = 0.0
	return local_offset


func _world_rotation_to_rig_local(world_rotation: Vector3) -> Vector3:
	if rig == null:
		return world_rotation
	var world_basis: Basis = Basis.from_euler(world_rotation)
	var local_basis: Basis = rig.global_transform.basis.inverse() * world_basis
	return local_basis.get_euler()


func _capture_head_only_recoil_start_local_position() -> Vector3:
	if rig != null:
		var head: Node3D = rig.get_socket("head")
		if head != null:
			return head.position
	return _get_head_only_grounded_local_position() + _world_horizontal_offset_to_local(_head_only_attack_world_offset)


func _capture_socket_local_position(socket_key: String) -> Vector3:
	if rig != null:
		var socket: Node3D = rig.get_socket(socket_key)
		if socket != null:
			return socket.position
	return _get_rest_pos(socket_key)


func _capture_socket_local_rotation(socket_key: String) -> Vector3:
	if rig != null:
		var socket: Node3D = rig.get_socket(socket_key)
		if socket != null:
			return socket.rotation
	return _get_rest_rot(socket_key)


func _capture_socket_local_scale(socket_key: String) -> Vector3:
	if rig != null:
		var socket: Node3D = rig.get_socket(socket_key)
		if socket != null:
			return socket.scale
	return Vector3.ONE


func _get_head_only_grounded_local_position() -> Vector3:
	var rest: Vector3 = _get_rest_pos("head")
	var base_local_offset: Vector3 = _world_horizontal_offset_to_local(_head_only_base_world_offset)
	return Vector3(rest.x, head_only_ground_socket_y, rest.z) + base_local_offset


func set_crawl_mode(enabled: bool) -> void:
	crawl_mode = enabled


func set_lizard_wall_climb_blend(blend: float) -> void:
	_lizard_wall_climb_blend = clampf(blend, 0.0, 1.0)


func set_player_body_progression_enabled(enabled: bool) -> void:
	player_body_progression_enabled = enabled
	if not enabled:
		_head_only_roll_angle = 0.0


func _capture_rest() -> void:
	# Capture EVERY socket's rest pose (body/limbs animate; feet get placed).
	for key in rig.sockets:
		var s := rig.get_socket(key)
		if s != null:
			_rest_pos[key] = s.position
			_rest_rot[key] = s.rotation
	_captured = true


func _get_rest_pos(key: String) -> Vector3:
	var value = _rest_pos.get(key, Vector3.ZERO)
	if value is Vector3:
		return value
	return Vector3.ZERO


func _get_rest_rot(key: String) -> Vector3:
	var value = _rest_rot.get(key, Vector3.ZERO)
	if value is Vector3:
		return value
	return Vector3.ZERO


func _calculate_weight(equipped_defs: Array) -> float:
	var w := 1.0
	for def in equipped_defs:
		if def is Dictionary:
			w += float(def.get("weight", 1.0)) - 1.0
	return max(w, 1.0)


func _update_torso_head_socket_offset(equipped_defs: Array) -> void:
	var fallback: Vector3 = torso_spring_head_offset
	_torso_head_socket_offset = fallback
	for raw_def in equipped_defs:
		if not raw_def is Dictionary:
			continue
		var definition: Dictionary = raw_def
		if str(definition.get("slot", "")) != "body":
			continue
		var socket_value: Variant = definition.get("head_socket_offset", definition.get("head_origin_offset", fallback))
		_torso_head_socket_offset = _as_vector3(socket_value, fallback)
		return


func _as_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		var vector_value: Vector3 = value
		return vector_value
	return fallback


func _animate_body() -> void:
	var sway := sin(walk_time) * body_sway_amount * total_equipped_weight * speed_ratio
	var bob := absf(sin(walk_time)) * body_bob_amount * speed_ratio
	# The leap supplies its own (bigger, step-synced) vertical arc; the canned
	# bob on top of it reads as shudder. Player-only: enemies never leap.
	if _ik_leap_lift > 0.0005:
		bob *= 0.4
	var breath := sin(_time * 1.8) * idle_breath_amount * (1.0 - speed_ratio)
	if _is_head_only():
		_animate_head_only(sway, breath)
		return
	if _is_torso_spring_only():
		_animate_torso_spring(sway, breath)
		return

	var body := rig.get_socket("body")
	if body != null and _rest_pos.has("body"):
		body.scale = Vector3.ONE
		body.position = _get_rest_pos("body") + Vector3(sway, bob + breath + lizard_wall_climb_lift * _lizard_wall_climb_blend, -0.08 * _lizard_wall_climb_blend)
		body.rotation = _get_rest_rot("body") + Vector3(torso_lean_amount * speed_ratio + lizard_wall_climb_pitch * _lizard_wall_climb_blend, 0.0, -sway * 0.6)

	var head := rig.get_socket("head")
	if head != null and _rest_pos.has("head"):
		head.position = _get_rest_pos("head") + Vector3(0.0, breath * 0.6 + lizard_wall_climb_head_lift * _lizard_wall_climb_blend, -0.10 * _lizard_wall_climb_blend)
		head.rotation = _get_rest_rot("head") + Vector3(-lizard_wall_climb_pitch * 0.35 * _lizard_wall_climb_blend, 0.0, sway * 0.3)
	_apply_detached_head_reattach_finish_blend(body, head)
	_animate_lizard_torso_blocks(sway, breath, 0.0)


func _is_head_only() -> bool:
	return player_body_progression_enabled and rig != null and rig.has_method("has_equipped_slot") and not bool(rig.call("has_equipped_slot", "body"))


# True from the moment a head-only attack fires until the head is back down,
# including the hit recoil, which is also played in the air.
func _head_only_attack_airborne() -> bool:
	if not _is_head_only():
		return false
	return not _head_only_attack_landed or _head_only_hit_recoil_timer > 0.0


func _is_torso_spring_only() -> bool:
	return (
		player_body_progression_enabled
		and rig != null
		and rig.has_method("has_equipped_slot")
		and bool(rig.call("has_equipped_slot", "body"))
		and not bool(rig.call("has_equipped_slot", "legs"))
	)


func _is_slot_equipped(slot: String) -> bool:
	return rig != null and rig.has_method("has_equipped_slot") and bool(rig.call("has_equipped_slot", slot))


# One arm is enough to punch with.
func _has_any_arm_equipped() -> bool:
	return _is_slot_equipped("right_arm") or _is_slot_equipped("left_arm")


# The torso only throws its head when it has no arm to swing. Launching the head
# while an arm is available is both worse-looking and a worse deal: a launch that
# misses detaches the head, which is a heavy price for a swing the player could
# have thrown with a fist.
func _torso_head_launch_available() -> bool:
	return _is_torso_spring_only() and not _has_any_arm_equipped()


func _animate_head_only(sway: float, breath: float) -> void:
	var head: Node3D = rig.get_socket("head")
	if head == null or not _rest_pos.has("head"):
		return
	if rig.has_method("set_head_only_visual_guard"):
		rig.call("set_head_only_visual_guard", true)

	if _reattach_tornado_active:
		_apply_detached_head_reattach_tornado(head)
		return

	var hop: float = absf(sin(walk_time)) * head_only_hop_amount * speed_ratio
	var rest: Vector3 = _get_rest_pos("head")
	var base_local_offset: Vector3 = _world_horizontal_offset_to_local(_head_only_base_world_offset)
	var target_position: Vector3 = Vector3(rest.x + sway * 0.8, head_only_ground_socket_y + hop, rest.z) + base_local_offset
	var target_rotation: Vector3 = _get_rest_rot("head") + Vector3(_head_only_roll_angle, 0.0, sway * head_only_roll_amount)
	head.scale = Vector3.ONE
	if _detached_head_landing_timer > 0.0:
		var duration: float = maxf(detached_head_mode_blend_duration, 0.01)
		var t: float = 1.0 - clampf(_detached_head_landing_timer / duration, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - t, 1.65)
		head.position = _detached_head_landing_start_position.lerp(target_position, eased)
		head.rotation = _detached_head_landing_start_rotation.lerp(target_rotation, eased)
		head.scale = _detached_head_landing_start_scale.lerp(Vector3.ONE, eased)
		return
	head.position = target_position
	head.rotation = target_rotation


func _apply_detached_head_reattach_tornado(head: Node3D) -> void:
	var t: float = clampf(_reattach_tornado_progress, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var angle: float = TAU * detached_head_reattach_tornado_turns * t
	var radius: float = detached_head_reattach_tornado_radius * (1.0 - eased)
	var spiral_offset: Vector3 = Vector3(
		cos(angle) * radius,
		sin(t * PI) * detached_head_reattach_tornado_lift + sin(angle) * radius * 0.28,
		sin(angle) * radius * 0.62
	)
	var path_position: Vector3 = _reattach_tornado_start_position.lerp(_reattach_tornado_target_position, eased)
	var body_pull: Vector3 = _reattach_tornado_body_position.lerp(_reattach_tornado_target_position, eased)
	head.position = path_position.lerp(body_pull, 0.35 * sin(t * PI)) + spiral_offset
	head.rotation = _reattach_tornado_start_rotation.lerp(_get_rest_rot("head"), eased)
	head.rotation.x += angle * 0.18
	head.rotation.z += sin(angle) * 0.35 * (1.0 - eased)
	head.scale = Vector3.ONE
	if t >= 0.999:
		head.position = _reattach_tornado_target_position
		head.rotation = _get_rest_rot("head")
		_reattach_tornado_active = false
		_reattach_tornado_timer = 0.0
		_reattach_tornado_progress = 1.0


func _apply_detached_head_reattach_finish_blend(_body: Node3D, head: Node3D) -> void:
	if _reattach_finish_blend_timer <= 0.0:
		return
	var duration: float = maxf(_reattach_finish_blend_duration, 0.01)
	var t: float = 1.0 - clampf(_reattach_finish_blend_timer / duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	if head != null:
		head.position = _reattach_finish_head_start_position.lerp(head.position, eased)
		head.rotation = _reattach_finish_head_start_rotation.lerp(head.rotation, eased)
		head.scale = Vector3.ONE.lerp(head.scale, eased)


func _animate_torso_spring(sway: float, breath: float) -> void:
	var body := rig.get_socket("body")
	var head := rig.get_socket("head")
	if body == null or not _rest_pos.has("body"):
		return

	var phase := fposmod(walk_time, TAU)
	var airborne: float = maxf(sin(phase), 0.0) * speed_ratio
	var contact: float = pow(1.0 - airborne, 2.0) * speed_ratio
	var hop: float = airborne * torso_spring_hop_amount
	var compression: float = contact * torso_spring_compress_amount
	var forward_shove: float = airborne * torso_spring_forward_offset
	var spring_tilt: float = sin(phase) * torso_spring_tilt_amount * speed_ratio

	var body_rest: Vector3 = _get_rest_pos("body")
	body.position = Vector3(body_rest.x + sway * 0.45, torso_spring_ground_socket_y + hop + breath - compression * 0.45, body_rest.z - forward_shove)
	body.rotation = _get_rest_rot("body") + Vector3(torso_lean_amount * 0.35 * speed_ratio + spring_tilt, 0.0, -sway * 0.45)
	body.scale = Vector3(1.0 + compression * 0.45 - airborne * 0.04, 1.0 - compression + airborne * 0.10, 1.0 + compression * 0.35 - airborne * 0.04)

	if head != null and _rest_pos.has("head"):
		var head_phase := fposmod(phase - torso_spring_head_pop_delay, TAU)
		var head_pop: float = maxf(sin(head_phase), 0.0) * torso_spring_head_pop_amount * speed_ratio
		head.position = body.position + _torso_head_socket_offset + Vector3(sway * 0.38, compression * 0.32 + head_pop, forward_shove * 0.45)
		_torso_head_socket_local_position = head.position
		head.rotation = _get_rest_rot("head") + Vector3(-spring_tilt * 0.55, 0.0, sway * 0.42)
	# Sockets are siblings of the body socket, not children of it, so nothing pulls
	# the arms down when the torso drops to torso_spring_ground_socket_y. The head
	# is re-anchored above; without the same treatment the arms hang at their
	# standing rest height, floating detached above the torso.
	_anchor_socket_to_body("right_arm", body)
	_anchor_socket_to_body("left_arm", body)
	_apply_detached_head_reattach_finish_blend(body, head)


# Keeps a socket at its normal offset from the torso while the torso itself is
# displaced. Derived from the captured rest layout rather than a tuned constant,
# so it stays correct if ModularSkeletonRig.SOCKET_LAYOUT changes.
func _anchor_socket_to_body(key: String, body: Node3D) -> void:
	if body == null or not _rest_pos.has(key) or not _rest_pos.has("body"):
		return
	var socket: Node3D = rig.get_socket(key)
	if socket == null:
		return
	socket.position = body.position + (_get_rest_pos(key) - _get_rest_pos("body"))


func _animate_limbs() -> void:
	var swing := sin(walk_time) * speed_ratio
	# Arms swing opposite to the legs (right arm forward with left leg) and forward
	# with movement — flipped from before, which sent them backward.
	_swing("right_arm", -swing * arm_swing_amount)
	_swing("left_arm", swing * arm_swing_amount)
	_swing("right_leg", -swing * leg_swing_amount)
	_swing("left_leg", swing * leg_swing_amount)


# How much of the idle ready-stance is showing. Gated on _ik_active() so it is the
# split PLAYER only — every enemy, and the head-only/torso/crawl/demo modes, stay
# bit-identical. Fades with movement, so the gait never has to fight it.
func _idle_stance_blend() -> float:
	if not idle_stance_enabled or not _ik_active():
		return 0.0
	return clampf(1.0 - speed_ratio * 2.5, 0.0, 1.0)


func _update_idle_stance(delta: float) -> void:
	_idle_blend = lerpf(_idle_blend, _idle_stance_blend(), 1.0 - exp(-idle_guard_blend_speed * delta))


# The ready pose: CHEST pitched forward (author was explicit — the chest, not a
# waist fold, so this rides the body socket's own rotation and leaves the waist
# joint to the gait), breathing on top of that lean, and both arms in a LOW guard.
# Runs after _animate_limbs/_animate_joints (so it overrides the idle rest pose)
# but BEFORE the attack and aim overlays, which stay free to take the arms.
func _apply_idle_stance() -> void:
	if _idle_blend < 0.001:
		return  # bit-identical when the stance is not showing
	var b: float = _idle_blend
	var breath: float = sin(_time * idle_breath_speed) * deg_to_rad(idle_chest_breath_deg)

	# CHEST: lean forward, and let the breath ride the lean itself so the ribcage
	# visibly swells and settles rather than just bobbing.
	var body: Node3D = rig.get_socket("body")
	if body != null:
		body.rotation.x += (deg_to_rad(idle_chest_lean_deg) + breath) * b

	# ARMS: shoulders forward and tucked in, elbows folded up — a guard held LOW.
	# Mind the handedness: this rig faces +Z, so its right is -X and left is +X,
	# which flips the sign of the inward tuck per side.
	for key in ["right_arm", "left_arm"]:
		var arm: Node3D = rig.get_socket(key)
		if arm == null:
			continue
		var tuck: float = deg_to_rad(idle_guard_arm_tuck_deg) * b
		arm.rotation.x += deg_to_rad(idle_guard_arm_raise_deg) * b
		# +Z forward => right arm is at -X and tucks with +Z roll, left mirrors.
		arm.rotation.z += tuck if key == "right_arm" else -tuck
		var elbow: Node3D = rig.get_socket(key + "_lower")
		if elbow != null:
			# Elbows bend NEGATIVE on this rig (see _animate_joints' bend_sign).
			elbow.rotation.x -= deg_to_rad(idle_guard_elbow_deg) * b


func _animate_crawl_body() -> void:
	var pull := sin(walk_time)
	var shove := absf(pull) * body_bob_amount * 0.65 * speed_ratio
	var breath := sin(_time * 1.8) * idle_breath_amount * (1.0 - speed_ratio)
	var forward_shove := absf(pull) * crawl_forward_offset * speed_ratio

	var body := rig.get_socket("body")
	if body != null and _rest_pos.has("body"):
		body.scale = Vector3.ONE
		body.position = _get_rest_pos("body") + Vector3(pull * body_sway_amount * 0.65 * speed_ratio, -crawl_body_drop + shove + breath + lizard_wall_climb_lift * _lizard_wall_climb_blend, -forward_shove - 0.08 * _lizard_wall_climb_blend)
		body.rotation = _get_rest_rot("body") + Vector3(crawl_body_pitch + lizard_wall_climb_pitch * 0.45 * _lizard_wall_climb_blend, pull * 0.10 * speed_ratio, -pull * 0.16 * speed_ratio)

	var head := rig.get_socket("head")
	if head != null and _rest_pos.has("head"):
		head.position = _get_rest_pos("head") + Vector3(0.0, -crawl_body_drop - 0.12 + breath + lizard_wall_climb_head_lift * _lizard_wall_climb_blend, -0.22 - forward_shove * 0.35 - 0.08 * _lizard_wall_climb_blend)
		head.rotation = _get_rest_rot("head") + Vector3(-crawl_head_lift, pull * 0.06 * speed_ratio, pull * 0.10 * speed_ratio)
	_apply_detached_head_reattach_finish_blend(body, head)
	_animate_lizard_torso_blocks(pull * body_sway_amount * speed_ratio, breath, crawl_body_pitch)


func _animate_crawl_limbs() -> void:
	var pull := sin(walk_time) * speed_ratio
	var right_pull := maxf(pull, 0.0)
	var left_pull := maxf(-pull, 0.0)

	_swing("right_arm", -0.45 - right_pull * crawl_pull_amount + left_pull * 0.35)
	_swing("left_arm", -0.45 - left_pull * crawl_pull_amount + right_pull * 0.35)

	var right_arm := rig.get_socket("right_arm")
	if right_arm != null:
		right_arm.position = _get_rest_pos("right_arm") + Vector3(0.06 * right_pull, -crawl_arm_drop, 0.08 - right_pull * crawl_arm_reach)
		right_arm.rotation.z += right_pull * crawl_shoulder_roll - left_pull * 0.18
	var left_arm := rig.get_socket("left_arm")
	if left_arm != null:
		left_arm.position = _get_rest_pos("left_arm") + Vector3(-0.06 * left_pull, -crawl_arm_drop, 0.08 - left_pull * crawl_arm_reach)
		left_arm.rotation.z -= left_pull * crawl_shoulder_roll - right_pull * 0.18

	_swing("right_leg", crawl_leg_tuck)
	_swing("left_leg", crawl_leg_tuck)
	var right_leg := rig.get_socket("right_leg")
	if right_leg != null:
		right_leg.position = _get_rest_pos("right_leg") + Vector3(0.03, -0.10, 0.16)
	var left_leg := rig.get_socket("left_leg")
	if left_leg != null:
		left_leg.position = _get_rest_pos("left_leg") + Vector3(-0.03, -0.10, 0.16)
	var right_foot := rig.get_socket("right_foot")
	if right_foot != null:
		right_foot.position = _get_rest_pos("right_foot") + Vector3(0.0, 0.02, 0.12)
		right_foot.rotation = _get_rest_rot("right_foot") + Vector3(crawl_leg_tuck * 0.5, 0.0, 0.0)
	var left_foot := rig.get_socket("left_foot")
	if left_foot != null:
		left_foot.position = _get_rest_pos("left_foot") + Vector3(0.0, 0.02, 0.12)
		left_foot.rotation = _get_rest_rot("left_foot") + Vector3(crawl_leg_tuck * 0.5, 0.0, 0.0)


func _apply_lizard_wall_climb_limb_pose() -> void:
	if _lizard_wall_climb_blend <= 0.001:
		return

	var reach: float = lizard_wall_climb_limb_reach * _lizard_wall_climb_blend
	var right_arm: Node3D = rig.get_socket("right_arm")
	if right_arm != null:
		right_arm.position = right_arm.position + Vector3(0.04, reach * 0.35, -reach)
		right_arm.rotation.x -= reach * 1.8
		right_arm.rotation.z += reach * 0.55
	var left_arm: Node3D = rig.get_socket("left_arm")
	if left_arm != null:
		left_arm.position = left_arm.position + Vector3(-0.04, reach * 0.35, -reach)
		left_arm.rotation.x -= reach * 1.8
		left_arm.rotation.z -= reach * 0.55

	var right_leg: Node3D = rig.get_socket("right_leg")
	if right_leg != null:
		right_leg.position = right_leg.position + Vector3(0.02, -reach * 0.12, reach * 0.35)
		right_leg.rotation.x += reach * 0.9
	var left_leg: Node3D = rig.get_socket("left_leg")
	if left_leg != null:
		left_leg.position = left_leg.position + Vector3(-0.02, -reach * 0.12, reach * 0.35)
		left_leg.rotation.x += reach * 0.9


func _animate_lizard_torso_blocks(sway: float, breath: float, base_pitch: float) -> void:
	if rig == null:
		return

	var body: Node3D = rig.get_socket("body")
	if body == null:
		return

	var front: Node3D = body.get_node_or_null("LizardTorsoFront") as Node3D
	var rear: Node3D = body.get_node_or_null("LizardTorsoRear") as Node3D
	if front == null or rear == null:
		return

	var flex: float = sin(walk_time) * lizard_torso_flex_amount * speed_ratio
	var idle_flex: float = sin(_time * 1.6) * lizard_torso_flex_amount * 0.25 * (1.0 - speed_ratio)
	var total_flex: float = flex + idle_flex + sway * 0.45
	var wall_pitch: float = lizard_wall_climb_pitch * _lizard_wall_climb_blend
	front.rotation = Vector3(base_pitch * 0.18 + wall_pitch * 0.55, total_flex, -total_flex * 0.35)
	rear.rotation = Vector3(-base_pitch * 0.10 - wall_pitch * 0.25, -total_flex * 0.8, total_flex * 0.25)
	front.position.y = -0.02 + breath * 0.4 + lizard_wall_climb_lift * 0.35 * _lizard_wall_climb_blend
	rear.position.y = -0.04 - breath * 0.2 - lizard_wall_climb_lift * 0.12 * _lizard_wall_climb_blend


func _swing(key: String, angle: float) -> void:
	var s := rig.get_socket(key)
	if s != null and _rest_rot.has(key):
		s.rotation = _get_rest_rot(key) + Vector3(angle, 0.0, 0.0)


# Bends each limb's mid joint (elbow/knee) so the limb flexes during the walk
# instead of swinging as one rigid stick. Poses the skinned bone directly.
func _animate_joints() -> void:
	if rig == null:
		return
	for key in rig.limb_joints:
		var info: Dictionary = rig.limb_joints[key]
		var wave := 0.5 + 0.5 * sin(walk_time + _joint_phase(key))
		var bend := joint_bend_base + joint_bend_swing * speed_ratio * wave
		# Elbows bend forward, knees bend backward — flip the arm direction.
		var bend_sign := -1.0 if ("arm" in key) else 1.0

		# Read the discriminator BEFORE touching "skel": that key does not exist on
		# a socket entry, and the typed assignment below would halt the script
		# rather than fail soft like the rest of this codebase.
		if String(info.get("kind", "skin")) == "socket":
			# Grey-box rig: the elbow/knee IS a socket, so rotate it directly. Lower
			# sockets rest at identity, hence the plain assign. Assigning (not +=)
			# means anything else writing this node's rotation would be stomped —
			# nothing does today; _animate_wobble only touches the upper sockets.
			var joint_node: Node3D = info.get("node") as Node3D
			if joint_node == null or not is_instance_valid(joint_node):
				continue
			joint_node.rotation = Vector3(bend * bend_sign, 0.0, 0.0)
			continue

		var skel: Skeleton3D = info["skel"]
		if skel == null or not is_instance_valid(skel):
			continue
		var bone: int = info["bone"]
		var rest_rot: Quaternion = info["rest_rot"]
		skel.set_bone_pose_rotation(bone, rest_rot * Quaternion(Vector3(1.0, 0.0, 0.0), bend * bend_sign))


func _joint_phase(key: String) -> float:
	match key:
		"left_leg":
			return PI
		"right_arm":
			return PI
		_:
			return 0.0


# Loose-skeleton rattle: adds a small jiggle rotation on top of the swing and
# slides each bone slightly in and out of its socket, each with its own phase.
func _animate_wobble() -> void:
	if not wobble_enabled or rig == null:
		return

	var ik: bool = _ik_active()
	for key in ["right_arm", "left_arm", "right_leg", "left_leg", "left_foot", "right_foot", "head"]:
		if (_is_head_only() or _is_torso_spring_only()) and key == "head":
			continue
		# Under IK the foot socket IS the plant, and its rest offset is the shin
		# length the solver measures. Sliding it would both rattle a foot that is
		# supposed to be nailed down and change the bone length mid-solve. The legs
		# stay in: the solver runs after this and reads the wobbled hip, so the
		# rattle survives as hip motion the legs absorb rather than fight.
		if ik and (key == "left_foot" or key == "right_foot"):
			continue

		var s := rig.get_socket(key)
		if s == null or not _rest_pos.has(key):
			continue

		var ph := _wobble_phase(key)
		var wx := sin(_time * wobble_speed + ph) * wobble_rotation
		var wz := sin(_time * wobble_speed * 1.4 + ph * 1.6) * wobble_rotation

		# Arms/legs already got a swing this frame — add the jiggle on top. Feet and
		# head have no swing, so set their rotation from rest + jiggle.
		if _rest_rot.has(key) and (key == "left_foot" or key == "right_foot" or key == "head"):
			s.rotation = _get_rest_rot(key) + Vector3(wx, 0.0, wz)
		else:
			s.rotation += Vector3(wx, 0.0, wz)

		# Slide the bone in and out along its outward direction from the body.
		var rest_pos: Vector3 = _get_rest_pos(key)
		var base_pos: Vector3 = rest_pos
		# Modes that displace a socket away from its standing rest must keep the
		# pose set earlier this frame, or the slide snaps it back to rest. Crawl
		# already did this; torso-spring drops the body ~0.58 m and needs it too,
		# otherwise the arms strand themselves at standing shoulder height.
		if (crawl_mode or _is_torso_spring_only()) and (key == "head" or key == "right_arm" or key == "left_arm"):
			base_pos = s.position
		var out_dir: Vector3 = rest_pos
		if out_dir.length() > 0.01:
			out_dir = out_dir.normalized()
		else:
			out_dir = Vector3.DOWN
		s.position = base_pos + out_dir * (sin(_time * wobble_speed * 0.8 + ph) * wobble_slide)


func _wobble_phase(key: String) -> float:
	match key:
		"right_arm": return 0.0
		"left_arm": return 1.7
		"right_leg": return 3.1
		"left_leg": return 4.6
		"left_foot": return 2.2
		"right_foot": return 5.0
		"head": return 0.8
		_: return 0.0


# --- Phase E: aim and attack overlays -----------------------------------------

func _update_aim_overlay(delta: float) -> void:
	var target: float = 1.0 if _aim_requested else 0.0
	_aim_blend = lerp(_aim_blend, target, 1.0 - exp(-aim_overlay_blend_speed * delta))


func _apply_aim_overlay() -> void:
	if _aim_blend <= 0.001:
		return

	var right_arm: Node3D = rig.get_socket("right_arm")
	if right_arm != null:
		right_arm.rotation.x -= aim_right_arm_forward * _aim_blend
		right_arm.rotation.z -= aim_right_arm_draw * _aim_blend

	var left_arm: Node3D = rig.get_socket("left_arm")
	if left_arm != null:
		left_arm.rotation.x -= aim_left_arm_forward * _aim_blend
		left_arm.rotation.z += aim_left_arm_brace * _aim_blend

	var body: Node3D = rig.get_socket("body")
	if body != null:
		body.rotation.x -= aim_torso_lean * _aim_blend

	var head: Node3D = rig.get_socket("head")
	if head != null:
		head.rotation.x -= aim_head_dip * _aim_blend


func _update_attack_overlay(delta: float) -> void:
	_attack_timer = max(_attack_timer - delta, 0.0)
	if _head_only_hit_recoil_timer > 0.0:
		_head_only_hit_recoil_timer = maxf(_head_only_hit_recoil_timer - delta, 0.0)
	var target := 1.0 if _attack_timer > 0.0 else 0.0
	if _head_only_hit_recoil_timer > 0.0:
		target = 1.0
	if _torso_head_recoil_timer > 0.0:
		_torso_head_recoil_timer = maxf(_torso_head_recoil_timer - delta, 0.0)
		target = 1.0
	if _torso_head_miss_fall_active:
		target = 1.0
	if _torso_head_miss_detach_requested:
		target = 1.0
	if _is_head_only() and not _head_only_attack_contacted:
		target = 1.0
	if _is_torso_spring_only() and not _torso_head_attack_contacted:
		target = 1.0
	_attack_blend = lerp(_attack_blend, target, 1.0 - exp(-attack_overlay_blend_speed * delta))


# Adds a combo pose ON TOP of the walk pose, so attacks read clearly whether idle
# or moving.
func _apply_attack_overlay() -> void:
	if _attack_blend <= 0.001:
		return
	if _is_head_only():
		_apply_head_only_attack_pose()
		return
	if _torso_head_launch_available():
		_apply_torso_head_attack_pose()
		return
	var punch: float = _attack_pose_strength()
	match _combo_step_for_equipped_arms():
		2:
			_apply_left_combo_pose(punch)
		3:
			_apply_finisher_combo_pose(punch)
		COMBO_STEP_ARM_SWORD:
			_apply_arm_sword_pose(punch)
		_:
			_apply_right_combo_pose(punch)


# The combo normally alternates right -> left -> both arms. With only one arm
# equipped every step has to swing THAT arm, or the swing plays on an empty
# socket and the attack reads as doing nothing. With progression off (rig
# sandbox, enemies) every grey-box limb is present, so the normal cycle stands.
func _combo_step_for_equipped_arms() -> int:
	if not player_body_progression_enabled:
		return _attack_combo_step
	var has_right: bool = _is_slot_equipped("right_arm")
	var has_left: bool = _is_slot_equipped("left_arm")
	if has_right == has_left:
		return _attack_combo_step
	return 1 if has_right else 2


func _attack_pose_strength() -> float:
	if _attack_duration_current <= 0.001:
		return _attack_blend
	return _attack_strike_curve(_attack_phase()) * _attack_blend


# Anticipation -> strike -> follow-through.
#
# This used to be sin(phase * PI): a symmetric arc that eased in and out at the
# same rate, with no wind-back and no snap, which is exactly what made a hit read
# as floaty. A strike lands because the fast part is fast RELATIVE to a slow part
# before it, so the swing now spends ~45% winding back, ~18% striking, and the rest
# following through.
#
# Returns NEGATIVE during the windup. That is the anticipation: every combo pose
# subtracts strength * amount from a rotation, so a negative value swings the arm
# BACK before it comes forward, for free, with no per-pose changes.
func _attack_strike_curve(phase: float) -> float:
	var windup_end: float = clampf(attack_windup_portion, 0.05, 0.70)
	var strike_end: float = minf(windup_end + maxf(attack_strike_portion, 0.02), 0.95)
	var hold_end: float = minf(strike_end + maxf(attack_strike_hold, 0.0), 0.99)

	if phase < windup_end:
		# Wind back, decelerating into the top of the swing.
		var wind_t: float = phase / windup_end
		return -attack_anticipation * sin(wind_t * PI * 0.5)

	if phase < strike_end:
		# The strike: accelerate out of the windup into full extension.
		var strike_t: float = (phase - windup_end) / maxf(strike_end - windup_end, 0.001)
		return lerpf(-attack_anticipation, 1.0, strike_t * strike_t)

	if phase < hold_end:
		# Hold full extension. The strike is deliberately only a few frames, so
		# without this the hit pose is never on screen long enough to read.
		return 1.0

	# Follow-through: settle back, slower than the strike went out.
	var settle_t: float = (phase - hold_end) / maxf(1.0 - hold_end, 0.001)
	return pow(1.0 - settle_t, 2.0)


func _attack_phase() -> float:
	if _attack_duration_current <= 0.001:
		return 1.0
	return 1.0 - clampf(_attack_timer / _attack_duration_current, 0.0, 1.0)


func _apply_head_only_attack_pose() -> void:
	var head := rig.get_socket("head")
	if head == null:
		return

	if _head_only_hit_recoil_timer > 0.0:
		_apply_head_only_hit_recoil_pose(head)
		return

	var phase: float = _attack_phase()
	if phase >= 0.999 and not _head_only_attack_landed:
		# The lunge has to move the PLAYER, not just the head visual. Accumulating
		# it into _head_only_base_world_offset instead left the head drifting
		# 0.85 m further from the capsule on every attack, forever. The Player
		# consumes this request in the same frame, so the head does not pop: it
		# stays where the launch left it and the body arrives underneath it.
		_head_only_body_catch_up_offset += _head_only_attack_direction * head_only_attack_lunge
		_head_only_body_catch_up_requested = true
		_head_only_attack_world_offset = Vector3.ZERO
		_head_only_attack_landed = true
		_head_only_attack_contacted = true
		var rest: Vector3 = _get_rest_pos("head")
		var landed_local_offset: Vector3 = _world_horizontal_offset_to_local(_head_only_base_world_offset)
		head.position = Vector3(rest.x, head_only_ground_socket_y, rest.z) + landed_local_offset
		head.scale = Vector3.ONE
		return
	if _head_only_attack_landed:
		_head_only_attack_world_offset = Vector3.ZERO
		head.scale = Vector3.ONE
		return

	var charge_end: float = clampf(head_only_attack_charge_portion, 0.05, 0.75)
	if phase < charge_end:
		var charge_t: float = phase / charge_end
		var charge: float = sin(charge_t * PI * 0.5) * _attack_blend
		_head_only_attack_world_offset = _head_only_attack_direction * (-head_only_attack_lunge * 0.14 * charge)
		var charge_local_offset: Vector3 = _world_horizontal_offset_to_local(_head_only_attack_world_offset)
		head.position.y -= head_only_attack_charge_squash * charge
		head.position += charge_local_offset
		head.rotation.x -= head_only_attack_roll * 0.22 * charge
		head.scale = Vector3(
			1.0 + head_only_attack_charge_squash * 0.55 * charge,
			1.0 - head_only_attack_charge_squash * 0.75 * charge,
			1.0 + head_only_attack_charge_squash * 0.45 * charge
		)
		return

	var jump_t: float = (phase - charge_end) / maxf(1.0 - charge_end, 0.001)
	var arc: float = sin(jump_t * PI) * _attack_blend
	var commit: float = sin(jump_t * PI * 0.5) * _attack_blend
	# The charge compression has to unwind INTO the launch. Reading the launch
	# straight off the rest pose snapped the squash/pullback off in a single
	# frame, which teleported the head ~0.23 m and read as a speed spike.
	var release_t: float = clampf(jump_t / maxf(head_only_attack_release_portion, 0.001), 0.0, 1.0)
	var release: float = (1.0 - release_t) * _attack_blend
	_head_only_attack_world_offset = _head_only_attack_direction * head_only_attack_lunge * (commit - 0.14 * release)
	var jump_local_offset: Vector3 = _world_horizontal_offset_to_local(_head_only_attack_world_offset)
	head.position += jump_local_offset
	head.position.y += head_only_attack_arc * arc - head_only_attack_charge_squash * release
	head.rotation.x += head_only_attack_roll * (commit - 0.22 * release)
	var stretch: float = arc * 0.12
	var launch_scale := Vector3(1.0 - stretch * 0.5, 1.0 + stretch, 1.0 - stretch * 0.35)
	var charge_scale := Vector3(
		1.0 + head_only_attack_charge_squash * 0.55 * _attack_blend,
		1.0 - head_only_attack_charge_squash * 0.75 * _attack_blend,
		1.0 + head_only_attack_charge_squash * 0.45 * _attack_blend
	)
	head.scale = charge_scale.lerp(launch_scale, release_t)


func _apply_head_only_hit_recoil_pose(head: Node3D) -> void:
	var duration: float = maxf(head_only_hit_recoil_duration, 0.001)
	var t: float = 1.0 - clampf(_head_only_hit_recoil_timer / duration, 0.0, 1.0)
	var hold_ratio: float = clampf(head_only_hit_recoil_hold / duration, 0.0, 0.65)
	var move_t: float = 0.0
	if hold_ratio < 0.999:
		move_t = clampf((t - hold_ratio) / maxf(1.0 - hold_ratio, 0.001), 0.0, 1.0)
	var eased: float = move_t * move_t * (3.0 - 2.0 * move_t)
	var impact_t: float = 1.0
	if hold_ratio > 0.001:
		impact_t = clampf(t / hold_ratio, 0.0, 1.0)
	var impact_weight: float = 1.0 - impact_t
	var settle_wave: float = sin(move_t * TAU) * (1.0 - move_t) * head_only_hit_recoil_settle
	var recoil_direction: Vector3 = _head_only_hit_recoil_end_offset - _head_only_hit_recoil_start_offset
	recoil_direction.y = 0.0
	if recoil_direction.length() <= 0.001:
		recoil_direction = -_head_only_attack_direction
	else:
		recoil_direction = recoil_direction.normalized()
	var horizontal_push: float = sin(move_t * PI) * (1.0 - move_t * 0.25)
	var horizontal_recoil: Vector3 = recoil_direction * head_only_hit_recoil_horizontal_push * horizontal_push
	horizontal_recoil += recoil_direction * settle_wave
	var world_offset: Vector3 = _head_only_hit_recoil_start_offset.lerp(_head_only_hit_recoil_end_offset, eased)
	world_offset += horizontal_recoil
	_head_only_attack_world_offset = world_offset - _head_only_base_world_offset

	var local_recoil: Vector3 = _world_horizontal_offset_to_local(horizontal_recoil)
	var local_position: Vector3 = _head_only_hit_recoil_start_local_position.lerp(_head_only_hit_recoil_end_local_position, eased)
	var bounce_height: float = maxf(head_only_hit_recoil_arc, head_only_hit_recoil_lift)
	var bounce: float = sin(move_t * PI) * bounce_height * (1.0 - move_t * 0.25)
	head.position = local_position + local_recoil + Vector3(0.0, bounce, 0.0)
	var roll: float = impact_weight * head_only_hit_recoil_roll * 0.65
	roll += sin(move_t * PI) * head_only_hit_recoil_roll + settle_wave * 1.8
	head.rotation = _get_rest_rot("head") + Vector3(_head_only_roll_angle - roll, 0.0, settle_wave * 0.35)
	var squash: float = impact_weight * 0.13 + sin(move_t * PI) * 0.075
	head.scale = Vector3(1.0 + squash * 0.7, 1.0 - squash, 1.0 + squash * 0.35)


func _apply_torso_head_attack_pose() -> void:
	var body := rig.get_socket("body")
	var head := rig.get_socket("head")
	if body == null or head == null:
		return

	if _torso_head_recoil_timer > 0.0:
		_apply_torso_head_recoil_pose(body, head)
		return

	if _torso_head_miss_fall_active:
		_apply_torso_head_miss_fall_pose(body, head)
		return

	if _torso_head_miss_detach_requested:
		_apply_torso_head_miss_body_hold_pose(body)
		head.position = _future_head_only_ground_position()
		head.rotation = _get_rest_rot("head")
		head.scale = Vector3.ONE
		return

	if _torso_head_attack_landed:
		_torso_head_attack_world_offset = Vector3.ZERO
		head.position = _torso_head_socket_local_position
		head.rotation = _get_rest_rot("head")
		head.scale = Vector3.ONE
		return

	var phase: float = _attack_phase()
	var charge_end: float = clampf(torso_head_attack_charge_portion, 0.05, 0.75)
	var coil: float = 0.0
	if phase < charge_end:
		var charge_t: float = phase / charge_end
		coil = sin(charge_t * PI * 0.5) * _attack_blend
		_torso_head_attack_world_offset = _torso_head_attack_direction * (-torso_head_attack_lunge * 0.10 * coil)
		var charge_local_offset: Vector3 = _world_horizontal_offset_to_local(_torso_head_attack_world_offset)
		body.position.y -= torso_head_attack_coil * coil
		body.rotation.x += torso_head_attack_coil * 0.85 * coil
		body.scale = Vector3(1.0 + coil * 0.16, 1.0 - coil * 0.20, 1.0 + coil * 0.12)
		head.position += charge_local_offset
		head.position.y -= torso_head_attack_coil * 0.35 * coil
		head.rotation.x -= torso_head_attack_roll * 0.18 * coil
		_capture_torso_head_miss_body_hold_transform()
		return

	var launch_t: float = (phase - charge_end) / maxf(1.0 - charge_end, 0.001)
	var commit: float = sin(launch_t * PI * 0.5) * _attack_blend
	var arc: float = sin(launch_t * PI) * _attack_blend
	_torso_head_attack_world_offset = _torso_head_attack_direction * (torso_head_attack_lunge * commit)
	_torso_head_socket_local_position = _capture_socket_local_position("head")
	var launch_local_offset: Vector3 = _world_horizontal_offset_to_local(_torso_head_attack_world_offset)
	head.position += launch_local_offset
	head.position.y += torso_head_attack_arc * arc
	head.rotation.x += torso_head_attack_roll * commit
	body.rotation.x -= torso_head_attack_coil * 0.30 * arc
	body.scale = Vector3(1.0 - arc * 0.04, 1.0 + arc * 0.08, 1.0 - arc * 0.03)
	if not _torso_head_miss_body_hold_transform_ready:
		_capture_torso_head_miss_body_hold_transform()

	if phase >= 0.999 and not _torso_head_attack_landed:
		_torso_head_detach_world_offset = _torso_head_attack_direction * torso_head_attack_lunge
		_torso_head_attack_world_offset = _torso_head_detach_world_offset
		_torso_head_attack_landed = true
		_torso_head_attack_contacted = true
		_torso_head_miss_fall_active = true
		_torso_head_miss_fall_timer = maxf(detached_head_landing_duration, 0.01)
		_torso_head_miss_fall_start_position = _capture_socket_local_position("head")
		_torso_head_miss_fall_start_rotation = _capture_socket_local_rotation("head")
		_torso_head_miss_fall_start_scale = _capture_socket_local_scale("head")
		if not _torso_head_miss_body_hold_transform_ready:
			_capture_torso_head_miss_body_hold_transform()


func _apply_torso_head_miss_fall_pose(body: Node3D, head: Node3D) -> void:
	_apply_torso_head_miss_body_hold_pose(body)
	var duration: float = maxf(detached_head_landing_duration, 0.01)
	var t: float = 1.0 - clampf(_torso_head_miss_fall_timer / duration, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 1.45)
	var target_position: Vector3 = _future_head_only_ground_position()
	var target_rotation: Vector3 = _get_rest_rot("head")
	var bounce: float = sin(t * PI) * detached_head_landing_bounce * (1.0 - t)
	head.position = _torso_head_miss_fall_start_position.lerp(target_position, eased) + Vector3(0.0, bounce, 0.0)
	head.rotation = _torso_head_miss_fall_start_rotation.lerp(target_rotation, eased)
	head.rotation.x += detached_head_landing_roll * sin(t * PI) * (1.0 - t * 0.35)
	head.scale = _torso_head_miss_fall_start_scale.lerp(Vector3.ONE, eased)
	_torso_head_attack_world_offset = _torso_head_detach_world_offset

	if t >= 0.999:
		head.position = target_position
		head.rotation = target_rotation
		head.scale = Vector3.ONE
		_torso_head_miss_fall_active = false
		_torso_head_miss_fall_timer = 0.0
		_torso_head_miss_detach_requested = true


func _apply_torso_head_miss_body_hold_pose(body: Node3D) -> void:
	if body == null:
		return
	body.scale = Vector3.ONE


func _future_head_only_ground_position() -> Vector3:
	var rest: Vector3 = _get_rest_pos("head")
	var launch_local_offset: Vector3 = _world_horizontal_offset_to_local(_torso_head_detach_world_offset)
	return Vector3(rest.x, head_only_ground_socket_y, rest.z) + launch_local_offset


func _apply_torso_head_recoil_pose(body: Node3D, head: Node3D) -> void:
	var duration: float = maxf(torso_head_attack_recoil_duration, 0.001)
	var t: float = 1.0 - clampf(_torso_head_recoil_timer / duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var arc: float = sin(t * PI)
	var pullback: Vector3 = _world_horizontal_offset_to_local(-_torso_head_attack_direction * torso_head_attack_recoil_pullback * arc)
	var current_socket_position: Vector3 = _torso_head_socket_local_position
	if current_socket_position == Vector3.ZERO:
		current_socket_position = _torso_head_recoil_end_local_position
	var local_position: Vector3 = _torso_head_recoil_start_local_position.lerp(current_socket_position, eased)
	head.position = local_position + pullback + Vector3(0.0, torso_head_attack_recoil_arc * arc, 0.0)
	head.rotation = _get_rest_rot("head") + Vector3(-torso_head_attack_roll * arc, 0.0, torso_head_attack_roll * 0.25 * sin(t * TAU))
	body.scale = Vector3(1.0 + arc * 0.06, 1.0 - arc * 0.08, 1.0 + arc * 0.04)
	body.rotation.x += torso_head_attack_coil * 0.22 * arc
	_torso_head_attack_world_offset = _torso_head_attack_direction * torso_head_attack_lunge * (1.0 - eased)


# The swing curve sampled EARLIER by `lag`, so this joint trails whatever drives
# it. Clamped at 0, so a lagging joint simply has not started yet rather than
# reading the windup backwards.
func _attack_strength_lagged(lag: float) -> float:
	if _attack_duration_current <= 0.001:
		return _attack_blend
	return _attack_strike_curve(clampf(_attack_phase() - lag, 0.0, 1.0)) * _attack_blend


# Adds the attack's elbow motion ON TOP of the walk bend _animate_joints assigned.
# Negative strength (the windup) cocks it further; positive (the strike) whips it
# straight. No-ops on an unsplit rig, which has no elbow.
func _whip_elbow(joint_key: String, strength: float) -> void:
	if is_zero_approx(strength):
		return
	var elbow: Node3D = rig.get_socket(joint_key)
	if elbow == null:
		return
	elbow.rotation.x += attack_elbow_whip * strength


func _apply_right_combo_pose(strength: float) -> void:
	# `strength` drives the TORSO — it leads. The shoulder trails it and the elbow
	# trails the shoulder, so the limb drags instead of snapping as one piece.
	var arm_strength: float = _attack_strength_lagged(attack_overlap_arm)
	var elbow_strength: float = _attack_strength_lagged(attack_overlap_arm + attack_overlap_elbow)

	var arm := rig.get_socket("right_arm")
	if arm != null:
		arm.rotation.x -= attack_arm_forward * arm_strength
		arm.rotation.z -= 0.18 * arm_strength
	_whip_elbow("right_arm_lower", elbow_strength)
	var body := rig.get_socket("body")
	if body != null:
		body.rotation.y += attack_torso_twist * strength
		body.rotation.x -= attack_lunge * strength


func _apply_left_combo_pose(strength: float) -> void:
	var arm_strength: float = _attack_strength_lagged(attack_overlap_arm)
	var elbow_strength: float = _attack_strength_lagged(attack_overlap_arm + attack_overlap_elbow)

	var arm := rig.get_socket("left_arm")
	if arm != null:
		arm.rotation.x -= combo_left_arm_forward * arm_strength
		arm.rotation.z += 0.22 * arm_strength
	_whip_elbow("left_arm_lower", elbow_strength)
	var counter_arm := rig.get_socket("right_arm")
	if counter_arm != null:
		counter_arm.rotation.x += attack_arm_forward * 0.25 * arm_strength
	var body := rig.get_socket("body")
	if body != null:
		body.rotation.y -= attack_torso_twist * 0.9 * strength
		body.rotation.x -= attack_lunge * 0.8 * strength


# Combo step 4: the right arm swings the torn-off left arm like a sword.
#
# This is the per-SWING motion only. Holding the arm in the hand is _update_arm_sword,
# because the arm stays off across all three swings while `strength` drops to 0
# between them — riding strength here would snap it home after the first one.
func _apply_arm_sword_pose(strength: float) -> void:
	var arm_strength: float = _attack_strength_lagged(attack_overlap_arm)
	var elbow_strength: float = _attack_strength_lagged(attack_overlap_arm + attack_overlap_elbow)

	var right_arm: Node3D = rig.get_socket("right_arm")
	if right_arm == null:
		return
	right_arm.rotation.x -= arm_sword_swing * arm_strength
	right_arm.rotation.z -= 0.18 * arm_strength
	# The elbow trails hardest here: a rigid stick swinging another rigid stick is
	# the most robotic thing the rig can do.
	_whip_elbow("right_arm_lower", elbow_strength)
	var body: Node3D = rig.get_socket("body")
	if body != null:
		body.rotation.y += arm_sword_torso_twist * strength
		body.rotation.x -= arm_sword_lunge * strength


func is_arm_sword_held() -> bool:
	return _arm_sword_swings > 0


# Counts a swing. The Player keeps feeding step 4 while is_arm_sword_held(), so
# the combo does not advance until the arm has gone back.
func note_arm_sword_swing() -> void:
	_arm_sword_swings += 1
	_arm_sword_idle_timer = 0.0


# Keeps the torn-off arm in the right hand between swings, and puts it back once
# it has landed its swings. Runs every frame — unlike the combo pose, which stops
# being called the moment _attack_blend decays.
func _update_arm_sword(delta: float) -> void:
	if _arm_sword_swings > 0:
		_arm_sword_idle_timer += delta
		var finished: bool = _arm_sword_swings >= arm_sword_swing_count and _attack_timer <= 0.0
		var abandoned: bool = _arm_sword_idle_timer > arm_sword_hold_timeout
		# Release only once the LAST swing has finished playing, not the instant it
		# starts, or the arm snaps home mid-swing.
		if finished or abandoned or not _both_arms_equipped():
			_arm_sword_swings = 0

	var target: float = 1.0 if _arm_sword_swings > 0 else 0.0
	_arm_sword_hold = lerp(_arm_sword_hold, target, 1.0 - exp(-arm_sword_hold_speed * delta))
	if _arm_sword_hold <= 0.001:
		return  # arm is home; leave the normal animator's write alone

	var left_arm: Node3D = rig.get_socket("left_arm")
	if left_arm == null:
		return
	# Read the hand AFTER the swing has been applied this frame, so the blade
	# travels with the arm holding it.
	var hand: Vector3 = _right_hand_rig_position()
	left_arm.position = left_arm.position.lerp(hand, _arm_sword_hold)
	left_arm.rotation = left_arm.rotation.lerp(
		Vector3(arm_sword_blade_pitch, 0.0, 0.0), _arm_sword_hold)


func _both_arms_equipped() -> bool:
	return _is_slot_equipped("right_arm") and _is_slot_equipped("left_arm")


# The right hand — the far end of the forearm — in the left arm socket's parent
# space, which is the rig. Falls back to the whole arm's tip on an unsplit rig,
# where there is no elbow socket.
func _right_hand_rig_position() -> Vector3:
	var forearm: Node3D = rig.get_socket("right_arm_lower")
	if forearm != null:
		return rig.to_local(forearm.global_transform * Vector3(0.0, -0.29, 0.0))
	var arm: Node3D = rig.get_socket("right_arm")
	if arm == null:
		return Vector3.ZERO
	return rig.to_local(arm.global_transform * Vector3(0.0, -0.58, 0.0))


func _apply_finisher_combo_pose(strength: float) -> void:
	var arm_strength: float = _attack_strength_lagged(attack_overlap_arm)
	var elbow_strength: float = _attack_strength_lagged(attack_overlap_arm + attack_overlap_elbow)

	var right_arm := rig.get_socket("right_arm")
	if right_arm != null:
		right_arm.rotation.x -= combo_finisher_arm_forward * arm_strength
		right_arm.rotation.z -= 0.28 * arm_strength
	var left_arm := rig.get_socket("left_arm")
	if left_arm != null:
		left_arm.rotation.x -= combo_finisher_arm_forward * arm_strength
		left_arm.rotation.z += 0.28 * arm_strength
	_whip_elbow("right_arm_lower", elbow_strength)
	_whip_elbow("left_arm_lower", elbow_strength)
	var body := rig.get_socket("body")
	if body != null:
		body.rotation.y += combo_finisher_torso_twist * strength
		body.rotation.x -= combo_finisher_lunge * strength
	var head := rig.get_socket("head")
	if head != null:
		head.rotation.x -= 0.12 * strength


# --- Phase F: foot IK locomotion -----------------------------------------------
#
# Feet are anchored in WORLD space. Each frame: probe the ground under where a
# foot WANTS to be, step it there when it has fallen too far behind, drop the
# pelvis to the average foot height, then solve each leg to reach its anchor.
#
# The plant has to be world-space. A rig-local anchor translates with the capsule
# and yaws with turn_target, so "planted" would not be a constant — that is the
# bug the deleted _place_foot had, and no amount of smoothing fixes it.

# Split player only. The waist joint is the existing discriminator (see
# _animate_waist): the animator is shared with every enemy and has no per-rig
# flag, and only a split rig has the knee socket this solver rotates. The
# head-only and torso-spring gates are "there are no legs equipped".
func _ik_active() -> bool:
	if not ik_feet_enabled or rig == null:
		return false
	if not rig.has_method("get_waist_joint") or rig.call("get_waist_joint") == null:
		return false
	if crawl_mode or _is_head_only() or _is_torso_spring_only():
		return false
	return _demo_mode == DemoMode.OFF


# Rest metrics of one leg, all READ FROM THE CAPTURED REST POSE rather than from
# the rig's layout constants: a gorilla's leg is 0.44 and a lizard's 0.40, so a
# hardcoded 0.31 would be silently wrong the day either of them is split.
func _ik_leg_chain(foot_key: String) -> Dictionary:
	var leg_key: String = IK_LEG_OF_FOOT[foot_key]
	var lower_key: String = leg_key + "_lower"
	var rest_foot: Vector3 = _get_rest_pos(foot_key)
	return {
		"leg": leg_key,
		"lower": lower_key,
		"thigh": _get_rest_pos(lower_key).length(),
		"shin": rest_foot.length(),
		# The rest shin is NOT collinear with the thigh: the ankle sits at
		# (0,-0.27,0.06), tilting it ~12.5 deg FORWARD. So knee.rotation.x = 0 is a
		# slightly broken knee, and the +X hinge STRAIGHTENS it before it bends it.
		# This offset is what makes "PI - interior angle" mean a real bend.
		"knee_rest": atan2(rest_foot.z, -rest_foot.y),
		# Rig-local Y the ankle sits at when standing, used as the pelvis baseline.
		"ankle_rest_y": _get_rest_pos(leg_key).y + _get_rest_pos(lower_key).y + rest_foot.y,
	}


func _update_foot_ik(delta: float) -> void:
	if not _ik_active():
		_ik_ready = false
		_ik_grounded_prev = false
		_ik_leap_pitch = 0.0
		_ik_leap_lift = 0.0
		_ik_pelvis_dy = 0.0
		_ik_pelvis_lean = 0.0
		_ik_pelvis_follow = Vector3.ZERO
		_ik_follow_fast = Vector3.ZERO
		_ik_follow_slow = Vector3.ZERO
		_ik_transition = 0.0
		_ik_velocity_prev = _ik_velocity
		return
	if _body == null:
		_body = _find_body()

	# TRANSITION signal: how hard the movement just changed — a brake, a turn, a
	# reversal all spike it. Held with a slow decay so it stays up through the
	# feet's catch-up, and read by the magnet to damp its overshoot during any of
	# them (the speed-only damping missed turns/reversals, which happen at speed).
	var accel: float = (_ik_velocity - _ik_velocity_prev).length()
	_ik_velocity_prev = _ik_velocity
	_ik_transition = maxf(_ik_transition * exp(-ik_magnet_transition_decay * delta),
		clampf(accel / maxf(ik_magnet_transition_thresh, 0.001), 0.0, 1.0))
	for foot_key in FOOT_KEYS:
		if rig.get_socket(foot_key) == null or rig.get_socket(IK_LEG_OF_FOOT[foot_key] + "_lower") == null:
			return  # unsplit or mid-rebuild: leave the FK pose alone

	# _apply_pelvis_carry (+=) and _apply_waist_carry (rotate-in-place) both need
	# these sockets' positions ASSIGNED from rest earlier in the same frame or they
	# compound frame over frame. With the wobble on, its position assign is that
	# reset; with it off nothing writes the four limb sockets, and the carry sent an
	# arm 200 m off the rig in 10 s (measured). Re-base them here in that case —
	# exactly the assign the wobble would have made with zero slide.
	if not wobble_enabled:
		for key in ["right_arm", "left_arm", "right_leg", "left_leg"]:
			var s: Node3D = rig.get_socket(key)
			if s != null and _rest_pos.has(key):
				s.position = _get_rest_pos(key)

	_ik_velocity = Vector3(_ik_velocity.x, 0.0, _ik_velocity.z)
	if not _ik_ready:
		_ik_reset_plants()

	var grounded: bool = _body is CharacterBody3D and (_body as CharacterBody3D).is_on_floor()
	if grounded and not _ik_grounded_prev:
		_ik_land_plants()
	_ik_grounded_prev = grounded
	if grounded:
		_ik_update_steps(delta)
	else:
		# Airborne: nothing to plant on. Hang the feet under the hips and carry them
		# with the rig, or they stretch toward the ground the jump just left.
		_ik_stepping = ""
		for foot_key in FOOT_KEYS:
			_ik_step_t[foot_key] = 1.0
			_ik_plant[foot_key] = (_ik_plant[foot_key] as Vector3).lerp(
				_ik_hang_world(foot_key), 1.0 - exp(-ik_foot_response * delta))
			_ik_plant_normal[foot_key] = Vector3.UP

	_ik_update_leap(delta)
	_ik_update_pelvis(delta, grounded)
	_apply_pelvis_carry()
	# The plants are chosen; the hips have just moved. Solve each leg to the plant,
	# but never past what the leg can reach on the ground: at a run the body demands
	# a stride longer than the leg is (0.32 m reach vs a 1.4 m demand at 6 m/s), so
	# above that ceiling the planted foot SKATES forward rather than floating up
	# toward an unreachable target. Below it the clamp never bites and the foot is
	# genuinely nailed down.
	for foot_key in FOOT_KEYS:
		var goal: Vector3
		if ik_foot_magnet:
			goal = _ik_magnet_foot(foot_key, _ik_foot_world(foot_key), delta)
		else:
			goal = _ik_reachable_target(foot_key)
		_ik_solve_leg(foot_key, goal, _ik_foot_normal(foot_key), delta)


# Where a foot rides when there is no ground under it: straight down from its hip
# at the standing ankle depth.
func _ik_hang_world(foot_key: String) -> Vector3:
	var chain: Dictionary = _ik_leg_chain(foot_key)
	var leg_rest: Vector3 = _get_rest_pos(chain["leg"])
	return rig.to_global(Vector3(leg_rest.x, float(chain["ankle_rest_y"]) + _ik_pelvis_dy, leg_rest.z))


# Landing edge. The airborne hang leaves each plant wherever the fall's smoothing
# got it — ~v/14 m above the floor after landing at v — and NOTHING else restores
# plant Y: steps fire on XZ error alone, so a standing landing never steps and the
# skeleton would stand on air indefinitely (measured: both feet 0.23 m up, forever,
# after a 5 m/s fall). Snapping the plants straight to ground instead dropped the
# foot sockets 0.44 m in ONE frame (adversarial review, measured). So the landing
# is a CATCH: each foot arcs from wherever the fall left it down to the probed
# ground as a normal step — the legs visibly reach down to take the weight.
func _ik_land_plants() -> void:
	for foot_key in FOOT_KEYS:
		var plant: Vector3 = _ik_plant[foot_key]
		var ground: Dictionary = _ik_probe_ground(plant)
		if ground.is_empty():
			ground = _ik_probe_ground(_ik_anchor_world(foot_key, false))
		_ik_step_from[foot_key] = plant
		_ik_step_to[foot_key] = ground.get("position", _ik_anchor_world(foot_key, false)) as Vector3
		_ik_step_to_normal[foot_key] = ground.get("normal", Vector3.UP) as Vector3
		_ik_step_t[foot_key] = 0.0
	# Mark one catch as the newest swing so the leap cycle plays its landing
	# compression while the feet come down.
	_ik_stepping = _ik_next_foot
	_ik_next_foot = _ik_other_foot(_ik_next_foot)


func _ik_reset_plants() -> void:
	_ik_stepping = ""
	_ik_pelvis_dy = -ik_hip_drop
	for foot_key in FOOT_KEYS:
		var anchor: Vector3 = _ik_anchor_world(foot_key, false)
		var ground: Dictionary = _ik_probe_ground(anchor)
		_ik_plant[foot_key] = ground.get("position", anchor) as Vector3
		_ik_plant_normal[foot_key] = ground.get("normal", Vector3.UP) as Vector3
		_ik_step_t[foot_key] = 1.0
		_ik_step_from[foot_key] = _ik_plant[foot_key]
		_ik_step_to[foot_key] = _ik_plant[foot_key]
		_ik_step_to_normal[foot_key] = _ik_plant_normal[foot_key]
		# Seed the magnet at the foot's CURRENT world spot, not the plant, so a
		# re-activation (e.g. head-only → full body when the torso is equipped)
		# springs the foot IN toward the plant at the capped speed instead of the
		# leg snapping to it in one frame (measured 0.56 m jump when seeded at the
		# plant). On a fresh spawn the socket already sits near the plant, so this
		# is a no-op there.
		var foot_node: Node3D = rig.get_socket(foot_key)
		if foot_node != null and is_finite(foot_node.global_position.x) and is_finite(foot_node.global_position.y) and is_finite(foot_node.global_position.z):
			_ik_foot_pos[foot_key] = foot_node.global_position
		else:
			_ik_foot_pos[foot_key] = _ik_plant[foot_key]
		_ik_foot_vel[foot_key] = Vector3.ZERO
	_ik_ready = true


# Where this foot WANTS to be: OUTBOARD of its hip's rest spot by ik_stance_width
# (deliberately not directly under the hip), in world space, optionally thrown
# forward so a step lands ahead of the body. Reads the hip's REST, not its live
# position, so the anchor does not inherit the wobble it is independent of.
func _ik_anchor_world(foot_key: String, with_lead: bool) -> Vector3:
	var chain: Dictionary = _ik_leg_chain(foot_key)
	var leg_rest: Vector3 = _get_rest_pos(chain["leg"])
	var rest_foot: Vector3 = _get_rest_pos(foot_key)
	# Push outward along the hip's own side (right_leg sits at +X, left at −X), so
	# each foot widens away from the centreline rather than toward it. The width
	# BLENDS between two stances rather than fading to zero: idle_stance_width is
	# the spread ready-stance the author asked for when still, ik_stance_width is
	# the moving one. Changing speed re-aims the anchor, the old plants exceed the
	# step trigger, and the feet re-settle on their own — no extra machinery.
	var stance_engage: float = clampf(speed_ratio * 2.5, 0.0, 1.0)
	var idle_w: float = idle_stance_width if (idle_stance_enabled and _ik_active()) else 0.0
	var width: float = lerpf(idle_w, ik_stance_width, stance_engage)
	var side: float = signf(leg_rest.x) if not is_zero_approx(leg_rest.x) else 1.0
	var anchor_x: float = leg_rest.x + side * width
	# Standing feet sit at idle_foot_forward (under the hips by default); moving
	# feet keep the socket's natural forward offset. Blended by the same ramp so
	# stopping re-settles the feet back under the body on its own.
	var foot_fwd: float = lerpf(idle_foot_forward, rest_foot.z, stance_engage) if _ik_active() else rest_foot.z
	var anchor: Vector3 = rig.to_global(Vector3(anchor_x, float(chain["ankle_rest_y"]), leg_rest.z + foot_fwd))
	if with_lead and _ik_velocity.length() > 0.05:
		# Ahead by ik_stride_lead LAUNCH-INTERVAL travels — what the capsule
		# covers per step, NOT per swing. With overlap the swing lasts longer
		# than the launch interval, and scaling the lead by swing duration threw
		# every plant ~50% too far ahead: metre-long swings (measured), faster
		# feet, and over-thrown plants dragged back from out of reach. 1.5 lands
		# the plant ~half a stride ahead of the moving anchor and lets it drift
		# ~half a stride behind — the plants straddle the capsule.
		var launch_travel: float = _ik_velocity.length() * _ik_step_duration_now() \
			* (1.0 - clampf(ik_step_overlap, 0.0, 0.9))
		anchor += _ik_velocity.normalized() * (launch_travel * ik_stride_lead)
	return anchor


# Spherecast straight down. A sphere is what the user asked for and it is the
# right shape: a ray drops into cracks and off ledge edges that a foot would
# actually bridge.
func _ik_probe_ground(around: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return {}
	if _ik_probe_shape == null:
		_ik_probe_shape = SphereShape3D.new()
	_ik_probe_shape.radius = maxf(ik_probe_radius, 0.005)

	var base_y: float = rig.global_position.y
	var start := Vector3(around.x, base_y + ik_probe_up, around.z)
	var motion := Vector3(0.0, -(ik_probe_up + ik_probe_down), 0.0)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _ik_probe_shape
	query.transform = Transform3D(Basis(), start)
	query.motion = motion
	if _body != null:
		query.exclude = [_body.get_rid()]

	var span: Array = world.direct_space_state.cast_motion(query)
	if span.size() < 2 or float(span[0]) >= 1.0:
		return {}  # nothing under the foot within the sweep

	# The sphere stops one radius above the surface, so the contact is a radius
	# below its centre. get_rest_info at the UNSAFE fraction (where it is just
	# touching) refines that to the real point and gives us the slope.
	var centre: Vector3 = start + motion * float(span[0])
	var result := {
		"position": Vector3(centre.x, centre.y - _ik_probe_shape.radius, centre.z),
		"normal": Vector3.UP,
	}
	query.transform = Transform3D(Basis(), start + motion * float(span[1]))
	query.motion = Vector3.ZERO
	var rest := world.direct_space_state.get_rest_info(query)
	if not rest.is_empty():
		result["position"] = rest["point"]
		result["normal"] = rest["normal"]
	return result


# Each stride is a little LEAP driven by the newest swing's clock: pelvis lift
# is a ballistic parabola over the swing, and the chest pitches UP at push-off
# then eases through to slightly DOWN as the foot touches — the "chest and
# waist compress" landing. Both are zero the moment no foot is in flight and
# fade out entirely at creep speeds, so idle and slow shuffles stay quiet.
func _ik_update_leap(delta: float) -> void:
	# The foot CLOSEST to touchdown drives the cycle. With overlap a new swing
	# launches before the old one lands; keying on the NEWEST swing snapped the
	# pitch back to "up" right before every touchdown, so the compression never
	# played (measured: pitch never passed -8 deg). Keying on max t makes the
	# compression land exactly with the foot — and turns the driver into a
	# sawtooth at each handoff, which is why BOTH outputs are smoothed here.
	var t := -1.0
	for k in FOOT_KEYS:
		if float(_ik_step_t[k]) < 1.0:
			t = maxf(t, float(_ik_step_t[k]))
	var engage: float = clampf(speed_ratio * 2.5, 0.0, 1.0)
	var lift_target := 0.0
	var pitch_target := 0.0
	if t >= 0.0:
		# The tail taper drives the TARGET to zero well before touchdown so the
		# SMOOTHED lift is already low when the plant lands — otherwise its lag
		# hands the landing a pelvis that is still airborne-high, and the
		# landing snap has to eat the difference (which compressed the visible
		# jump amplitude and, past ~0.2, dragged plants).
		lift_target = ik_leap_height * 4.0 * t * (1.0 - t) * engage \
			* (1.0 - smoothstep(0.72, 0.96, t))
		# Up through the launch, compressing from mid-flight into the touch.
		var settle: float = smoothstep(0.25, 1.0, t)
		pitch_target = lerpf(-deg_to_rad(ik_leap_pitch_up_deg), deg_to_rad(ik_leap_pitch_down_deg), settle) * engage
	_ik_leap_lift = lerpf(_ik_leap_lift, lift_target, 1.0 - exp(-ik_leap_pitch_response * 1.4 * delta))
	_ik_leap_pitch = lerpf(_ik_leap_pitch, pitch_target, 1.0 - exp(-ik_leap_pitch_response * delta))


# Swings OVERLAP: the next may launch while the previous is landing, with
# ik_step_overlap of it still to go. The launch ORDER is still strictly
# alternating ("make each leg move after the other"); what the overlap buys is
# airtime — each swing lasts 1/(1-overlap) longer at the same ground coverage,
# which is what stops the feet reading as teleports at speed. _ik_stepping is
# the NEWEST swing (the follow weights key on it); the older one is always
# further along and completes first.
func _ik_update_steps(delta: float) -> void:
	# BRAKE SETTLE. Near a standstill, gently SLIDE each planted foot to its idle
	# anchor instead of letting the trigger fire a discrete adjustment step — the
	# step-then-magnet-catch-up is what read as "feet adjust too much" when
	# braking. The slide shrinks the step error, so no settle step fires; the
	# magnet just follows the drifting plant. Only near rest, so a real stride is
	# never slid (that would be skate).
	if ik_idle_settle_enabled and speed_ratio < ik_idle_settle_speed:
		var k: float = 1.0 - exp(-ik_idle_settle_rate * delta)
		for foot_key in FOOT_KEYS:
			if float(_ik_step_t[foot_key]) >= 1.0:
				# Slide ONLY on the ground plane (XZ) — the anchor's Y is a rig-rest
				# height, not the probed ground, so lerping Y too sank the foot ~8 mm
				# on flat ground and would pull it to the wrong altitude on a slope/
				# step. The plant keeps its own ground Y; only re-centres horizontally.
				var cur: Vector3 = _ik_plant[foot_key]
				var slid: Vector3 = cur.lerp(_ik_anchor_world(foot_key, false), k)
				_ik_plant[foot_key] = Vector3(slid.x, cur.y, slid.z)

	var dur: float = maxf(_ik_step_duration_now(), 0.001)
	for foot_key in FOOT_KEYS:
		if float(_ik_step_t[foot_key]) >= 1.0:
			continue
		var t: float = float(_ik_step_t[foot_key]) + delta / dur
		_ik_step_t[foot_key] = minf(t, 1.0)
		if t >= 1.0:
			_ik_plant[foot_key] = _ik_step_to[foot_key]
			_ik_plant_normal[foot_key] = _ik_step_to_normal[foot_key]
			_ik_next_foot = _ik_other_foot(foot_key)
			if _ik_stepping == foot_key:
				_ik_stepping = ""
			_ik_snap_dip_for_landing(foot_key)

	# The launch gate: the newest swing must be far enough into its landing.
	if _ik_stepping != "" and float(_ik_step_t[_ik_stepping]) < 1.0 - clampf(ik_step_overlap, 0.0, 0.9):
		return

	# Whoever is furthest from home goes first, but a foot may not go twice in a
	# row while the other is also overdue, and a foot already in flight may not
	# be picked again. The trigger stays loose through the brake now (the settle
	# SLIDE above centres the feet without a step); the idle floor is only a
	# backstop for drift the slide has not caught.
	var trigger: float = lerpf(ik_idle_step_trigger, ik_step_trigger, clampf(speed_ratio * 2.5, 0.0, 1.0))
	var candidates: Array = []
	for foot_key in FOOT_KEYS:
		if float(_ik_step_t[foot_key]) < 1.0:
			continue
		var err: float = _ik_step_error(foot_key)
		if err > trigger:
			candidates.append([err, foot_key])
	if candidates.is_empty():
		return
	var pick: String = String(candidates[0][1])
	if candidates.size() > 1:
		pick = _ik_next_foot
	elif pick != _ik_next_foot and float(_ik_step_t[_ik_next_foot]) >= 1.0 and _ik_step_error(_ik_next_foot) > trigger * 0.5:
		# The other leg is nearly overdue too — let it take its turn first so the
		# alternation does not slip a beat.
		pick = _ik_next_foot
	_ik_begin_step(pick)


func _ik_other_foot(foot_key: String) -> String:
	return "left_foot" if foot_key == "right_foot" else "right_foot"


# The cadence is coupled to speed through the leg's real stride: one step may
# cover at most ik_step_reach of capsule travel, so duration = reach / speed.
# A fixed duration lets a fast capsule advance further per step than the leg can
# express — the plants then trail permanently and the body devolves into a glide
# no matter how the follow is computed. This coupling is what keeps the feet
# CENTRED on the capsule, which is what lets the body ride them raw.
func _ik_step_duration_now() -> float:
	var speed: float = _ik_velocity.length()
	if speed <= 0.01:
		return ik_step_duration
	# With overlap, launches happen every duration*(1-overlap), so the coverage
	# constraint is on the LAUNCH interval — the swing itself gets the rest as
	# extra airtime. At a 6 m/s sprint this also lifts the duration off its floor
	# (0.082 s vs a floor-clamped 0.06), which removed the sprint's trailing.
	var launch_share: float = 1.0 - clampf(ik_step_overlap, 0.0, 0.9)
	return clampf(ik_step_reach / (speed * launch_share), ik_step_duration_min, ik_step_duration)


# How far the plant has drifted from where the foot wants to be, on the ground
# plane. Y is excluded: a slope must not fire a step by itself.
func _ik_step_error(foot_key: String) -> float:
	var anchor: Vector3 = _ik_anchor_world(foot_key, false)
	var plant: Vector3 = _ik_plant[foot_key]
	return Vector2(anchor.x - plant.x, anchor.z - plant.z).length()


func _ik_begin_step(foot_key: String) -> void:
	var target: Vector3 = _ik_anchor_world(foot_key, true)
	var ground: Dictionary = _ik_probe_ground(target)
	_ik_step_from[foot_key] = _ik_plant[foot_key]
	_ik_step_to[foot_key] = ground.get("position", target) as Vector3
	_ik_step_to_normal[foot_key] = ground.get("normal", Vector3.UP) as Vector3
	_ik_step_t[foot_key] = 0.0
	_ik_stepping = foot_key


# The plant, or the arc a stepping foot is currently riding along it. The arc is
# shaped to read as the user's walk cycle rather than a symmetric hop:
#   - the LIFT peaks early (t~0.35): the knee comes forward and UP first, because a
#     raised foot still near its hip forces a deep forward knee bend in the solver;
#   - the forward travel is BACK-LOADED (pow 1.6): the foot hangs back while it
#     lifts, then EXTENDS down-and-forward to plant, straightening the knee — the
#     "downward diagonal extension" reach.
func _ik_foot_world(foot_key: String) -> Vector3:
	var t: float = float(_ik_step_t[foot_key])
	if t >= 1.0:
		return _ik_plant[foot_key]
	var forward_t: float = _swing_forward_curve(t)
	var flat: Vector3 = (_ik_step_from[foot_key] as Vector3).lerp(_ik_step_to[foot_key], forward_t)
	# Eased through smoothstep FIRST: pow(t,0.7) alone has infinite slope at t=0,
	# which popped the foot ~7 cm upward on the first frame of every step — the
	# single biggest per-frame jump in the whole gait (measured). The 0.6 exponent
	# keeps the lift peaking early (t≈0.37) so the knee still leads up-and-forward.
	var lift: float = sin(pow(smoothstep(0.0, 1.0, t), 0.6) * PI) * ik_step_height
	# Forward reach overshoot: bulge the swing foot ahead along the rig's FACING
	# (+Z for this rig, which _animate_facing keeps aimed at the movement), scaled
	# by speed so it only appears when actually moving. Zero at both ends of the
	# swing, so the plant is untouched: no skate, no collapse.
	#
	# THE CURVE MATTERS MORE THAN THE MAGNITUDE. The first version used
	# sin(pow(t,0.8)*PI), and pow with an exponent BELOW 1 has an INFINITE
	# derivative at t=0 — the reach snapped on ~0.12 m in a single frame at every
	# swing start, which measured as a 3x-body-speed spike and read as the feet
	# teleporting (author-reported). Same trap as the old pow(t,0.7) lift. Fix:
	# feed a smoothstep (zero slope at both ends) and use an exponent ABOVE 1,
	# which both keeps the start smooth AND skews the peak LATE (~t=0.55, so the
	# leg is at full forward extension on the way DOWN into the plant — 0.8
	# actually peaked EARLY, at 0.42, the opposite of what was wanted).
	if ik_stride_reach_boost > 0.0001 and speed_ratio > 0.05:
		var fwd: Vector3 = rig.global_basis.z
		fwd.y = 0.0
		if fwd.length() > 0.01:
			var u: float = pow(smoothstep(0.0, 1.0, t), 1.3)
			flat += fwd.normalized() * (sin(u * PI) * ik_stride_reach_boost * speed_ratio)
	return flat + Vector3.UP * lift


# A landing must be reachable on the frame it happens. The smoothed leap lift
# lags its zero-at-touchdown target by a few frames, and a pelvis that is still
# high when the plant arrives hands the fresh plant straight to the skate guard
# (measured: 7% slide at leap height 0.18, with visible backward drag pops).
# Snapping the dip down at the landing event is the compression thud of
# absorbing a jump — the smoothed dip then recovers on its own slow rate.
func _ik_snap_dip_for_landing(foot_key: String) -> void:
	var chain: Dictionary = _ik_leg_chain(foot_key)
	var leg_rest: Vector3 = _get_rest_pos(chain["leg"])
	var foot_l: Vector3 = rig.to_local(_ik_plant[foot_key])
	var hip_x: float = leg_rest.x + _ik_pelvis_follow.x
	var hip_z: float = leg_rest.z + _ik_pelvis_follow.z + _ik_pelvis_lean
	var spread: float = Vector2(foot_l.x - hip_x, foot_l.z - hip_z).length()
	var leg_len: float = (float(chain["thigh"]) + float(chain["shin"])) * 0.96
	var vert_avail: float = sqrt(maxf(leg_len * leg_len - spread * spread, 0.0009))
	var span: float = leg_rest.y - foot_l.y
	var needed: float = vert_avail - span - _ik_leap_lift
	if needed < _ik_pelvis_dy:
		_ik_pelvis_dy = maxf(needed, -(ik_hip_drop_moving + ik_stride_dip + ik_max_drop))


# Trapezoid velocity for the swing, slightly back-loaded: ease in 25% (the foot
# hangs back while it lifts — the authored look), CRUISE, ease out 18% into the
# plant. An eased hump peaks at ~1.6x the average speed; this peaks at ~1.27x,
# and with the strides mostly airborne that peak is exactly the per-frame foot
# jump the eye reads — the foot SAILS with the leap instead of whipping past it.
func _swing_forward_curve(t: float) -> float:
	var e_in := 0.25
	var e_out := 0.18
	var norm: float = 1.0 - (e_in + e_out) * 0.5
	if t < e_in:
		return (t * t) / (2.0 * e_in) / norm
	if t <= 1.0 - e_out:
		return (e_in * 0.5 + (t - e_in)) / norm
	var tail: float = t - (1.0 - e_out)
	return (e_in * 0.5 + (1.0 - e_in - e_out) + tail - (tail * tail) / (2.0 * e_out)) / norm


func _ik_foot_normal(foot_key: String) -> Vector3:
	var t: float = float(_ik_step_t[foot_key])
	if t >= 1.0:
		return _ik_plant_normal[foot_key]
	return (_ik_plant_normal[foot_key] as Vector3).lerp(_ik_step_to_normal[foot_key], t).normalized()


# MAGNET: the foot is a critically-ish-damped spring chasing `target`. It reaches
# a still, in-range target (so a planted foot touches the ground and holds) but
# lags and overshoots while moving — the loose cartoon foot. The result is then
# clamped to the leg's reach: an out-of-reach target leaves the foot stretched to
# the limit REACHING toward it, never dragging a plant, so there is no skate to
# fight — the reach shortfall just reads as a stretch. Returns the world position
# the leg should solve to.
func _ik_magnet_foot(foot_key: String, target: Vector3, delta: float) -> Vector3:
	var pos: Vector3 = _ik_foot_pos.get(foot_key, target)
	var vel: Vector3 = _ik_foot_vel.get(foot_key, Vector3.ZERO)
	# Semi-implicit spring: a = k*(target - pos) - c*vel. Integrate at a capped
	# sub-step so a spike in delta (a stall) cannot blow the spring up. Damping
	# rises toward critical as the character slows, so the stop does not overshoot.
	var h: float = minf(delta, 1.0 / 60.0)
	# Damp toward critical when SLOW (brake settle) OR mid-TRANSITION (turn/
	# reversal), so the spring never overshoots a target that just jumped; stays
	# bouncy only in steady motion.
	var settle: float = maxf(clampf(1.0 - speed_ratio * 2.0, 0.0, 1.0), _ik_transition)
	var damp: float = lerpf(ik_magnet_damping, ik_magnet_damping_idle, settle)
	var accel: Vector3 = (target - pos) * ik_magnet_stiffness - vel * damp
	vel += accel * h
	vel = vel.limit_length(ik_foot_max_speed)  # ceiling so a whipped target can't snap the foot
	pos += vel * h
	# Reach clamp: keep the ankle within the leg of the hip. Kill only the OUTWARD
	# velocity at the limit so the spring can still slide the foot along the reach
	# sphere toward the target instead of jamming.
	var chain: Dictionary = _ik_leg_chain(foot_key)
	var hip: Node3D = rig.get_socket(chain["leg"])
	if hip != null:
		var reach: float = (float(chain["thigh"]) + float(chain["shin"])) * 0.99
		var d: Vector3 = pos - hip.global_position
		var dist: float = d.length()
		if dist > reach and dist > 0.0001:
			var n: Vector3 = d / dist
			pos = hip.global_position + n * reach
			var outward: float = vel.dot(n)
			if outward > 0.0:
				vel -= n * outward
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		pos = target
		vel = Vector3.ZERO
	_ik_foot_pos[foot_key] = pos
	_ik_foot_vel[foot_key] = vel
	return pos


# The foot's world target, pulled back onto ground the leg can actually reach. A
# stepping foot is left alone — it is following its own arc and is meant to lift.
# Only a planted foot the body has overrun gets dragged, and only on the ground
# plane so its height is untouched.
func _ik_reachable_target(foot_key: String) -> Vector3:
	var target: Vector3 = _ik_foot_world(foot_key)
	if float(_ik_step_t[foot_key]) < 1.0:
		return target  # in flight: following its own arc, meant to lift
	var chain: Dictionary = _ik_leg_chain(foot_key)
	var hip: Node3D = rig.get_socket(chain["leg"])
	if hip == null:
		return target
	var reach: float = (float(chain["thigh"]) + float(chain["shin"])) * 0.99
	var hip_w: Vector3 = hip.global_position
	var vert: float = hip_w.y - target.y
	# Horizontal distance the leg still has once it has spent length on the drop.
	var horiz: float = sqrt(maxf(reach * reach - vert * vert, 0.0004))
	var flat := Vector2(target.x - hip_w.x, target.z - hip_w.z)
	if flat.length() <= horiz:
		return target
	flat = flat.normalized() * horiz
	var dragged := Vector3(hip_w.x + flat.x, target.y, hip_w.z + flat.y)
	# Move the stored plant too, so the skate is a genuine world position the next
	# step error measures against — not a per-frame illusion the anchor forgets.
	_ik_plant[foot_key] = dragged
	return dragged


# "Use average feet position for leg and body position." The pelvis rides the mean
# of the two feet, RELATIVE to the flat-ground standing baseline — never as an
# absolute world height, which would pin the torso to a fixed altitude and leave
# it on the ground during a jump. ik_hip_drop is folded in here because it is the
# same quantity: how far the pelvis sits below its straight-legged rest.
# The crouch the gait is currently using: tall when standing (legs near-straight,
# a normal stand — author-directed), sinking to ik_hip_drop_moving once moving so
# the legs have the bend a real stance needs. Same quick ramp as the stance width
# and the leap, so all three engage together.
func _ik_hip_drop_now() -> float:
	return lerpf(ik_hip_drop, ik_hip_drop_moving, clampf(speed_ratio * 2.5, 0.0, 1.0))


func _ik_update_pelvis(delta: float, grounded: bool) -> void:
	var target: float = -_ik_hip_drop_now()
	var lean_target := 0.0
	var follow_target := Vector3.ZERO
	if grounded:
		var sum := 0.0
		var rest_sum := 0.0
		var feet_flat := Vector3.ZERO
		var rest_flat := Vector3.ZERO
		var w_swing: float = 0.5 + clampf(ik_step_drive, 0.0, 1.0) * 0.5
		for foot_key in FOOT_KEYS:
			var chain: Dictionary = _ik_leg_chain(foot_key)
			sum += rig.to_local(_ik_plant[foot_key]).y
			rest_sum += float(chain["ankle_rest_y"])
			# Where the feet ARE (the mid-step arc counts: the surge should build
			# through the swing, not pop when it plants) vs where they'd rest. The
			# swinging foot gets the lion's share of the weight — its reach is what
			# drags the torso, which is the whole feet-driven read — and the weights
			# are applied to the rest side too, so follow stays 0 at rest exactly.
			var w := 0.5
			if _ik_stepping == foot_key:
				w = w_swing
			elif _ik_stepping != "":
				w = 1.0 - w_swing
			var foot_now: Vector3 = rig.to_local(_ik_foot_world(foot_key))
			var leg_rest: Vector3 = _get_rest_pos(chain["leg"])
			feet_flat += w * Vector3(foot_now.x, 0.0, foot_now.z)
			rest_flat += w * Vector3(leg_rest.x, 0.0, leg_rest.z + _get_rest_pos(foot_key).z)
		var mean_offset: float = (sum - rest_sum) / float(FOOT_KEYS.size())
		target = clampf(mean_offset, -ik_max_drop, 0.0) - _ik_hip_drop_now()
		# Lean the hips forward into the movement so the reaching foot can plant
		# ahead of the body — the "movement comes from the feet, not the hips" read.
		lean_target = ik_run_lean * speed_ratio
		# The horizontal half of "use average feet position for body position": the
		# capsule glides at constant speed, so an un-offset body IS hip-led motion.
		# Riding the (weighted) feet makes the body's world motion pulse with the
		# steps instead — the weights sum to 1, so no division here.
		follow_target = (feet_flat - rest_flat) * clampf(ik_body_follow, 0.0, 1.0)

	_ik_pelvis_lean = lerp(_ik_pelvis_lean, lean_target, 1.0 - exp(-ik_pelvis_response * delta))
	# Fast minus slow: the same signal through two smoothings. The steady trail
	# the plants always have behind the capsule lives in BOTH and cancels; the
	# per-step pulse only lives in the fast one and survives. Clamp AFTER the
	# difference — the raw signal may sit past the clamp, the pulse never should.
	# This runs BEFORE the stride dip so the dip measures spreads against where
	# the hips are GOING this frame, not where they were — at each step handoff
	# the follow target jumps, and an estimator one frame behind under-dips
	# exactly when the leading leg is longest.
	_ik_follow_fast = _ik_follow_fast.lerp(follow_target, 1.0 - exp(-ik_body_follow_response * delta))
	_ik_follow_slow = _ik_follow_slow.lerp(follow_target, 1.0 - exp(-ik_body_follow_recenter * delta))
	_ik_pelvis_follow = (_ik_follow_fast - _ik_follow_slow).limit_length(ik_body_follow_max)

	if grounded:
		# STRIDE DIP — what buys strides past the standing envelope. When a leg's
		# horizontal spread would put its plant out of reach, the pelvis gives
		# vertically by exactly the shortfall (up to ik_stride_dip): geometry, not
		# style. dy must satisfy sqrt(x^2 + (span + dy)^2) <= L, hence
		# dy <= sqrt(L^2 - x^2) - span. Released as the legs come back under the
		# body, it reads as weight transfer.
		var dip_needed := 0.0
		for foot_key in FOOT_KEYS:
			# PLANTED feet only. Including in-flight feet made the estimator
			# subtract the leap lift every frame, so the pelvis dipped by exactly
			# the jump height and the jump knob visibly did nothing
			# (author-reported). A mid-flight foot that cannot reach its arc just
			# clamps in the solve — a tucked leg under a jump. A PLANTED foot is
			# the one the skate guard would drag (measured 27% slide without this
			# clause), and at touchdown the lift is near zero anyway, so
			# protecting only plants keeps the feet honest without cancelling
			# the jump.
			if float(_ik_step_t[foot_key]) < 1.0:
				continue
			var chain: Dictionary = _ik_leg_chain(foot_key)
			var leg_rest: Vector3 = _get_rest_pos(chain["leg"])
			var foot_l: Vector3 = rig.to_local(_ik_foot_world(foot_key))
			var hip_x: float = leg_rest.x + _ik_pelvis_follow.x
			var hip_z: float = leg_rest.z + _ik_pelvis_follow.z + _ik_pelvis_lean
			var spread: float = Vector2(foot_l.x - hip_x, foot_l.z - hip_z).length()
			# 0.96 vs the skate guard's 0.99: the dip estimator must be CONSERVATIVE
			# relative to the guard, or the pelvis arrives exactly at the drag
			# threshold and smoothing jitter tips half the strides into a slide.
			var leg_len: float = (float(chain["thigh"]) + float(chain["shin"])) * 0.96
			var vert_avail: float = sqrt(maxf(leg_len * leg_len - spread * spread, 0.0009))
			var span: float = leg_rest.y - foot_l.y  # vertical hip->plant at zero dy
			dip_needed = minf(dip_needed, vert_avail - span - _ik_leap_lift)
		target = minf(target, maxf(dip_needed, target - ik_stride_dip))

	# Asymmetric: the dip DROPS fast and RISES slow. Reach is needed the frame the
	# legs scissor apart — a symmetric τ of ~0.1 s arrives after the skate guard
	# has already dragged the plant (measured: 9.5% skate at 2.5 m/s from lag
	# alone) — while the recovery between strides can afford to be graceful.
	var dy_rate: float = ik_pelvis_response * (3.0 if target < _ik_pelvis_dy else 0.8)
	_ik_pelvis_dy = lerp(_ik_pelvis_dy, target, 1.0 - exp(-dy_rate * delta))


# The one pelvis offset every consumer shares: the vertical ride (dy), the forward
# lean, and the feet-follow. The waist carry reads this too, so the bend pivots on
# the waist plane wherever the pelvis actually is.
func _ik_pelvis_offset() -> Vector3:
	return Vector3(_ik_pelvis_follow.x, _ik_pelvis_dy + _ik_leap_lift, _ik_pelvis_follow.z + _ik_pelvis_lean)


# Stands in for the pelvis parent this rig does not have. Every socket is a child
# of the RIG, so moving the body socket alone would dip the chest and leave the
# hips, head and arms standing — the figure would tear at the waist. +Z is this
# rig's forward, so the lean pushes the whole upper body over the planted feet.
func _apply_pelvis_carry() -> void:
	var offset: Vector3 = _ik_pelvis_offset()
	if offset.length_squared() < 0.0000001:
		return
	for key in IK_PELVIS_CARRIED:
		var socket: Node3D = rig.get_socket(key)
		if socket != null:
			socket.position += offset


# Two-bone analytic IK in RIG-LOCAL space, honouring the DOF the sockets actually
# have: the hip is pitch+roll, the knee is a pure sagittal hinge (rotation.x) —
# that is all there is to rotate.
func _ik_solve_leg(foot_key: String, target_world: Vector3, ground_normal: Vector3, delta: float) -> void:
	var chain: Dictionary = _ik_leg_chain(foot_key)
	var hip: Node3D = rig.get_socket(chain["leg"])
	var knee: Node3D = rig.get_socket(chain["lower"])
	var foot: Node3D = rig.get_socket(foot_key)
	if hip == null or knee == null or foot == null:
		return

	var thigh: float = float(chain["thigh"])
	var shin: float = float(chain["shin"])
	if thigh <= 0.001 or shin <= 0.001:
		return

	# hip.position is already rig-local (its parent IS the rig), so the target only
	# has to come back to rig space to be in the hip's own frame.
	var to_target: Vector3 = rig.to_local(target_world) - hip.position
	var reach: float = thigh + shin
	var dist: float = to_target.length()
	if dist < 0.0001:
		return
	# Both singularities. The upper clamp is not polish: at dist == reach exactly,
	# acos(-1) = PI and the knee's bend direction is undefined, so it pops between
	# forward and backward on float noise. Rest already sits at 99.9%.
	var clamped: float = clampf(dist, absf(thigh - shin) + 0.001, reach * 0.995)
	var dir: Vector3 = to_target / dist
	to_target = dir * clamped

	# Decompose the aim. Godot's default euler order is YXZ, so rotation (a,0,r)
	# composes X(a)*Z(r), which maps the thigh's rest -Y onto
	# (sin r, -cos r*cos a, -cos r*sin a). Inverting that gives:
	var roll: float = asin(clampf(dir.x, -1.0, 1.0))
	var aim: float = atan2(-to_target.z, -to_target.y)  # cos(roll) > 0 factors out

	# Law of cosines on the hip -> knee -> ankle triangle.
	var cos_alpha: float = clampf((thigh * thigh + clamped * clamped - shin * shin) / (2.0 * thigh * clamped), -1.0, 1.0)
	var cos_knee: float = clampf((thigh * thigh + shin * shin - clamped * clamped) / (2.0 * thigh * shin), -1.0, 1.0)
	var alpha: float = acos(cos_alpha)   # thigh's offset from the hip->ankle line
	var interior: float = acos(cos_knee) # PI is a straight leg

	# MINUS alpha swings the knee FORWARD (+Z is this rig's forward), so the knee
	# leads and the ankle trails: a human knee, not a bird's.
	hip.rotation = Vector3(aim - alpha, 0.0, roll)
	knee.rotation = Vector3(float(chain["knee_rest"]) + (PI - interior), 0.0, 0.0)

	# The ankle now sits on the target. Only its orientation is left.
	if not ik_align_to_normal:
		foot.rotation = _get_rest_rot(foot_key)
		return
	var up: Vector3 = ground_normal.normalized()
	# Reject normals that are not walkable-ground-up: a spherecast at a step EDGE
	# or off a ledge returns the vertical FACE normal (up.y ~0), and feeding that
	# to the basis below built a degenerate/non-rotation Basis that crashed
	# get_quaternion in the slerp (only ever hit on uneven ground). Keep the foot
	# level in those cases.
	if up.length_squared() < 0.5 or up.y < 0.5:
		up = Vector3.UP
	var forward: Vector3 = rig.global_basis.z  # THIS RIG FACES +Z, not Godot's -Z
	forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = rig.global_basis.y - up * rig.global_basis.y.dot(up)
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	var right: Vector3 = up.cross(forward)
	if right.length() < 0.001:
		return
	right = right.normalized()
	# Re-derive forward from right×up so the three axes are EXACTLY orthonormal —
	# a hair of non-orthogonality from float error is enough to make the Basis a
	# non-rotation and fail the slerp.
	forward = right.cross(up).normalized()
	var aligned := Basis(right, up, forward).orthonormalized()
	# Slerp on the rotation quaternion, preserving the foot's own scale, so any
	# non-uniform/negative scale accumulated down the chain can never hand the
	# slerp a non-rotation basis.
	var t: float = clampf(1.0 - exp(-ik_foot_response * delta), 0.0, 1.0)
	var scale: Vector3 = foot.global_basis.get_scale()
	var cur_q: Quaternion = foot.global_basis.orthonormalized().get_rotation_quaternion()
	var new_q: Quaternion = cur_q.slerp(aligned.get_rotation_quaternion(), t)
	foot.global_transform = Transform3D(Basis(new_q).scaled(scale), foot.global_position)


func _find_body() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n
		n = n.get_parent()
	return null


func _animate_facing(delta: float, facing_direction: Vector3) -> void:
	if turn_target == null:
		return
	var flat := Vector3(facing_direction.x, 0.0, facing_direction.z)
	if flat.length() < 0.01:
		return
	var target_yaw := atan2(flat.x, flat.z)
	turn_target.rotation.y = lerp_angle(turn_target.rotation.y, target_yaw, 1.0 - exp(-turn_smoothing * delta))
