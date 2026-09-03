# Performance Backlog

This file is the active performance worklist for Summit Sessions. Historical investigation, rejected experiments, and the original phased roadmap are preserved in `docs/history/PERFORMANCE_ROADMAP_2026-09-02.md`.

The authoritative reproducible measurement contract is `docs/PERFORMANCE_BASELINE_1080P.md`. `docs/BASELINE.md` remains historical context only.

## Current performance contract

- Target output: 1920×1080 at 60 FPS where the selected hardware tier is expected to support it.
- Medium on the locally tested Intel UHD adapter has met the recorded 16.67 ms p95 target at 0.65 render scale for daytime and sunset scenarios.
- High should be validated on representative discrete-GPU release hardware at 1.0 render scale.
- Ultra remains best-effort rather than a release baseline.
- Performance changes must be measured against the reproducible scenario matrix rather than inferred from source size, object count, or FPS alone.

## Active work

### P0 — Release-hardware validation

- [ ] Repeat the maintained 1080p benchmark matrix on each representative supported hardware tier.
- [ ] Record OS, CPU, GPU, driver, Godot version, preset, render scale, snow tier, and effective GI state for every result.
- [ ] Validate daytime and sunset separately.
- [ ] Treat hardware-specific failures as measured release risks rather than extrapolating from headless CI.

### P0 — Production snow profiling

- [ ] Profile Fast and Premium snow on representative GPUs.
- [ ] Measure near/far detail blending, crystal/sparkle response, subsurface contribution, and material cost.
- [ ] Verify texture import memory behavior and mip/compression state before considering shader-quality reductions.
- [ ] Only add a farther-distance snow path if profiling shows the remaining noise/detail work is material to frame time.

### P1 — High-preset discrete-GPU pass

- [ ] Run the same deterministic benchmark scenarios on representative discrete hardware using High at 1.0 render scale.
- [ ] Identify the dominant CPU, GPU, submission, memory, or overdraw bound before choosing changes.
- [ ] Re-test summit overview, dense vegetation, full downhill run, heavy spray, rail-heavy view, large jump, bail/crash, and sunset.

### P1 — Remaining production optimization candidates

Only pursue these when the benchmark identifies the corresponding bottleneck:

- shared/cached snow and environment materials where equivalent state allows reuse;
- farther-distance snow simplification when GPU-bound;
- high-haze and post-effect overdraw refinement when GPU-bound;
- tree/prop batching extensions when CPU/submission-bound;
- ski-track mesh update/coalescing work when main-thread profiling justifies it;
- LOD-distance centralization through `EnvironmentAssetDefinition`;
- export-content audit and removal of confirmed packaged development bloat.

### P2 — Pipeline cleanup

These are maintainability tasks, not automatic performance wins. Keep them behind behavior and benchmark checks:

- [ ] Move course feature dictionaries toward typed resources once the content-design metadata contract is stable.
- [ ] Consolidate duplicated terrain-mesh construction only after interfaces are clear.
- [ ] Continue centralizing reusable material definitions where it reduces duplicated authored state.
- [ ] Keep source/derived asset conventions explicit and preserve provenance/licensing records.

## Evidence-required / deferred work

Do not implement these without a measured need and matched visual review where applicable:

- dynamic resolution;
- large persistent snow-deformation textures;
- LightmapGI migration;
- broad occluder-sector systems;
- major summit tessellation increases;
- global reductions to anisotropic filtering;
- global snow-darkening or aggressive material changes;
- renderer/plugin infrastructure added only for hypothetical future optimization.

## Validation rules

Every performance PR that changes runtime rendering, world construction, VFX, materials, LODs, or batching should:

1. run the existing static and runtime Quality Gate;
2. identify the benchmark scenario and hardware used;
3. compare against an ancestry-compatible baseline on the same machine/settings;
4. report frame-time/cadence and relevant render/memory counters;
5. include matched visual captures when visual quality changes;
6. avoid claiming a GPU or CPU improvement when only FPS was observed without enough evidence to identify the bound.

## Related documents

- `docs/PERFORMANCE_BASELINE_1080P.md` — current reproducible performance measurements and scenario contract.
- `docs/KNOWN_ISSUES.md` — unresolved production/performance validation items.
- `docs/CONTENT_DESIGN_PLAN.md` — active course/content work; performance should be rechecked as course density changes.
- `docs/history/PERFORMANCE_ROADMAP_2026-09-02.md` — original investigation, phased plan, stale findings, and rejected ideas preserved for decision history.
