# Phase 1 — Camera collision-solver correctness and P0 target-loss fix

First make it mechanically impossible for camera collision/fallback logic to abandon the skier. This phase is correctness only; do not tune “feel.”

### Inspect / edit

- player/camera/camera_collision_solver.gd

- player/camera_controller.gd

- tests/camera_airborne_viewport_diagnostic.gd

- tests/camera_performance_acceptance.gd / .tscn

- tests/camera_low_speed_acceptance.gd / .tscn if present locally

### Implementation

1\. Add a solver-level regression for the overlap-only case: cast_motion returns a safe fraction at/near 1.0 but the destination sphere overlaps geometry. The trace result must never return the colliding desired point as its safe position.

2\. Fix CameraCollisionSolver.trace(). If destination overlap is detected without an earlier cast hit, find the furthest clear point on the segment (binary search/backoff using destination_is_clear or an equivalent bounded query). Return a position that is actually clear.

3\. Add a convex-crest AIR→LANDING→GROUND regression at realistic high speed (roughly 20–30 m/s) and run it at 30/60/120 Hz. Use real curved/convex geometry, not an infinite flat floor.

4\. Remove raw frame_start_position as a repeatable fallback after meaningful target translation. Convert every emergency candidate to target-relative space or feed-forward previous offset.

5\. Fallback hierarchy: desired pose → collision-safe pull-in → lift/shoulder only if needed → feed-forward previous valid target-relative pose → last stable target-relative pose → bounded hard reacquire. Every step must enforce min/max distance, min up offset, destination clearance and segment safety.

6\. When a sweep is blocked by a crest, prefer shortening the chase arm toward the target using the safe fraction. The camera is not a physical body; controlled pull-in is preferable to target loss.

7\. Do not advance away the knowledge of missed target translation. If a frame cannot complete the desired follow motion, the next frame must still account for the target-relative deficit rather than only the newest per-frame displacement.

8\. If emergency fallback repeats, target distance exceeds the configured maximum, or the target is hard-invalid/offscreen, invoke a hard reacquire to the closest validated target-relative position.

### Acceptance

| **Metric**                     | **Required result**                                                                                                                                       |
|--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| Destination-overlap regression | Old code fails; new solver returns a clear point.                                                                                                         |
| Convex crest                   | No persistent camera world freeze; skier remains visible through crest/landing.                                                                           |
| Distance                       | Never exceeds current maximum_camera_distance beyond a small numeric tolerance after final commit.                                                        |
| Translation inheritance        | Over any ~0.25 s window where target advances materially, camera cannot remain near-zero in world translation unless a same-window hard reacquire occurs. |
| Fallback loop                  | No repeated multi-frame frame_start_position-style emergency loop.                                                                                        |
| Rates                          | 30/60/120 Hz behavior remains equivalent within reasonable tolerance.                                                                                     |

> **Do not —** Do not hide the defect by increasing maximum camera distance, flattening the crest, moving the jump, disabling collision, or snapping to an unvalidated point.

# Phase 2 — Camera landing recovery and jump-framing continuity

With target loss solved, remove visible takeoff/landing state switches while preserving enough vertical motion to feel airborne.

### Inspect / edit

- player/camera_controller.gd

- player/camera/camera_framing_solver.gd

- player/camera/composition_evaluator.gd

- tests/camera_airborne_viewport_diagnostic.gd

- existing camera visual-evidence fixtures

### Implementation

1\. Resolve LANDING policy explicitly. In reviewed master, LANDING is included in soft_composition_state while also entering the early GROUND/LANDING/RAIL branch. Give LANDING one clear path that always preserves hard skier visibility and collision safety and can perform bounded recovery.

2\. Extend the ground→AIR diagnostic to begin on the real ~18° course slope. The current flat-normal reproduction is insufficient because AIR transitions raw_surface_up toward world-up.

3\. Retain the takeoff surface normal for a short handoff, then blend deliberately toward the chosen airborne reference. Do not let the camera reference frame rotate sharply at the same instant AIR framing/FOV/distance change.

4\. Use planar/downhill travel speed for ordinary speed-distance, speed-height, FOV and look-ahead. Keep vertical jump velocity inside AIR framing rather than treating it as general speed.

5\. Reduce simultaneous AIR scale changes. During the first ~0.2–0.3 s, keep camera distance and FOV close to the grounded solution; let the vertical framing target provide most of the jump read.

6\. Retune CameraFramingSolver one variable at a time. The reviewed solver uses a 0.5 m dead zone and multiplies response by 0.35 during the first 0.18 s. A/B the early multiplier/dead-zone response rather than changing all profile values at once.

7\. Add projected subject screen-rect telemetry. Camera distance and FOV can each stay inside rate limits while the skier still visibly grows/shrinks; gate the combined result.

### Starting acceptance targets

| **Metric**              | **Initial gate**                                                                                                                                 |
|-------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| Screen-Y continuity     | At 540p-equivalent scale, ordinary takeoff center movement over any 0.2 s window should be roughly ≤60 px unless collision recovery is active.   |
| Subject-size continuity | Projected body/ski rect height should not change by more than ~15–18% over an ordinary 0.2 s AIR-entry window without a collision-driven reason. |
| Hard frame              | Body landmarks stay inside the configured hard rect; hard recovery overrides landing-look aesthetics.                                            |
| Horizon/pitch           | No violent pitch/horizon snap as surface normal transitions to AIR.                                                                              |
| Landing                 | LANDING can recover an invalid composition instead of being trapped by an early return.                                                          |

# Phase 3 — Ground-turn framing and restrained speed feel

Make carving communicate trajectory and speed without reintroducing zoom pumping, orbiting or camera shake.

### Implementation

1\. Create a signed turn/trajectory lead, not only an absolute heading-angle look-ahead. Derive direction from smoothed planar velocity change, edge/turn sign, or another authoritative turn signal already available locally.

2\. Apply the lead primarily to the look target rather than aggressively orbiting the camera. Start with a small world-space lateral/forward bias (roughly 1–2 m total at strong sustained carve), smooth it, and clamp it.

3\. Extend the existing camera viewport diagnostic with sustained left/right carve cases and assert mirrored behavior, no oscillation, and a modest screen offset in the direction of travel.

4\. Keep speed response restrained. Prefer nearby world parallax (later environment phase) and small planar FOV response. Do not add continuous shake or large dynamic FOV.

> **Gate —** Linked carves show useful look into the turn while the skier remains comfortably inside the frame; straight-line and jump framing are unchanged.
