# Content Pass Implementation

This document records the implemented content architecture, the deterministic evidence now available, and the remaining human acceptance gates. `ParkCourseProfile` remains the source of truth; gameplay physics, trick tuning, animation, rail balance, and public gameplay states are unchanged.

## Current status: automated evidence vs human acceptance

| Area | Automated status | Human-only status |
| --- | --- | --- |
| Six main spots, semantic metadata, challenges, Session Yard profile, and local telemetry | Implemented and covered by content/runtime acceptance scenes | Clean-player route readability, retry behavior, and marker usefulness remain open |
| Animation presentation | All production grabs and style poses are exercised by the 30/60/120 Hz deterministic matrix and multi-angle capture | Controller feel, unusual grab combinations, final cloth/pole review, target-display review, and long-session feel remain open |
| Lower-run and hub dressing | Catalog-backed deterministic decoration, grounding, collision policy, and LOD contracts are checked | Final art direction, target-display readability, and profiler-driven performance review remain open |

Automated completion is not a substitute for the human gates in the last column. No controller, subjective-feel, target-GPU, or human visual-acceptance item is marked complete here.

## Main resort spots

| Stable ID | Display name | Anchor (x, z) | Recommended marker (x, z) | Route intent |
| --- | --- | ---: | ---: | --- |
| `summit_fundamentals` | Summit Fundamentals | 0, 116 | 0, 138 | Wide roller bypass; small-table progression; two-step jib line |
| `upper_fork` | Upper Fork | 0, 86 | 0, 104 | Safe flow/berms; intermediate air and rail; expert bonk transfer |
| `technical_yard` | Technical Yard | 2, 47 | 0, 72 | Mogul/butter recovery; table progression; kink/DFD/wall technical line |
| `transfer_zone` | Transfer Zone | 3, 2 | 0, 35 | Roller bypass; hip/tube line; spine-proxy and box transfers |
| `lower_hero` | Lower Hero and Rainbow | 5, -49 | 0, -20 | Butter recovery; large-table/S-rail line; Rainbow, side-hit, and wall transfers |
| `finale` | Finale | 2, -111 | 0, -78 | Box/berm runout; step-down line; cannon/DFD commitment line |

Every runtime feature now carries `feature_id`, `spot_id`, `route`, `skill_floor`, `skill_ceiling`, `intent_tags`, `risk_level`, `hero_feature`, and `optional` metadata in addition to its existing asset and collision contract. `ParkSpotSpec` owns stable spot identity, its anchor and recommended marker, intent tags, and ordered feature references. Validation rejects duplicate IDs/names, unknown kinds, invalid dimensions, underspecified rails, invalid spot assignments, and broken challenge references.

The course builder remains deterministic:

```text
ParkCourseProfile dictionaries
        + ParkSpotSpec / challenge definitions
                         |
                         v
ParkCourseBuilder -> shared render/collision builders -> runtime feature metadata
                         |
                         +-> resort runtime
                         +-> static preview baker
```

## Capability audit

No new feature type is required for the current acceptance model:

- `CenterSpine` remains a profiled side-hit proxy. A true two-face spine stays deferred until playtesting demonstrates a line the proxy cannot support.
- Berms and profiled side hits provide banked transfer and recovery geometry without a separate diagonal-bank kind.
- Existing boxes and independent rail specs cover the current technical progression; no stair set is required yet.
- `GrindRail3D` already consumes deterministic multi-point paths. `SRail`, `Rainbow`, and `YardCurveRail` exercise deliberate curved/kinked authoring without changing capture or balance contracts.

## Optional challenges

`ParkChallengeTracker` evaluates data definitions against normalized, authoritative outcomes. Supported conditions are straight/minimum rotation, grab-and-land, named or any rail, ordered feature sequence, clean landing, no bail, minimum score, selected route, and run completion. It exposes snapshots and completion signals only; it has no movement, physics, or landing-resolution dependency.

The pause menu includes a Spot Challenges panel. It displays the active spot's challenge definitions and completion status from `ParkContentTracker`; the UI does not evaluate or mutate challenge state.

## Session Yard

`resources/course/session_yard_course_profile.tres` is a separate opt-in profile with one recommended marker, central setup terrain, small and medium jumps, a flat box, a four-point curved rail, side hit, recovery berm, wall, and terrain-only butter line. It uses the same course builder and asset/collision contracts as the main resort. It is deliberately not the default course and is not exposed as progression content before the main resort's clean-player playtest gate.

## Local telemetry

`ParkContentTracker` records a bounded, development-only trace (maximum 256 records) for spot entry, feature approach/completion, route sequence, rail capture/result, landing, bail source, marker save/return, attempt count, score, challenge completion, and run completion. Release builds still feed the in-memory challenge evaluator but do not retain the diagnostic trace unless `--content-trace` is explicitly supplied.

## Preview workflow

The main resort and Session Yard use the deterministic commands documented in `docs/WORLD_AUTHORING.md`. Their generated `.tscn` previews live under ignored `world/generated/` and must be reviewed in the editor after layout changes. The lower-run/hub dressing is built by the same runtime path around `lower_run`, `finale`, and `ParkLayout.hub_position()` anchors. Reviewed screenshots have not been committed because the required clean-player/human sight-line pass has not yet occurred; adding images before that review would incorrectly present unaccepted geometry as final.

## Automated coverage

- `content_pass_acceptance.tscn`: six stable spots, complete metadata, three route tiers, marker placement, bypass/recovery semantics, references, validator rejection cases.
- `park_content_runtime_acceptance.tscn`: repeated-build equivalence, runtime metadata, side-hit shared render/collision geometry, Session Yard content and deterministic ordering, local telemetry.
- `park_challenge_acceptance.tscn`: rotation, grab/land, named and any rail, sequence, score, route, clean/no-bail challenge evaluation.
- `session_flow_acceptance.tscn`: resort content observer and pause-menu challenge surface in the normal finish flow.
- `environment_asset_production_acceptance.tscn` and `environment_visual_acceptance.tscn`: catalog-backed lower-run/hub dressing, deterministic anchors, grounding, non-collision decoration, catalog LOD ranges, and existing feature/collision contracts.
- `animation_presentation_quality_acceptance.tscn`: every supported production grab plus style poses, hold/contact reach, equipment attachments, landing handoff, and 30/60/120 Hz continuity.

## Remaining acceptance and art work

Automated work completed in this pass:

- The multi-angle animation presentation audit captures front, side, opposite-side, and three-quarter views for every grab and style pose. It emits per-frame JSON and still evidence under `.godot_user/captures/animation_presentation_audit_<fps>/`.
- The lower run and hub have deterministic, catalog-backed `snow_boulder` dressing outside the authored route/feature corridor. Added procedural assets inherit finite, ordered catalog LOD distances; near shadow readability is retained and far detail is shadow-free.
- These checks preserve existing feature geometry, collision ownership, and public gameplay contracts.

The deterministic commands are:

```powershell
& $env:GODOT_PATH --path . --fixed-fps 30 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-animation-presentation-audit --audit-fps=30
& $env:GODOT_PATH --path . --fixed-fps 60 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-animation-presentation-audit --audit-fps=60
& $env:GODOT_PATH --path . --fixed-fps 120 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-animation-presentation-audit --audit-fps=120
& $env:GODOT_PATH --headless --path . res://tools/world/bake_resort_preview.tscn -- --output=res://world/generated/resort_preview.tscn
```

Generated previews and captures are evidence only and remain ignored.

Code/system limitation:

- Feature dictionaries remain intentionally untyped until M1 human acceptance stabilizes the field set. Migrate them to `ParkFeatureSpec` resources afterward without changing builder output.

Human/tuning gates:

- Run clean-player sessions at normal physics rate for all six spots. Record safe-line discovery, voluntary retries, marker use, second-line discovery, and miss recovery.
- Review both generated previews for approach readability, crossovers, landing/runout spacing, and the Session Yard retry loop.
- Tune placements from observations; automated metadata cannot prove that a route reads correctly at gameplay camera height.

Art limitations:

- Lower-run and hub dressing/LOD are now procedurally dressed and contract-tested, but final art direction, target-display review, and profiler-driven optimization remain open.
- New spine, stair, bank, or rail art should only be commissioned if accepted lines prove the current procedural vocabulary insufficient.

Human-only gates still open:

- clean-player sessions at normal physics rate for all six spots;
- controller hardware validation, subjective skiing/camera/landing/rail feel, and long-session stability;
- unusual grab combinations and final cloth/pole visual review from normal gameplay cameras;
- target-display and target-GPU review, including representative snow/VFX cost;
- review of generated previews for approach readability, crossovers, landing/runout spacing, and Session Yard retry flow.

Typed `ParkFeatureSpec` migration and default Session Yard exposure remain deferred until the stated clean-player gate passes. Visual capture shutdown warnings are now treated as blocking gate failures; the current capture and diagnostic runs complete without renderer leak warnings.
