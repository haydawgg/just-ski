# Performance backlog

This file is the active performance worklist for Summit Sessions. The reproducible measurement contract and recorded results live in [Performance Baseline 1080p](PERFORMANCE_BASELINE_1080P.md).

## Current contract

- Target output: 1920×1080 at 60 FPS where the selected hardware tier is expected to support it.
- Medium has met the recorded 16.67 ms p95 target on the locally tested Intel UHD adapter at 0.65 render scale for daytime and sunset scenarios.
- High should be validated on representative discrete-GPU release hardware at 1.0 render scale.
- Ultra is best-effort rather than a release baseline.
- Performance changes must be measured against the maintained deterministic scenario matrix. Do not infer wins from source size, object count, or FPS alone.

## P0 — clean current-`master` baseline refresh

- [ ] Recapture the maintained 1080p matrix on a clean `master` worktree so the maintained reference reflects current behavior instead of the 2026-09-02 dirty-tree capture (issue #30).
- [ ] Update the [performance reference](PERFORMANCE_BASELINE_1080P.md) identity block with the new commit, tree state, and capture date.

## P0 — release-hardware validation

- [ ] Repeat the maintained 1080p benchmark matrix on each representative supported hardware tier.
- [ ] Record OS, CPU, GPU, driver, Godot version, preset, render scale, snow tier, and effective GI state for every result.
- [ ] Validate daytime and sunset separately.
- [ ] Treat hardware-specific failures as measured release risks rather than extrapolating from headless CI.
- [ ] A/B the player-following reflection probe on target hardware (`.\tests\visual_profile.ps1 -IsolationModes baseline,environment_effects`); compare `Resort.player_probe_summary()` recapture counts/intervals and inspect skis, goggles, rails, and feature highlights for specular jumps before keeping, throttling, or removing the probe.

## P0 — production snow profiling

- [ ] Profile Fast and Premium snow on representative GPUs.
- [ ] Measure near/far detail blending, crystal/sparkle response, subsurface contribution, and material cost.
- [ ] Verify texture import memory behavior and mip/compression state before considering shader-quality reductions.
- [ ] Add a farther-distance snow path only if profiling shows the remaining detail work is material to frame time.

## P1 — High-preset discrete-GPU pass

- [ ] Run the deterministic benchmark scenarios on representative discrete hardware using High at 1.0 render scale.
- [ ] Identify the dominant CPU, GPU, submission, memory, or overdraw bound before choosing changes.
- [ ] Re-test summit overview, dense vegetation, full downhill run, heavy spray, rail-heavy view, large jump, bail/crash, and sunset.

## P1 — conditional optimization candidates

Only pursue an item when profiling identifies the corresponding bottleneck:

- shared/cached snow and environment materials where equivalent state allows reuse;
- farther-distance snow simplification when GPU-bound;
- haze/post-effect overdraw refinement when GPU-bound;
- tree/prop batching extensions when CPU/submission-bound;
- ski-track mesh update/coalescing when main-thread profiling justifies it;
- LOD-distance centralization through `EnvironmentAssetDefinition`;
- export-content audit and removal of confirmed packaged development bloat.

## P2 — pipeline cleanup

These are maintainability tasks, not automatic performance wins:

- [ ] Move course feature dictionaries toward typed resources after the content metadata contract is stable.
- [ ] Consolidate duplicated terrain-mesh construction only after interfaces are clear.
- [ ] Continue centralizing reusable material definitions where it reduces duplicated authored state.
- [ ] Preserve explicit source/derived asset conventions and provenance records.

## Evidence-required / deferred

Do not implement these without a measured need and matched visual review where applicable:

- dynamic resolution;
- large persistent snow-deformation textures;
- LightmapGI migration;
- broad occluder-sector systems;
- major summit tessellation increases;
- global reductions to anisotropic filtering;
- global snow-darkening or aggressive material changes;
- renderer/plugin infrastructure added only for hypothetical optimization.

## Validation rules

Every performance change affecting runtime rendering, world construction, VFX, materials, LODs, or batching should:

1. run the existing static and runtime quality gates;
2. identify the benchmark scenario and hardware used;
3. compare against an ancestry-compatible baseline on the same machine/settings;
4. report frame-time/cadence and relevant render/memory counters;
5. include matched visual captures when visual quality changes;
6. avoid claiming a GPU or CPU improvement when the evidence only shows an FPS change without identifying the bound.

## Related documents

- [Performance Baseline 1080p](PERFORMANCE_BASELINE_1080P.md) — reproducible measurements and scenario contract.
- [Known Issues](KNOWN_ISSUES.md) — unresolved production/performance validation items.
- [Content Design](CONTENT_DESIGN_PLAN.md) — active course/content work; recheck performance as course density changes.
- [Graphics](GRAPHICS.md) — renderer/settings architecture and visual validation boundary.