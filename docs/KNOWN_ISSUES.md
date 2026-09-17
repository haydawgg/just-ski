# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Ski and pole IK

- **Equipment collision coverage is not yet universal.** Pole shafts now clear torso/leg envelopes and each other (grab-aware), grounded pole tips are floor-bounded, boot targets are stance-separated, ski nose/tail pairs hold span, crash equipment is constrained, swept visual ski segments stop at solid park features, blocked AIR pole shafts retract preview IK, and pole strikes on solid features (plus steep snow faces far from touchdown) bail through the crash evaluator with grab, landing-window, and speed exemptions. There is still no general solver for arbitrary combinations of equipment and body geometry.
