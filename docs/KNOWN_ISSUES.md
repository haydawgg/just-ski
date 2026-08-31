# Known Issues

This file tracks unresolved behavior, missing production work, and checks that still require human validation. Completed validation notes and historical implementation milestones are documented elsewhere.

## Ski feel and controls

- **Crest unweighting is weaker than intended.** The current front/rear contact-probe spacing undersamples some roller crests at the production seat height, so tip-load unweighting can read too softly. Relevant tuning lives in the ski contact geometry and `tip_grip_gain`.
- **Controller feel still needs broader hardware validation.** Xbox, PlayStation, and generic controllers use Godot/SDL input abstraction, but glyph-family detection, hot-plug behavior, deadzone feel, and rumble strength should be verified on physical devices.
- **Long-session feel still needs human playtesting.** Camera comfort, landing/crash threshold preference, rail-balance drift, and high-speed handling are covered by automated behavior checks but still need longer subjective play sessions.
- **Thin-feature rail capture needs an extended stress test.** Automated coverage exercises live rail capture and normal feature traversal, but it does not replace a long high-speed session across narrow rails, boxes, and tubes.

## Animation and character presentation

- **Grab contact is intentionally approximate on the production body.** The production mesh has different shoulder and arm proportions from the canonical pose driver, so grabs are designed for readable near-contact rather than exact wrist-to-marker locking.
- **Occasional pole/body and cloth/skin intersections may still occur.** These need visual checking from multiple camera angles during normal play. The current rig does not attempt full-body collision solving or cloth simulation.
- **Secondary-motion amplitudes still need final visual tuning.** Deterministic tests cover continuity, settling, clamps, combined trick/grab behavior, and frame-rate consistency, but the final inertia feel is still a presentation judgment.

## Graphics and performance

- **Snow presentation still needs representative GPU profiling.** Fast and Premium snow compile and run, but near/far detail blending, crystal response, subsurface strength, and production GPU cost need a dedicated profiling pass.
- **Advanced renderer options are not fully exposed in the menu.** The current settings cover render scale, TAA, shadow quality, snow quality, SSAO, SSIL, SSR, fog, display mode, resolution, VSync, and FPS cap. FSR2, HDR, GI-mode selection, reflection-quality controls, and risky-resolution confirmation are not implemented.
- **The resort is not final production art.** The current environment is procedurally constructed and includes authored presentation dressing, but it still lacks a final handcrafted environment-art pass, a deliberate LOD strategy, and a profiler-driven 1080p High optimization pass.

## Audio and capture

- **Most gameplay audio is procedural.** Speed, skid, rail, wind, pop, and impact feedback are synthesized at runtime. Authored powder, ice, ambience, wind, and spatial feature recordings are not yet included.
- **Gameplay clips use MJPEG-in-MP4 and contain no game audio.** F9 arms the next summit run for capture. The recorder writes JPEG video frames into an MP4 container, which produces larger files and has weaker browser/Discord compatibility than H.264. H.264 encoding and synchronized game audio are future work.

## Recovery presentation

- **Out-of-bounds recovery is abrupt.** After a short grace period the game shows a notice and respawns through the normal session path. There is no production fade, wipe, rewind, or other transition presentation yet.
