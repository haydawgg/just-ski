# Known Issues

This file tracks concrete, actionable bugs and missing functionality. It is authoritative for current behavior: when an intended contract in another maintained document differs from what the implementation does today, this file wins until the behavior or the other document changes. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Ski and pole IK

- **Equipment-to-world overlap recovery is not yet universal.** Registered body, ski, boot, pole-shaft, and basket proxies have deterministic presentation self-collision with explicit intentional-contact groups and multi-rate acceptance (see [Animation](ANIMATION.md)). Existing feature sweeps still own ski/pole impacts, but a final animated attachment that begins inside world geometry is outside `cast_motion()`'s travel-fraction contract and can be produced after the gameplay sweep, because final animation attachment updates run after part of the gameplay sweep path. A general fix needs a starting-overlap recovery policy plus an explicit decision about whether recovery is visual-only or enters gameplay crash handling.
