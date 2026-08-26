# Ski Physics

## State model

`SkierController` owns four explicit states: Ground, Air, Grind, and Bail. The physics controller owns motion; visuals only read that state.

Ground contact is sampled at four logical ski locations (front/rear, left/right). A contact is accepted when at least half of the probes hit. The mean normal drives slope projection and basis alignment.

## Ground integration

The velocity is separated into the ski-forward and ski-right axes on the current snow tangent. Gravity is projected onto that tangent. Forward drag is intentionally low and includes a quadratic aerodynamic component; tuck reduces that component. Lateral velocity is removed by a bounded grip force:

```text
grip = min(max_edge_grip, base_lateral_grip + |edge| × max_edge_grip × speed_ratio)
```

Because grip is bounded, a strong lateral load becomes a skid rather than an impossible instantaneous turn. Braking raises lateral grip and forward friction but never snaps velocity to zero. Steering rotates the ski tangent gradually; it is stronger at low speed and more momentum-led at high speed.

## Air and landing

Pop adds a surface-normal impulse on top of existing velocity. Air input adds angular acceleration to a separately tracked angular velocity; damping reduces it gradually.

Landings use a weighted quality score rather than one cutoff. Forward/travel alignment contributes 32%, skier-up/surface-normal alignment 36%, impact 22%, and remaining angular speed 10%. The score maps to clean, sketchy, hard, or bail outcomes. Thresholds are centralized in `resources/physics/default_ski_profile.tres`.

## Rails

Every `GrindRail3D` owns a visual-independent `Curve3D`. Capture requires minimum velocity, distance within the authored radius, and a plausible tangent approach. Momentum is projected onto the tangent and carried through friction/gravity to exit. This keeps capture forgiving without a large invisible magnet.

## Tuning

All important motion values live in `SkiPhysicsProfile`: gravity, forward/lateral friction, edge response, grip, braking, drag/tuck, pop, air acceleration/damping, landing thresholds, and rail values. F3 displays contact confidence, normal, slip, carve force, angular velocity, and current rail.
