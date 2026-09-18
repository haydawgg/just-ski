# Summit Sessions content design

This document is the maintained course/content design contract. It describes the current resort structure, the rules new content must follow, and the human validation that remains open. Completed implementation history belongs in Git and pull requests, not in this file.

## Current status

The structural content pass is implemented:

- six stable main-resort spots;
- semantic feature metadata and stable spot IDs;
- optional spot/line challenges;
- an opt-in Session Yard profile;
- local development telemetry for attempts, routes, landings, rails, bails, markers, challenges, run completion, and per-spot camera/landing/trick diagnostics;
- deterministic runtime and preview construction from the same course data;
- automated acceptance for content references, ordering, metadata, challenges, and Session Yard construction.

The remaining gates are primarily human-only: clean-player route readability, voluntary retry behavior, marker usefulness, controller feel, camera/landing/rail feel, unusual grab combinations, final presentation review, representative GPU/display review, and long-session validation.

`ParkFeatureSpec` migration, default-menu exposure of Session Yard, and new geometry kinds remain deferred until those human gates produce a concrete need.

## Product target

The primary player is a controller-first, skill-oriented action-sports player who wants to improve through practice and create stylish lines. Real skiers, score chasers, and clip creators are important secondary users, but the course should first serve players who enjoy learning a mechanical system.

The intended loop is:

```text
learn -> attempt -> understand -> retry -> master -> express -> capture
```

Content should support that loop through readable cause and effect, low-friction retries, multiple valid approaches, meaningful route choices, memorable session spots, recovery opportunities, and enough depth that mastery comes from technique rather than stat progression.

A feature is not complete merely because it can be traversed. A strong feature creates decisions.

## Content design rules

### 1. Three-layer feature test

Every hero feature should support a readable beginner use, a deliberate intermediate extension, and an expert possibility that may not be obvious on the first pass.

Example:

```text
Tabletop
- beginner: straight air
- intermediate: 360 + grab
- expert: diagonal transfer to rail or bank
```

### 2. Spots over obstacle chains

Prefer compact clusters of interacting terrain and features over long sequences of unrelated obstacles. A good spot should be worth repeating from one marker and should support several planned lines.

### 3. Terrain is gameplay

Rollers, banks, berms, compressions, side hits, transitions, ridges, and speed-control sections are intentional gameplay. Rails and jumps should not carry the entire freestyle experience.

### 4. Safe line plus ambitious line

Most major sections should expose an obvious survivable route and at least one optional higher-risk route.

### 5. Failure can create a line

Where practical, use banks, runouts, or secondary features so a missed transfer can become an improvised continuation instead of an automatic reset.

### 6. Route choice must change technique

Different routes should emphasize different skills: speed control, carving, airtime, rail balance, transfer precision, recovery, or style. Avoid parallel lanes that look different but play the same.

### 7. Preserve deterministic authoring

Gameplay geometry must continue to come from course data and reusable builders. Do not introduce one-off editor-only gameplay geometry that bypasses collision, readability, test, or asset contracts.

### 8. Fix geometry before physics

Do not change skier physics to make a weak feature or approach playable. Tune placement, approach, landing, runout, or feature dimensions first. Physics changes require a gameplay-system reason beyond one content problem.

## Main resort spots

The main resort is organized into six stable spots. Their IDs are part of the content/debug contract.

| Stable ID | Display name | Purpose |
| --- | --- | --- |
| `summit_fundamentals` | Summit Fundamentals | Low-risk onboarding for speed, carving, straight air, first grab, and first jib. Every feature is bypassable and useful marker positions are nearby. |
| `upper_fork` | Upper Fork | First meaningful route decision: air, flow, and jib choices with at least one crossover and one expert transfer. |
| `technical_yard` | Technical Yard | Compact session spot built around repeatable box/rail/wall attempts, with a safer progression option and usable recovery terrain. |
| `transfer_zone` | Transfer Zone | Creative line-building area where hip/side-hit/box/tube relationships support normal landings, transfers, and a direct safe route. |
| `lower_hero` | Lower Hero and Rainbow | Memorable lower-park landmark centered on the Rainbow, with standard and expert entries plus side-hit/butter/wall alternatives. |
| `finale` | Finale | Final meaningful choice between air and technical finishes, with a catch/recovery route reconnecting both to the finish. |

### Spot acceptance standard

Each spot should answer these questions in play, not just in metadata:

- Can a first-time player identify a safe route without explanation?
- Can a player place or use a marker and retry the intended feature with little friction?
- Is a second line discoverable after basic competence?
- Does an expert have a reason to combine or transfer between features?
- Can a physically plausible miss continue without always forcing a respawn?
- Does the spot remain readable from normal gameplay camera height and speed?

## Metadata and content structure

The current course profile remains dictionary-backed. Runtime features carry stable identity and semantic metadata including:

```text
feature_id
spot_id
route
skill_floor
skill_ceiling
intent_tags
risk_level
hero_feature
optional
```

Spot definitions provide stable identity, display name, anchor, recommended marker position, intent tags, and ordered feature references. This metadata exists for content organization, UI, telemetry, and tests; it does not own physics.

Typed `ParkFeatureSpec` resources are a deferred authoring improvement. Migrate only after human playtesting shows the current field set is stable enough to justify the change. Any migration must preserve deterministic ordering, builder output, collision/asset contracts, preview equivalence, and validation of duplicate IDs, invalid kinds/dimensions, broken spot references, and underspecified rails.

## Optional challenges

Challenges are suggestions, not progression gates. Players must always be able to ignore them and free ski.

The current evaluator can express goals such as minimum rotation, grab-and-land, named/any rail use, ordered feature sequences, clean landing, no-bail completion, minimum score, selected route, and run completion. Challenge evaluation consumes authoritative gameplay outcomes; UI displays state but does not decide it.

Challenges should teach possibilities that already exist in the geometry. Do not add challenge-only physics behavior or invisible exceptions.

## Session Yard

The Session Yard is an opt-in retry-focused profile using the same builders, physics, scoring, assets, and collision contracts as the main resort. It exists for concentrated practice and validation, not as a separate gameplay mode.

Keep it opt-in until clean-player testing establishes that:

- the six main resort spots read correctly;
- marker/retry behavior is understandable;
- the yard provides a clear benefit rather than hiding course-design problems;
- its feature density and retry loop hold up in normal controller play.

## New geometry policy

Do not add a geometry kind because the feature list looks incomplete. Add one only when an accepted line cannot be expressed cleanly with the existing builders.

The current vocabulary already covers tabletop/hip/roller/berm/side-hit forms, boxes, tubes, multi-point rails, wall features, bonks, cannons, gates, moguls, and butter/setup terrain. A true two-face spine, dedicated transfer bank, stair set, or richer curved-rail authoring remains valid future work only if playtesting demonstrates a specific missing skiing decision.

## M1 validation gate

**M1 is the product-validation gate for this phase.** Do not proceed into substantial M2–M4 implementation merely because the planned geometry exists. First demonstrate through human play that the redesigned resort creates voluntary retries, readable choices, memorable spots, and useful recovery behavior. Minimal diagnostic metadata needed to observe M1 is allowed, but new feature systems, challenge infrastructure, and authoring migrations remain downstream of this gate.

### Human playtest scorecard

Use these as directional prototype targets, not telemetry-driven progression requirements:

| Measure | Target signal |
|---|---|
| Marker reuse | Players intentionally return to at least two spots during a session. |
| Voluntary retries | A player makes at least three attempts at a favored spot without being instructed to do so. |
| Route diversity | Different routes or techniques appear across players or repeated attempts without prompting. |
| Discovery | At least one advanced or unintended line/approach is discovered during skilled play. |
| Failure recovery | Missed transfers/features often allow continued skiing when physically plausible instead of forcing a reset. |
| Spot recall | After a run, players can identify or describe at least two memorable spots. |
| Beginner readability | A safe route is recognizable without requiring an explanation of the intended line. |
| Expert depth | Skilled players find a reason to revisit at least one spot after successfully traversing it. |

Do not treat one player's exact counts as a pass/fail statistic. Look for repeated evidence across sessions. If players consistently traverse a spot once and move on, revise geometry before adding systems intended to direct them back to it.

### Performance regression checkpoints

M1 deliberately increases local course density and visual overlap, so performance should be checked while the layout is still cheap to change.

- After **Technical Yard**, run the maintained quality gate and benchmark the dense-feature view on the normal reference hardware/settings. Compare against an ancestry-compatible baseline on the same machine.
- After **Lower Hero Spot + Finale**, repeat the maintained deterministic 1080p scenario matrix used for active performance work.
- Treat these checks as regression detection, not invitations to speculative optimization. If a meaningful regression appears, identify the CPU/GPU/submission/memory bound before changing content or rendering systems.
- Preserve matched visual review when a performance fix changes feature readability, snow, environment presentation, or sight lines.

## Human validation priority

The next content work should be observation and tuning rather than another structural implementation pass.

Run clean-player sessions at normal physics rate and record, for each spot:

- safe-line discovery without coaching;
- first successful feature use;
- voluntary retries;
- marker use and placement mistakes;
- second-line discovery;
- transfer attempts;
- miss recovery versus forced reset;
- confusion about route/readability versus confusion about controls.

Debug builds and runs started with `--content-trace` expose `spot_diagnostics`
through `ParkContentTracker.snapshot()`. Each stable spot accumulates camera
fallback deltas and states, peak carve look-ahead, normalized landing outcomes,
landing speed loss/retention, and the latest landed-trick target/residual
feedback. Use these values to locate what the player experienced; they are
diagnostic evidence, not success targets or progression rules.

Review the generated resort and Session Yard previews for approach sightlines, crossovers, landing/runout spacing, and feature relationships, but treat gameplay-camera observation as authoritative for readability.

## Automated coverage

The maintained runtime/static gates already cover the structural content contract, including stable spots, metadata propagation, reference validation, challenge evaluation, deterministic rebuild equivalence, Session Yard construction, and normal session-flow integration.

Use the normal project gates after content changes:

```powershell
.\tests\static_quality_gate.ps1
.\tests\runtime_quality_gate.ps1
```

For editor inspection, use the shared preview workflow in [World Authoring](WORLD_AUTHORING.md).

Automated metadata and geometry checks cannot establish whether a line is fun, readable, comfortable, or worth repeating. Those remain human acceptance criteria.
