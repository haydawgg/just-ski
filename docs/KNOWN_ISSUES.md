# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Ski and pole IK

- **Equipment-to-world overlap recovery is not yet universal.** Registered body, ski, boot, pole-shaft, and basket proxies now have deterministic presentation self-collision with explicit intentional-contact groups and multi-rate acceptance. Existing feature sweeps still own ski/pole impacts, but a final animated attachment that begins inside world geometry is outside `cast_motion()`'s travel-fraction contract and can be produced after the gameplay sweep. A general fix needs a starting-overlap recovery policy plus an explicit decision about whether it is visual-only or enters gameplay crash handling. See `docs/EQUIPMENT_COLLISION_RESEARCH.md`.
