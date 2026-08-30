# Skier Animation

## Interface and ownership

`SkierAnimationController` is a deep presentation module. Gameplay crosses one seam with two operations:

```gdscript
apply_frame(frame: SkierAnimationFrame, delta: float)
trigger(event: int, strength: float = 1.0, side: float = 0.0)
```

The frame is a reusable, allocation-free presentation snapshot. It contains state, speed, edge, steering intent, actual turn rate, signed lateral acceleration, carve/skid ratios, skier and velocity headings, heading/travel separation, slope/contact data, independent left/right ski distances, normals and hit positions, tuck, compression, angular velocity, air time, predicted landing time, grab pose/input strength/hold and release time, switch stance, rail information, Flick-It command/phase, gesture direction and strength, trigger pressure, grab amount/tweak, authoritative accumulated rotation, signed rotation residual, rotation progress, pre-bail warning weight, and a read-only crash snapshot. Events cover pop, landing variants, rail entry/exit, bail, and respawn.

The animation module never changes the gameplay transform, velocity, collision, or physics state. Procedural layers now drive an invisible canonical `SkierPoseDriver`; presentation is selected behind a `SkierRigAdapter` seam. `SkeletonSkierRig` retargets that canonical pose into an imported `Skeleton3D`, while `PrimitiveSkierRig` preserves the previous generated geometry as a temporary fallback and comparison adapter. No `AnimationTree`, root motion, or second procedural state machine owns the skier.

## Rig adapters and articulated driver

The canonical driver retains independent joints for pelvis, spine, chest, head, hips, knees, boots, skis, shoulders, elbows, hands, and poles. It contains no meshes. Existing pose construction, response hierarchy, joint limits, grab solve, debug rotations, and smoothing continue to operate on these transforms.

`SkierSkeletonProfile` maps semantic joints to model-specific bone names and stores the model transform, neutral rotations, axis corrections, translation scale, and equipment offsets. The skeleton adapter validates required bones, uniqueness, ancestry, finite rests, and the presence of a skinned mesh before use. Each frame it converts canonical Euler deltas to quaternions, changes basis through the configured axis correction, composes from the neutral pose, writes local bone poses, and performs one skeleton update. Pelvis, chest, and shoulder position deltas are likewise applied relative to their captured neutral positions; every other mapped bone remains rotation-only.

Boots and ski pivots attach to the mapped foot bones; pole pivots attach to the hands. Skis and poles are not skeleton bones. Each ski retains binding, inside, nose, and tail markers, and each pole retains a tip marker. `BoneAttachment3D.override_pose` remains false, so attachments follow bones without becoming another pose owner. The old generated jacket, pants, helmet, goggles, gloves, boots, skis, and poles live only in `PrimitiveSkierRig`.

`RigMode.AUTO` prefers the skeleton and records a validation reason before falling back to the primitive adapter. `RigMode.SKELETON` is the strict CI path, while the `--primitive-skier` user argument forces the debug fallback. Adapter name and fallback reason are exposed through animation telemetry and F3.

## Basic skiing pose

Normal downhill skiing is driven by measured physics rather than a separate animation state machine. Speed continuously deepens ankle, knee, and hip flex, lowers the pelvis, pitches the torso forward, tucks the arms, and increases pole trail. The neutral pose remains athletic at low speed instead of returning to a straight-legged mannequin stance.

Carve strength combines edge engagement with speed, lateral acceleration/turn rate, carve ratio, skid suppression, and steering intent. Independent damped channels respond in mass order: skis, legs, pelvis, torso, arms, then poles. Leg loading begins during ordinary engaged turns instead of waiting for the deep-carve label. Loaded carves displace and drop the pelvis inside the turn, visibly compress the inside leg, extend the outside leg, edge both skis, counter-rotate the chest toward travel, level the head, and counterbalance with the arms while a reduced balance-root share prevents whole-body banking from dominating.

Reversing the last loaded turn starts a short crossover window. The skis and lower legs release first, the legs extend and pelvis rises while crossing the skis, then the pelvis, torso, arms, and poles settle progressively onto the new edge. These channels affect presentation only and never write back to movement physics.

Existing skid ratio, edge engagement, and heading/travel separation also produce a continuous slarve weight. It blends the loaded carve into a lower, counter-rotated skid silhouette before the stronger hockey-stop override. Switch stance mirrors lead-leg loading, pelvis and shoulder relationship, head spotting, hand carriage, and pole split inside the articulated rig; it never turns or redirects the gameplay root.

## Terrain suspension

`SkiContactSolver` retains its authoritative four-probe average for physics while also exposing read-only left/right aggregates from the same rays. Animation compares each side's ray distance with the existing physics seat distance, then applies framerate-independent smoothing before changing the pose.

Each ski gap produces an independent bounded flex delta on top of the Phase 2 crouch and carve pose. The average gap moves the pelvis by only a reduced fraction, while left/right disagreement adds a small bounded pelvis roll. Spine, chest, and head counter that terrain roll progressively, preserving the skis → knees → pelvis → chest → head response hierarchy. Per-ski confidence combines ray coverage, distance, front/rear height and normal agreement, authoritative grounding, and sample continuity. Low confidence or a gap outside the available leg/pelvis travel smoothly attenuates the procedural correction instead of forcing exact contact.

When both contacts are valid, the rear-to-front contact direction supplies longitudinal pitch for one rigid whole-ski target. Roll comes from a stable terrain normal; strongly disagreeing front/rear normals are not blindly averaged, and the sample closest to the previous stable orientation is preferred. Missing samples fall back gracefully. Ski angles remain clamped, exponentially damped, and rate-limited to prevent flips or one-frame spikes.

A single terrain-influence channel follows the existing grounded flag. It ramps in after contact and decays after takeoff, releasing gaps, normal alignment, and pelvis compensation without inventing another grounded state or magnetizing airborne skis. Debug snapshots expose gaps, normalized leg compression, compression velocity, influence, terrain angles, foot targets, and the stabilized pelvis target. F3 draws the side samples/normals, ski-to-target lines, pelvis target, and compression bars.

## Jump and airborne pose

Jump presentation is driven by existing physics, not a second trajectory. Grounded `jump_charge` continuously compresses ankles, knees, hips, pelvis, torso, and arms. Authoritative takeoff metadata distinguishes a charged pop from a terrain hop and captures pop strength plus takeoff-surface-relative upward speed at the AIR transition.

A short takeoff hold gives way to smoothed early-air, apex, and descent weights from slope-relative upward velocity, air time, and predicted remaining air time. At takeoff the controller caches a deterministic style side from gesture, the last loaded turn, or switch stance. Straight airs use that side for a bounded leg, pelvis, torso, arm, ski, and pole motif instead of converging on symmetric legs and arms-wide balance. Small hops stay compact; larger charged pops extend more, compact more at apex, and open again on descent. Terrain influence continues to decay after takeoff so skis are not magnetized in the air. Actual angular velocity supplies restrained spin/flip/cork support; the animation module never writes root rotation.

`tests/jump_animation_acceptance.tscn` covers charge scaling, pop/takeoff/early-air/apex/descent sequencing, three jump sizes, tiny terrain hops, straight air at multiple speeds, and physics-driven 360 support. `tests/jump_animation_inspection.tscn` is a development-only slow-motion viewer for those phases.

## Airborne rotation and trick intent

Phase 8 consumes the existing Flick-It command phase, `TrickController.accumulated_rotation`, body-frame angular velocity, root/velocity headings, and landing prediction. It never writes `SkierController.global_basis` or angular velocity. A grounded horizontal setup produces a bounded upper-body prewind while the skis remain under the skiing/takeoff pose; abandoned intent exponentially unwinds. The real takeoff release propagates a small visual lead from shoulders/chest through spine and pelvis into compact legs.

Yaw, pitch, and roll remain separate animation channels. Rates are component-clamped and delta-filtered for presentation only. Yaw spins use bounded shoulder/chest/pelvis lead, athletic knee flex, asymmetric arm tuck, restrained head spotting, and pole lag. Existing pitch flips and yaw/roll corks receive smaller layered corrections; the physical root carries the actual rotation, including combined-axis execution. There is no new invert physics or trick family.

Spin presentation derives four visual phases from the existing command phase, angular rate, accumulated rotation, residual, and landing prediction: `SETUP`, `COMPACT`, `SPOT`, and `OPEN`. Compactness scales continuously with filtered angular demand, so a slower 180 stays more open while faster/higher-count spins tuck further. A periodic local motif derived from authoritative accumulated yaw changes leg scissor, pelvis placement, torso twist, leading arm, ski pitch, and pole lag at each quarter turn; it repeats smoothly for higher spins without adding root rotation. Head/chest spotting appears near half-turn alignment, while opening requires explicit release or final landing readiness. Trick influence requires intent or meaningful measured rotation, preventing minor terrain-hop drift from selecting a spin pose. Both skis inherit the same root rotation and receive no divergent trick yaw, preserving boot/ski separation.

Rotation families layer distinct shapes over that shared timing. Frontflips fold the torso forward and bring knees/skis toward the chest with arms compact in front. Backflips open the chest and hips on initiation, then use a controlled inversion tuck and longer ski line. Corks use diagonal torso twist, asymmetric shoulder/hip drop, one compressed leg, and one extended ski line.

As predicted contact approaches, head/chest spotting uses velocity direction and signed rotation residual while arms open and legs begin extending. The trick weight yields progressively to Phase 6; strong unfinished rotation retains a bounded amount of commitment instead of pretending completion. Under- and over-rotation produce opposite internal recovery without reversing or snapping the physical root. `GRIND` suppresses the trick layer so Phase 7 owns support; actual rotation after rail release can reactivate it.

`tests/trick_animation_acceptance.tscn` covers straight air, prewind/abort, takeoff release, mirrored left/right 180 and 360 spins, higher-spin scaling, signed under/over-rotation, smooth/rough landing handoff, air-to-rail and rail-exit-to-spin sequences, existing flip/cork support, root-authority invariants, ski separation, and bounded per-frame changes.

## Airborne grabs and hand targeting

Phase 9 consumes the existing live `TrickController.GrabPose`, analog trigger pressure, tweak vector, pressure-weighted hold duration, release window, Phase 8 rotation state, and Phase 6 landing prediction. It does not write trajectory, root rotation, ski physics, collision, airtime, or scoring state. The controller retains only presentation weights and the last visual definition long enough to animate release; gameplay remains the sole owner of preserved grab name, duration, tweak integral, and landed score.

`SkierPoseShapeDefinition` is the shared authored-shape Resource for pelvis displacement plus torso, limb, ski, arm, and pole rotations. `default_grab_animation_library.tres` specializes it with the nine supported physical hand-to-ski grabs: mirrored Safety, Mute, and Japan variants, plus Tail, Nose, and Double. Grab definitions add the authoritative hand, ski-local target marker, reach response, contact thresholds, and hysteresis.

`default_style_pose_library.tres` uses the same base shape for Spread Eagle, Daffy, Shifty Left, and Shifty Right, but contains no hand, ski marker, contact, or IK data. `TrickController.style_pose`, `style_name`, and `style_seconds` are tracked independently from physical grabs while using the established style scoring path. Reusable authored shapes live in Resources; procedural timing and telemetry interpretation remain inside the animation module.

Each ski owns cached local marker nodes for its outside/inside binding area, nose, and rear/tail region. The controller reads each marker's current global transform after leg/ski motion, so the target follows the skier through spins and tweaks instead of lagging in world space. Body compactness uses the maximum of spin and grab demand before adding only the remaining grab contribution. The authored target leg folds upward through hip, knee, boot, and ski; pelvis/torso and free arm create the silhouette; a bounded two-bone solve with a stable outward elbow pole supplies only the final reach. Shoulder, elbow, torso, knee, boot, ski, and ski-separation limits are enforced before blending.

Visual phases are `SETUP → REACH → CONTACT → HOLD → RELEASE → RECOVER`. Pose and contact use separate delta-aware weights. The target knee and ski rise first, pelvis and torso compact next, the shoulder reaches only after body commitment, and bounded arm targeting finishes contact. Contact has acquire/maintain hysteresis, while release input immediately makes contact decay without snapping the arm or erasing the remembered gameplay trick. Small airs may remain a partial reach. Near landing, held grabs retain a bounded compromised pose while Phase 6 extends legs, opens arms, and realigns skis; released grabs yield faster. `GRIND` applies no grab layer, leaving Phase 7 authoritative.

`tests/grab_animation_acceptance.tscn` covers grounded suppression, a frame-sequenced Safety Left reach/hold/release, mirrored and cross-body targeting, all supported definitions, style poses without fake targets, straight and left/right/high-spin grabs, short airtime, early and late landing handoffs, ski-local target motion, bounded one-frame changes, root authority, and released-grab naming/scoring persistence.

## Landing anticipation, impact, and recovery

Landing presentation is staged on top of Phase 5 descent and Phase 3 terrain suspension. It never alters trajectory or physics.

1. **Alignment** — below `landing_alignment_start` (0.32 s by default), only subtle ski/surface alignment and head/torso spotting begin. Active tricks and held grabs retain their silhouette.
2. **Readiness** — below `landing_readiness_start` (0.18 s by default), legs extend, the pelvis rises, arms prepare, and trick/grab layers yield. The pose becomes dominant only inside roughly the final 0.10 s. If prediction is unavailable, the current descent pose continues unchanged.
3. **Contact** — the authoritative AIR→GROUND transition (`_handle_landing` / `_reseat_on_snow`) captures slope-relative impact speed, impact severity, balance error, ski/body alignment errors, lateral/forward velocity, and optional spin residual. Tiny terrain hops scale severity by air time so they stay subtle.
4. **Compression** — a decaying impact layer drives ankle/knee/hip flex, pelvis drop, lagged torso pitch, arm open, and pole lag. Depth scales with severity and layers additively with terrain suspension. Left/right gaps and lateral bias produce asymmetric absorption.
5. **Recovery and handoff** — after roughly 100-220 ms of compression, the layer returns exponentially over roughly 220-550 ms; soft landings recover quickly and hard landings use the slower end of the band. Terrain influence ramps back in, steering remains live, and moderate balance error adds a damped wobble without changing physics.

A clean landing with meaningful recorded airtime can additionally trigger a short stomp presentation: decisive centered compression, parallel skis, quiet chest/head, hands forward, and a strong stacked recovery. Tiny terrain reseats and sketchy or hard outcomes never arm this layer.

`LandingSolver` measures impact as velocity into the surface normal, so matched downslope landings score softer than flat impacts at the same world-space downward speed. CLEAN / SKETCHY / HARD outcomes bias compression depth and recovery. An unrecoverable upright, impact, or angular gate reports one deterministic failure reason to the crash path; failed landings do not also emit successful landing feedback.

`tests/landing_animation_acceptance.tscn` covers anticipation timing, explicit compression/recovery timing bands, severity scaling, downslope vs flat, tiny hops, rough-landing wobble, spin correction, uneven contact, and steering responsiveness during recovery. `tests/ski_feel_acceptance.tscn` separately locks air-trim authority, severity-scaled landing control recovery, restrained speed FOV, mirrored turn bank, and air-state bank release.

## Pre-bail and controlled crash

Landing prediction drives a restrained airborne pre-bail channel when upright or angular plausibility is approaching failure. It opens the arms, offsets the torso and pelvis toward the actual danger side, and loosens the legs without changing collision, trajectory, root rotation, or the landing verdict. The channel decays normally when the skier recovers.

`CrashContext` is the authoritative presentation input after a crash. It records reason, source, source state, incoming/resolved velocity, impact normal and speed, angular speed, balance/lateral bias, elapsed time, rest status, and one of four stages:

1. **Release** — the previous trick, grab, or rail pose yields while incoming momentum remains readable.
2. **Impact** — the pose reacts along the measured impact normal and lateral side.
3. **Fall** — torso, pelvis, limbs, skis, and poles follow a bounded directional tumble derived from real angular velocity.
4. **Rest** — motion settles into a stable fallen pose until physics confirms recovery or respawn clears it.

This remains a controlled procedural fall retargeted through the active adapter. It does not add a `RigidBody3D`, `PhysicalBoneSimulator3D`, equipment detachment, or a second gameplay state machine. Skeleton and primitive presentations consume the same crash pose and recovery timing.

The final animation ownership order is physics snapshot → base athletic pose → locomotion/carve → terrain suspension → air/jump → rail/trick/grab → landing → secondary motion → pre-bail/crash override → joint limits → hierarchical blend. Crash is the final authored pose override, but root motion remains owned by `SkierController` and every joint still passes through the existing limits and response hierarchy.

`tests/crash_recovery_acceptance.tscn` covers guarded crash entry, failure sources, momentum continuity, exactly-once feedback/scoring, telemetry, repeated crash/respawn cleanup, and bounded rest recovery. `tests/animation_acceptance.tscn` covers pre-bail direction and all four controlled-fall stages. The uninterrupted 30/60/120 Hz route in `tests/animation_polish_acceptance.tscn` includes a failed trick, every crash stage, respawn, and ski-away.

## Rail and box animation

Rail presentation stays a pure visualization layer on top of the authoritative `SkierController` grind state (`_try_capture_rail`, `_update_grind`, `_exit_rail`, `_slip_off_rail`). Animation never writes rail position, orientation, velocity, or attach/detach decisions.

1. **Approach** — a read-only, non-attaching proximity/heading scan (`GrindRail3D.approach_preview`, `SkierController._scan_rail_approach`) feeds `rail_approach_anticipation`. While still skiing or airborne, this only opens the arms slightly, centers the torso, and readies the knees — normal skiing/jump presentation continues underneath.
2. **Entry** — the real AIR→GRIND transition captures entry severity from actual capture-moment physics (vertical impact, approach misalignment, body tilt) and triggers a sharper, smaller absorption layer than a snow landing (`rail_entry_max_compression` is roughly half of a hard landing's depth). Ankles/knees/hips/pole lag scale with severity; clean entries barely register.
3. **Slide** — `rail_balance` (already computed from real drift/kink physics) drives a response hierarchy: skis stay nearly stable, legs/pelvis take a moderate share, the torso counters, and the arms carry the largest visible correction, with near-failure amplifying the arm/torso response without ever deciding a bail. A 50-50 keeps centered parallel skis, symmetrical legs, and a square upper body. `rail_pose` drives boardslides into pronounced ski/pelvis yaw, chest counter-rotation, asymmetric legs, and a wider arm line, producing a clear gameplay-camera silhouette without changing capture or balance physics.
4. **Handoff** — Phase 3 terrain suspension already decays to zero during `GRIND` (its `grounded` input is forced false outside `State.GROUND`), so rail support and snow suspension never fight; no second grounded state was invented. Poles, which previously stayed perfectly neutral through a grind, now trail with speed/entry lag.
5. **Exit** — `rail_distance_to_end` builds exit anticipation (legs ready to extend, pelvis rises, arms ready) before detach. On release, `rail_influence` decays instead of cutting instantly, letting a fading fraction of the last balance/slide pose carry briefly into the air before Phase 5's airborne pose and Phase 6's landing system take over untouched.

`tests/rail_animation_acceptance.tscn` exercises approach subtlety, entry severity scaling (and that it stays smaller than a comparable snow landing), the arms-over-skis balance hierarchy, absence of fake constant wobble, sideways slide/chest-counter separation, exit anticipation, terrain-suspension yielding, pole trailing, and a full approach→entry→slide→exit→air→landing sequence with bounded per-frame deltas. `tests/physics_collision_acceptance.tscn` additionally confirms a real physics-driven rail capture populates entry severity and rail influence correctly.

## Secondary motion and inertia polish

Phase 10 remains inside `SkierAnimationController`; callers still provide the same frame and event interface. The controller derives bounded, animation-only lateral/vertical/yaw acceleration, heading separation, hand acceleration, terrain compression velocity, and landing-compression velocity. Every temporal filter uses an exponential delta-aware response. No noise, independent ski wobble, physics force, or new gameplay state is introduced.

Primary targets are built first. A restrained follow-through layer then propagates motion through pelvis/spine/chest, shoulders/elbows/hands, and finally poles. Chest response combines actual acceleration with the residual between pelvis and torso carve channels; the head counters only a small share and yields to Phase 8 spotting. Free arms follow torso acceleration asymmetrically, while the active grab hand progressively suppresses inertia during reach and almost fully suppresses it at contact. Pole-local inertia is driven by measured hand acceleration and yaw acceleration, tightens during compact spins, and settles faster when its driving signal disappears. Terrain and landing compression velocity supply a small leg rebound through hip/knee/boot only; skis remain rigidly attached to boots.

The final transform pass now uses a joint response hierarchy rather than one rate for the entire rig: skis/boots and legs respond first, then pelvis, spine, chest/head, shoulders, elbows/hands, and poles. POP temporarily raises each rate by a body-part-specific share without making poles as fast as the feet. Crossover carry is allowed to decay after takeoff, heading/travel input is filtered before reaching chest/head, and air flex decays instead of being cleared immediately.

Conflicting ownership was reduced rather than hidden behind larger clamps. Phase 5 owns symmetric spin leg compactness while Phase 8 contributes only directional asymmetry and pelvis organization. Phase 6 owns landing leg extension as its anticipation rises; Phase 8 landing/open arms yield progressively. Grab leg contribution yields near landing, and landing compression preserves headroom for terrain-driven leg flex.

`tests/animation_polish_acceptance.tscn` replays one uninterrupted straight→S-turns→uneven-terrain→pop→360→grab→release→landing→rail→exit→landing→ski-away sequence at 30, 60, and 120 Hz. It checks rate-equivalent final poses and lag amplitudes, stable spin-grab contact, bounded transforms and one-frame deltas, signal clamps, pole settling, and traversal of every existing locomotion state without changing root physics.

`tests/animation_silhouette_acceptance.tscn` uses the real `SkiCameraController` following a disabled/manual `SkierController`, not a surrogate static camera. It checks neutral/carve/slarve/hockey stop, regular/switch, spin phases, frontflip/backflip/cork, 50-50/boardslide, straight air/grabs/styles, delayed descent readiness, and stomp. Every representative pair must move at least one landmark by 12% of projected body height and at least three landmarks by 5%. Direct joint tests remain for anatomy, timing, and root-authority invariants.

`tests/animation_silhouette_inspection.tscn` is the deterministic visual companion. With `--capture-silhouette-showcase`, it records a 21.6-second, 30 fps sequence through the actual follow camera covering neutral, carve, slarve, switch, straight air, evolving spin, grab, all styles, all rotation families, both rail silhouettes, delayed landing preparation, and clean stomp. It writes the MP4 and 18 representative PNG frames to `.godot_user/captures/` for normal-speed and still-frame review.

## Pose library

- Ground: neutral glide, speed crouch, left/right carve, deep carve, tuck, left/right hockey stop, jump compression, terrain absorption, and recovery reactions.
- Air: directional Flick-It setup/release, compact spin with head spotting, progressive front/back flip tuck, asymmetric left/right cork, release/open, landing anticipation, and switch counter-pose.
- Landing: descent preparation, contact compression, severity-scaled recovery, rough-landing wobble, and spin residual correction.
- Tricks: safety, mute, Japan, tail, nose, double grab, spread eagle, daffy, and mirrored shifty left/right.
- Rails: approach anticipation, entry absorption, 50-50 slide, intent-driven left/right boardslide with chest counter-rotation, arms-led balance correction, exit anticipation, and a fading release into air.
- Reactions: pop extension, predictive pre-bail, directional crash release/impact/fall/rest, and blended respawn reset.

Pose construction follows the fixed ownership order documented above. Continuous trigger pressure weights the grab layer. Data-driven shared shapes, ski-local grab markers, whole-body compactness, target-leg folding, and a bounded procedural two-bone finish make supported grabs physically readable while keeping style-only poses separate. Landing prediction reduces grab influence without silently clearing late gameplay input, then Phase 6 realigns the skis before contact. Respawn clears every temporal channel immediately but lets visible joints return through the normal hierarchy, avoiding a one-frame pose snap.

Pose blending uses exponential response values from `SkierAnimationProfile`. Stance angles, speed crouch, carve load references, upper/lower-body angles, crossover timing, per-layer and per-joint response rates, bounded inertial gains, terrain following/influence/normal response, pelvis follow and limits, leg travel/rebound, pole trailing, jump anticipation, air-phase timing/compact, landing anticipation/compression/recovery/wobble, pre-bail response, controlled-crash stages, Flick-It response, head spotting, grab compression, reaction durations, and rail values are centralized in `resources/animation/default_animation_profile.tres`.

## Debugging and tests

F3 adds animation state, active pose, blend value, air phase, jump size, charge anticipation, trick active/intent, spin direction, filtered yaw/pitch/roll rates, accumulated/residual rotation, prewind/release/pose/compactness/spotting/landing weights, grab type/hand/ski/phase/pose/contact/reach/hold values, landing phase/severity/balance/compression, rail phase/influence/approach-anticipation/entry-severity/entry-compression/slide-angle/exit-anticipation, crash reason/source/stage/impact/angular/balance/rest values, pre-bail weight, filtered inertial signals, torso/arm/pole lag magnitudes, secondary-motion weight, Flick-It command, and presentation phase to the debug HUD. World debug lines include physical root forward, velocity direction, predicted contact, and active hand-to-ski target lines. `tests/animation_acceptance.tscn` drives the module through synthetic frames and verifies rig structure, low/high-speed athletic stance, pole trail, mirrored loaded carves, inside/outside leg differentiation, upper/lower-body separation, crossover response order and unloading, linked S-turns, layered air poses, continuous hand reach, opening/landing behavior, pre-bail/crash reactions, and one-shot reactions without changing physics internals.

`tests/terrain_suspension_course.tscn` builds a controlled lane with smooth snow, rollers, asymmetric left/right bumps, a dip, a crest, and a deliberately awkward ramp/trough/recovery transition. It verifies independent compression/extension, calmer pelvis travel, limited normal following, grounded/air blending, confidence attenuation and recovery, bounded one-frame ski/pelvis/leg changes, low/medium/high-speed traversal, and linked carve-plus-terrain behavior.

`tests/skeleton_rig_acceptance.tscn` additionally drives the production Skeleton3D through straight skiing, mirrored hard carves, switch, jump, 360/720, frontflip/backflip/cork, spread/daffy/shifty, rail/boardslide, landing, and crash stages plus all nine grabs. It verifies mapped world orientation, fixed helper poses, invariant limb lengths, finite and bounded landmarks, boot/ski and hand/pole attachment stability, and a production wrist-to-attached-ski reach envelope. Tail and nose ski pitch signs are locked here so their contact markers cannot regress away from the reaching hand.

`tests/jump_animation_acceptance.tscn` verifies charge anticipation, pop extension, takeoff/early-air/apex/descent sequencing, jump-size scaling, terrain-hop restraint, straight-air ski control, and physics-driven spin support.

`tests/landing_animation_acceptance.tscn` verifies landing anticipation, slope-aware severity, compression scaling, downslope vs flat response, tiny-hop restraint, recovery timing, rough-landing wobble, spin correction, uneven contact, and steering during recovery.

`tests/trick_animation_acceptance.tscn` verifies the Phase 8 intent→prewind→release→rotation→spot/open→landing sequence against supported yaw, pitch, and roll gameplay data without adding grabs or new trick physics.

`tests/grab_animation_acceptance.tscn` verifies Phase 9's setup→reach→contact→hold→release→recover sequence, supported target mappings, spin/landing layering, bounded anatomy, target tracking, and released-grab scoring persistence.

`tests/animation_polish_acceptance.tscn` verifies the frozen final stack: filtered motion signals, connected response hierarchy, torso/arm/pole follow-through, grab-contact priority, transition continuity, controlled crash/respawn, settling, and full-run equivalence at 30/60/120 Hz.
