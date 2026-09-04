# Skier Animation

Summit Sessions uses procedural skier presentation driven by gameplay telemetry. The animation system does not own locomotion, collision, trick physics, or root motion.

## Gameplay / presentation boundary

`SkierAnimationController` is fed through two public operations:

```gdscript
apply_frame(frame: SkierAnimationFrame, delta: float)
trigger(event: int, strength: float = 1.0, side: float = 0.0)
```

`SkierAnimationFrame` is a reusable presentation snapshot built by gameplay. It carries the information the visual system needs, including locomotion state, speed, steering/carve/skid response, terrain contact, ski frame, air/trick state, landing prediction, grab/style state, rail information, and crash context.

The animation controller may smooth, classify, and blend that data for presentation, but it must not change the gameplay transform, velocity, collision state, rail state, or scored trick state.

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

The HUD can show continuous in-progress rotation while landed scoring resolves to the established trick buckets. Both read the same gameplay-owned rotation history.

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

The grab system blends authored body shapes with bounded arm targeting. Ski-local markers move with the skier, so grab targets remain attached through spins and tweaks. On the production `Skeleton3D`, the adapter receives a typed visual reach request after canonical retargeting and applies bounded upper-spine/clavicle assistance, an actual-length two-bone arm solve, and marker-aligned wrist orientation. The palm contact point is calibrated against the attached equipment marker, with a `0.18 m` acquisition cap and a `0.12 m` maintenance envelope during `HOLD`; no bone scaling, root translation, or gameplay transform is involved. The primitive adapter keeps the canonical solver path, and production helper bones return to their neutral pose outside grabs. Contact is presentation-only; scoring state remains owned by the trick system.

Grab presentation moves through setup, reach, contact, hold, release, and recovery behavior without snapping the root or changing airtime. Landing preparation can progressively take priority as contact approaches.

## Landing presentation

Landing animation has two separate responsibilities:

- anticipation before contact, using the predicted landing frame;
- impact/recovery after the authoritative gameplay landing event.

Before contact, the skier can begin aligning skis, spotting, opening the arms, and extending the legs. A presentation-only readiness measure evaluates whether the current pose is visually prepared; it does not decide the gameplay landing result.

After contact, clean, sketchy, and hard landing events drive different compression and recovery responses. Clean landings may trigger a short stomp layer. Failed landings hand off to the bail presentation instead of also playing a successful landing reaction.

## Rails

Rail presentation reads the gameplay grind state, spline direction, balance, approach information, entry severity, and selected rail pose.

The layer covers neutral 50-50 stance, boardslide presentation, balance compensation, entry compression, exit preparation, and pop/release handoff. Gameplay remains responsible for spline travel and balance failure.

## Bail presentation

Bail animation is a staged procedural fall layered over gameplay's authoritative `BAIL` motion. It is not a physics ragdoll.

The animation controller reads the captured crash context and produces a controlled release, impact, fall, and rest presentation. Recovery/respawn events reset the visual state at the same boundary used by gameplay.

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

F3 exposes animation telemetry such as active rig adapter, fallback reason, locomotion state, pose/blend information, terrain influence, air/trick phases, landing readiness, grab state, rail state, secondary motion, and bail presentation. The production adapter diagnostics also expose measured arm lengths, attached target positions, palm contact points, post-solve reach errors, helper-bone state, and the current reach solver state.

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

For a focused production contact review, use the capture-only grab showcase. It writes deterministic stills for Mute, Japan, Tail, Nose, and Double to `.godot_user/captures/production_grab_showcase`:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 30 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-production-grab-showcase
```

Output is written under `.godot_user/captures/`.
