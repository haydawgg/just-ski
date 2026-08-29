# Ski Physics

## State model

`SkierController` owns four explicit states: Ground, Air, Grind, and Bail. The physics controller owns motion; visuals only read that state.

The transition contract is fixed: GROUND→AIR on pop or lost support; AIR→GROUND on a plausible landing; AIR→BAIL on an unrecoverable landing or solid-feature impact; AIR→GRIND on valid spline capture; GRIND→AIR on exit, pop-off, or balance slip; BAIL→GROUND only after confirmed bounded rest; and any state→AIR through the authoritative respawn boundary. A rail balance failure first slips into AIR, preserving its side/balance context so a later physical obstacle impact can become a contextual crash without inventing a GRIND→BAIL shortcut.

Ground contact is sampled at four logical ski locations (front/rear, left/right). Probes cast along the last snow normal (world down before first contact), not the skier's body up, and they hit terrain only. A contact is accepted when at least half of the probes hit, or when the capsule reports a sane floor. The mean normal drives slope projection and basis alignment. Coyote time keeps ground integration running across a one-frame gap; a short minimum air time blocks false landings on lips.

## Collision layers

- Layer 1 Terrain: snow, kickers, landings, banks, lodge.
- Layer 2 Player: the skier capsule.
- Layer 3 Features: tree trunks and other solid park obstacles.
- Layer 4 Grind: rail/box/pipe visuals' collision. The skier does not physically collide with grind; capture is kinematic from the spline.

Kickers are ballistic tabletops: a convex lip, a slope-aligned table sized to ~72% of an authored takeoff trajectory, and a slope-aligned landing. `Resort` owns the active `SkiPhysicsProfile` and passes the same resource to course construction and the skier, so jump sizing uses the player's actual air gravity and pop impulse. Each tabletop and hip authors a normalized design-pop strength. Rollers are long convex whoops that unweight via tip-load. Hips are yawed tabletops that add a lateral takeoff component for lane transfers.

## Ground integration

The park main face is authored around **18°** and ~300 m of world-Z. Snow and air both use Earth gravity (9.81 m/s²), so takeoffs, acceleration, and landings share one believable ballistic model. Jump, rail, roller, and hip features are placed on that plane by `ParkLayout` so Y is derived from the slope instead of guessed. A small `glide_acceleration` remains to overcome numerical and contact friction when pointed downhill; forward stick pressure increases tip bite and that glide a little.

The velocity is separated onto the current snow tangent. Forward drag is intentionally low and includes a quadratic aerodynamic component; tuck reduces that component. Contact probes also read the explicitly authored physical surface kind; color and visual material do not select physics. Powder has more drag and less edge grip, packed snow is the neutral baseline, and groomed feature decks are faster and more responsive.

Controller axes have one input pipeline: raw action strength enters the configurable inner/outer deadzone and response curve exactly once. This avoids stacking the InputMap deadzone with a second deadzone. Keyboard input still resolves to full digital strength.

Steering rotates ski heading by the requested yaw plus a speed-scaled sidecut term, so an edged ski keeps biting instead of only following the stick. Edge sets faster than it releases, which holds a carve when you ease off the stick. When the edge is near centered, heading weathervanes toward travel (including switch) so the skis run straight after a skid. Tip/tail probe span plus left-stick pressure scales grip: loaded tips bite, a convex rollover or back-pressure unweights.

```text
grip = (base_lateral_grip + |edge| × max_edge_grip × lerp(0.82, 1.0, speed_ratio)) × tip_load_scale × pressure_scale
carve_ratio = clamp(grip / (speed × |edge| × (steer_rate + speed × sidecut)), 0, 1)
```

Turn yaw is deliberately weighty: a low-speed reference carve changes heading by roughly 30-40°/s rather than pivoting the skier like an arcade vehicle. A speed-dependent soft limit prevents ski heading from running implausibly far ahead of travel direction. Only slope-normal alignment is smoothed, so terrain blending cannot eat steering. Unbraked steering ramps in with speed so a near-stop cannot pirouette; braking bypasses that gate and continuously blends steering boost, grip, and speed scrub from a minor speed check to a deliberate hockey-stop pivot.

## Ground contact

A dedicated suspension layer keeps the skis on the snow instead of gliding on a stale tangent plane. Contact probes cast from slightly above the body origin and only declare grounding when the surface sits within `ground_probe_reach`; a one-sided spring pulls the body toward the average terrain contact point whenever the probes sit above the seat height, so spawn drops, convex crests, and raised deck lips settle smoothly instead of hovering. The capsule is offset so its resting contact puts the body origin at the seat height with skis kissing the surface. Terrain hops (crests, deck lips) rejoin the snow silently through a non-jump reseat, while only deliberate pops run the full landing presentation. Berms and butter pads ramp their uphill edges into lead-in transitions so a fall-line rider rides up the bank instead of dead-stopping on a deck wall; a short wall-pin hop covers any remaining wedge deadlock.

## Air and landing

Pop adds a 4.6 m/s surface-normal impulse on top of existing velocity. On the benchmark slope this produces about 1.3-1.8 m of rise and roughly one second of airtime instead of a floaty super-jump. Flick impulses seed angular velocity; left stick supplies low-authority yaw/flip trim at roughly 25-30% of the corresponding committed impulse per second, so a 360 requires a takeoff gesture rather than being freely steered in the air. Base air damping is light enough to finish that rotation without changing the ballistic arc. A segmented ballistic sweep predicts the landing surface; landing damping only rises near impact when the player is no longer giving active rotation or grab input. Downward velocity is capped only as a world-safety limit for extreme falls.

Landings combine a weighted quality score with hard plausibility gates, and they only run after `min_air_time`. Forward/travel alignment contributes 32%, skier-up/surface-normal alignment 36%, impact 22%, and remaining angular speed 10%. A clean or sketchy result additionally requires sufficient upright alignment and bounded impact; the clean impact window includes a comfortable full-charge pop while harder impacts remain sketchy. Upside-down, over-spun, or over-speed impacts bail regardless of the weighted average. Successful landings project velocity onto the snow tangent before applying sketchy/hard speed loss. Impact severity briefly reduces ordinary steering by at most 32%, recovering over 0.25-0.45 seconds; braking retains full authority, so this communicates weight without taking recovery control away. Failed landings preserve incoming linear and angular momentum into the controlled crash path. A grab's live pose may open before contact, but its accumulated duration, tweak, name, and points persist through landing.

`CourseRecovery` separately catches impossible or out-of-bounds positions after a short grace period and returns the skier through the normal session respawn path. This is a world-safety boundary, not part of ordinary landing or bail evaluation.

## Crash handling

All crash sources cross one guarded `enter_crash(CrashContext)` boundary. Failed landings identify upright, impact, or angular failure deterministically. Solid feature collisions use the incoming normal speed and total speed/retention thresholds from `SkiPhysicsProfile`; low-speed brushes stay ordinary contacts. The boundary snapshots source state, source type, incoming and resolved velocity, impact normal/speed, angular speed, and rail/lateral context before clearing active trick/grab/rail presentation. Scoring and the crash signal fire exactly once, while total score and best trick remain intact.

BAIL preserves motion and applies bounded air/ground angular damping rather than multiplying velocity away on entry. The presentation advances through Release, Impact, Fall, and Rest from the authoritative crash clock. Ground recovery requires both low linear/angular motion and a confirmation/hold interval; `crash_max_duration` provides a final bound. Manual and course respawns clear crash, rail-detach, landing, prediction, motion-history, and animation-frame state at one boundary. F3 exposes reason, source, stage, impact, angular speed, balance, rest, and elapsed time.

## Rails

Every `GrindRail3D` owns a visual-independent `Curve3D`. Capture requires minimum velocity, distance within the authored radius, a bounded vertical gap, and a plausible tangent approach. Entry blends over a short interval instead of snapping instantly, and the initial lateral miss biases the first balance correction. Momentum is projected onto the tangent; gravity and friction apply along the spline, including reverse travel on uphill/rainbow features. Balance drifts with kinks, boardslides, and an explicit per-rail `drift_bias`; object names never influence physics. Left stick counters drift. Crossing the fail threshold slips off into air (not an instant bail). Grind bodies live on their own physics layer so they cannot bounce the capsule off the spline or pull the camera forward as occluders.

## Park layout

Six downhill zones share the 18° face, with readable jump, flow, and jib routes plus frequent transfers. The data-driven course profile currently authors 36 features: gates, rollers, tabletops, hips, side hits, berms, moguls, butter pads, rails, boxes, tubes, wallrides, bonks, and a cannon. Tabletops use `ParkLayout.jump_table(active_profile, speed, extra_lip, drop, design_pop)` so course geometry cannot drift from player gravity or pop tuning. Rails sit on `snow_at + normal` with per-feature capture radius, approach tolerance, friction, and drift bias.

## Scoring loop

Successful air and rail exits feed `RunScoring`, which owns score, combo, line-link timing, best-trick data, and clean/bail run counters. A short jump→rail or rail→jump link awards a line bonus. The HUD mirrors that state and displays combo time plus rail balance. Crossing the finish opens a medal/results summary and persists a personal best; marker respawn clears the pending line link, while summit restart clears the full run score.

## Tuning

The default profile targets grounded, momentum-led freeride handling inspired by modern big-mountain ski games: real gravity, restrained pop, limited edge grip, speed-dependent steering, strong but progressive braking, and low-authority air correction. It is an original calibration, not a reproduction of another game's internal values.

All important motion values live in `SkiPhysicsProfile`: ground/air gravity, per-surface response, glide, pressure, forward/lateral friction, edge set/release, sidecut, weathervane, high/low-speed steering, heading/travel limits, analog braking, drag/tuck, jump charge/pop, coyote/min air time, terminal speed, air damping/landing prediction, landing retention/gates/control recovery, feature-impact thresholds, crash rest/damping bounds, bail recovery, and rail capture/balance/exit values. Superseded one-shot bail speed/tumble tuning has been removed. F3 displays raw and shaped steering, effective steer rate, slope angle, heading/travel separation, brake amount, carve/skid ratio, grip versus centripetal demand, landing control authority, contact data, angular velocity, rail state, and crash context.

## Feel benchmark

`tests/physics_benchmark.tscn` is the deterministic end-to-end handling route. It covers a sustained carve, linked S-turns, a seeded 22 m/s high-speed carve/skid transition, ground acceleration, charged pop, 360, released grab, landing, and braking. The high-speed check requires progressive edge loading during the first 0.25 seconds, bounded one-second heading change and heading/travel separation, measurable skid when grip demand exceeds supply, and at least 60% momentum retention. Its JSON telemetry is written under `user://`, never into the repository.

`tests/crash_recovery_acceptance.tscn` separately covers failed-landing and feature-impact sources, low-speed non-crashes, exact-once accounting, preserved momentum, bounded rest recovery, telemetry, manual cleanup, and 20 repeated crash/respawn cycles.
