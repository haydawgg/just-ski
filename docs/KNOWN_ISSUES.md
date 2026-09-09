# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Animation, physics, and bail recovery

- **Grounded tumble choreography still needs a human visual pass.** Grounded `FALL` now couples residual crash spin to surface roll around `normal × travel`, fades that roll as speed drops, and uses speed-aware snow alignment that is strongest in `REST`/`RECOVERY`. FALL sprawl follows skier-local travel through the existing crash pose/settling layers. Automated coverage asserts axes, caps, degenerate fallbacks, per-frame rotation bounds, airborne continuity, and rest/recovery timing; whether the fall reads as a body sliding and rolling on snow remains a presentation judgment.
- **Landing crouch release is two-stage but still needs a human visual pass.** Impact compression holds while wobble decays, then a profile-owned delay extends the legs. Automated coverage asserts wobble-first release, ordinary timing bands, 3 s pathological release, 30/60/120 Hz phase timing, idle, and no extra landing/stomp event. Whether the stand-up reads as stabilize-then-extend rather than a single spring remains a presentation judgment.

## Trick scoring and contact state

- **Airborne ski landing-plane agreement still needs a human visual pass.** AIR preview IK now matches the cached predicted landing plane inside the existing anticipation window, with a dedicated preview weight, extension clearance, stance separation, reach safeguards, and a cheap feature-obstruction veto. Automated coverage asserts window validity, plane tangency, stance, ownership isolation, one prediction evaluation per physics step, AIR-to-GROUND handoff, and 30/60/120 Hz determinism. Whether the preparation reads as a smooth pre-touchdown settle remains a presentation judgment.
- **Grab recognition is proximity-based by design.** Initial contact now requires a 0.14 m hand-to-ski reach with pose, airtime, hold-time, and scoring gates behind it. Whether 0.14 m reads as convincing contact still needs a human camera pass.

## Ski and pole IK

- **Skis and poles penetrate each other, the character, and the environment.** Boot targets are hard-separated to a minimum stance so X-shaped configurations cannot form, and crash equipment constraints keep skis roughly horizontal with tucked poles, but there is no full-body collision solver: skis can intersect terrain/features and poles can pass through the body or snow.
- **Visual skis can intersect park features.** The orange bonk's collider, visual mesh, snow cap, and slope seating are contract-tested to agree, and feature impacts use the guarded crash evaluator, but skis themselves are presentation-only and carry no collision.

## Graphics and performance

- **Advanced renderer options are not fully exposed in the menu.** The current settings cover render scale, TAA, shadow quality, snow quality, SSAO, SSIL, SSR, fog, display mode, resolution, VSync, FPS cap, and a profile-gated GI toggle. FSR2, HDR, reflection-quality controls, and risky-resolution confirmation are not implemented.

## Audio and capture

- **Gameplay clips use MJPEG-in-MP4 and contain no game audio.** The recorder produces large MJPEG-in-MP4 files with limited browser/Discord compatibility and does not include synchronized game audio. H.264 output and audio capture are missing.
