# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Animation, physics, and bail recovery

- **Extreme high-energy bails can briefly show a near-vertical ski silhouette during `FALL`.** The body collider and contact probes now stay surface-aligned while the rendered skier tumbles, roll speed is capped, and `REST` cannot begin until the root is snow-aligned. The remaining awkward frames are transient rather than a held vertical-ski pose, but the fall animation is still visibly stylized at the highest angular speeds.

## Ski and pole IK

- **Equipment collision coverage is not yet universal.** Pole shafts now clear torso/leg envelopes and grounded pole tips are floor-bounded; boot targets are stance-separated; crash equipment is constrained; and swept visual ski segments stop at solid park features. There is still no general solver for ski-to-ski, pole-to-pole, every airborne terrain contact, or arbitrary combinations of equipment and body geometry.

## Graphics and performance

- **Advanced renderer options are not fully exposed in the menu.** The current settings cover render scale, TAA, shadow quality, snow quality, SSAO, SSIL, SSR, fog, display mode, resolution with timed Keep/Revert confirmation, VSync, FPS cap, and a profile-gated GI toggle. FSR2, HDR, and reflection-quality controls are not implemented.
