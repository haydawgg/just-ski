# Skier Animation

## Interface and ownership

`SkierAnimationController` is a deep presentation module. Gameplay crosses one seam with two operations:

```gdscript
apply_frame(frame: SkierAnimationFrame, delta: float)
trigger(event: int, strength: float = 1.0, side: float = 0.0)
```

The frame is a reusable, allocation-free presentation snapshot. It contains state, speed, edge, steering intent, actual turn rate, signed lateral acceleration, carve/skid ratios, skier and velocity headings, heading/travel separation, slope/contact data, independent left/right ski distances, normals and hit positions, tuck, compression, angular velocity, air time, predicted landing time, grab pose, switch stance, rail information, Flick-It command/phase, gesture direction and strength, trigger pressure, grab amount/tweak, and rotation progress. Events cover pop, landing variants, rail entry/exit, bail, and respawn.

The animation module never changes the gameplay transform, velocity, collision, or physics state. The current articulated primitive rig is one adapter at this seam; a future imported Skeleton3D/AnimationTree rig can replace it without changing skiing code.

## Articulated rig

The runtime rig contains independent joints for pelvis, spine, chest, head, hips, knees, boots, skis, shoulders, elbows, hands, and poles. The visible model includes a jacket, pants, helmet, goggles, gloves, boots, skis, and poles. All meshes are Godot primitives, so no third-party asset license is involved.

## Basic skiing pose

Normal downhill skiing is driven by measured physics rather than a separate animation state machine. Speed continuously deepens ankle, knee, and hip flex, lowers the pelvis, pitches the torso forward, tucks the arms, and increases pole trail. The neutral pose remains athletic at low speed instead of returning to a straight-legged mannequin stance.

Carve strength combines edge engagement with speed, lateral acceleration/turn rate, carve ratio, skid suppression, and steering intent. Independent damped channels respond in mass order: skis, legs, pelvis, torso, arms, then poles. Loaded carves displace and drop the pelvis inside the turn, compress the inside leg, lengthen the outside leg, edge both skis, counter-rotate the chest toward travel, level the head, and counterbalance with the arms.

Reversing the last loaded turn starts a short crossover window. The skis and lower legs release first, the legs extend and pelvis rises while crossing the skis, then the pelvis, torso, arms, and poles settle progressively onto the new edge. These channels affect presentation only and never write back to movement physics.

## Terrain suspension

`SkiContactSolver` retains its authoritative four-probe average for physics while also exposing read-only left/right aggregates from the same rays. Animation compares each side's ray distance with the existing physics seat distance, then applies framerate-independent smoothing before changing the pose.

Each ski gap produces an independent bounded flex delta on top of the Phase 2 crouch and carve pose. The average gap moves the pelvis by only a reduced fraction, while left/right disagreement adds a small bounded pelvis roll. Spine, chest, and head counter that terrain roll progressively, preserving the skis → knees → pelvis → chest → head response hierarchy. Per-ski confidence combines ray coverage, distance, front/rear height and normal agreement, authoritative grounding, and sample continuity. Low confidence or a gap outside the available leg/pelvis travel smoothly attenuates the procedural correction instead of forcing exact contact.

When both contacts are valid, the rear-to-front contact direction supplies longitudinal pitch for one rigid whole-ski target. Roll comes from a stable terrain normal; strongly disagreeing front/rear normals are not blindly averaged, and the sample closest to the previous stable orientation is preferred. Missing samples fall back gracefully. Ski angles remain clamped, exponentially damped, and rate-limited to prevent flips or one-frame spikes.

A single terrain-influence channel follows the existing grounded flag. It ramps in after contact and decays after takeoff, releasing gaps, normal alignment, and pelvis compensation without inventing another grounded state or magnetizing airborne skis. Debug snapshots expose gaps, normalized leg compression, compression velocity, influence, terrain angles, foot targets, and the stabilized pelvis target. F3 draws the side samples/normals, ski-to-target lines, pelvis target, and compression bars.

## Jump and airborne pose

Jump presentation is driven by existing physics, not a second trajectory. Grounded `jump_charge` continuously compresses ankles, knees, hips, pelvis, torso, and arms. Authoritative takeoff metadata distinguishes a charged pop from a terrain hop and captures pop strength plus takeoff-surface-relative upward speed at the AIR transition.

A short takeoff hold gives way to smoothed early-air, apex, and descent weights from slope-relative upward velocity, air time, and predicted remaining air time. Small hops stay compact; larger charged pops extend more, compact more at apex, and open again on descent. Terrain influence continues to decay after takeoff so skis are not magnetized in the air. Actual angular velocity supplies restrained spin/flip/cork support; the animation module never writes root rotation.

`tests/jump_animation_acceptance.tscn` covers charge scaling, pop/takeoff/early-air/apex/descent sequencing, three jump sizes, tiny terrain hops, straight air at multiple speeds, and physics-driven 360 support. `tests/jump_animation_inspection.tscn` is a development-only slow-motion viewer for those phases.

## Pose library

- Ground: neutral glide, speed crouch, left/right carve, deep carve, tuck, left/right hockey stop, jump compression, terrain absorption, and recovery reactions.
- Air: directional Flick-It setup/release, compact spin with head spotting, progressive front/back flip tuck, asymmetric left/right cork, release/open, landing anticipation, and switch counter-pose.
- Tricks: safety, mute, Japan, tail, nose, double grab, spread eagle, and daffy.
- Rails: 50-50, left/right boardslide, speed crouch, counter-rotation, balance lean, and entry/exit absorption.
- Reactions: pop extension, clean/sketchy/hard landing compression, bail tumble, and respawn reset.

Pose construction is layered in locomotion, setup/release, rotation, grab/tweak, and landing/reaction order. Continuous trigger pressure weights the grab layer. A procedural two-bone arm solve reaches actual binding, nose, and tail targets; leg tuck and chest compression keep the reach physically readable. Landing prediction fades the grab and realigns the skis before contact.

Pose blending uses exponential response values from `SkierAnimationProfile`. Stance angles, speed crouch, carve load references, upper/lower-body angles, crossover timing, per-layer response rates, terrain following/influence/normal response, pelvis follow and limits, leg travel, pole trailing, jump anticipation, air-phase timing/compact, compression depths, Flick-It response, head spotting, grab compression, reaction durations, and rail values are centralized in `resources/animation/default_animation_profile.tres`.

## Debugging and tests

F3 adds animation state, active pose, blend value, air phase, jump size, charge anticipation, Flick-It command, and presentation phase to the debug HUD. `tests/animation_acceptance.tscn` drives the module through synthetic frames and verifies rig structure, low/high-speed athletic stance, pole trail, mirrored loaded carves, inside/outside leg differentiation, upper/lower-body separation, crossover response order and unloading, linked S-turns, layered air poses, continuous hand reach, opening/landing behavior, and one-shot reactions without changing physics internals.

`tests/terrain_suspension_course.tscn` builds a controlled lane with smooth snow, rollers, asymmetric left/right bumps, a dip, a crest, and a deliberately awkward ramp/trough/recovery transition. It verifies independent compression/extension, calmer pelvis travel, limited normal following, grounded/air blending, confidence attenuation and recovery, bounded one-frame ski/pelvis/leg changes, low/medium/high-speed traversal, and linked carve-plus-terrain behavior.

`tests/jump_animation_acceptance.tscn` verifies charge anticipation, pop extension, takeoff/early-air/apex/descent sequencing, jump-size scaling, terrain-hop restraint, straight-air ski control, and physics-driven spin support.
