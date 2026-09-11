# Active model-executable implementation plan

This directory contains the active repo-aligned implementation plan for the gameplay, camera, character, course, terrain/snow, world/environment, presentation, performance, display, and supporting QA work identified from the gameplay review and repository audit.

The plan is split only to keep it readable and diffable in GitHub. Treat the parts below as one ordered execution specification. A coding model should read the full plan for context, then implement only the assigned phase and obey the stop/gate rules in the plan.

1. [Overview and architecture](00_OVERVIEW_AND_ARCHITECTURE.md)
2. [Issue register and Phase 0](01_ISSUES_AND_PHASE_0.md)
3. [Camera — Phases 1–3](02_CAMERA_PHASES_1_3.md)
4. [Character/contact — Phases 4–7](03_CHARACTER_CONTACT_PHASES_4_7.md)
5. [Course/world — Phases 8–11](04_COURSE_WORLD_PHASES_8_11.md)
6. [Release — Phases 12–13](05_RELEASE_PHASES_12_13.md)
7. [PR sequence, test ownership, prohibited shortcuts, definition of done](06_PR_TESTS_DOD.md)
8. [Appendices and model handoff](07_APPENDICES.md)

## Lifecycle

This is an active worklist under the repository documentation policy. Keep it in `docs/` while the work is active. When the plan is fully executed, remove the temporary implementation-plan directory or fold any durable contracts into the maintained owning documentation rather than preserving a completed roadmap indefinitely.
