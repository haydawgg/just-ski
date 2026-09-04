# Content Pass Implementation

This document records the implemented content architecture and the remaining human acceptance gates. `ParkCourseProfile` remains the source of truth; gameplay physics, trick tuning, animation, rail balance, and public gameplay states are unchanged.

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

The main resort and Session Yard use the deterministic commands documented in `docs/WORLD_AUTHORING.md`. Their generated `.tscn` previews live under ignored `world/generated/` and must be reviewed in the editor after layout changes. Reviewed screenshots have not been committed because the required clean-player/human sight-line pass has not yet occurred; adding images before that review would incorrectly present unaccepted geometry as final.

## Automated coverage

- `content_pass_acceptance.tscn`: six stable spots, complete metadata, three route tiers, marker placement, bypass/recovery semantics, references, validator rejection cases.
- `park_content_runtime_acceptance.tscn`: repeated-build equivalence, runtime metadata, side-hit shared render/collision geometry, Session Yard content and deterministic ordering, local telemetry.
- `park_challenge_acceptance.tscn`: rotation, grab/land, named and any rail, sequence, score, route, clean/no-bail challenge evaluation.
- `session_flow_acceptance.tscn`: resort content observer and pause-menu challenge surface in the normal finish flow.

## Remaining acceptance and art work

Code/system limitation:

- Feature dictionaries remain intentionally untyped until M1 human acceptance stabilizes the field set. Migrate them to `ParkFeatureSpec` resources afterward without changing builder output.

Human/tuning gates:

- Run clean-player sessions at normal physics rate for all six spots. Record safe-line discovery, voluntary retries, marker use, second-line discovery, and miss recovery.
- Review both generated previews for approach readability, crossovers, landing/runout spacing, and the Session Yard retry loop.
- Tune placements from observations; automated metadata cannot prove that a route reads correctly at gameplay camera height.

Art limitations:

- Lower-run and hub dressing/LOD remain a separate production-art pass.
- New spine, stair, bank, or rail art should only be commissioned if accepted lines prove the current procedural vocabulary insufficient.
