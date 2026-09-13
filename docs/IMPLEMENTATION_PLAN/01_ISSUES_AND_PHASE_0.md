# 4. Consolidated issue register

| **ID**    | **Pri.** | **Issue**                                                                                                                                                             | **Primary ownership**                                           |
|-----------|----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------|
| CAM-01    | P0       | Camera can remain behind after final crest/landing until skier disappears.                                                                                            | camera_controller.gd; camera_collision_solver.gd                |
| CAM-02    | P0       | Emergency paths can commit frame_start_position after target has moved, allowing repeated world-space freeze.                                                         | camera_controller.gd                                            |
| CAM-03    | P1       | Collision trace can report destination overlap while returning desired position when cast_motion safe_fraction is 1.0.                                                | camera_collision_solver.gd                                      |
| CAM-04    | P1       | LANDING is both soft-composition and handled in the early GROUND/LANDING/RAIL branch; recovery contract is ambiguous.                                                 | camera_controller.gd                                            |
| CAM-05    | P1       | Takeoff camera pumps vertically and in subject scale.                                                                                                                 | camera_framing_solver.gd; camera_controller.gd                  |
| CAM-06    | P1       | Ground slope normal blends toward world-up on AIR entry; flat synthetic tests miss the 18° transition.                                                                | camera_controller.gd; camera_airborne_viewport_diagnostic.gd    |
| CAM-07    | P2       | Full 3D velocity can feed ordinary speed distance/FOV behavior; vertical jump velocity can masquerade as speed.                                                       | camera_controller.gd                                            |
| CAM-08    | P2       | Turn look-ahead remains weak/center-locked; absolute heading-angle logic does not explicitly create inside-turn composition.                                          | camera_controller.gd                                            |
| CAM-09    | P2       | Resolved: removed the unused `maximum_position_speed` export; camera motion remains governed by the active spring, correction, distance-rate, and reacquire limits.       | camera_controller.gd                                            |
| CHAR-01   | P1       | Physics contact width can directly force the rendered skis too far apart.                                                                                             | ski_contact_solver.gd; skier_controller.gd; animation IK        |
| CHAR-02   | P1       | Existing isolated stance tests can bypass actual gameplay ski-target path.                                                                                            | tests/animation_silhouette_acceptance.gd + new end-to-end case  |
| CHAR-03   | P1       | High-speed ground stance is too deep even before carve/terrain load.                                                                                                  | ground pose + default_animation_profile.tres                    |
| CHAR-04   | P1       | Straight no-trick AIR becomes upright/mannequin-like.                                                                                                                 | air_trick_pose_layer.gd; skier_animation_controller.gd; profile |
| CHAR-05   | P1       | Landing preview/IK can visually reach for snow and consume suspension before contact.                                                                                 | air preview IK + animation controller                           |
| CHAR-06   | P1       | AIR→GROUND ownership is only 0.08 s by default.                                                                                                                       | default_animation_profile.tres; controller                      |
| CHAR-07   | P2       | Carve reads as pelvis swing more than outside-ski load/counter-angulation.                                                                                            | ground pose / animation controller                              |
| CHAR-08   | P2       | Skis and edge angle are hard to read at normal chase distance.                                                                                                        | equipment materials/scale + animation presentation              |
| CHAR-09   | P2       | Poles hang too vertically and secondary inertia is under-readable.                                                                                                    | animation controller / pole presentation                        |
| VFX-01    | P1       | Carve/skid spray ownership is tied to fixed left/right emitters rather than loaded ski/edge.                                                                          | world/vfx/ski_snow_vfx.gd                                       |
| VFX-02    | P1       | Landing one-shot can be restarted during a longer landing window, producing repeated bursts.                                                                          | world/vfx/ski_snow_vfx.gd                                       |
| VFX-03    | P1       | Contact shadow remains blob-like and too confident/dark in low AIR.                                                                                                   | contact shadow implementation                                   |
| VFX-04    | P1       | Existing contact-shadow diagnostic can reuse final transforms for earlier samples and compare different cameras.                                                      | shadow diagnostic/test                                          |
| COURSE-01 | P1       | Current run has insufficient recovery/setup time between major features.                                                                                              | park_course_profile.gd                                          |
| COURSE-02 | P1       | Primary line is too cluttered; mandatory-feeling rails/rollers interfere with jump setup.                                                                             | feature_specs / line membership                                 |
| COURSE-03 | P1       | Desired three-jump progression conflicts with a fourth StepDownTable unless its role is explicit.                                                                     | feature_specs + spot/challenge metadata                         |
| COURSE-04 | P1       | Six stable spot/content IDs and challenge/telemetry relationships must survive or be migrated deliberately.                                                           | spot_specs/challenge_specs/content tracker/tests                |
| TERR-01   | P1       | Table/deck/landing pieces expose slab-like seams and construction logic.                                                                                              | park_layout.gd + render blending                                |
| TERR-02   | P1       | Main presentation snow and gameplay collision can diverge, especially shoulders.                                                                                      | summit_environment_builder.gd                                   |
| TERR-03   | P2       | Jump readability partly relies on opaque turquoise guide geometry rather than terrain shape/lighting.                                                                 | jump readability markers                                        |
| SNOW-01   | P1       | Summit presentation shader disables shadows; reviewed render surface spans the face longitudinally.                                                                   | summit_environment_builder.gd; snow_summit.gdshader             |
| SNOW-02   | P2       | Strong additive drift + luminance floor can flatten or clip snow values.                                                                                              | snow_summit.gdshader                                            |
| SNOW-03   | P2       | Park-feature detail persists farther than base piste detail, reinforcing pasted-on slabs.                                                                             | snow presentation/profile                                       |
| WORLD-01  | P2       | Trees share one structural recipe and broad batch LOD; visual repetition is structural.                                                                               | park_tree_batch.gd                                              |
| WORLD-02  | P2       | Mountain peaks share the same ring-scale topology family; seed changes are insufficient.                                                                              | summit_environment_builder.gd                                   |
| WORLD-03  | P2       | Mountain shader haze and global fog/aerial perspective can double-wash background depth.                                                                              | distant_mountain.gdshader; environment profile                  |
| WORLD-04  | P2       | World is sparse and lacks nearby parallax/resort infrastructure to sell 60–75 km/h.                                                                                   | resort dressing / asset catalog                                 |
| WORLD-05  | P2       | Lift and park-feature environmental integration read as placeholder/minimal.                                                                                          | resort dressing / assets                                        |
| WORLD-06  | P3       | Sky/world history are too clean: limited clouds, grooming history, scraped landings, accumulated snow.                                                                | environment art pass                                            |
| PERF-01   | P2       | Moving reflection probe needs frame-time/specular A/B before release.                                                                                                 | world/resort.gd                                                 |
| QA-01     | P1       | Camera performance acceptance is too flat/grounded to reproduce AIR→LANDING convex-crest failure.                                                                     | tests/camera_performance_acceptance.gd                          |
| QA-02     | P1       | Camera tests need projected subject-size and screen-Y continuity metrics.                                                                                             | camera viewport diagnostic/acceptance                           |
| QA-03     | P1       | Stance QA needs real contact→frame→IK end-to-end path.                                                                                                                | new/extended animation/contact acceptance                       |
| QA-04     | P1       | Jump readability must be reviewed with guide strips hidden.                                                                                                           | environment visual evidence                                     |
| QA-05     | P2       | Fine visual approval must use native/lossless GPU captures, not only the MJPEG source.                                                                                | visual evidence workflow                                        |
| QA-06     | P0       | The standardized baseline is reproducible in intent but not deterministic enough for strict before/after attribution.                                                 | Phase 0 canonical scripted/input-trace fixture                  |
| QA-07     | P0       | New acceptance fixtures can exist without being registered in the executable quality/runtime gate.                                                                    | test aggregators / quality gate                                 |
| PERF-02   | P1       | Environment, terrain, VFX and presentation changes lack a whole-game release performance budget beyond the reflection-probe A/B.                                      | profiling acceptance + Phase 12                                 |
| COURSE-05 | P1       | Hero-jump acceptance is centered on nominal design speed without an explicit approach-speed/angle robustness envelope.                                                | course acceptance / trajectory QA                               |
| WORLD-07  | P1       | Added resort/parallax dressing can obstruct the chase camera even when props are outside the primary ski corridor.                                                    | environment placement + camera visibility QA                    |
| QA-08     | P1       | Integrated release acceptance is dominated by a clean happy-path run and does not explicitly preserve crash, recovery, respawn, low-speed and feature-state behavior. | Phase 13 regression matrix                                      |
| QA-09     | P2       | Camera/lighting sign-off does not explicitly cover supported aspect ratios, resizing/window modes, or actual SDR/HDR output state.                                    | display/settings + visual acceptance                            |

# Phase 0 — Preflight, local drift check and reproducible baseline

Do not tune anything yet. Confirm the exact local implementation, capture the old behavior, and make the later phases measurable.

### Inspect first

- player/camera_controller.gd; player/camera/camera_collision_solver.gd; player/camera/camera_framing_solver.gd; player/camera/composition_evaluator.gd

- player/skier_controller.gd; player/ski_contact_solver.gd; resources/physics/default_ski_profile.tres

- player/animation/skier_animation_controller.gd; player/animation/air_trick_pose_layer.gd; player/animation/ground_pose_layer.gd; resources/animation/default_animation_profile.tres

- world/course/park_course_profile.gd; world/course/park_course_builder.gd; world/park_features/park_layout.gd

- world/summit_environment_builder.gd; shaders/snow_summit.gdshader; snow presentation profiles; world/resort_environment_profile.gd

- world/vfx/ski_snow_vfx.gd; world/vfx/ski_contact_presentation.gd; world/environment/park_tree_batch.gd; world/resort.gd

- Relevant tests plus tests/quality_gate.ps1, tests/runtime_quality_gate.ps1 if present, profiling/performance-profile acceptance present in the local tree, and visual evidence/bundle scripts.

### Procedure

1\. Record git rev-parse HEAD and git status --short. Save a patch or note for any already-dirty relevant file; do not overwrite user work.

2\. Diff local versions against the connected-master assumptions in this document. Mark each issue as CONFIRMED, CHANGED PATH, or NOT PRESENT.

3\. Establish a canonical deterministic acceptance artifact: fixed spawn/transform, RNG/world seed or equivalent captured content state, exact input timeline/trace or script, primary physics-rate target, quality preset, viewport/aspect and named event markers. The route must include high-speed straight skiing, linked left/right carves, small/medium/large air, clean landings, the convex crest/landing case, and at least five seconds of continued skiing afterward.

4\. Capture the baseline by running the canonical artifact unchanged. Re-run the exact artifact before/after every phase that can affect its measurements. If the local project has no input replay facility, add the smallest scripted acceptance fixture needed for this run; do not build a general replay system for this plan.

5\. Enable/extend telemetry for camera state, target distance, final candidate/fallback reason, collision safe fraction, screen rect, body occlusion, camera/target displacement, surface-up vector, FOV and subject rect height.

6\. Capture animation telemetry: ski target separation, contact hit separation, ground flex, AIR flex/phase, landing anticipation/preview weight, landing compression, leg loading, pole direction.

7\. Capture course telemetry: each hero jump lip, design speed, predicted range, actual lip speed, landing end, next lip, and time from stable landing recovery to next takeoff.

8\. Run the existing quality gate and runtime gate/aggregators used by the local tree, generate the existing visual analysis bundle, and record profiling acceptance before making behavior changes. Record known pre-existing failures separately so later regressions cannot be confused with baseline debt.

> **Gate —** Baseline artifacts exist; the canonical deterministic run is identified and repeatable; the final camera divergence is reproducible or a local equivalent is identified; existing gate/profiling status is recorded; and every later phase has the telemetry needed to prove improvement without changing the test conditions silently.
>
> **Do not —** Do not tune values, flatten terrain, move jumps, or classify recorder duplicate frames as simulation hitches during baseline.
