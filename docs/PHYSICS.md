# Ski Physics

## State model

`SkierController` owns four explicit states: Ground, Air, Grind, and Bail. The physics controller owns motion; visuals only read that state.

Ground contact is sampled at four logical ski locations (front/rear, left/right). Probes cast along the last snow normal (world down before first contact), not the skier's body up, and they hit terrain only. A contact is accepted when at least half of the probes hit, or when the capsule reports a sane floor. The mean normal drives slope projection and basis alignment. Coyote time keeps ground integration running across a one-frame gap; a short minimum air time blocks false landings on lips.

## Collision layers

- Layer 1 Terrain: snow, kickers, landings, banks, lodge.
- Layer 2 Player: the skier capsule.
- Layer 3 Features: tree trunks and other solid park obstacles.
- Layer 4 Grind: rail/box/pipe visuals' collision. The skier does not physically collide with grind; capture is kinematic from the spline.

Kickers use a convex wedge so the takeoff is a rideable plane rather than the uphill face of a rotated box.

## Ground integration

The velocity is separated onto the current snow tangent. Gravity is projected onto that tangent. Forward drag is intentionally low and includes a quadratic aerodynamic component; tuck reduces that component.

Steering rotates ski heading by the requested yaw plus a speed-scaled sidecut term, so an edged ski keeps biting instead of only following the stick. Edge sets faster than it releases, which holds a carve when you ease off the stick. When the edge is near centered, heading weathervanes toward travel (including switch) so the skis run straight after a skid. Pointing down the fall line adds a small glide assist; tuck trades a little bite for speed. Tip/tail probe span scales grip: loaded tips bite, a convex rollover unweights.

```text
grip = (base_lateral_grip + |edge| × max_edge_grip × lerp(0.82, 1.0, speed_ratio)) × tip_load_scale
carve_ratio = clamp(grip / (speed × |edge| × (steer_rate + speed × sidecut)), 0, 1)
```

Turn yaw is applied fully each tick. Only slope-normal alignment is smoothed, so terrain blending cannot eat steering. Steering ramps in with speed so a near-stop cannot pirouette without a hockey-stop pivot; high-speed steering is slower than low-speed steering, but still arcade-playable. Braking raises grip and yaw rate for hockey-stop pivots without snapping velocity to zero.

## Air and landing

Pop adds a surface-normal impulse on top of existing velocity. Air input adds angular acceleration to a separately tracked angular velocity; damping reduces it gradually.

Landings use a weighted quality score rather than one cutoff, and they only run after `min_air_time`. Forward/travel alignment contributes 32%, skier-up/surface-normal alignment 36%, impact 22%, and remaining angular speed 10%. Successful landings project velocity onto the snow tangent before applying sketchy/hard speed loss. The score maps to clean, sketchy, hard, or bail outcomes. Thresholds are centralized in `resources/physics/default_ski_profile.tres`.

## Rails

Every `GrindRail3D` owns a visual-independent `Curve3D`. Capture requires minimum velocity, distance within the authored radius, and a plausible tangent approach. Momentum is projected onto the tangent and carried through friction/gravity to exit. Grind bodies live on their own physics layer so they cannot bounce the capsule off the spline. A capture this tick skips landing so snow under the rail cannot steal the grind.

## Tuning

All important motion values live in `SkiPhysicsProfile`: gravity, glide, forward/lateral friction, edge set/release, sidecut, weathervane, high/low-speed steering, steering speed reference, ground-align rate, skid friction, tip grip, braking, drag/tuck, pop, coyote/min air time, air acceleration/damping, landing thresholds, and rail values. F3 displays contact confidence, normal, slip, carve force, angular velocity, and current rail.
