# Production ski-run QA checklist

Use this checklist when changing or replacing scenes in the environment asset catalog. The checked automated items are covered by the runtime suite or the standalone GPU visual gate; the hands-on play pass remains a release activity.

## Automated gates

- [x] `environment_asset_contract_acceptance.tscn` passes in `AUTO` mode and selects the production scenes.
- [x] `environment_asset_production_acceptance.tscn` runs the resort in strict `PRODUCTION` mode without a fallback.
- [x] Concrete physical render/collision bounds are within ±10% and grounded at snow contact.
- [x] `GUIDE` assets have no collider and route flags use a soft/translucent treatment.
- [x] `GRIND_ONLY` features retain the grind layer and do not enter skier capsule-impact collision.
- [x] `crash_recovery_acceptance.tscn` and `camera_low_speed_acceptance.tscn` cover recovery lifecycle, score preservation, crash equipment, swept camera clearance, and telemetry.
- [x] `camera_performance_acceptance.tscn` samples the real camera update at 30, 60, and 120 Hz and records bounded pose cost without a machine-specific timing threshold.
- [x] `quality_gate.ps1` runs the static physics, static shader, and complete runtime gates as one reproducible command.
- [x] `sunset_environment_acceptance.tscn` validates the warm sky/low sun profile, Forward+ SDFGI settings, static GI geometry, and quality gating.
- [x] `summit_environment_acceptance.tscn` validates deterministic heightfield samples, preserved `MainSnowFace` collision, authored ridge meshes, and collider-free summit decorations.
- [x] `sunset_visual_quality_gate.ps1` runs the Vulkan sunset trajectory capture and focused near-black-region metric; it remains separate from the headless runtime checks.
- [x] `environment_visual_quality_gate.ps1` clears and refreshes `res://.godot_user/captures/snow_depth_after`, requires all nine PNG/JSON pairs, checks the GPU process exit/logs, and runs the snow-depth metric against the fresh capture set.
- [x] `ramp_surface_visual_quality_gate.ps1` captures the tabletop approach/lip/deck/landing plus roller, berm, and side-hit surfaces at the gameplay camera in Day and Sunset, with `PARK_FEATURE` material telemetry and no automatic baseline update.
- [x] `visual_evidence_acceptance.tscn` and `visual_evidence_static_acceptance.ps1` validate the Codex evidence schema, deterministic ordering, structured telemetry, artifact hashes, dimensions, path containment, and malformed-fixture cases without a GPU.
- [x] `visual_analysis_bundle.ps1` is the canonical local GPU workflow for maintained environment, animation, and sunset evidence.
- [x] `visual_analysis_bundle.ps1 -IncludeMotion` can sweep Day/Golden/Sunset at the requested render scales with fixed-rate motion telemetry and contact sheets.
- [x] `visual_analysis_bundle.ps1 -IncludeRecovery` captures the out-of-bounds fade, respawn, camera reset, and completed lifecycle as reviewable phase artifacts.
- [x] `continuous_course_release_acceptance.tscn` drives the production spawn-to-finish course with normal input, all three real hero takeoffs and landings, no reset between events, and at least five seconds of skiing after LargeTable. It is registered in the release-stress runtime shard.

## Human visual pass

- [ ] Replay the supplied route at 30, 60, and 120 Hz with keyboard and controller.
- [ ] Compare gate posts, trees, rails, slabs, panels, boundaries, and the skier against the meter-scale reference at near, mid, and gameplay distances.
- [ ] Contact every reachable solid feature and confirm the visual surface and collider agree; pass through route guides to confirm they never produce an invisible impact.
- [ ] Grind rails and boxes capture only through the grind affordance and never bounce the skier capsule.
- [ ] Trigger high-speed landings, rail exits, boundary recoveries, and the supplied crash. Confirm the HUD identifies the reason and the camera keeps the pelvis/upper body readable.
- [ ] Confirm fade-out → respawn → camera reset → fade-in occurs once, combo/link clears, and total score remains unchanged.
- [ ] Install Godot 4.7.2 export templates, create the platform release export used for the target build, and smoke-test that exported build with the same route.
- [ ] Compare the daytime and sunset scenes at near, mid, and horizon distances; tune glare, shadow density, and snow readability on the target display.
- [ ] Review the seven ramp-surface shots in Day and Sunset; confirm the Snow 02 texture remains readable through the approach, rotated lip/deck/landing, roller, berm, and side hit, with no visible UV-dependent tiling or pop against adjacent piste.
- [ ] Review the bundle report's environment landing subject crops and sunset capture on the target display; confirm the shadow-safe summit surface retains shoulder/form readability while the rest of the scene keeps the intended GI/shadow balance.
- [ ] Review the motion-sweep contact sheets at each target environment/render-scale pair; confirm carve, straight, and landing sweeps remain readable for the full ten seconds.
- [ ] Review the recovery phase captures; confirm the notice, fade, respawn, and completed frame communicate one clean transition at the target display refresh rate.

The environment gate also records landing telemetry for first contact, impact,
compression, recovery, and final landing. Confirm `vfx_mode="landing"` and an
active landing emitter in the landing JSON before judging spray separation.

## Integrated release acceptance (Phase 13)

The canonical run is `tests/canonical_release_run.tscn` (trace version
`canonical_release_run/v1`): fixed spawn acceleration, linked left/right
carves, small/medium/large hero airs with clean landings, 300+ frames after the
final landing, and the finish runout. It records wall/physics/process
percentiles, camera telemetry, event markers, and probe telemetry to
`user://canonical_release_profile.json`. Baseline `ebd9276` vs final: 1828 vs
1854 frames, wall p50/p95 8.30/8.34 ms both, airtimes 2.08/2.63/3.25 s vs
2.15/2.83/3.42 s, zero grounded hard-invalid frames and zero camera fallbacks
in both. GPU/human performance and visual review remain outstanding.

The complementary physical integration trace is
`tests/continuous_course_release_acceptance.tscn`
(`continuous_course_release_acceptance/v1`). Unlike the deterministic benchmark,
it begins at the production spawn and drives ordinary input/state transitions to
the real finish without teleporting, writing transforms or velocities, resetting
the camera, or calling `reset_for_benchmark`. Its 60 Hz acceptance run completed
in 33.22 s (1,993 physics frames) with no bail or recovery respawn, zero hard
composition-invalid frames, and these measured events:

| Measurement | SmallTable | MediumTable | LargeTable |
| --- | ---: | ---: | ---: |
| Lip speed | 16.36 m/s | 17.71 m/s | 17.28 m/s |
| Airtime | 1.85 s | 1.98 s | 1.95 s |
| Lateral line error | 1.34 m | 0.70 m | 1.66 m |
| Continuous grounded recovery | 4.05 s | 5.32 s | 2.43 s before finish |
| Stable recovery confirmation | 0.50 s | 0.50 s | 0.50 s |

The skier continued for 8.57 s after LargeTable before the authoritative finish.
Camera target distance remained 3.64–7.40 m; 102 bounded fallback samples were
recorded and no hard-invalid sample occurred. The structured trace is written to
`user://continuous_course_release_profile.json`.

The production drop-in now measures 77.69 slope metres from spawn to the
SmallTable structure, within the accepted 60–100 m region. The continuous trace
charged at 8.83 s / 14.66 m/s and took off at 9.50 s / 16.36 m/s. The extra
distance was added uphill; the three hero jumps and their established spacing
were not moved, and skier physics was not retuned.

| Gate area | Executable evidence |
| --- | --- |
| Camera correctness | `camera_convex_crest_follow_acceptance`, `camera_kidnapped_reacquire_acceptance`, `camera_collision_destination_acceptance`, `camera_airborne_viewport_diagnostic` (30/60/120 Hz), `camera_runtime_stability_acceptance` |
| Camera comfort | `camera_airborne_viewport_diagnostic`, `camera_low_speed_acceptance`, `environment_camera_sweep_acceptance` |
| Contact/stance | `contact_stance_acceptance`, `terrain_suspension_course`, `crest_unweighting_acceptance` |
| Animation | `jump_animation_acceptance`, `landing_animation_acceptance`, `trick_animation_acceptance`, `grab_animation_acceptance`, `animation_silhouette_acceptance` |
| VFX/shadow | `snow_vfx_acceptance`, `contact_shadow_diagnostic`, `environment_visual_acceptance` |
| Course | `continuous_course_release_acceptance`, `course_rhythm_acceptance`, `park_challenge_playthrough_acceptance`, `release_jump_envelope_acceptance` |
| Terrain | `park_terrain_continuity_acceptance`, `wedge_viewport_diagnostic`, `physics_collision_acceptance` |
| Snow/lighting | `snow_lighting_architecture_acceptance`, `environment_visual_acceptance`, `sunset_environment_acceptance` |
| Environment | `environment_tree_batch_acceptance`, `resort_density_acceptance`, `summit_environment_acceptance` |
| Performance | `canonical_release_run`, `profiling_acceptance`, `performance_profile_schema_acceptance`, `performance_compare_acceptance` |
| Display/UI | `display_aspect_acceptance`, `settings_acceptance`, `trick_ui_acceptance`, `clip_recorder_lifecycle_acceptance` |
| Visual evidence | `visual_evidence_acceptance` plus the GPU capture gates below (human review outstanding) |
| Regression preservation | `static_quality_gate.ps1` plus all six runtime shards |

Stress evidence: `release_jump_envelope_acceptance` sweeps each hero jump at
±15% entry speed, ±3.5 m lateral offsets, and ±8° approach error (18/18 clean)
plus a deliberate ride-around per jump (3/3), a 0.9 s terrain takeoff smaller
than every table air, and a 30-pass convex-crest loop (30/30 grounded landings,
0 bails) — 58 discrete landing/crest passes total; `release_carve_stress_acceptance`
runs eight linked high-speed carves with zero invalid frames;
`release_cross_state_acceptance` covers braked low-speed recovery, bail
recovery, and respawn relocation; the environment camera sweep was already
re-run after final dressing.

Observation (pre-existing, out of Phase 13 scope): a near-stationary grounded
skier placed on the flat BottomHub finish pad receives a snow-normal impulse
that launches it off the pad. Normal play crosses the finish trigger before
that region, so it does not affect the shipping run; it is recorded here rather
than fixed.

## GPU-backed sunset visual check

Run this on the Vulkan/NVIDIA reference machine after the headless gates:

```powershell
.\tests\sunset_visual_quality_gate.ps1
```

The command captures the same deterministic 1280×720 sunset trajectory, then rejects any contiguous near-black region larger than 2% of the lower gameplay ROI after HUD/skier masks. It is intentionally supplemental and separate from `quality_gate.ps1`, because the headless runtime gate does not validate the rendered pixels on the reference GPU.

For daytime snow and landing review, run:

```powershell
.\tests\environment_visual_quality_gate.ps1
```

Both GPU gates wait for the capture process, inspect its exit code and logs,
require fresh output files, and fail when a renderer shutdown leak is reported.

For the complete Codex-facing review bundle, run `.\tests\visual_analysis_bundle.ps1` after the headless gate. Do not update baselines from this dirty worktree; baseline seeding must use an explicitly reviewed clean reference capture.

## Local GPU characterization and deferred review

On the available NVIDIA GeForce RTX 4050 Laptop GPU, Godot 4.7.2 Forward+ at
1920×1080, High preset and render scale 1.0, the maintained identical daytime
trace produced the following local probe A/B. This is characterization, not a
shipping-hardware budget or sign-off.

| Isolation | Avg / p95 / p99 / max frame time | Probe recaptures | Recapture frame samples |
| --- | --- | ---: | --- |
| Baseline | 5.74 / 6.61 / 27.35 / 65.89 ms | 2, none in AIR | 64.35, 65.79 ms |
| Environment effects isolation | 5.32 / 6.41 / 23.44 / 72.61 ms | 2, none in AIR | 4.41, 4.51 ms |
| Probe disabled | 5.66 / 6.06 / 31.43 / 73.20 ms | 0 | n/a |

Because disabling the probe did not improve the overall tail and recapture-frame
cost changed materially with isolation mode, the local result is inconclusive;
the existing recapture policy remains unchanged. `Resort.player_probe_summary()`
now records recapture intervals, process frames and their frame-time samples for
a repeatable target-hardware comparison. **TARGET_HARDWARE_A_B_DEFERRED.**

Machine-generated visual evidence is under
`.godot_user/visual_runs/visual_20260912_232703_893_0e28b7b`. It records the
commit, dirty state, renderer, GPU, dimensions, preset, environment and hashes,
and contains Day/Golden/Sunset structured PNG evidence plus the available motion
traces and guide-hidden ramp captures. This run is not a human approval. Its
manifest currently reports three objective errors: the snow-depth pixel check is
red against the maintained 0.095 threshold (0.061 average spread), the Sunset
carve motion manifest was not produced after a local audio-device invalidation,
and the Sunset straight motion log contains a renderer shutdown warning. The
earlier eight `scenario ROI is invalid` errors came from PR #69 adding the
`medium_deck`, `medium_landing`, `large_knuckle` and `large_landing` shots
without catalog entries; those entries now exist in `tests/visual_scenarios.json`
and the bundle was rebuilt with the Python post-processor only, which produced
all eight subject crops. Preserve the remaining objective results; do not lower
the metric or call the partial bundle green. The complete pass summary is in
`docs/RELEASE_READINESS_REPORT.md`.

The uninterrupted gameplay trace has its own passing structured, lossless
1280×720 set at `.godot_user/visual_runs/continuous_course_release`: 16 frames
cover both linked carve directions, every approach/charge, takeoff, apex and
first-contact landing, five seconds after LargeTable, and the actual finish,
along with the JSON telemetry. Guide-hidden ramp sets are at
`.godot_user/visual_runs/ramp_surface_daytime_noguides` and
`.godot_user/visual_runs/ramp_surface_sunset_noguides`. Contact-shadow height
samples are under `.godot_user/contact_shadow_gpu`, and the passing Sunset
near-black capture is under `.godot_user/captures` (see
`.godot_logs/sunset_visual_gate.stdout.log` for its exact timestamped filename).
The separately refreshed canonical and skier-hidden environment sets are under
`.godot_user/captures/snow_depth_after*`; both produced all artifacts, but the
maintained snow-depth check remains red at 0.044 average spread versus 0.095.

**HUMAN_REVIEW_DEFERRED:** athletic pose quality, perceived camera comfort, snow
realism, jump readability, resort believability, ski readability, shadow
aesthetics, overall presentation, target-display review and human play-testing.
