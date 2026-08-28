# Skier Animation

## Interface and ownership

`SkierAnimationController` is a deep presentation module. Gameplay crosses one seam with two operations:

```gdscript
apply_frame(frame: SkierAnimationFrame, delta: float)
trigger(event: int, strength: float = 1.0, side: float = 0.0)
```

The frame is a reusable, allocation-free presentation snapshot. It contains state, speed, edge, steering intent, actual turn rate, signed lateral acceleration, carve/skid ratios, skier and velocity headings, heading/travel separation, slope/contact data, independent left/right ski distances, normals and hit positions, tuck, compression, angular velocity, air time, predicted landing time, grab pose/input strength/hold and release time, switch stance, rail information, Flick-It command/phase, gesture direction and strength, trigger pressure, grab amount/tweak, authoritative accumulated rotation, signed rotation residual, and rotation progress. Events cover pop, landing variants, rail entry/exit, bail, and respawn.

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

## Airborne rotation and trick intent

Phase 8 consumes the existing Flick-It command phase, `TrickController.accumulated_rotation`, body-frame angular velocity, root/velocity headings, and landing prediction. It never writes `SkierController.global_basis` or angular velocity. A grounded horizontal setup produces a bounded upper-body prewind while the skis remain under the skiing/takeoff pose; abandoned intent exponentially unwinds. The real takeoff release propagates a small visual lead from shoulders/chest through spine and pelvis into compact legs.

Yaw, pitch, and roll remain separate animation channels. Rates are component-clamped and delta-filtered for presentation only. Yaw spins use bounded shoulder/chest/pelvis lead, athletic knee flex, asymmetric arm tuck, restrained head spotting, and pole lag. Existing pitch flips and yaw/roll corks receive smaller layered corrections; the physical root carries the actual rotation, including combined-axis execution. There is no new invert physics or trick family.

Spin compactness scales continuously with filtered angular demand, so a slower 180 stays more open while faster/higher-count spins tuck further. Trick influence requires intent or meaningful measured rotation, preventing minor terrain-hop drift from selecting a spin pose. Both skis inherit the same root rotation and receive no divergent trick yaw, preserving boot/ski separation while small knee/arm asymmetry keeps the pose alive.

As predicted contact approaches, head/chest spotting uses velocity direction and signed rotation residual while arms open and legs begin extending. The trick weight yields progressively to Phase 6; strong unfinished rotation retains a bounded amount of commitment instead of pretending completion. Under- and over-rotation produce opposite internal recovery without reversing or snapping the physical root. `GRIND` suppresses the trick layer so Phase 7 owns support; actual rotation after rail release can reactivate it.

`tests/trick_animation_acceptance.tscn` covers straight air, prewind/abort, takeoff release, mirrored left/right 180 and 360 spins, higher-spin scaling, signed under/over-rotation, smooth/rough landing handoff, air-to-rail and rail-exit-to-spin sequences, existing flip/cork support, root-authority invariants, ski separation, and bounded per-frame changes.

## Airborne grabs and hand targeting

Phase 9 consumes the existing live `TrickController.GrabPose`, analog trigger pressure, tweak vector, pressure-weighted hold duration, release window, Phase 8 rotation state, and Phase 6 landing prediction. It does not write trajectory, root rotation, ski physics, collision, airtime, or scoring state. The controller retains only presentation weights and the last visual definition long enough to animate release; gameplay remains the sole owner of preserved grab name, duration, tweak integral, and landed score.

`default_grab_animation_library.tres` defines the nine supported hand-to-ski grabs: mirrored Safety, Mute, and Japan variants, plus Tail, Nose, and Double. Spread Eagle and Daffy remain data-driven aerial style poses but deliberately have no fabricated ski-contact target. Definitions carry the authoritative display mapping, hand, target ski/marker, compactness, torso/pelvis/leg/free-arm offsets, reach response, and contact hysteresis.

Each ski owns cached local marker nodes for its outside/inside binding area, nose, and rear/tail region. The controller reads each marker's current global transform after leg/ski motion, so the target follows the skier through spins and tweaks instead of lagging in world space. Body compactness uses the maximum of spin and grab demand before adding only the remaining grab contribution. The authored target leg folds upward through hip, knee, boot, and ski; pelvis/torso and free arm create the silhouette; a bounded two-bone solve with a stable outward elbow pole supplies only the final reach. Shoulder, elbow, torso, knee, boot, ski, and ski-separation limits are enforced before blending.

Visual phases are `SETUP → REACH → CONTACT → HOLD → RELEASE → RECOVER`. Pose and contact use separate delta-aware weights. Contact has acquire/maintain hysteresis, while release input immediately makes contact decay without snapping the arm or erasing the remembered gameplay trick. Small airs may remain a partial reach. Near landing, held grabs retain a bounded compromised pose while Phase 6 extends legs, opens arms, and realigns skis; released grabs yield faster. `GRIND` applies no grab layer, leaving Phase 7 authoritative.

`tests/grab_animation_acceptance.tscn` covers grounded suppression, a frame-sequenced Safety Left reach/hold/release, mirrored and cross-body targeting, all supported definitions, style poses without fake targets, straight and left/right/high-spin grabs, short airtime, early and late landing handoffs, ski-local target motion, bounded one-frame changes, root authority, and released-grab naming/scoring persistence.

## Landing anticipation, impact, and recovery

Landing presentation is staged on top of Phase 5 descent and Phase 3 terrain suspension. It never alters trajectory or physics.

1. **Anticipation** — when predicted remaining air time drops below `landing_anticipation_start`, legs extend, skis yaw/pitch toward the predicted contact, torso/head prepare for the slope, and arms open slightly. Grab fade and the existing descent weight still apply. If prediction is unavailable, the current descent pose continues unchanged.
2. **Contact** — the authoritative AIR→GROUND transition (`_handle_landing` / `_reseat_on_snow`) captures slope-relative impact speed, impact severity, balance error, ski/body alignment errors, lateral/forward velocity, and optional spin residual. Tiny terrain hops scale severity by air time so they stay subtle.
3. **Compression** — a decaying impact layer drives ankle/knee/hip flex, pelvis drop, lagged torso pitch, arm open, and pole lag. Depth scales with severity and layers additively with terrain suspension. Left/right gaps and lateral bias produce asymmetric absorption.
4. **Recovery** — after peak compression the layer returns exponentially; soft landings recover quickly, hard landings recover slowly. Moderate balance error adds a damped wobble (pelvis shift, torso counter-lean, asymmetric arms/skis) without triggering bail. Spin residual shows as bounded upper/lower correction, not a root snap override.
5. **Handoff** — as the impact layer decays, Phase 3 terrain influence ramps back in and normal skiing continues. Steering remains live throughout; landing is additive presentation only.

`LandingSolver` already measures impact as velocity into the surface normal, so matched downslope landings score softer than flat impacts at the same world-space downward speed. CLEAN / SKETCHY / HARD outcomes bias compression depth and recovery; BAIL remains the existing crash path.

`tests/landing_animation_acceptance.tscn` covers anticipation timing, severity scaling, downslope vs flat, tiny hops, recovery timing, rough-landing wobble, spin correction, uneven contact, and steering responsiveness during recovery.

## Rail and box animation

Rail presentation stays a pure visualization layer on top of the authoritative `SkierController` grind state (`_try_capture_rail`, `_update_grind`, `_exit_rail`, `_slip_off_rail`). Animation never writes rail position, orientation, velocity, or attach/detach decisions.

1. **Approach** — a read-only, non-attaching proximity/heading scan (`GrindRail3D.approach_preview`, `SkierController._scan_rail_approach`) feeds `rail_approach_anticipation`. While still skiing or airborne, this only opens the arms slightly, centers the torso, and readies the knees — normal skiing/jump presentation continues underneath.
2. **Entry** — the real AIR→GRIND transition captures entry severity from actual capture-moment physics (vertical impact, approach misalignment, body tilt) and triggers a sharper, smaller absorption layer than a snow landing (`rail_entry_max_compression` is roughly half of a hard landing's depth). Ankles/knees/hips/pole lag scale with severity; clean entries barely register.
3. **Slide** — `rail_balance` (already computed from real drift/kink physics) drives a response hierarchy: skis stay nearly stable, legs/pelvis take a moderate share, the torso counters, and the arms carry the largest visible correction, with near-failure amplifying the arm/torso response without ever deciding a bail. `rail_pose` (the actual `RAIL_SLIDE_LEFT/RIGHT` intent, previously only used for scoring text) now drives a genuine sideways slide angle: hips/skis rotate toward the intent while the chest counter-rotates and stays clamped to a plausible range, so a boardslide is a real lower/upper-body separation instead of a snap.
4. **Handoff** — Phase 3 terrain suspension already decays to zero during `GRIND` (its `grounded` input is forced false outside `State.GROUND`), so rail support and snow suspension never fight; no second grounded state was invented. Poles, which previously stayed perfectly neutral through a grind, now trail with speed/entry lag.
5. **Exit** — `rail_distance_to_end` builds exit anticipation (legs ready to extend, pelvis rises, arms ready) before detach. On release, `rail_influence` decays instead of cutting instantly, letting a fading fraction of the last balance/slide pose carry briefly into the air before Phase 5's airborne pose and Phase 6's landing system take over untouched.

`tests/rail_animation_acceptance.tscn` exercises approach subtlety, entry severity scaling (and that it stays smaller than a comparable snow landing), the arms-over-skis balance hierarchy, absence of fake constant wobble, sideways slide/chest-counter separation, exit anticipation, terrain-suspension yielding, pole trailing, and a full approach→entry→slide→exit→air→landing sequence with bounded per-frame deltas. `tests/physics_collision_acceptance.tscn` additionally confirms a real physics-driven rail capture populates entry severity and rail influence correctly.

## Pose library

- Ground: neutral glide, speed crouch, left/right carve, deep carve, tuck, left/right hockey stop, jump compression, terrain absorption, and recovery reactions.
- Air: directional Flick-It setup/release, compact spin with head spotting, progressive front/back flip tuck, asymmetric left/right cork, release/open, landing anticipation, and switch counter-pose.
- Landing: descent preparation, contact compression, severity-scaled recovery, rough-landing wobble, and spin residual correction.
- Tricks: safety, mute, Japan, tail, nose, double grab, spread eagle, and daffy.
- Rails: approach anticipation, entry absorption, 50-50 slide, intent-driven left/right boardslide with chest counter-rotation, arms-led balance correction, exit anticipation, and a fading release into air.
- Reactions: pop extension, bail tumble, and respawn reset.

Pose construction is layered in locomotion, setup/release, rotation, grab/tweak, and landing/reaction order. Continuous trigger pressure weights the grab layer. Data-driven ski-local markers, whole-body compactness, target-leg folding, and a bounded procedural two-bone finish make supported grabs physically readable. Landing prediction reduces grab influence without silently clearing late gameplay input, then Phase 6 realigns the skis before contact.

Pose blending uses exponential response values from `SkierAnimationProfile`. Stance angles, speed crouch, carve load references, upper/lower-body angles, crossover timing, per-layer response rates, terrain following/influence/normal response, pelvis follow and limits, leg travel, pole trailing, jump anticipation, air-phase timing/compact, landing anticipation/compression/recovery/wobble, Flick-It response, head spotting, grab compression, reaction durations, and rail values are centralized in `resources/animation/default_animation_profile.tres`.

## Debugging and tests

F3 adds animation state, active pose, blend value, air phase, jump size, charge anticipation, trick active/intent, spin direction, filtered yaw/pitch/roll rates, accumulated/residual rotation, prewind/release/pose/compactness/spotting/landing weights, grab type/hand/ski/phase/pose/contact/reach/hold values, landing phase/severity/balance/compression, rail phase/influence/approach-anticipation/entry-severity/entry-compression/slide-angle/exit-anticipation, Flick-It command, and presentation phase to the debug HUD. World debug lines include physical root forward, velocity direction, predicted contact, and active hand-to-ski target lines. `tests/animation_acceptance.tscn` drives the module through synthetic frames and verifies rig structure, low/high-speed athletic stance, pole trail, mirrored loaded carves, inside/outside leg differentiation, upper/lower-body separation, crossover response order and unloading, linked S-turns, layered air poses, continuous hand reach, opening/landing behavior, and one-shot reactions without changing physics internals.

`tests/terrain_suspension_course.tscn` builds a controlled lane with smooth snow, rollers, asymmetric left/right bumps, a dip, a crest, and a deliberately awkward ramp/trough/recovery transition. It verifies independent compression/extension, calmer pelvis travel, limited normal following, grounded/air blending, confidence attenuation and recovery, bounded one-frame ski/pelvis/leg changes, low/medium/high-speed traversal, and linked carve-plus-terrain behavior.

`tests/jump_animation_acceptance.tscn` verifies charge anticipation, pop extension, takeoff/early-air/apex/descent sequencing, jump-size scaling, terrain-hop restraint, straight-air ski control, and physics-driven spin support.

`tests/landing_animation_acceptance.tscn` verifies landing anticipation, slope-aware severity, compression scaling, downslope vs flat response, tiny-hop restraint, recovery timing, rough-landing wobble, spin correction, uneven contact, and steering during recovery.

`tests/trick_animation_acceptance.tscn` verifies the Phase 8 intent→prewind→release→rotation→spot/open→landing sequence against supported yaw, pitch, and roll gameplay data without adding grabs or new trick physics.

`tests/grab_animation_acceptance.tscn` verifies Phase 9's setup→reach→contact→hold→release→recover sequence, supported target mappings, spin/landing layering, bounded anatomy, target tracking, and released-grab scoring persistence.
