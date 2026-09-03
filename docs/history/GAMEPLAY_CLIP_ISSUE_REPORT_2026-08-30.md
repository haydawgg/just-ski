# Gameplay clip issue report — ski run

## Triage summary

| Field | Value |
| --- | --- |
| Source | `ski_clip_2026-08-30_14-32-07.mp4` |
| Duration / format | 33.6 seconds, 960 × 540, 30 fps video |
| Build / platform / input | Not provided |
| Severity | **Major** |
| Priority | **High** |
| Scope | Environmental scale, collision affordance, crash recovery, and camera framing |

The clip damages course readability, physical credibility, and player-control feedback. The findings below are independently triageable. “Confirmed” means directly visible in the clip; “source-corroborated” means the current implementation supports the interpretation; “visually suspected” means the clip suggests a problem but does not prove its cause.

## Findings

### 1. Environmental props lack a consistent human-scale standard

**Evidence:** confirmed visual mismatch; some observations remain perspective-dependent.

- **00:00–00:02 and 00:31–00:33:** the start/finish gate posts and nearby course props provide an inconsistent scale reference against the skier. Post height, spacing, and apparent thickness do not read as one intentional gate family.
- **00:07–00:20:** gray feature slabs, long boxes/rails, colored panels, trees, and guide objects vary in apparent size relative to the skier. The slab/box proportions are confirmed in-frame; the exact meter error of distant trees and panels is visually suspected because perspective and camera distance affect the comparison.
- Gate dimensions should be authored against a 1-unit = 1-meter convention and an adult-skier reference of approximately 1.62–1.98 m.

**Player impact:** players cannot reliably judge approach speed, jump distance, clearance, or whether a feature is rideable.

### 2. Solid-looking objects behave like non-solid “ghost” geometry

**Evidence:** confirmed visual/physical ambiguity; source-corroborated for route guidance.

- **00:07–00:20:** several rigid-looking rails, slabs, panels, and guide objects read as obstacles or surfaces, yet the skier does not receive a clear physical response when passing through/near them. The clip does not directly contact every distant object, so a broken collider is not proven for each one.
- Source inspection corroborates the route-guide case: `ParkLayout.add_gate()` authors route-gate visuals with collision disabled (`non_colliding` metadata). This is valid for guidance only if those posts/flags are visibly soft and clearly non-solid.
- Do **not** infer broken collision for the orange barriers that remain at a distance and are never directly contacted in the clip.

**Player impact:** the visual language does not communicate which geometry blocks, grinds, redirects, or is safe to pass through. This makes failures look random and undermines trust in the course.

### 3. Crash recovery allows player and camera clipping

**Evidence:** confirmed.

- **00:20.6–00:24.5:** the skier/crash animation visibly intersects a cyan-and-white linear course asset. During the same fall the camera swings behind or into nearby geometry and temporarily loses a readable view of the player.
- **00:20.5–00:21.5:** speed drops from roughly 76 to 0 while the HUD labels the attempt “SKETCHY.” The clip does not expose a definitive collider, so the immediate trigger is visually suspected; it may be a failed landing, feature impact, or course-boundary response.
- **00:29–00:31:** recovery/respawn appears abrupt. The player returns to the start area without a clear fade or completion cue.
- The HUD appears to retain score/multiplier presentation around the return to the gate. Current source behavior resets the line link during `SkierController.respawn_at()` but previously did not explicitly clear combo state; this is source-corroborated as a stale-state risk.

**Player impact:** the fall is difficult to understand, the skier can disappear into geometry, and recovery feels like a teleport rather than an intentional state transition.

## Reproduction steps

1. Launch the build with the same route, camera profile, and input configuration used for the supplied clip (build/platform/input details are not provided).
2. Start at the summit gate and ride through the upper and mid-course features shown at **00:07–00:20**.
3. Approach the cyan-and-white linear feature at the speed shown near **00:20.5** and reproduce the failed landing/impact.
4. Record the skier, camera, collision diagnostics, crash reason, collider name/layer/normal, and scoring snapshot through **00:20.6–00:31**.
5. Repeat at 30, 60, and 120 Hz with keyboard and controller input.

## Expected versus actual behavior

| Area | Expected | Actual in clip |
| --- | --- | --- |
| Scale | Props share a documented meter scale and read consistently against the skier. | Gate, tree, slab, rail, and panel proportions vary; exact error is not measurable from every angle. |
| Affordance | Visible SOLID geometry has matching collision; GUIDE geometry is visibly soft/non-solid; GRIND_ONLY geometry captures only through the grind contract. | Several rigid-looking objects appear ghost-like or have ambiguous affordance. |
| Crash cause | Crash HUD/telemetry identifies landing, angular error, feature impact, or leaving-course reason. | The clip shows a “SKETCHY” failure but no readable cause. |
| Crash pose | Skis, poles, boots, pelvis, and body remain attached and readable through release, impact, fall, and rest. | Equipment/body intersections are visible or suspected during the fall. |
| Recovery | Input freezes; fade-out → respawn → camera reset → fade-in completes once; total score is preserved while combo/link state clears. | Return is abrupt and camera/player framing is lost during the crash/recovery sequence. |
| Camera | Swept-volume collision keeps at least 0.35 m from geometry and keeps the skier in a playable screen region. | Camera moves behind/inside geometry and loses the skier temporarily. |

## Suggested investigation areas

- Validate each environment asset against nominal dimensions, grounding point, LOD distances, and source/license metadata.
- Use one authored source for render and collision extents; audit collision layers, normals, and impact speeds in crash diagnostics.
- Keep route gates and landing/takeoff markers collider-free, translucent, and unmistakably guidance-only.
- Separate landing, feature-impact, and out-of-bounds crash/recovery reasons in telemetry and HUD presentation.
- Clamp crash equipment attachment constraints and add automated ski-separation/pole-attachment checks.
- Replace a single camera ray with a swept camera volume, excluding the skier and guide layers, with a last-valid-pose fallback.
- Add a deterministic replay and screenshot pass at near, mid, and gameplay distances to verify scale and contrast.

## Acceptance criteria

- Every catalog asset has a stable ID, nominal meter dimensions, asset class, readability category, LOD distances, and source/license metadata.
- Authored dimensions remain within ±10% of catalog dimensions, with origins grounded at snow contact.
- Every `SOLID` asset has visible collision extents within ±10% of its mesh; every `GUIDE` asset has no collider and is visually identifiable as non-solid; `GRIND_ONLY` assets do not bounce the skier capsule.
- No clip-replay frame places the skier or camera inside terrain or feature geometry.
- Crash replay identifies a valid landing, feature, or out-of-bounds cause and reports collider name/layer/normal/impact speed when applicable.
- Crash equipment keeps calibrated ski separation and pole/body attachments through release, impact, fall, and rest.
- Recovery emits exactly one lifecycle sequence, returns the skier to a valid position, clears combo and line-link state, and preserves total score.
- In deterministic replay of the supplied route, the skier remains within the camera’s playable screen region for at least 95% of frames.
- Environment screenshots pass contrast/readability checks at near, mid, and gameplay-distance views.
- Existing physics, animation, character-scale, camera, environment, and runtime-quality tests remain green; manual 30/60/120 Hz keyboard/controller play passes the supplied route, high-speed landings, rails, boundaries, crashes, and recovery.
