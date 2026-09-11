**JUST SKI**

**Model-Executable Repo-Aligned Gameplay, Camera, Character, Course & World Implementation Plan**

*Supersedes the earlier repo-aligned plan; incorporates the full gameplay review, subsequent repository audit, test audit, model-execution rules, and the release-control revisions for deterministic acceptance, regression preservation, gate registration, performance/display validation, and cross-state safety.*

> **Repository reference —** haydawgg/just-ski, connected master at 760393ced82df8c4047bbb590c1265bb87f286b5. The local working tree may be newer; local code is authoritative for implementation.
>
> **Primary source of truth —** The supplied 19.9 s no-trick gameplay clip is authoritative for visible failures. Repo code is supporting evidence for architecture and likely causes.
>
> **Execution contract —** A coding model must work phase-by-phase, inspect the local tree first, add or update regression coverage, run targeted tests plus the quality gate, generate visual evidence, and stop/report on any contradiction or failed gate. Before/after claims must use the canonical acceptance artifact established in Phase 0, and every new acceptance fixture must be registered in the appropriate executable gate before it counts as coverage.
>
> **Scope —** Camera, normal skiing/no-trick animation, skis/poles/contact, course design, terrain/snow, world/environment, presentation and supporting QA. Trick design and audio redesign are intentionally out of scope; existing audio and unrelated runtime acceptance must remain green.

# 1. How to use this plan with a coding model

This document is intentionally written as an execution specification, not a backlog of vague recommendations. A capable coding model should receive the whole document for context but should implement one phase at a time.

## 1.1 Copy-paste execution instruction

> **Recommended prompt —** Read the entire attached Just Ski implementation plan so you understand dependencies, but implement only the phase I assign. Treat the local working tree as authoritative. Before editing, inspect the named files, record HEAD/status, and identify any mismatch between the plan and local code. Add failing regression coverage first where practical. Make the smallest architecture-aligned fix. Do not alter unrelated dirty files, delete/relax tests merely to pass, or replace existing systems unless the phase explicitly requires it. Run the phase-specific tests, then the full quality gate, generate the requested visual evidence, and report files changed, root cause, tests, before/after metrics, remaining visual review, and contradictions. Stop after the phase or immediately if a required gate fails. Use the Phase 0 canonical deterministic acceptance artifact for comparable before/after evidence. A newly created test does not count as coverage until it is wired into the relevant quality/runtime gate and proven to execute.

## 1.2 Non-negotiable model rules

1\. Local checkout first: run git rev-parse HEAD and git status --short, then inspect every named file before editing. Never force the local tree to match connected master.

2\. Preserve unrelated work. Do not use destructive reset/checkout operations on files the model did not own for the current phase.

3\. One behavior family per change set. Camera correctness, camera feel, contact/stance, animation, course layout, snow/world art, and UI are separate change families.

4\. Regression before polish. Reproduce the defect in an automated fixture or diagnostic first where practical; then fix it; then retain the test.

5\. Do not weaken tests to make the patch pass. If an existing test encodes a bad contract, explain why, replace it with the correct contract, and preserve equivalent or stronger coverage.

6\. Do not substitute constants for architecture. If the phase identifies a coupling bug (for example physics-probe width driving visual stance), decouple the systems instead of hiding the symptom with one value.

7\. Do not claim visual success without visual evidence. If the model cannot inspect GPU captures itself, it must generate them and clearly mark human visual review as outstanding.

8\. A failed phase gate is a stop condition. Report the failure and do not continue into later phases where the failed dependency could invalidate tuning.

9\. Preserve previously proven behavior. Every completed phase must keep all earlier phase gates and existing acceptance suites outside its intended change family at least as strong as the recorded baseline. Any newly introduced unrelated failure is a STOP condition, not acceptable collateral damage.

10\. Register new coverage. Any new acceptance .gd/.tscn or equivalent fixture must be added to the appropriate local quality/runtime gate or test aggregator and its execution must be demonstrated. An orphan test file does not count as coverage.

11\. Use the out-of-scope dependency exception narrowly. Do not opportunistically repair unrelated scoring, controls, persistence, challenge, display or trick issues. If a pre-existing out-of-scope defect makes a required phase gate invalid, make only the minimum blocking fix as a separate change family, add regression coverage, and document why it was necessary before returning to the assigned phase.

12\. Compare like with like. Baseline and post-change measurements must use the same canonical spawn/state, deterministic seed or content state, input trace/script, physics-rate target, viewport/aspect, quality preset and named hardware configuration unless the test explicitly varies one of them. Record every intentional variation.

13\. No-trick skiing is the baseline. Do not introduce grabs/spins/tucks as camouflage for a weak straight-air pose.

## 1.3 Required phase completion report

| **Field**              | **Required content**                                                                                                                                              |
|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Local HEAD / status    | Commit SHA before work; dirty files present; files intentionally touched.                                                                                         |
| Plan/local mismatches  | Any assumption in this document that no longer matches the current checkout and how the implementation was adapted.                                               |
| Root cause             | Code-level explanation of the defect or design limitation fixed in this phase.                                                                                    |
| Files changed          | Exact paths and why each changed.                                                                                                                                 |
| Tests                  | Tests created/extended and why they would have failed before the fix.                                                                                             |
| Commands/results       | Targeted test results, quality gate result, and any GPU/visual-evidence command result.                                                                           |
| Before/after metrics   | Camera distance/screen rect, stance width, handoff duration, setup time, render/collision error, etc., as relevant.                                               |
| Visual evidence        | Paths/labels/timestamps of captures; state whether a human still needs to inspect them.                                                                           |
| Remaining risks        | Anything not solved or intentionally deferred.                                                                                                                    |
| Gate                   | PASS or STOP. Do not start the next phase on STOP.                                                                                                                |
| Canonical run identity | When the canonical acceptance run is relevant: trace/script version, seed/content state, spawn, physics rate, viewport/aspect, quality preset and hardware label. |
| Gate registration      | For every new acceptance fixture: the aggregator/gate it was registered in and evidence that the gate actually executed it.                                       |
| Preservation check     | Previously passed phase gates and unrelated acceptance suites re-run as required; distinguish pre-existing failures from regressions introduced by this phase.    |

# 2. Evidence hierarchy, caveats and baseline observations

| **Rank** | **Evidence**                 | **How to use it**                                                                                                       |
|----------|------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| 1        | Supplied gameplay clip       | Authoritative for what visibly happens: camera loss, framing jumps, pose, terrain readability, environment composition. |
| 2        | Current local working tree   | Authoritative for what the coding model should edit.                                                                    |
| 3        | Connected master @ 760393c   | Architecture/reference snapshot used to identify likely causes and test ownership.                                      |
| 4        | Numeric targets in this plan | Starting acceptance ranges. Adjust only with measured evidence, not intuition alone.                                    |

> **Recorder caveat —** The repo documents that debug MJPEG recording can repeat nearby encoded frames under JPEG worker back-pressure. Duplicate frames seen around ~8.6–8.9 s and ~19.2–19.5 s are not sufficient evidence of gameplay stutter.
>
> **Capture-quality caveat —** The source is 960×540 MJPEG. It is strong evidence for camera movement, pose, composition and broad lighting, but final antialiasing, thin ski edges, tiny snow texture and shader crispness require native-resolution lossless captures.

## 2.1 Measured clip anchors

| **Area**                 | **Observed evidence**                                                                                                            | **Use in regression**                                                       |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| Catastrophic camera loss | At ~12.8 s the skier is ~61×52 px; by ~13.5 s ~13×12 px; target disappears by ~14.6–15 s while camera renders empty environment. | Must never recur. Add target-distance and world-translation assertions.     |
| Takeoff framing \#1      | Around 3.0→3.1 s skier center shifts upward by ~128 px on a 540 px-tall capture; subject also grows.                             | Bound screen-Y derivative and subject-size derivative.                      |
| Takeoff framing \#2      | Around 8.2→8.4 s center shifts upward ~129 px while width grows ~12%.                                                            | Ground→AIR regression on a real slope.                                      |
| Carve framing            | During 4.9–7.6 s horizontal subject center remains roughly 458–503 px on a 960 px frame.                                         | Add modest directional lead rather than permanent center lock.              |
| Straight-air pose        | Repeatedly near-straight knees, upright torso and hanging poles at several jumps.                                                | No-trick silhouette acceptance.                                             |
| Landing transition       | Visible upright AIR pose can become broad ground squat over only a few frames.                                                   | AIR→GROUND ownership/handoff acceptance.                                    |
| World                    | Without the skier, late frames are dominated by uniform gray foreground, sparse props and large smooth mountains.                | Static environment capture must remain convincing without character motion. |

# 3. Repository architecture the implementation must respect

The connected repo is already modular. The plan therefore extends existing systems rather than introducing replacement camera, animation, VFX or level frameworks.

| **Subsystem**             | **Primary ownership**                                                     | **Implementation constraint**                                                                               |
|---------------------------|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| Camera coordinator        | player/camera_controller.gd                                               | Own state policy, target-relative movement, composition, look-ahead, FOV, collision fallback and telemetry. |
| Camera collision          | player/camera/camera_collision_solver.gd                                  | Own sphere sweep/destination overlap/clearance query mechanics; policy remains in coordinator.              |
| Camera framing            | player/camera/camera_framing_solver.gd                                    | Own airborne vertical anchor/dead-zone response.                                                            |
| Composition math          | player/camera/composition_evaluator.gd                                    | Own projected body bounds, hard/inner rect violation and candidate scoring.                                 |
| Ski contact               | player/ski_contact_solver.gd + resources/physics/default_ski_profile.tres | Own physical snow probes, normals, hit positions, contact confidence and surface class.                     |
| Character bridge          | player/skier_controller.gd                                                | Converts gameplay/contact state into SkierAnimationFrame and visual ski targets.                            |
| Animation                 | player/animation/skier_animation_controller.gd and pose layers            | Own procedural stance, AIR phase, landing anticipation, secondary movement, poles and IK integration.       |
| Animation tuning          | resources/animation/default_animation_profile.tres                        | Profile/resource values should be preferred over hard-coded tuning when architecture is sound.              |
| Snow/VFX                  | world/vfx/ski_snow_vfx.gd + ski_contact_presentation.gd                   | Use the existing contact adapter and emitters; do not add a parallel VFX system.                            |
| Course data               | world/course/park_course_profile.gd                                       | Feature positions/design speeds/line membership and spot/challenge definitions are data contracts.          |
| Feature construction      | world/course/park_course_builder.gd + world/park_features/park_layout.gd  | Tabletop geometry is already trajectory-aware; reuse it.                                                    |
| Summit/piste presentation | world/summit_environment_builder.gd + snow shaders                        | Presentation-only render terrain can diverge from the coarse gameplay collider; manage that deliberately.   |
| Environment               | world/resort.gd + world/environment/\*                                    | Trees, ridges, props, reflection probe and resort dressing.                                                 |
| QA                        | tests/\* + quality_gate.ps1 + visual evidence scripts                     | Extend existing fixtures before adding new standalone harnesses.                                            |

## 3.1 Important current-master contracts

| **Contract**              | **Connected-master observation**                                                                              | **Implication**                                                                               |
|---------------------------|---------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| Camera hard limits        | Follow distance defaults ~4.3 m; min ~3.35; max ~7.4; min up offset ~0.7.                                     | Tests should derive limits from controller properties, not duplicate constants.               |
| AIR state changes         | AIR adds distance/height/FOV/look-ahead changes while airborne framing independently changes vertical anchor. | Multiple simultaneous state changes can create visible pumping.                               |
| Physics contact footprint | Default left/right probe x offsets are about −0.34/+0.34 m.                                                   | A 0.68 m physical sample width must not automatically become a 0.68 m rendered stance.        |
| Ground pose               | Resource neutral knee flex 0.55 + speed knee flex 0.34.                                                       | High speed can drive an always-loaded squat before carve/terrain layers.                      |
| AIR flex                  | Resource air_takeoff_leg_flex 0.20; compact flex 0.68.                                                        | Small no-trick air can begin too straight because compactness scales with air size/phase.     |
| Landing handoff           | landing_pose_handoff_duration = 0.08 s.                                                                       | Only ~2.4 frames at 30 fps; likely too abrupt for ordinary AIR→GROUND ownership.              |
| Course slope              | ParkLayout pitch ~18°, face width ~64 m, face length ~337 m in reviewed master.                               | Width is adequate; longitudinal rhythm is the primary course limitation.                      |
| Hero tables               | SmallTable, MediumTable, LargeTable plus StepDownTable are present.                                           | Preserve stable names while making three primary hero jumps; explicitly decide StepDown role. |
| Snow summit shader        | snow_summit.gdshader uses shadows_disabled and strong presentation-only value shaping.                        | Do not treat flat piste as only a texture problem.                                            |
| Trees                     | One structural MultiMesh tree recipe; variant mostly color; broad batch-level LOD.                            | Need structural variants and spatial batching rather than simple random color.                |
| Player reflection probe   | Can recapture after ~10 m with ~0.33 s minimum interval on enabled quality tiers.                             | Must be A/B tested for frame-time/specular discontinuity.                                     |
