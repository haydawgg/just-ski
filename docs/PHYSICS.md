# Ski Physics

## State model

`SkierController` owns four explicit states: Ground, Air, Grind, and Bail. The physics controller owns motion; visuals only read that state.

Ground contact is sampled at four logical ski locations (front/rear, left/right). Probes cast along the last snow normal (world down before first contact), not the skier's body up, and they hit terrain only. A contact is accepted when at least half of the probes hit, or when the capsule reports a sane floor. The mean normal drives slope projection and basis alignment. Coyote time keeps ground integration running across a one-frame gap; a short minimum air time blocks false landings on lips.

## Collision layers

- Layer 1 Terrain: snow, kickers, landings, banks, lodge.
- Layer 2 Player: the skier capsule.
- Layer 3 Features: tree trunks and other solid park obstacles.
- Layer 4 Grind: rail/box/pipe visuals' collision. The skier does not physically collide with grind; capture is kinematic from the spline.

Kickers are ballistic tabletops: a convex lip, a slope-aligned table sized to ~72% of the no-pop/half-pop range, and a slope-aligned landing. Rollers are long convex whoops that unweight via tip-load. Hips are yawed tabletops that add a lateral takeoff component for lane transfers.

## Ground integration

The park main face is authored around **18°** and ~300 m of world-Z. Snow uses `gravity` (~24); air uses a lower `air_gravity` (~14) for readable hang time. Jump, rail, roller, and hip features are placed on that plane by `ParkLayout` so Y is derived from the slope instead of guessed. A small `glide_acceleration` remains as assist when pointed downhill; forward stick pressure increases tip bite and that glide a little.

The velocity is separated onto the current snow tangent. Forward drag is intentionally low and includes a quadratic aerodynamic component; tuck reduces that component.

Steering rotates ski heading by the requested yaw plus a speed-scaled sidecut term, so an edged ski keeps biting instead of only following the stick. Edge sets faster than it releases, which holds a carve when you ease off the stick. When the edge is near centered, heading weathervanes toward travel (including switch) so the skis run straight after a skid. Tip/tail probe span plus left-stick pressure scales grip: loaded tips bite, a convex rollover or back-pressure unweights.

```text
grip = (base_lateral_grip + |edge| × max_edge_grip × lerp(0.82, 1.0, speed_ratio)) × tip_load_scale × pressure_scale
carve_ratio = clamp(grip / (speed × |edge| × (steer_rate + speed × sidecut)), 0, 1)
```

Turn yaw is applied fully each tick. Only slope-normal alignment is smoothed, so terrain blending cannot eat steering. Steering ramps in with speed so a near-stop cannot pirouette without a hockey-stop pivot; high-speed steering is slower than low-speed steering, but still arcade-playable. Braking raises grip and yaw rate for hockey-stop pivots without snapping velocity to zero.

## Air and landing

Pop adds a surface-normal impulse on top of existing velocity. Flick impulses seed angular velocity; left stick supplies low-authority yaw/flip trim. Base air damping is light so a committed takeoff spin reaches ~360° on the middle kicker; damping rises in the last ~0.2 s before predicted landing so the skier can square up.

Landings use a weighted quality score rather than one cutoff, and they only run after `min_air_time`. Forward/travel alignment contributes 32%, skier-up/surface-normal alignment 36%, impact 22%, and remaining angular speed 10%. Successful landings project velocity onto the snow tangent before applying sketchy/hard speed loss. Bail tumbles in place, keeps a fraction of speed, and recovers on the snow you landed on — it does not force a marker respawn.

## Rails

Every `GrindRail3D` owns a visual-independent `Curve3D`. Capture requires minimum velocity, distance within the authored radius, and a plausible tangent approach. Momentum is projected onto the tangent; gravity and friction apply along the spline, including reverse travel on uphill/rainbow features. Balance drifts with speed, kinks, and boardslides; left stick counters it. Crossing the fail threshold slips off into air (not an instant bail). Grind bodies live on their own physics layer so they cannot bounce the capsule off the spline.

## Park layout

Two downhill lines share the 18° face. Jumps sit on skier's left; the technical rail line sits on the right. Tabletops use `ParkLayout.jump_table(speed, extra_lip)` with this game's air gravity and half-pop so a clean takeoff flick matches the designed rotation window. Rails sit on `snow_at + normal` with per-feature capture radius and friction. A hip, spine bank, transfer box, and lower quarter let you cross lanes without leaving the mover.

## Scoring loop

Successful air and rail exits feed the trick scorer. A short jump→rail or rail→jump link awards a line bonus. The HUD keeps a combo multiplier that rises with consecutive scored tricks and resets on bail. Marker respawn does not clear combo; summit restart does.

## Tuning

All important motion values live in `SkiPhysicsProfile`: ground/air gravity, glide, pressure, forward/lateral friction, edge set/release, sidecut, weathervane, high/low-speed steering, tip grip, braking, drag/tuck, pop, coyote/min air time, air damping/landing window, landing thresholds, bail recover, and rail balance values. F3 displays contact confidence, pressure, normal, slip, carve force, angular velocity, rail balance, and current rail.
