# Summit Sessions documentation

The `docs/` directory contains maintained project contracts, active worklists, and release/validation procedures. It is not an archive of implementation history.

## Product and gameplay

- [Content design](CONTENT_DESIGN_PLAN.md) — current course goals, spot structure, design rules, and remaining human gates.
- [Trick control target](TRICK_CONTROL_TARGET.md) — durable trick-system design principles.
- [Controls](CONTROLS.md) — controller and keyboard behavior.
- [Physics](PHYSICS.md) — locomotion, contact, landing, bail, rail, and tuning ownership.

## Presentation and world

- [Animation](ANIMATION.md) — procedural presentation architecture and ownership boundaries.
- [Graphics](GRAPHICS.md) — renderer, settings, snow, environment, HUD, and visual validation.
- [World authoring](WORLD_AUTHORING.md) — deterministic course authoring and preview workflow.
- [Environment asset catalog](ENVIRONMENT_ASSET_CATALOG.md) — environment asset contracts.

## Validation and performance

- [Known issues](KNOWN_ISSUES.md) — concrete unresolved bugs and missing functionality only; authoritative when an intended contract differs from current behavior.
- [Controller validation](CONTROLLER_VALIDATION.md) — physical-device validation matrix.
- [Production ski-run QA](PRODUCTION_SKI_RUN_QA.md) — end-to-end human gameplay and visual checks.
- [Performance backlog](PERFORMANCE_BACKLOG.md) — active measured performance work.
- [1080p performance reference](PERFORMANCE_BASELINE_1080P.md) — reproducible measurement contract and dated 2026-09-02 reference results.
- [Visual evidence](VISUAL_EVIDENCE.md) — deterministic GPU capture/review workflow.

## Build, media, and assets

- [Release](RELEASE.md) — supported toolchain, Windows export, smoke testing, and licensing boundary.
- [Export content](EXPORT_CONTENT.md) — production resource packaging boundary.
- [Clip capture](CLIP_CAPTURE.md) — prototype/debug recorder contract.
- [Asset policy](ASSET_POLICY.md) — binary-asset growth and provenance rules.
- [Asset sources](ASSET_SOURCES.md) — third-party attribution and source records.

## Documentation policy

Keep a document here only when it remains useful as one of the following:

1. a current product/design contract;
2. a current technical ownership/reference contract;
3. an active worklist or known-issues list;
4. a reproducible validation, performance, authoring, build, or release procedure;
5. a licensing/provenance record that must remain with the project.

Do not add dated postmortems, completed implementation plans, root-cause notes, one-off visual-fix reports, or superseded roadmaps as permanent docs. Put that context in the relevant issue, pull request, commit history, or release notes. If a temporary investigation document is necessary while work is active, remove it or fold its durable conclusions into the maintained reference when the work closes.

Documentation should describe stable behavior and current status. Exact tuning values belong in the owning resources unless they are part of a deliberate external contract.