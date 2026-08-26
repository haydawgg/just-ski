# Skier Animation

## Interface and ownership

`SkierAnimationController` is a deep presentation module. Gameplay crosses one seam with two operations:

```gdscript
apply_frame(frame: SkierAnimationFrame, delta: float)
trigger(event: int, strength: float = 1.0, side: float = 0.0)
```

The frame is a reusable, allocation-free presentation snapshot. It contains state, speed, edge, skid, tuck, compression, contact, angular velocity, air time, predicted landing time, grab pose, switch stance, rail information, Flick-It command/phase, gesture direction and strength, trigger pressure, grab amount/tweak, and rotation progress. Events cover pop, landing variants, rail entry/exit, bail, and respawn.

The animation module never changes the gameplay transform, velocity, collision, or physics state. The current articulated primitive rig is one adapter at this seam; a future imported Skeleton3D/AnimationTree rig can replace it without changing skiing code.

## Articulated rig

The runtime rig contains independent joints for pelvis, spine, chest, head, hips, knees, boots, skis, shoulders, elbows, hands, and poles. The visible model includes a jacket, pants, helmet, goggles, gloves, boots, skis, and poles. All meshes are Godot primitives, so no third-party asset license is involved.

## Pose library

- Ground: neutral glide, speed crouch, left/right carve, deep carve, tuck, left/right hockey stop, jump compression, terrain absorption, and recovery reactions.
- Air: directional Flick-It setup/release, compact spin with head spotting, progressive front/back flip tuck, asymmetric left/right cork, release/open, landing anticipation, and switch counter-pose.
- Tricks: safety, mute, Japan, tail, nose, double grab, spread eagle, and daffy.
- Rails: 50-50, left/right boardslide, speed crouch, counter-rotation, balance lean, and entry/exit absorption.
- Reactions: pop extension, clean/sketchy/hard landing compression, bail tumble, and respawn reset.

Pose construction is layered in locomotion, setup/release, rotation, grab/tweak, and landing/reaction order. Continuous trigger pressure weights the grab layer. A procedural two-bone arm solve reaches actual binding, nose, and tail targets; leg tuck and chest compression keep the reach physically readable. Landing prediction fades the grab and realigns the skis before contact.

Pose blending uses exponential response values from `SkierAnimationProfile`. Important angles, compression depths, Flick-It response, head spotting, grab compression, reaction durations, and rail values are centralized in `resources/animation/default_animation_profile.tres`.

## Debugging and tests

F3 adds animation state, active pose, blend value, Flick-It command, and presentation phase to the debug HUD. `tests/animation_acceptance.tscn` drives the module through synthetic frames and verifies rig structure, layered poses, mirrored corks, continuous hand reach, opening/landing behavior, and one-shot reactions without depending on physics internals.
