# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Startup and reset

- **Spawn-to-snow settling can still look abrupt.** The initial airborne hover transitions into skiing shortly after spawn. Unarmed post-spawn seating no longer plays a landing crouch, and pose/IK/camera state is primed before the first frame, but the root still seats onto the support surface as the hover falls.

## Animation, physics, and bail recovery

- **Grounded tumble choreography still needs a human visual pass.** Bail entry clears locomotion channels, grounded crashes keep a damped tumble with stage-dependent snow alignment, FALL/REST keep minimum secondary motion, and recovery returns through one rate-limited transition with a seeded ground settle. Automated coverage asserts the lifecycle, momentum, and continuity bounds; whether the fall reads convincingly is a presentation judgment.
- **Landing crouch release is bounded but still needs a human visual pass.** Balance-driven wobble decays with presentation age with a 1.5 s failsafe, so rotational landings can no longer hold compression indefinitely. Automated coverage asserts release within 3 s; the feel of the release remains a presentation judgment.

## Trick scoring and contact state

- **Airborne skis do not IK-anticipate the predicted surface.** Terrain probes and capsule touchdown end airborne state within 0.05 m of the seat, touchdown freezes the shared trick-rotation snapshot used by display, scoring, and landing validity, and anticipation leg extension is restrained near the seat. The rendered skis are still FK-posed in AIR, so exact pre-touchdown surface agreement still needs a human visual pass.
- **Grab recognition is proximity-based by design.** Initial contact now requires a 0.14 m hand-to-ski reach with pose, airtime, hold-time, and scoring gates behind it. Whether 0.14 m reads as convincing contact still needs a human camera pass.

## Ski and pole IK

- **Skis and poles penetrate each other, the character, and the environment.** Boot targets are hard-separated to a minimum stance so X-shaped configurations cannot form, and crash equipment constraints keep skis roughly horizontal with tucked poles, but there is no full-body collision solver: skis can intersect terrain/features and poles can pass through the body or snow.
- **Visual skis can intersect park features.** The orange bonk's collider, visual mesh, snow cap, and slope seating are contract-tested to agree, and feature impacts use the guarded crash evaluator, but skis themselves are presentation-only and carry no collision.

## Graphics and performance

- **Advanced renderer options are not fully exposed in the menu.** The current settings cover render scale, TAA, shadow quality, snow quality, SSAO, SSIL, SSR, fog, display mode, resolution, VSync, FPS cap, and a profile-gated GI toggle. FSR2, HDR, reflection-quality controls, and risky-resolution confirmation are not implemented.

## Audio and capture

- **Gameplay clips use MJPEG-in-MP4 and contain no game audio.** The recorder produces large MJPEG-in-MP4 files with limited browser/Discord compatibility and does not include synchronized game audio. H.264 output and audio capture are missing.
