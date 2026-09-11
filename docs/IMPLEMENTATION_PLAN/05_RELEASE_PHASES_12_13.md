# Phase 12 — Release performance, display validation, reflection probe, HUD and capture-tool separation

Finish release-time performance and display validation, then resolve presentation systems that can create instability or confuse captures without changing core skiing behavior.

### Whole-game performance characterization

1\. Resolve the target hardware / target-FPS / quality matrix from the current repo documentation or project settings before claiming a final performance PASS. If no shipping target is defined, record the exact test machine and representative local quality presets and treat the result as a provisional non-regression characterization, not a universal performance claim.

2\. Use the existing profiling acceptance and performance-profile schema where present. Record total frame time and CPU/GPU breakdown when exposed by local tooling, including median and tail behavior (p95/p99 or the closest supported equivalent). Also record draw/instance, particle or memory peaks only when the existing harness exposes them; do not invent metrics.

3\. Characterize the canonical run at baseline and final state, including dense resort sections, heavy contact VFX, the longest hero jump/landing and reflection-probe recapture. Existing profiling acceptance must remain green; any regression relative to the recorded baseline must be quantified and explained rather than hidden by lowering the test load.

4\. Declare the numerical pass budget before the final A/B from the named target-FPS/hardware contract. If the project has no such contract, do not fabricate one: report the measured deltas and mark final target-hardware performance review outstanding.

### Display / aspect / HDR validation

1\. Express automated composition limits in normalized viewport coordinates where practical; keep 540p-equivalent pixel values only as readable reference numbers. This prevents a camera PASS from depending on one capture resolution.

2\. Run representative supported resolutions/aspect ratios and window modes: the primary shipping/default configuration plus at least one wider and one narrower supported aspect when the project UI allows them. Verify hard-frame containment, HUD clipping, typography hierarchy and camera lead rather than assuming 16:9 behavior generalizes.

3\. For HDR-capable paths, validate presentation against the window/display actual active HDR state rather than only a saved preference. If a pre-existing local display/HDR defect prevents trustworthy snow/lighting sign-off, record it at baseline and use the Rule 11 exception only if it blocks this phase.

4\. Do not let a display/settings failure masquerade as a camera or lighting regression. Capture the effective resolution, aspect/window mode and SDR/HDR state alongside every final visual-evidence set.

### Reflection probe

1\. A/B the player-following reflection probe at target hardware/settings. Measure frame time around recapture and inspect skis, goggles, rails and feature highlights for visible jumps.

2\. If benefit is minor, reduce recapture frequency, disable during active downhill motion, or remove it. Do not keep an experimental ~10 m / ~0.33 s recapture policy by default without evidence.

### HUD / capture

- Hide developer camera/animation/telemetry overlays by default in release builds but preserve toggles/tooling.

- Do not treat the red REC indicator or circular input visualization in the supplied clip as confirmed release-HUD defects unless they reproduce without capture/debug tooling.

- Perform final typography/hierarchy/spacing cleanup after camera/world composition is stable.

- Use native-resolution lossless screenshots or the repo visual-evidence harness for final texture/shader/equipment approval; do not use the 960×540 MJPEG alone.

> **Gate —** Whole-game profiling remains within the declared target contract or is explicitly marked provisional when no target is defined; no unexplained frame-time/specular discontinuity comes from probe recapture; representative display/aspect paths preserve composition and UI; SDR/HDR evidence reflects the actual active mode; and release captures contain only intentional game UI while QA tooling remains available when explicitly enabled.

# Phase 13 — Integrated release acceptance

Prove the fixes together. Individual subsystem tests are necessary but not sufficient because the original defects were interactions between camera, terrain, animation and presentation.

### Canonical deterministic no-trick acceptance run

**Execution rule —** Use the Phase 0 canonical artifact unchanged for the primary before/after acceptance comparison. If a final tuning change requires changing the canonical artifact itself, version the artifact, explain why, and re-establish a baseline rather than comparing different inputs as if they were the same test.

1\. Start/drop-in and accelerate to high speed.

2\. Linked left/right carves with no tricks.

3\. Jump 1 clean straight air and landing.

4\. Recovery/setup and Jump 2 clean straight air and landing.

5\. Recovery/setup and Jump 3 long straight air over the most demanding convex landing/crest.

6\. Continue skiing for at least five seconds after the final landing; camera must not diverge.

7\. Finish/runout and static environment review.

### Cross-state preservation matrix

- Crash/bail → REST/recovery → normal skiing: existing crash/recovery acceptance remains green and camera reacquires cleanly.

- Low-speed/stop/restart: camera and stance recover without state lock, oscillation or stale target-relative fallback.

- Respawn/marker/course-recovery relocation: discontinuous player relocation cannot leave camera, presentation or animation state stranded; pre-existing session/scoring semantics are not silently changed.

- Rail/feature traversal plus one-sided/low-confidence contact: equipment/contact changes from this plan do not break existing feature-state or equipment-collision acceptance.

- Miss/ride-around path for each hero jump: recovery remains possible and the camera/course do not require the nominal feature trajectory to stay valid.

- These are preservation checks. A failure already recorded in the Phase 0 baseline is not automatically scope expansion; a new failure caused by this plan is a STOP.

### Automated release gates

| **Area**                | **Required final gate**                                                                                                                                                                                              |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Camera correctness      | 0 persistent target-loss frames; no unbounded distance; no repeated stale-world fallback; collision destination always clear; 30/60/120 Hz passes.                                                                   |
| Camera comfort          | No obvious AIR-entry zoom/pitch jump; subject-size and screen-Y continuity meet tuned thresholds; modest carve lead.                                                                                                 |
| Contact/stance          | Physics probe width no longer dictates visual stance; flat-snow stance stays inside min/preferred/max bounds.                                                                                                        |
| Animation               | No-trick air remains athletic; landing preparation preserves suspension; impact/rebound is continuous; carve loading readable.                                                                                       |
| VFX/shadow              | Per-ski load-aware spray; one landing burst; shadow altitude cue correct; diagnostics truly sample their claimed frames/cameras.                                                                                     |
| Course                  | Three increasingly larger primary jumps, clean center line, ~3–4 s setup rhythm, long final runout, StepDown role explicit.                                                                                          |
| Terrain                 | No prominent modular seams; render/collision correspondence within active-zone tolerance; jump shape readable with guide strips hidden.                                                                              |
| Snow/lighting           | Primary piste receives useful form/shadow; no concrete-gray wash or catastrophic low-sun shadow artifact.                                                                                                            |
| Environment             | Structural tree/mountain variety; clean depth layering; useful near-field parallax; no obvious whole-course LOD behavior.                                                                                            |
| Performance             | Existing profiling/quality gates pass; canonical-run performance meets the declared target contract or is explicitly provisional; probe policy is justified with measured recapture cost.                            |
| Visual evidence         | Native/lossless GPU capture at target shipping resolution or at least 1280×720 if no final target is defined; every set records canonical trace/version plus effective display state; human visual review completed. |
| Display/UI              | Representative supported resolution/aspect/window modes preserve camera hard-frame/composition and UI layout; SDR/HDR captures reflect actual active output state; release capture has intentional UI only.          |
| Regression preservation | Cross-state matrix and unrelated acceptance suites do not regress versus Phase 0; newly added fixtures are registered in executable gates and actually run.                                                          |

### Required stress runs

- 50+ convex-crest/landing passes at varied entry speeds and slight approach angles.

- High-speed linked carves left/right with camera and stance telemetry.

- At least three no-trick air sizes: small terrain takeoff, medium table, long hero jump.

- Graphics visual matrix across representative quality settings and at least daytime plus low-angle light if those are supported.

- Native-resolution static captures of snow, jump seams, trees/mountains and equipment at normal chase distance.

- For each hero jump, run the recorded robustness envelope around nominal entry speed (about ±15%), lateral offset and slight approach-angle error, including deliberate misses/ride-arounds.

- Environment-camera occlusion sweep on the canonical line and edge-of-lane variations after final resort dressing.

- Cross-state preservation pass covering crash/recovery, low speed, respawn/marker relocation, rail/feature traversal and one-sided/low-confidence contact using existing fixtures where available.
