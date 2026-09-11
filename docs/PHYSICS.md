# Ski Physics

This document describes the current gameplay-physics contract. The implementation in `player/skier_controller.gd` and the resources under `resources/physics/` are the source of truth for tuning values.

## Ownership and states

`SkierController` owns movement, collision, and locomotion state. Presentation systems may read the result but do not move the skier.

The controller has four states:

- `GROUND` — supported ski contact and snow movement.
- `AIR` — ballistic movement, trick rotation, landing prediction, and landing evaluation.
- `GRIND` — spline-constrained rail travel with balance.
- `BAIL` — momentum-preserving fall and bounded recovery.

Normal transitions are Ground → Air on pop or lost support, Air → Ground on a valid landing, Air → Grind on valid rail capture, Air → Bail on a failed landing or qualifying feature impact, Grind → Air on exit/pop/slip, and Bail → Ground only after grounded rest and recovery. An unsupported bail that reaches the configured maximum duration uses the normal SessionManager respawn path instead of fabricating ground support. Session and course respawns use the controller reset path so transient motion and presentation state is cleared consistently.

## Contact and collision

Snow contact is sampled at four logical ski positions. Their front/rear and left/right offsets, probe distance, and probe-origin height are data in the active `SkiPhysicsProfile`; the solver retains a compatibility default for direct callers without a profile. The solver produces average support data for gameplay and left/right contact data for presentation. Current-sample `average_normal` is refreshed from any valid terrain hit, even above the grounded band; `last_normal` is retained only as the next probe-direction fallback when no terrain hit is available. Contact follows terrain orientation rather than the skier's visual body orientation.

The player uses a `CharacterBody3D` collision body. Terrain and solid features remain physical collision surfaces. Rails use spline capture for grind travel rather than relying on the player capsule to balance on rail geometry. While grinding, the controller independently sweeps the skier body toward the requested rail position, filters the result to solid Features, and sends qualifying impacts through the same profile-based crash evaluator; `GRIND_ONLY` rail bodies remain outside that feature-impact path.

A short coyote window smooths brief support gaps, and a minimum airborne interval prevents immediate false landings around lips and contact transitions.

## Ground movement

Ground motion is momentum-led rather than direct velocity steering. The controller projects gravity onto the snow surface, applies low forward drag and bounded lateral grip, tracks edge engagement, and compares grip demand with available grip to produce carving or skidding.

Steering response depends on speed and edge state. Sidecut response keeps an engaged ski turning after initial stick input, while released edges allow ski heading to settle toward travel direction. Braking progressively increases speed scrub and turning authority. Tuck reduces aerodynamic drag.

Input shaping is centralized through `InputManager`. Stick input passes through the configured inner deadzone, outer deadzone, and response curve once before gameplay consumes it.

### Pressure and terrain response

Left-stick Y changes ski pressure. Forward pressure loads the tips and increases bite; back pressure helps unweight the skis.

Terrain suspension keeps support tied to the sampled snow rather than a stale tangent plane. Crests, banks, deck transitions, and uneven left/right support can therefore affect loading and pose. Physical surface kind is authored gameplay data and can change drag/grip independently of visual color.

## Pop and air movement

A deliberate pop adds a surface-normal impulse to existing momentum. Right-stick gestures seed angular velocity. Left-stick air correction is intentionally lower-authority than a committed trick gesture.

Air movement remains ballistic. Animation, grabs, HUD, and trick presentation do not rewrite the root trajectory.

A segmented predictor estimates likely landing position and normal for preparation and debugging. The real landing result still comes from actual contact.

## Landing evaluation

The long terrain probes support suspension and landing prediction; they no
longer independently trigger touchdown. Probe-based landing requires support
within 0.05 m of the intended seat. A swept capsule collision with rideable
terrain resolves landing in the same physics tick, using incoming velocity
before `move_and_slide` removes the impact component. Terrain hops return to
suspension without an immediate position snap. The regular crash/recovery suite
covers the former 0.53 m early-touchdown case, real snow collisions, impact-speed
preservation, and valid contact at the world origin.

Pop cancels inward suspension velocity before adding its normal impulse, while
preserving tangential and outward momentum. Regression coverage includes all
three cases on a sloped normal. The reference gameplay jump remains inside its
existing envelope (0.76 m peak, 0.88 s airtime at 120 Hz).

Landing evaluation combines travel alignment, skier/surface alignment, impact severity, and remaining angular motion. The score weights, impact-severity biases, and balance biases are owned by the active `SkiPhysicsProfile`; hard plausibility gates remain explicit safety logic. Hard plausibility gates prevent obviously inverted, excessively rotating, or extreme impacts from passing only because a weighted average is acceptable.

Successful landings retain and project motion onto the receiving surface, classify the outcome for scoring/presentation, and may briefly reduce ordinary steering after a heavier impact. The AIR-to-GROUND state change is immediate, but the airborne root orientation is preserved and settles toward the receiving surface inside GROUND at a bounded angular rate. Clean landings use the short end of the settle envelope; heavier non-bail landings use the longer end and transfer only a small, damped amount of airborne yaw/tilt residual. The initial ground target keeps the touchdown heading, while normal ground steering and weathervaning correct it afterward. Failed landings preserve incoming momentum into the bail path instead of freezing the skier.

Grab presentation may release before contact, but trick metadata required for landed scoring remains available until the landing resolves.

## Bail and recovery

All fall entry passes through a guarded gameplay boundary that records the source and relevant impact/motion context before transient trick, grab, and rail presentation is cleared.

`BAIL` is controlled physics rather than ragdoll simulation. Linear momentum is retained and angular motion is damped within configured bounds. Rail release supplies a filtered, bounded angular presentation value instead of passing through the normal air-entry reset. Recovery waits for a sufficiently quiet grounded rest state, then advances through an explicit presentation recovery while gameplay remains in `BAIL`. `GROUND` begins only after that recovery duration reaches its skiing-ready endpoint and grounded support is still present. An airborne bail that reaches the configured maximum duration, or loses support before recovery can complete, uses normal marker/default respawn and cannot transition directly to `GROUND`.

Solid-feature contact becomes a bail only when the profile's impact conditions are met. Low-speed brushes remain ordinary collisions.

Unsupported bail rotation follows damped angular momentum without a world-up
correction. Snow contact owns alignment. Airborne and grounded angular damping
are tuned separately, while linear damping is unchanged so softer rotation does
not shorten the post-impact slide or move the eventual recovery point. Grounded
`FALL` couples residual crash spin toward surface roll around `ground_normal ×
travel`, using planar speed over an effective body radius, then profile-limited
coupling, cap, and fade.
Alignment is a speed-aware slerp toward a snow pose: weak while sliding quickly,
stronger as speed falls, and strongest in `REST`/`RECOVERY`. It never strengthens
just because travel sped up. Degenerate normals or travel keep the existing
damped angular momentum instead of inventing an axis. Crash presentation treats
zero stage time/progress as the start of a stage, including the first recovery
frame, so total crash time cannot prematurely complete the get-up pose or
contact IK. `crash_recovery_acceptance.tscn` covers inverted pitch/roll
continuity, ground-coupled roll axes, unchanged linear slide damping,
travel-direction sprawl, multi-rate rotation bounds, stage handoffs through the
real controller, and the complete rest/recovery lifecycle. The event-driven
crash viewport diagnostic additionally bounds grounded ski angle against the
live snow plane and records a GPU clip for choreography review.

Crash entry clears downhill locomotion channels (edge, steering, carve, tuck,
pressure, skid) while preserving linear/angular momentum, so no pre-crash skiing
posture leaks into crash presentation or telemetry. Grounded crashes roll and
slide with incoming momentum still visible. Recovery clears locomotion again,
realigns the root within one ground-settle angular step, and seeds the standard
orientation settle for the remainder instead of snapping. The crash recovery
suite guards entry clearing, ground-coupled tumble, low-speed settle motion,
and rate-limited recovery.

Terrain-hop reseating uses the same bounded root-orientation settling as
deliberate landings. The landing orientation suite covers tilted reseating at
30, 60, and 120 Hz; the reproduced 18.4-degree instantaneous correction is
removed. Contact seating uses actual probe hits to establish validity, so a
terrain hit at world position `(0, 0, 0)` is no longer mistaken for missing data.
Unarmed post-spawn seating uses an explicit `_spawn_settle_active` window enabled
only by initial spawn/reset and `respawn_at()`. Reset samples terrain contact
synchronously and publishes that pose before `respawn_applied`, but gameplay
remains in AIR. While the window is active the root approaches the support
surface with `seat_approach_speed` as the hard ceiling, then the existing quiet
`_reseat_on_snow()` path enters GROUND without landing presentation. Terrain hops,
crest transitions, and charged pops do not share this window. The landing
orientation suite guards the spawn-settle lifecycle at 30, 60, and 120 Hz.

## Rails

`GrindRail3D` owns a `Curve3D` used for gameplay travel. Capture checks approach speed, proximity, vertical gap, and tangent plausibility.

After capture, momentum is projected onto the spline tangent, entry blends toward the rail, gravity and friction act along the spline, and travel may reverse if the geometry and momentum allow it. Signed speed integrates through zero when the slope opposes travel, so an uphill grind decelerates, stops, and reverses instead of being held at a crawl. The 0.35 m/s crawl floor only sustains travel while gravity assists the current direction; on a flat rail friction decays the speed to a stall, and a sustained stall releases the rail into a gentle drop after the profile's `rail_stall_release_time`. Each requested rail translation is independently swept against solid Features; qualifying impacts enter `BAIL` without enabling rail collision or a second root-motion pass. Left-stick X counters balance drift.

Kinks, slide stance, authored drift bias, and the initial capture offset can increase balance demand. The same contact point, tangent, slope, kink, balance, and balance-rate values are forwarded to presentation. Crossing the balance limit atomically releases rail ownership and enters `AIR` with bounded inherited angular state; a subsequent failed landing uses that state when entering bail.

## Root, ski, and boot ownership

The `CharacterBody3D` remains the only root-motion owner. Terrain/rail contact produces authoritative ski targets without allowing animation to rewrite the root. Each boot has a calibrated ski-local binding transform; the presentation system converts a ski target to a boot target and uses bounded pelvis compensation plus specialized two-bone leg IK to reach it. In unconstrained air and bail stages the relationship reverses: the evaluated boot pose drives the rigid boot/ski assembly, and contact IK is reduced or disabled. Immediately before touchdown, presentation-only AIR preview IK may reach toward the cached predicted landing plane without writing gameplay transforms, contact, scoring, or trick state.

## Course geometry

The resort is assembled from reusable, data-driven park features. Jumps, hips, rollers, banks, rails, boxes, tubes, wall features, and other obstacles are generated rather than manually built as one-off editor geometry.

Jump construction can read the active physics profile so feature sizing remains tied to the same gravity/pop calibration used by the skier. Generated terrain meshes also provide matching collision surfaces.

## Scoring and session flow

`RunScoring` owns run score, combo timing, line links, best-trick information, and clean/bail accounting. Air and rail outcomes feed scoring only after gameplay resolves the movement result.

The finish flow summarizes the run and persists the personal best. An active-run marker retry applies the configured retry cost, while automatic course recovery preserves run totals and retry count but clears transient combo/link state. Summit restart and Return to Marker from the results screen start a clean scoring run. Respawning any run that is already finished also clears the scoring run so the next trick is scorable.

## Tuning

The active `SkiPhysicsProfile` and Flick-It profile under `resources/physics/` contain the maintained calibration for gravity, friction, surfaces, edge response, steering, pressure, braking, pop, air behavior, landing acceptance, recovery, feature impacts, and rail handling.

Do not duplicate exact tuning values in this document unless they are intentionally part of a stable external contract. The resource files are the source of truth.

## Debugging and verification

F3 exposes live movement telemetry including the active state and useful contact, steering, grip, landing, rail, angular-motion, and recovery diagnostics.

Fast source-level check:

```powershell
.\tests\physics_static_acceptance.ps1
```

Full runtime gate:

```powershell
.\tests\runtime_quality_gate.ps1
```

`tests/runtime_quality_gate.ps1` is the maintained source of truth for the runtime scene list. `tests/physics_benchmark.tscn` remains the deterministic end-to-end handling benchmark and writes telemetry under Godot's user-data path rather than into the repository.

The handling benchmark starts at x=30 rather than x=28. With corrected touchdown
timing, the old timed linked turn physically hit `UpperBonk` (authored at x=22,
z=76), producing a collision-related speed loss. Moving the fixture 2 m right
keeps that intended snow-handling route clear; the zero-feature-collision,
speed-retention, carve, and jump assertions are unchanged. Actual obstacle
collision behavior remains covered by the physics collision and crash suites.
