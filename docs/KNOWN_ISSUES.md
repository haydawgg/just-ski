# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Animation, physics, and bail recovery

- **Extreme high-energy bails can briefly show a near-vertical ski silhouette during `FALL`.** The body collider and contact probes now stay surface-aligned while the rendered skier tumbles, roll speed is capped, and `REST` cannot begin until the root is snow-aligned. Tumble caps were lowered (`crash_roll_max_angular_speed` 3.2→2.2, `crash_ground_max_rotation_rate_degrees` 300→200, `crash_ground_angular_damping` 4.0→5.0) to shorten the worst frames, but the fall animation is still visibly stylized at the highest angular speeds and the improvement still needs human clip review.

## Ski and pole IK

- **Equipment collision coverage is not yet universal.** Pole shafts now clear torso/leg envelopes and each other (grab-aware), grounded pole tips are floor-bounded, boot targets are stance-separated, ski nose/tail pairs hold span, crash equipment is constrained, swept visual ski segments stop at solid park features, and blocked AIR pole shafts retract preview IK. There is still no general solver for every airborne terrain contact, crash-triggering airborne equipment impacts, or arbitrary combinations of equipment and body geometry.

## Graphics and performance

- **HDR output is not exposed in the menu.** The current settings cover render scale, upscaling (Bilinear/FSR 1.0/FSR 2.2) with sharpness, TAA, shadow quality, snow quality, SSAO, SSIL, SSR, reflection quality, fog, display mode, resolution with timed Keep/Revert confirmation, VSync, FPS cap, and a profile-gated GI toggle. HDR output remains unimplemented: it needs an HDR-capable tonemapper (Filmic/ACES are SDR-only), the `request_hdr_output` chain, and platform capability gates.
