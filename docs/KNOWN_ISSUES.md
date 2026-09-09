# Known Issues

This file tracks unresolved behavior, missing production work, and checks that still require human validation. Completed validation notes and historical implementation milestones are documented elsewhere.

## Recently resolved

- **Crest unweighting is covered and tuned.** Production roller geometry now has deterministic front/rear contact, tip-load, vertical-response, partial-support, and runout-recontact coverage in `tests/crest_unweighting_acceptance.tscn`. The active profile uses symmetric `0.84m` front/rear probe offsets; `tip_grip_gain` remains at its existing value.
- **Production grab contact is calibrated.** The default `Skeleton3D` adapter measures its scaled rest-pose arm lengths, follows attached equipment markers, and evaluates a calibrated palm point with `0.18 m` acquisition and `0.12 m` maintenance caps. Remaining grab presentation issues are limited to the intersections listed below.
- **Deterministic animation presentation coverage is complete for automated gates.** All grabs in `default_grab_animation_library.tres`, all four style poses, the transition phases, fixed front/side/opposite/three-quarter views, and 30/60/120 Hz continuity are covered by `animation_presentation_quality_acceptance.tscn` and the ignored `animation_presentation_audit_<fps>` captures. This does not close human feel or final cloth/pole review.
- **Visual capture correctness is now a blocking gate.** Headless capture requests fail clearly with `runtime.headless=true`; GPU environment and sunset gates clear stale outputs, wait for process exit, require pixels plus telemetry, run their metrics, and fail on timeout, nonzero exit, capture errors, or texture/ObjectDB shutdown warnings. The canonical daylight metric input is `res://.godot_user/captures/snow_depth_after`.
- **Lower-run and hub procedural dressing is contract-tested.** Deterministic catalog-backed boulders are grounded, non-colliding, outside the authored feature routes, and inherit finite ordered catalog LOD ranges. Final art direction and target-display/performance review remain open.

## Ski feel and controls

- **Controller feel still needs broader hardware validation.** Xbox, PlayStation, and generic controllers use Godot/SDL input abstraction, but glyph-family detection, hot-plug behavior, deadzone feel, and rumble strength should be verified on physical devices.
- **Long-session feel still needs human playtesting.** Camera comfort, landing/crash threshold preference, rail-balance drift, and high-speed handling are covered by automated behavior checks but still need longer subjective play sessions.
- **Thin-feature rail capture needs an extended stress test.** Automated coverage exercises live rail capture and normal feature traversal, but it does not replace a long high-speed session across narrow rails, boxes, and tubes.
- **The content pass still needs clean-player human acceptance.** Six stable spots, three route tiers, optional challenges, an opt-in Session Yard, and local telemetry are implemented and covered structurally. Human sessions must still confirm route readability, voluntary retries, practical markers, second-line discovery, and recovery from misses before typed feature migration or Session Yard menu exposure.

## Animation and character presentation

- **Daylight snow contrast is now within the automated visual target.** The September 2026 pass adds a neutral drift-value field and luminance floor to the render-only summit surface. Fresh capture runs average about 0.10 luminance spread (the gate keeps a 0.095 stability floor); blue-shadow coverage and the sunset near-black-region check pass. Keep a human art-direction review in the release matrix because the surface remains procedural.

- **Pole clearance is enforced; cloth simulation remains deferred.** The confirmed ground-pose inward pole crossing is fixed. Switch skiing and every supported grab/style pose now assert outward/downhill shafts with at least `0.10 m` pole-to-knee clearance at 30/60/120 Hz, while preserving hand attachment through a deterministic fallback. Clothing shells share the body skin weights and the tailored seam check passes. The rig has no full-body collision solver or cloth simulation, and the refreshed captures show no confirmed cloth penetration, so unusual combinations still need a human camera pass.
- **Secondary-motion amplitudes still need final visual tuning.** Deterministic tests cover continuity, settling, clamps, combined trick/grab behavior, and frame-rate consistency, but the final inertia feel is still a presentation judgment.

## Graphics and performance

- **Target-class integrated-GPU validation passed on the local Intel UHD adapter.** Medium now uses a measured 0.65 render scale and records roughly 13.6 ms average / 14.5 ms p95 at 1080p on Vulkan GPU index 2; repeat the same matrix on each supported hardware tier before release.

- **Snow presentation still needs representative GPU profiling.** Fast and Premium snow compile and run, but near/far detail blending, crystal response, subsurface strength, and production GPU cost need a dedicated profiling pass.
- **Advanced renderer options are not fully exposed in the menu.** The current settings cover render scale, TAA, shadow quality, snow quality, SSAO, SSIL, SSR, fog, display mode, resolution, VSync, FPS cap, and a profile-gated GI toggle. FSR2, HDR, reflection-quality controls, and risky-resolution confirmation are not implemented.
- **The resort is not final production art.** The summit-to-first-landing slice and the lower-run/hub edge dressing now have deterministic procedural coverage. The lower run and hub remain graybox-oriented in their broader terrain/feature language and still need human art-direction review plus a profiler-driven 1080p High optimization pass.
- **Renderer shutdown warnings are treated as capture failures.** The GPU environment, sunset, and animation capture teardowns drain render frames after freeing generated nodes; any leaked texture RID or ObjectDB warning now fails the corresponding gate. No such warning appears in the refreshed environment or sunset runs.

## Audio and capture

- **Most gameplay audio is procedural, but its measured average is within budget.** The refreshed uncapped profile records roughly 0.08–0.10 ms average processing; work is capped to prevent the old multi-millisecond first-fill spike. Authored powder, ice, ambience, wind, and spatial feature recordings remain future content work rather than a current performance blocker.
- **Gameplay clips use MJPEG-in-MP4 and contain no game audio.** The recorder writes JPEG video frames into an MP4 container, which produces larger files and has weaker browser/Discord compatibility than H.264. H.264 encoding and synchronized game audio are future work.

## Recovery presentation

- **Out-of-bounds recovery now has configurable fade-out, respawn, and fade-in timing plus a GPU review capture.** `visual_analysis_bundle.ps1 -IncludeRecovery` records the HUD notice, phase images, overlay alpha, camera/root transforms, and lifecycle signals; a human visual pass is still required for readability across display refresh rates. It is intentionally not treated as a physics pause.
