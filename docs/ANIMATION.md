# Skier Animation

Summit Sessions uses procedural skier presentation driven by gameplay telemetry. The animation system does not own locomotion, collision, trick physics, or root motion.

## Gameplay / presentation boundary

`SkierAnimationController` receives continuous frames, events, and explicit teleport resets:

```gdscript
apply_frame(frame: SkierAnimationFrame, delta: float, snap_pose: bool = false)
trigger(event: int, strength: float = 1.0, side: float = 0.0)
reset_to_frame(frame: SkierAnimationFrame)
```

`SkierAnimationFrame` is a reusable presentation snapshot built by gameplay. It carries the information the visual system needs, including locomotion state, speed, steering/carve/skid response, terrain contact, ski frame, air/trick state, landing prediction, grab/style state, rail information, and crash context.

The animation controller may smooth, classify, and blend that data for presentation, but it must not change the gameplay transform, velocity, collision state, rail state, or scored trick state.

Startup and respawn use `reset_to_frame` to clear pose/IK/secondary history and
evaluate the initial pose without advancing animation time. Before that evaluate,
gameplay synchronously samples terrain/contact so the published reset pose is
fresh-contact-aware while remaining in AIR. Canonical joints, the visible body,
and equipment attachments are synchronized before the player emits
`respawn_applied` and the camera resets. Ordinary frames retain their
normal smoothing. Player and camera reset physics interpolation after a teleport.
The camera runtime stability suite compares startup and post-crash reset body
landmarks, ski/pole transforms, and camera framing before any movement, and
checks that grab input/release state is cleared. Spawn settling does not add a
separate AIR ski IK path; predicted-surface targeting remains a later phase.

## Rig architecture

Presentation is split into three layers of responsibility:

1. `SkierPoseDriver` — canonical articulated joints used by the procedural pose code.
2. `SkierRigAdapter` — interface between the canonical driver and the visible rig.
3. A concrete adapter:
   - `SkeletonSkierRig` for the production Skeleton3D body.
   - `PrimitiveSkierRig` for the generated fallback/debug body.

`SkierAnimationController.RigMode` supports `AUTO`, `SKELETON`, and `PRIMITIVE`.

- `AUTO` prefers the configured skeleton and falls back to the primitive adapter if validation fails.
- `SKELETON` requires the production skeleton path.
- `PRIMITIVE` forces the generated fallback.

The command-line argument `-- --primitive-skier` forces the primitive presentation for debugging and comparison.

`SkierSkeletonProfile` owns model-specific bone mapping, neutral orientation data, axis correction, scale, attachment offsets, and optional production reach calibration. The default production profile maps `spine.002` and `shoulder.L/R` as optional upper-spine and clavicle helpers, records palm and wrist corrections, and measures the visible upper-arm and forearm lengths from the scaled rest transforms. Skis, boots, poles, helmet, and goggles remain presentation attachments rather than locomotion owners.

## Layer order

`apply_frame()` updates presentation signals first, then constructs the pose in a stable order. The current high-level stack is:

- base locomotion pose (`GROUND`, `AIR`, `GRIND`, or `BAIL`);
- trick layer;
- grab layer;
- style layer;
- landing layers;
- stomp layer;
- rail approach / release layers;
- event reactions;
- secondary motion;
- pre-bail response;
- joint limits and smoothing;
- rig-adapter synchronization.

This ordering matters. New animation work should tune or extend the existing layers rather than introduce a second system that competes for the same joints.

## Ground skiing

The ground pose is continuous rather than clip-based. It responds to measured gameplay signals such as speed, edge engagement, turn rate, lateral acceleration, carve/skid ratio, steering intent, pressure, switch stance, and braking.

The presentation emphasizes:

- athletic flex at neutral speed;
- progressive carve loading;
- inside/outside leg asymmetry;
- crossover when changing edges;
- slarve / skid silhouettes when grip demand exceeds clean-carve response;
- stronger hockey-stop presentation during braking;
- switch-aware stance and limb relationships.

These are visual responses only. They never steer the gameplay root.

## Terrain suspension

Animation reads left/right contact information derived from the gameplay contact probes. It uses that data to add bounded per-ski flex, pelvis compensation, terrain roll, and upper-body countering.

The terrain layer is confidence-weighted and smoothed. Missing or contradictory samples reduce presentation influence rather than forcing a foot or ski to an unreliable target. Terrain influence decays after takeoff so airborne skis are not visually magnetized back to the snow.

## Jump and air pose

Grounded jump charge compresses the skier before takeoff. Once airborne, the controller derives presentation phases from actual air state and landing prediction rather than running a separate animation trajectory.

Straight airs remain styled rather than becoming a symmetric mannequin pose. Spin, flip, and cork presentation reads measured angular motion and trick intent while leaving the real rotation on the gameplay root.

## Rotation presentation

Airborne rotation uses gameplay's authoritative accumulated rotation, angular velocity, trick command, and landing prediction.

Presentation can add:

- setup / prewind;
- compactness proportional to rotation demand;
- periodic leg, torso, arm, ski, and pole motifs through a spin;
- spotting near useful alignment points;
- opening and counter-rotation as the skier prepares to land;
- distinct visual shapes for flips and corks.

The HUD can show continuous in-progress rotation while landed scoring resolves to the established trick buckets. Both read the same gameplay-owned rotation history. Touchdown freezes a single rotation snapshot shared by the display, scoring, and landing validity, and accumulation cannot continue past contact; the landing orientation suite guards the freeze.

## Head, gaze, and headwear

The head is a full animation citizen, not a static attachment. Every locomotion layer declares a head attitude so the gaze reads intentionally and transitions never snap:

- **Ground/tuck:** the head counter-pitches the torso fold (`neutral_torso_pitch`, `speed_torso_pitch`, `tuck * 0.44`) so full tuck looks down the hill (~-35°) instead of at the skis (~-55°). Carve adds yaw/roll leveling (`chest_counter_yaw`, `carve_head_level`).
- **Straight air:** keeps a small look-toward-landing pitch plus the takeoff style-side bias, so the head carries its attitude across the lip instead of resetting to zero.
- **Spins:** the head leads into the rotation. `spin_head_spot` is the lead gain (wired into the trick-layer head yaw); `trick_head_yaw_limit` (0.48) bounds the total including landing-spot and residual terms.
- **Grabs:** no grab definition authors a head look, so the layer procedurally counter-pitches 45% of the torso fold — deep folds (Japan spine -0.4 / chest -0.24) keep the face out of the knees.
- **Rails:** the head counter-rolls half the torso counter-lean (`rail_torso_counter_lean * 0.5`) instead of inheriting the balance lean.
- **Landing/crash:** anticipation aims the head (`landing_anticipation_head_pitch`), impact nods it (`landing_head_nod`), and bail stages carry tumbling head poses.
- **Limits:** head pitch clamps at ±0.70 to admit the full-tuck compensation; yaw/roll stay at ±(`trick_head_yaw_limit`/0.48). Joint response (`head_joint_response` 8.5) smooths every transition.

Headwear (helmet shell, visor lip, goggle frame/lens/bridge/strap, ear pads) is procedural geometry in `SkierEquipment.build_headwear`, mounted on the head bone through `HeadAttachment`/`HeadMount`, so it tracks the animated head exactly. Fit conventions: the stack is centered on the skull axis; slim liner pads fill the head-to-shell gap; the strap tapers from shell-clearing radius over the dome to skull-hugging radius below the rim; the visor lip rests on the brow without interpenetrating the frame. `tests/head_presentation_acceptance.tscn` gates fit (symmetry, seating, clearances, no interpenetration) and head behavior (air attitude, spot wiring, grab counter, rail leveling, tuck gaze) with failing-first thresholds.

## Grabs and style poses

Physical grabs and style-only poses are data-driven resources.

`default_grab_animation_library.tres` contains the supported physical grabs and their hand / ski target definitions. `default_style_pose_library.tres` contains style poses that do not require hand-to-ski contact.

The grab system blends authored body shapes with bounded arm targeting. Ski-local markers move with the skier, so grab targets remain attached through spins and tweaks. On the production `Skeleton3D`, the adapter receives a typed visual reach request after canonical retargeting and applies bounded upper-spine/clavicle assistance, an actual-length two-bone arm solve, and marker-aligned wrist orientation. The palm contact point is calibrated against the attached equipment marker, with a `0.14 m` acquisition cap and a `0.12 m` maintenance envelope during `HOLD`; no bone scaling, root translation, or gameplay transform is involved. The primitive adapter keeps the canonical solver path, and production helper bones return to their neutral pose outside grabs. Contact is presentation-only; scoring state remains owned by the trick system.

Grab presentation moves through setup, reach, contact, hold, release, and recovery behavior without snapping the root or changing airtime. Landing preparation can progressively take priority as contact approaches.

## Landing presentation

Landing animation has two separate responsibilities:

- anticipation before contact, using the predicted landing frame;
- impact/recovery after the authoritative gameplay landing event.

Before contact, the skier can begin aligning skis, spotting, opening the arms, and extending the legs. A continuous presentation-only readiness envelope evaluates time-to-contact, surface orientation, vertical motion, and rotational residual. It does not replace the active trick phase or decide the gameplay landing result; the evaluated trick pose remains visible until contact starts the handoff. Anticipation leg extension is restrained by probe clearance near the seat (`LandingPoseLayer.air_extension_scale`), so the rendered skis cannot punch through the snow before the authoritative touchdown seats the body.

After contact, clean, sketchy, and hard landing events drive different compression and recovery responses. Clean landings may trigger a short stomp layer. Failed landings hand off to the bail presentation instead of also playing a successful landing reaction. Balance-driven wobble decays with presentation age with a 1.5 s failsafe, so rotational landings always release the crouch; the landing orientation suite guards the release.

## Rails

Rail presentation reads the gameplay grind state, spline direction, balance, approach information, entry severity, and selected rail pose.

The layer moves through `APPROACH`, `CONTACT`, `COMPRESSION`, `GRIND`, and `RELEASE`. It consumes contact point, tangent/up, slope, kink severity, speed, balance error/velocity, and progress for stance and counterbalance. Gameplay remains responsible for spline travel, ski contact targets, and balance failure.

## Lower-body ownership and IK

Gameplay owns the root. Ground/rail contact owns ski targets; free-air and bail presentation own the boot pose and derive each ski from its fixed binding transform. A state transition captures the final evaluated pose, including procedural layers and constraints, before the receiving owner begins.

The canonical pose controller routes authored ski intent through hips, knees, and boots, then keeps ski-local rotation neutral. A specialized analytic two-bone solve moves each hip-knee-boot chain toward contact-owned boot targets. Stable knee hints, bilateral pelvis compensation, reach and crossing checks, correction-rate limits, and state-dependent weights prevent inverted knees or stretched legs. Crossed targets are additionally hard-separated to the minimum stance (`SkiConstrainedLegIK.separate_boot_targets`) before the solve, so X-shaped ski configurations cannot form. Skiing IK releases in air/bail and returns progressively during rail contact and recovery.

```text
physics/gameplay root
  -> gameplay state and ski/contact targets
  -> base pose + procedural layers
  -> evaluated-pose transition
  -> ski-target smoothing + pelvis compensation
  -> ski-constrained leg IK
  -> arm/grab IK
  -> skeleton/equipment output
```

## Bail presentation

Bail animation is a staged procedural fall layered over gameplay's authoritative `BAIL` motion. It is not a physics ragdoll.

The animation controller reads the captured crash context and produces `RELEASE`, `IMPACT`, `FALL`, `REST`, and `RECOVERY` using stage-local progress. FALL sprawl is driven from skier-local planar travel (pelvis orientation, torso fold, shoulder/arm spread, leg drag, and ski silhouette) through the existing crash reaction layer rather than a second pose owner. FALL/REST keep minimum stage-driven secondary motion even at low slide speeds so the crash never presents as a frozen pose. Ordinary recovery remains in `BAIL` while the body recenters and leg IK reacquires contact, then emits recovery completion and enters ground presentation. Respawn remains a separate hard-reset path.

## Secondary motion

Hands and poles receive filtered inertia and lag based on measured motion. Secondary channels are clamped and smoothed to avoid single-frame spikes. They remain subordinate to the primary skiing, trick, grab, rail, landing, and bail layers.

## Data and tuning

Stable presentation tuning belongs in resources under `resources/animation/`:

- `default_animation_profile.tres`
- `default_grab_animation_library.tres`
- `default_style_pose_library.tres`
- `default_skier_skeleton_profile.tres`
- outfit / presentation profiles used by the visible rigs

Prefer changing these resources or the existing layer logic over adding overlapping state machines or pose owners.

## Debugging

F3 exposes animation telemetry such as pose owner and handoff progress, leg IK weight, pelvis compensation, binding error, reach/infeasibility, rail/crash phase, and the existing rig, trick, landing, grab, and secondary-motion information. Debug geometry shows contact targets, boot axes, knee hints, leg chains, and the rail frame. Opt-in transition tracing logs only ownership and lifecycle changes.

The exact diagnostic fields are implementation details and may change as the prototype evolves.

## Verification

Animation coverage is part of the full runtime gate:

```powershell
.\tests\runtime_quality_gate.ps1
```

The maintained gate includes focused suites for the base animation contract, production character presentation, skeleton retargeting, jumps, landings, rails, tricks, grabs, silhouette readability, polish/secondary motion, and recovery behavior.

For deterministic visual review, generate the silhouette comparison with:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 30 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-silhouette-showcase
```

For a focused production contact review, use the capture-only grab showcase. It writes deterministic stills for the five representative production poses Mute, Japan, Tail, Nose, and Double to `.godot_user/captures/production_grab_showcase`:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 30 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-production-grab-showcase
```

Output is written under `.godot_user/captures/`.

For the complete presentation audit, run all supported production grabs from
`default_grab_animation_library.tres` and all four style poses through setup,
reach, hold/contact, release, and recovery from four fixed views at 30, 60, and
120 Hz:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 30 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-animation-presentation-audit --audit-fps=30
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-animation-presentation-audit --audit-fps=60
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 120 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-animation-presentation-audit --audit-fps=120
```

Each run writes `animation_presentation_audit.json` and fixed hold stills under
`.godot_user/captures/animation_presentation_audit_<fps>/`. The JSON records the
pose, view, phase, hand-to-target error/contact state, pole-to-hand continuity,
boot/binding gap, torso/shoulder/knee/head motion deltas, landing handoff and
compression/recovery fields, inversion and terrain-clearance telemetry, finite
transform status, and state-transition validity. The acceptance scene also
checks final hold reach against the existing `0.12 m` maintenance envelope,
equipment attachment, landing handoff, and frame-rate-normalized continuity.

This is automated evidence only. Controller hardware, subjective skiing and
camera feel, unusual grab combinations, final cloth/pole visual review,
target-display/GPU review, and long-session validation remain human-only gates.

### Presentation audit follow-up (2026-09-06)

This pass addresses the seven animation handoff areas; passing the mechanical
checks is not a claim that every pose is artistically finished.

- Spins/flips: rotation-phase leg articulation and separate front-fold/back-arch
  tuck/open envelopes replace the largely constant rotation support pose.
- Corks: phase-dependent asymmetry opens out late. The inspection root now makes
  a closed tilted-axis turn with matching angular telemetry, enough inversion
  clearance, and a separate 0.6-second rail approach. These fixture changes do
  not alter gameplay rotation physics. The showcase is now 22.2 seconds long.
- Landing: impact handoff is shorter, stomp extension waits for compression,
  and contact IK has a landing-specific rate and pelvis reach allowance.
  Tangential root feedforward removes target drag without pushing contacts down
  during root seating. The analytic knee hinge avoids the Euler branch change
  above 90 degrees and uses a stable body-relative bend plane.
- Cork/rail handoff: the fixture finishes and opens the cork before acquiring
  rail support; ground and rail captures both supply production-style targets.
- Grabs: the selected leg reserves the authored contact shape during spins,
  ski lift assists reach, and spine/clavicle assistance is bounded. Production
  leg segment calibration and pelvis translation now agree with the canonical
  solver. Jacket seating tests compare against skinned, posed mesh vertices.
- Carve/takeoff: pelvis, torso and arm responses follow the load sooner; support
  IK preserves ski edge roll. Capture charge, contact and POP timing are coherent.
- Secondary motion: hands/poles respond sooner; pole stabilization uses the skier
  frame, including cross-body hand placement, rather than world gravity and the
  imported model's rotated axes.
- Pole/cloth follow-up: every switch, grab, and style sample is checked at 30,
  60, and 120 Hz. Pole shafts preserve their hand attachment while a deterministic
  skier-frame fallback keeps each shaft at least `0.10 m` from the knee envelope
  and points it outward/downhill. The production jacket, pants, and glove shells
  copy the source skin weights and the jacket waist ring is checked against the
  imported mesh. Full-body cloth collision or simulation remains deferred because
  the refreshed captures show no confirmed cloth penetration; unusual cross-body
  combinations still receive a human close-camera pass.

The new `animation_presentation_quality_acceptance.tscn` covers moving contact,
production boot/pelvis agreement, visible compression, bounded grab torso
assistance, all supported production grabs, all style poses, maintained contact
reach after acquisition, a 250 ms acquisition deadline during input HOLD,
landing handoff, flip rhythm, and slope-tangent contact advection. It is
included in the 16-scene animation runtime shard. The silhouette inspection
audit writes JSON beside its fixed images with contact and presentation
measurements.

Verification for this pass: animation runtime shard, terrain suspension course,
crest unweighting acceptance, ground hover probe, and the static gate. Rendered
review uses both showcase commands above, jump inspection, and environment
inspection; motion review sheets are under
`.godot_user/captures/presentation_repairs_final/`. Environment pixel review uses
the fresh `snow_depth_after` capture set and its landing telemetry.

The rendered follow-up fixed the two remaining confirmed issues from the prior
review: the Nose shoulder envelope was reduced from 1.735 rad to 1.125 rad
without losing contact, and the first grounded frame now seats the gameplay
root at the configured 0.190 m support offset. The imported jacket remains a
stylized skinned mesh under extreme poses, so normal gameplay review should
still check unusual grab combinations and control feel; deterministic fixtures
do not establish those.
Capture teardown now stops recorder workers, shuts down audio, frees generated
nodes, drains render frames on GPU, and treats texture/ObjectDB leak warnings as
gate failures. The refreshed environment and sunset GPU gates exit cleanly.
