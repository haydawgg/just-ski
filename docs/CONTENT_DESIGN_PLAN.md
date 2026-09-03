# Summit Sessions — Content Design Implementation Plan

This plan defines the next content-design phase for Summit Sessions. The goal is to get more value out of the existing skiing, trick, rail, landing, scoring, marker, and procedural-course systems before expanding into large new product systems.

The guiding product loop is:

```text
learn -> attempt -> understand -> retry -> master -> express -> capture
```

The content should support that loop by giving players readable beginner uses, deeper expert uses, meaningful route choices, memorable session spots, and room for self-directed experimentation.

---

## Product target

The primary player is a controller-first, skill-oriented action-sports player who wants to improve through practice and create stylish lines. Real skiers, score chasers, and clip creators are important secondary users, but the course should first serve players who enjoy learning a mechanical system.

Content should therefore optimize for:

- repeated attempts with low friction;
- readable cause and effect;
- multiple valid approaches to the same feature;
- increasing depth without requiring stat progression;
- style and line choice, not only maximum rotation;
- memorable spots that are worth sessioning;
- recovery routes that can turn mistakes into improvisation;
- content that remains deterministic and testable.

A feature is not complete merely because it can be traversed. A strong feature should create decisions.

---

## Current implementation advantages

The current architecture already gives content work a strong base:

- `world/course/park_course_profile.gd` centrally defines the current course through `feature_specs()`.
- `world/course/park_course_builder.gd` deterministically turns those specs into runtime features.
- Existing feature kinds include tabletops, hips, rollers, rails/boxes/tubes, berms, moguls, butter pads, side hits, wallrides, bonks, cannons, and gates.
- Rail travel is spline-backed and supports bidirectional movement.
- The current course already contains teaching, air, jib, flow, transfer, and finale ideas that can be reorganized instead of discarded.
- Session markers already support repeated practice.
- The world-authoring baker in `docs/WORLD_AUTHORING.md` allows the generated course to be inspected without abandoning deterministic runtime construction.

The first milestone should therefore be mostly course-data work. Do not change skier physics to make weak geometry playable. Fix the geometry first.

---

# Content design rules

Use these rules for every new or revised spot.

## Rule 1 — Three-layer feature test

Every hero feature should answer:

1. What can a beginner do here?
2. What can an intermediate player intentionally add?
3. What can an expert do that a new player may not initially notice?

Example:

```text
Tabletop
- beginner: straight air
- intermediate: 360 + grab
- expert: diagonal transfer to rail or bank
```

## Rule 2 — Spots over obstacle chains

Prefer memorable clusters of interacting features over long sequences of unrelated obstacles.

Bad:

```text
jump -> rail -> jump -> rail -> finish
```

Better:

```text
                high rail
               /
main jump ----<---- normal landing
      \         \
       side bank ---- box
```

A spot should support several attempts without requiring a full mountain restart.

## Rule 3 — Terrain is gameplay

Use rollers, banks, berms, compressions, side hits, transitions, ridges, and speed-control sections as intentional gameplay content. Rails and jumps should not carry the entire freestyle experience.

## Rule 4 — Safe line plus ambitious line

Most major sections should contain an obvious survivable route and at least one optional higher-risk route.

## Rule 5 — Failure should sometimes create a new line

Where practical, place banks, runouts, or secondary features beneath transfer attempts so a miss can become an improvised continuation rather than an automatic reset.

## Rule 6 — Route choice must affect technique

Different routes should ask for different skills: speed control, carving, airtime, rail balance, transfer precision, or recovery. Avoid three lanes that are visually different but mechanically equivalent.

## Rule 7 — Preserve deterministic authoring

New content must continue to build from course data and reusable builders. Do not introduce one-off editor-only gameplay geometry that bypasses collision, readability, test, or asset contracts.

---

# Milestone 1 — Recompose the existing resort into sessionable spots

**Priority: P0**

This milestone should use the current feature vocabulary whenever possible. It is primarily a redesign of placements, approaches, exits, and relationships between existing features.

## M1.1 — Summit Fundamentals

Use the current summit gate, rollers, `SmallTable`, `SummitFlatBox`, and `BeginnerTube` as one explicit learning cluster.

### Changes

- Keep a wide, low-risk center path that naturally teaches speed, carving, and straight airs.
- Offset the flat box so it requires a small but readable approach decision rather than being placed directly on the fall line.
- Keep the first rail/box entry forgiving and give it a large runout.
- Position the tube as the second-step jib feature with slightly more approach demand.
- Ensure a player can bypass every feature without leaving the teaching cluster.
- Create valid marker positions before the small table and before the first jib feature.

### Acceptance criteria

- A first-time player can ski through the area without being forced onto a feature.
- A player who understands pop can repeatedly practice the table from one marker.
- A player who understands basic rail capture can repeatedly practice the box/tube without a long return.
- The section supports straight air, basic spin, basic grab, basic grind, and bypass routes.

---

## M1.2 — Upper Fork

Turn the current upper park into the first real route decision.

Use the existing `UpperLeftSideHit`, `UpperRoller`, `UpperBermLeft`, `UpperBermRight`, `DownRail`, and `UpperBonk` as three interacting lanes:

- **Air line:** side hit / roller with a forgiving landing.
- **Flow line:** linked berms where speed and carving matter more than trick input.
- **Jib line:** down rail and bonk with a more technical cross-slope approach.

### Changes

- Let the three lines visually overlap or cross instead of reading as isolated parallel tracks.
- Add at least one crossover from the flow line into the jib line.
- Add at least one advanced transfer from the air line toward a rail or bank.
- Preserve a clean runout that rejoins the mid park.

### Acceptance criteria

- The route choice is readable from the approach.
- Each lane emphasizes a different player skill.
- At least one mid-run lane change is possible.
- An expert can create a line that uses content from more than one lane.

---

## M1.3 — Technical Yard

Recompose `MidButterPad`, `KinkRail`, `DFDBox`, `MidWallride`, and nearby terrain into a compact session spot.

This should become the park's first obvious "stay here and work on a line" location.

### Target layout concept

```text
                 kink rail
                /        \
approach -> butter pad     wallride
                \        /
                 DFD box
```

### Changes

- Bring feature starts close enough that one marker can reasonably serve multiple attempts.
- Give the butter pad a useful role as setup terrain rather than decorative flat space.
- Make the kink rail the technical centerpiece.
- Place the DFD box as the safer alternate progression step.
- Position the wallride so it can be used as either a destination or a recovery/transfer option.
- Avoid dead space after a missed rail.

### Acceptance criteria

- One marker location supports at least three distinct planned attempts.
- A beginner/intermediate player has a safe box option.
- An advanced player has at least two transfer possibilities.
- Missing a feature does not normally strand the player outside the playable flow.

---

## M1.4 — Transfer Zone

Strengthen the existing `HipTransfer`, `CenterSpine`, `LongTube`, `TransferBox`, `MidRoller`, and `TransferBonk` into the resort's creative line-building area.

`CenterSpine` is currently authored as a `side_hit`; keep that implementation for M1 and treat a true spine as later feature work.

### Changes

- Arrange the hip and side-hit/spine proxy so both can target more than one landing direction.
- Make `TransferBox` visibly reachable from more than one approach.
- Place `LongTube` so it can be entered normally or reached through an advanced transfer.
- Use the roller or a banked runout to catch failed transfers.
- Keep one direct safe route through the area.

### Acceptance criteria

The zone supports at least these conceptual lines:

```text
hip -> normal landing
hip -> transfer box
side hit -> long tube
transfer box -> pop -> bank/runout
safe bypass -> lower park
```

---

## M1.5 — Rainbow / Lower Park hero spot

Make `Rainbow` the memorable hero feature of the lower park and compose `SRail`, `LowerRightSideHit`, `LowerButterPad`, and `LowerWallride` around it.

### Changes

- Give the Rainbow a clearly readable normal entry.
- Add a difficult alternate entry that requires a prior feature or cross-slope approach.
- Let the lower side hit feed either a normal landing or an ambitious rail/wall transfer.
- Use the butter pad as setup/recovery terrain between technical features.
- Keep the wallride available as an alternate finish to the spot rather than an isolated object.

### Acceptance criteria

- The Rainbow is recognizable as a landmark from upstream.
- It has one readable standard use and at least one expert use.
- The surrounding features support at least three different complete spot lines.

---

## M1.6 — Finale choice

Turn `StepDownTable`, `FinalCannon`, `FinalBox`, `FinalDFDRail`, `FinalCatchBerm`, and the finish gate into a final player decision instead of a simple runout.

### Target choice

- **Air finish:** step-down / cannon route.
- **Technical finish:** box / DFD rail route.
- **Recovery:** catch berm reconnects both routes before the finish.

### Acceptance criteria

- The final ten seconds still contain meaningful choice.
- Neither line is universally superior for score or ease.
- Both routes reconnect cleanly to the finish.
- A failed technical attempt can still reach the finish without a forced respawn when physically plausible.

---

# Milestone 2 — Add content semantics and designer-facing structure

**Priority: P0/P1**

The current dictionary-based `feature_specs()` is useful for fast iteration, but it carries too little semantic information for a richer park. Add metadata before adding a challenge system or larger resort.

## M2.1 — Extend feature metadata

Add backward-compatible spec fields such as:

```text
spot_id
route
skill_floor
skill_ceiling
intent_tags
risk_level
hero_feature
optional
```

Suggested `intent_tags` values:

```text
learn
flow
air
jib
transfer
speed_control
precision
recovery
style
```

`ParkCourseBuilder` should copy these fields into feature metadata exactly as it already copies route/difficulty and asset-contract metadata.

### Acceptance criteria

- Existing feature specs remain valid with defaults.
- Every production course feature has a `spot_id`.
- Every hero feature identifies its expected skill range and intent.
- Debug/test code can query these tags without knowing individual node names.

---

## M2.2 — Add spot definitions

Introduce a lightweight spot definition owned by the course profile. A spot should contain at minimum:

```text
id
name
anchor
recommended_marker_position
intent_tags
feature_names
```

Optional later fields:

```text
challenge_ids
difficulty_summary
camera_landmark
```

Do not make spots responsible for physics. They are content organization and UX metadata.

### Acceptance criteria

- The summit, upper fork, technical yard, transfer zone, lower hero spot, and finale can each be addressed by stable IDs.
- A spot can be shown in debug UI or future menus without hard-coded node searches.

---

## M2.3 — Improve authoring workflow

After the M1 layout has been validated, consider migrating feature dictionaries into typed Godot `Resource` objects (`ParkFeatureSpec`, `ParkSpotSpec`) so designers can edit data without modifying GDScript source.

Do not start this migration before the field set is stable enough to justify it.

### Required work when migration begins

- Preserve deterministic iteration order.
- Preserve existing asset and collision contracts.
- Add validation for duplicate names, invalid spot IDs, unsupported kinds, impossible dimensions, and missing rail points.
- Keep the preview baker using the same source data as runtime.
- Add static/runtime acceptance coverage for resource loading and build equivalence.

---

# Milestone 3 — Expand the feature vocabulary only where content needs it

**Priority: P1**

Add new feature kinds because they unlock new skiing decisions, not because the list looks small.

## M3.1 — True snow spine

Add a reusable `spine` feature with two usable faces and a ridge that can be crossed or aired.

### Player uses

- beginner: ride one face as terrain;
- intermediate: air across the ridge;
- advanced: transfer across the spine at an angle or use it switch/reverse.

### Acceptance criteria

- Both faces produce stable ski contact.
- The ridge can be approached from either side where course geometry permits.
- Generated collision matches generated render geometry.

---

## M3.2 — Bank / transfer landing

Add a simple authored bank distinct from a long berm. Its purpose is to receive diagonal landings, wall-style airs, and failed transfers.

### Acceptance criteria

- Bank angle and orientation are explicit data.
- Landing evaluation naturally rewards alignment with the bank rather than special-casing the feature.
- The same bank can be used as intended landing, carving terrain, or recovery terrain.

---

## M3.3 — Stair set

Add a reusable stair-set feature that can host optional rails separately.

The stair set should create a recognizable freestyle spot rather than one monolithic scripted obstacle.

### Player uses

- gap the stairs;
- grind a handrail;
- gap onto a rail;
- transfer rail-to-rail when multiple rails are authored;
- use the adjacent bank/runout after a miss.

### Acceptance criteria

- Stairs have deterministic solid collision.
- Grind rails remain ordinary `GrindRail3D` features rather than being hidden inside the stair implementation.
- Course authors can vary stair count/length/width without custom scenes.

---

## M3.4 — Curved rail authoring

The rail gameplay is already spline-backed. Expose enough course data to author deliberately curved rails instead of relying only on piecewise point chains.

Possible implementation approaches:

- optional Curve3D handles per control point; or
- a documented interpolation/tension field that produces deterministic handles.

### Acceptance criteria

- Existing rails are unchanged by default.
- Curved rails can be baked and visually reviewed.
- Rail capture, balance, travel direction, and exit remain governed by the existing rail gameplay contract.

---

# Milestone 4 — Add optional spot and line challenges

**Priority: P1**

Challenges should teach possibilities and create goals without turning the game into a locked campaign.

## Design rule

Challenges are suggestions, not gates. A player should always be able to ignore them and free ski.

## M4.1 — Challenge definition data

Add challenge definitions that reference stable `spot_id` and feature IDs rather than node paths.

Useful condition types:

```text
land_any_trick
land_rotation_min
do_grab
grind_feature
grind_any
hit_feature_sequence
score_min
no_bail
clean_landing
finish_run
```

Keep the first implementation small. Do not build a generic scripting language.

---

## M4.2 — Initial challenge set

### Summit Fundamentals

- Land a straight air.
- Land a 180 or greater.
- Hold one grab and land.
- Grind the flat box.

### Upper Fork

- Complete the flow line without braking heavily.
- Hit one air feature and one jib feature in the same run.
- Bonk the upper feature and continue cleanly.

### Technical Yard

- Grind the DFD box.
- Grind the kink rail and pop off.
- Link two technical features without bailing.

### Transfer Zone

- Land a hip transfer.
- Reach `TransferBox` from a non-default approach.
- Hit two different routes through the spot.

### Lower Hero Spot

- Grind the Rainbow cleanly.
- Enter the Rainbow from the advanced approach.
- Link side hit -> rail/wall feature.

### Finale

- Finish through the air route.
- Finish through the technical route.
- Complete either route without a bail.

---

## M4.3 — Presentation

Start with one lightweight surface:

- pause-menu spot/challenge page; or
- compact challenge board/prompt near the spot.

Avoid a large mission UI until playtests prove players want it.

### Acceptance criteria

- Challenge text gives players ideas without obscuring the HUD.
- Challenge evaluation uses authoritative gameplay/scoring outcomes.
- A challenge never changes movement or landing results.

---

# Milestone 5 — Dedicated session content

**Priority: P2 after the main resort proves the design**

Build a compact `Session Yard` only after M1 playtests confirm that players enjoy staying at individual spots.

The Session Yard should maximize attempts per minute rather than simulate a full downhill run.

## Proposed layout

```text
                 curved / advanced rail
                        |
small jump ---- central setup ---- medium jump
                        |
                 box / stair set
                        |
                   bank / wall
```

### Requirements

- One or two marker locations can serve most features.
- Features are close enough for rapid experimentation but not so close that failed attempts constantly collide with unrelated geometry.
- Every hero feature has a safe approach and an expert transfer.
- The yard includes at least one terrain-only line.
- The yard should be a separate course profile or content configuration, not a special physics mode.

---

# Milestone 6 — Content playtest and telemetry loop

**Priority: Continuous**

Content should be changed based on observed player behavior, not only designer intent.

## Human playtest questions

For each spot, observe without explaining the intended line first:

- What does the player try first?
- Do they notice the route choice?
- Can they identify a safe line?
- Do they save a marker?
- Do they retry the same feature voluntarily?
- Do they discover a second use without being told?
- Does an advanced player find an approach the designer did not plan?
- When they miss a transfer, can they improvise or are they forced to reset?

## Useful local telemetry

Track at least:

```text
spot_id entered
feature approached
rail capture success/failure
landing result
bail source
marker save/return count
attempt count per spot
route/feature sequence
run completion
```

Telemetry should remain diagnostic and local during prototype development unless a separate privacy/product decision is made later.

## Content success criteria

A strong spot should show:

- repeated voluntary attempts;
- more than one commonly used line;
- increasing success across attempts;
- both safe and ambitious behavior;
- meaningful use of markers;
- low rates of accidental out-of-bounds recovery caused by layout mistakes.

---

# Recommended implementation order

Use this order unless playtesting reveals a blocker:

```text
1. M1 Summit Fundamentals
2. M1 Upper Fork
3. M1 Technical Yard
4. M1 Transfer Zone
5. M1 Lower Hero Spot
6. M1 Finale
7. M2 feature + spot metadata
8. playtest the complete redesigned resort
9. M3 only the new feature kinds that the playtest still needs
10. M4 optional challenges
11. M5 Session Yard
```

Do not implement all new feature types before the M1 redesign. The existing vocabulary is already broad enough to prove whether the spot/line philosophy works.

---

# Definition of done for a content spot

A spot is ready for the maintained prototype when all of the following are true:

- [ ] It has a stable `spot_id`.
- [ ] It has an obvious low-risk route.
- [ ] It has at least one intentional intermediate route.
- [ ] It has at least one expert/creative use.
- [ ] At least three meaningfully different attempts are possible within the spot.
- [ ] Approach speed is achievable through normal skiing without hidden boosts.
- [ ] Overshoot/undershoot behavior is understandable.
- [ ] A valid marker can be placed at a useful practice location.
- [ ] Missed features have a reasonable runout/recovery path where possible.
- [ ] Collision and visual geometry agree.
- [ ] The deterministic preview bake shows the feature correctly.
- [ ] Existing runtime quality gates remain green.
- [ ] At least one human playtest has been performed from a clean player perspective.

---

# Non-goals for this phase

Do not use content work as a reason to begin these systems yet:

- open-world mountain streaming;
- multiplayer;
- equipment stats;
- economy/unlocks;
- narrative campaign;
- large cosmetic inventory;
- online leaderboards;
- dozens of separate resorts.

The current priority is to prove that one resort can remain interesting because the **same geometry supports learning, mastery, line choice, style, and repeated sessioning**.

---

# First implementation slice

The best first code/content change is deliberately small:

1. Rework only the **Summit Fundamentals** and **Upper Fork** feature positions/specs in `ParkCourseProfile.feature_specs()`.
2. Do not change physics or trick tuning.
3. Bake the resort preview and review sight lines/spacing.
4. Run the full quality gate.
5. Playtest whether a new player can identify the safe route and whether an experienced player can find at least one crossover/transfer.
6. Iterate geometry before continuing farther downhill.

If that slice works, apply the same design rules to the Technical Yard, Transfer Zone, Lower Hero Spot, and Finale.
