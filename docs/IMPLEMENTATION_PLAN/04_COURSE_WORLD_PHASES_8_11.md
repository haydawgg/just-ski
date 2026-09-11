# Phase 8 — Rebuild the main run as a three-jump competition line

Change course rhythm, not just jump size. The primary line should feel like a real slopestyle-style big-air sequence with preparation, sightlines and recovery between progressively larger jumps.

### Architecture rules

- Keep ParkCourseProfile.feature_specs() as the source of feature placement/design inputs; do not hand-place the new line in world/resort.gd.

- Reuse ParkLayout.jump_table()/add_tabletop() trajectory-aware geometry first. Do not replace the generic jump generator until spacing/line rhythm has been validated with existing physics.

- Preserve SmallTable, MediumTable and LargeTable names as Jump 1/2/3 during the first redesign so existing name-based tests/content references break as little as possible.

- Explicitly move StepDownTable to an optional advanced/finale side line or migrate/remove it with all content references. Do not leave it as a fourth mandatory hero jump by accident.

- Preserve the six-spot/content ID contract where possible. If an ID or membership must change, update spot_specs(), challenge_specs(), route membership, preview/telemetry and tests in the same change.

### Target rhythm

| **Segment**          | **Design target**                                                                                                                |
|----------------------|----------------------------------------------------------------------------------------------------------------------------------|
| Drop-in              | Long clean acceleration zone, roughly 60–100 m depending on actual spawn speed/grade.                                            |
| Jump 1 / SmallTable  | Confidence-building hero jump; start around ~16–18 m/s design speed, ~7–8° lip, ~9–10 m width, then tune from actual trajectory. |
| Recovery 1           | Stable landing, then ~3–4 seconds of usable setup before Jump 2; no mandatory rail/roller in the center corridor.                |
| Jump 2 / MediumTable | Larger: ~19–21 m/s, ~8.5–10° lip, ~10–11 m width as initial inputs.                                                              |
| Recovery 2           | Again ~3–4 seconds of line correction/one or two carves and clear sightline to Jump 3.                                           |
| Jump 3 / LargeTable  | Showcase: ~22–24 m/s, ~10–12° lip, ~11–12+ m width; biggest airtime and longest landing.                                         |
| Runout               | At least ~60–90 m equivalent safe finish/runout before finish interactions/major obstacles.                                      |

### Spacing algorithm

1\. Do not start with fixed world-z coordinates. For each jump, query the existing predicted range/landing construction and measure the actual stable landing end.

2\. Place the next lip far enough downhill that the expected skier has ~3–4 s after landing recovery before takeoff. At 18–24 m/s that commonly implies ~55–90 m of usable setup depending on speed.

3\. Increase FACE_SLOPE_LENGTH / overall course extent through its existing single-source constant if necessary. A total hero-line length on the order of ~430–500+ m is reasonable if required to satisfy the timing and final runout; the timing gate is more important than a particular number.

4\. Maintain roughly 20–30 m of genuinely usable primary-lane width in setup zones. Optional rails/boxes/side hits should live off the clean center line.

5\. Shape each landing so its lower section opens progressively back into the course grade rather than dumping the skier onto a flat pad before the next ramp.

6\. Preserve sightlines: the next hero lip and approximate landing should be visible several seconds in advance; avoid convex terrain that hides the next feature until the last moment.

### Robustness and content migration checks

1\. Sweep each hero jump around its tuned design point rather than validating only the nominal trajectory. Use at least roughly ±15% entry-speed variation, modest lateral offsets and slight approach-angle error, then record short/long landing behavior, recovery space and whether the next feature remains deliberately reachable.

2\. Test a deliberate miss/ride-around path for each hero jump. Missing one feature must not force an unavoidable collision, trap the player behind course geometry, or make the next recovery corridor unusable.

3\. After feature/route metadata migration, run an end-to-end content smoke flow using the local authoritative events: start or activate the relevant content, use the intended feature/line, observe credit/telemetry, continue through the course and cross the finish. Record any pre-existing challenge/finish semantics that prevent a meaningful pass and apply Rule 11 only if they block this phase.

### Course acceptance

| **Check**                | **Pass condition**                                                                                                                                                                 |
|--------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Three-jump identity      | Only three jumps read as primary hero progression; StepDown is clearly secondary/optional if retained.                                                                             |
| Progression              | Jump 1 \< Jump 2 \< Jump 3 in commitment/airtime while all remain legitimate competition features.                                                                                 |
| Preparation              | After each landing the player can absorb, stabilize, choose line and make deliberate setup input before next lip.                                                                  |
| Center corridor          | No mandatory-looking jib/roller blocks the three-jump line.                                                                                                                        |
| Sightline                | Lip, knuckle, landing and route are readable from the normal camera without debug guides.                                                                                          |
| Content integrity        | Spot/challenge/feature IDs and telemetry either remain valid or have explicit migrations/tests.                                                                                    |
| Robustness envelope      | Each hero jump remains survivable/recoverable across the recorded speed/offset/approach sweep; misses have a deliberate recovery or ride-around outcome.                           |
| Behavioral content smoke | Course migration preserves or explicitly migrates content events through feature use, telemetry/credit and finish flow; pre-existing blocking semantics are separately identified. |

# Phase 9 — Terrain continuity, jump integration and render/collision correspondence

Make the course look sculpted into one mountain instead of assembled from rectangular snow slabs, while keeping simple gameplay collision where it is stable.

### Implementation

1\. Inspect the tabletop builder for intentional deck/landing gaps and separate snow bodies. Keep collision segmentation if useful, but create a continuous visual snow skin/collar across run-in → lip → deck/knuckle → landing → runout so no dark trench or material seam is visible from chase distance.

2\. Blend/bury feature bases into snow: accumulated snow, shallow depressions, support contact, worn approach/landing zones, and non-perfect rectangular material boundaries.

3\. Audit the presentation-only summit/face heightfield against the gameplay collider throughout the active ski corridor. In the playable region, visible snow and collision should remain within a few centimeters where the skier/camera can interact.

4\. Where decorative shoulders intentionally rise farther from the collider, prevent the camera from clipping through visible snow with a presentation collision proxy or camera-placement restriction.

5\. Keep collision simple and stable. Do not replace the whole MainSnowFace collider just because the render layer needs more believable form.

6\. Temporarily disable/hide opaque jump-readability guide strips during visual review. The lip/knuckle/landing must read from geometry, lighting and material alone; guides may remain as restrained gameplay aids afterward.

> **Gate —** At normal gameplay distance there is no obvious slab seam, trench, skirt or material jump between hero feature sections; skis and camera visually agree with the snow they are interacting with.

# Phase 10 — Snow shader and lighting architecture

Restore local snow form without globally darkening the mountain. Fix the shadow-receiving architecture first, then tune values.

### Implementation order

1\. Confirm how much of the visible main piste uses the SummitSnowRenderSurface locally. In reviewed master the generated surface spans the face longitudinally and receives snow_summit.gdshader, whose render mode disables shadows.

2\. Split interactive/playable piste rendering from any special presentation-only summit relief that genuinely needs shadow suppression. The normal skiing surface should receive useful directional/contact shadows from the sun and course objects.

3\. Do not simply remove shadows_disabled globally if it revives the original low-sun artifact. Create separate mesh/material regions or another local solution so the special relief can keep its workaround without flattening the main piste.

4\. Reduce aggressive additive luminance manipulation in snow_summit: the current strong drift term and luminance floor can compress terrain values. Prefer subtler multiplicative macro variation plus real normal/light response.

5\. After shadow architecture is correct, tune ambient sky contribution, shadow opacity/softness, local AO/form contrast, exposure and snow roughness together. Preserve bright snow; increase local slope/concavity readability rather than making everything gray.

6\. Review piste vs park-feature detail fade distances together so an upcoming ramp does not retain strong normal/detail while surrounding piste has already become featureless.

### Visual matrix

| **Distance / condition** | **What must remain readable**                                                              |
|--------------------------|--------------------------------------------------------------------------------------------|
| 10–20 m                  | Corduroy/micro variation, ski tracks, feature contact, edge shadows.                       |
| 40–60 m                  | Rollers, lip/knuckle/landing grade, feature base integration, meaningful snow form.        |
| 80–100 m                 | Hero jump silhouette and route hierarchy without texture noise dominating.                 |
| Day / golden / sunset    | No giant black presentation-only shadow artifact; no washed-out shadowless concrete piste. |
| Guides hidden            | Course geometry remains self-explanatory.                                                  |

> **Do not —** Do not “fix” snow by lowering global exposure or darkening every albedo. That would preserve the underlying form problem and hurt readability.

# Phase 11 — Environment depth, trees, mountains, resort density and speed cues

Make the static world convincing and use nearby environmental structure to sell scale and speed.

### Trees

1\. Replace color-only tree variation with ~3–5 structural conifer families (tall/narrow, broad/mature, juvenile, snow-heavy/irregular, optional broken/asymmetric).

2\. Spatially chunk MultiMesh batches so visibility/LOD operates on localized bounds rather than the entire course. Update tests that currently require exactly one batch: the new contract should require a bounded number of deterministic spatial batches with preserved collision/catalog roots.

3\. Reduce the large near/far LOD overlap and run a camera-distance sweep for pop/overdraw. Preserve deterministic placement and performance.

4\. Cluster trees naturally by scale/density rather than evenly scattering individual markers; use near/mid/far groups to establish scale.

### Mountains and haze

1\. Add multiple topology families to \_create_ridge_mesh or its caller instead of only changing seed/scale. Include massif, sharp peak, saddle/double peak, long ridge, asymmetric shoulder and distant low ridge forms.

2\. Rebalance background scale/placement so giant close mountains do not visually shrink the ski area.

3\. Choose one primary aerial-perspective system. If global fog already provides distance haze, reduce the independent mountain-shader haze blend; or vice versa. Avoid double-washing distant peaks into the sky.

4\. Preserve clear near/mid/far value layers and lower contrast/chroma with distance.

### Resort density and speed

- Add safe off-line parallax objects: piste markers, fences, flags, lift towers, snowguns, snow banks, signs, occasional rocks/tree clusters. Keep the main competition corridor free of collision clutter.

- Improve lift presentation with more believable towers/pulleys/chairs/station context and snow/contact integration.

- Add usage history: grooming/corduroy, previous ski lines, scraped landings, snow buildup around infrastructure and worn feature approaches.

- Add restrained sky identity (subtle high clouds/horizon variation) only after terrain and depth are correct.

### Camera / environment safety

1\. After dressing is placed, replay the canonical line plus edge-of-lane variations and measure body occlusion, camera collision recoveries, hard-frame violations and target visibility. Props can be outside the ski corridor and still be inside the chase-camera corridor.

2\. Move, thin or regroup persistent occluders first; preserve readable resort composition without surrounding the player with camera blockers. Any special occlusion/fade behavior must reuse local presentation/camera architecture rather than creating a parallel system unless the existing architecture cannot solve the case.

### Asset / provenance constraint

- Use existing repository assets, procedural geometry, or newly authored project-owned assets by default. Do not download arbitrary third-party art to satisfy this phase. Any externally supplied asset must have an explicit approved source/license and preserved attribution/import metadata before it can enter the repo.

> **Gate —** A static late-run frame without the skier reads as a believable mountain resort; speed is supported by nearby parallax rather than camera shake; and the dressed environment does not introduce persistent skier occlusion or pathological camera collision on the canonical/edge-of-lane sweeps.
