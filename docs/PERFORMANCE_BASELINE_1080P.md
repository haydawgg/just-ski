# Recorded 1080p performance reference

This document is the maintained reproducible performance-measurement contract for Summit Sessions plus the most recent retained reference measurements. Old investigations and superseded diagnoses belong in Git history rather than parallel baseline documents.

The measurements below are **not a performance claim about current `master`**. They were captured on September 2 from the exact source state identified below, and the tree was dirty at capture time. They remain useful as hardware/scenario reference evidence until a reviewed clean-tree baseline is recorded on current code. Active refresh work is tracked in [Performance Backlog](PERFORMANCE_BACKLOG.md).

## Measurement contract

- Capture date: 2026-09-02.
- Source commit: `012a0d40f6b7c91a53c80840794dacee5b651a29`.
- Working tree: dirty. These numbers are useful measurements but must not be described as a pristine commit baseline or current-master result.
- Godot: `4.7.2-stable (official)`.
- Reference host: Windows, 12th Gen Intel Core i7-12650H, NVIDIA GeForce RTX 4050 Laptop GPU.
- Output: 1920×1080; VSync and FPS cap disabled for profiling.
- Frame values are whole rendered-frame/wall-clock measurements from the deterministic inspection trajectory, not GPU timestamps.

The profiler records environment, preset, isolation scenario, commit/dirty state, hardware identity, Godot version, viewport, render scale, sample count, frame-time distribution, render counts/memory, and audio processing cost.

`tests/performance_compare.ps1` compares rows only when scenario and runtime identity are compatible. `-FailOnRegression` rejects both measured regressions and mismatched identities instead of pretending cross-hardware results are comparable.

## Recorded discrete-GPU matrix

| Environment | Preset | Scale | Average frame | p95 | FPS | Objects | Draw calls | Primitives | Audio average | Audio max |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Daytime | Low | 0.65 | 2.503 ms | 4.031 ms | 399.5 | 691 | 375 | 193,524 | 57.86 µs | 1,396 µs |
| Daytime | Medium | 0.65 | 2.267 ms | 4.313 ms | 441.1 | 778 | 462 | 234,748 | 55.21 µs | 1,028 µs |
| Daytime | High | 1.00 | 3.512 ms | 4.810 ms | 284.7 | 1,045 | 729 | 400,288 | 79.97 µs | 1,227 µs |
| Daytime | Ultra | 1.00 | 3.970 ms | 5.360 ms | 251.9 | 1,068 | 752 | 413,892 | 89.49 µs | 893 µs |
| Sunset | Low | 0.65 | 2.515 ms | 4.093 ms | 397.6 | 691 | 375 | 193,524 | 58.75 µs | 1,063 µs |
| Sunset | Medium | 0.65 | 2.291 ms | 4.299 ms | 436.5 | 778 | 462 | 234,748 | 55.96 µs | 985 µs |
| Sunset | High | 1.00 | 4.356 ms | 5.780 ms | 229.6 | 1,045 | 729 | 400,288 | 101.24 µs | 1,334 µs |
| Sunset | Ultra | 1.00 | 4.852 ms | 6.271 ms | 206.1 | 1,068 | 752 | 413,892 | 112.20 µs | 1,540 µs |

All recorded RTX 4050 rows were below the 16.67 ms whole-frame target in that capture. The machine-readable evidence is `docs/performance/2026-09-02-current-tree-summary.json`; the filename is retained for traceability and should be read as a dated snapshot, not as a claim that it represents the current repository tree.

## Integrated-GPU validation

The same harness was forced to the local Intel UHD Graphics Vulkan adapter. Medium used a measured 0.65 3D render scale with Fast snow and no GI.

The recorded baseline p95 was:

- daytime: `14.134 ms`;
- sunset: `14.202 ms`.

Both stayed below the 16.67 ms target on that host. Baseline audio averages were `266.92 µs` and `303.91 µs`. The machine-readable records are in `docs/performance/2026-09-02-intel-uhd-medium.json`.

This is one integrated-GPU host, not a universal hardware guarantee. Repeat the matrix on every supported/release-representative tier before distribution.

## Recorded optimization result

At the time of the September 2 capture, tree presentation used one render-only `ParkTreeBatch` with six component `MultiMeshInstance3D` submissions while lightweight placement roots retained collision, deterministic placement, scale variation, and asset metadata.

In the comparable sunset High measurement, the change reduced:

- draw calls from `1,134` to `729` (`35.7%`);
- objects from `1,450` to `1,045` (`27.9%`).

Primitives increased because MultiMesh submits the full batch; that was an accepted tradeoff for the measured source state. Do not extrapolate these deltas to later code without an ancestry-compatible rerun on the same hardware/settings.

## Regression policy

For matching scenarios and hardware identity:

- whole-frame p95 should not regress by more than 10%;
- draw calls and objects should not regress by more than 10% unless an intentional visual/content change is reviewed;
- visual changes require matched captures;
- a measured FPS difference alone is not sufficient evidence to claim a CPU or GPU optimization;
- cross-adapter, cross-version, viewport, render-scale, or incompatible-preset comparisons are not regressions.

A candidate from current `master` should not use the September 2 dirty-tree measurements as a blocking regression baseline unless the comparison tool confirms compatible identity and the reviewer explicitly accepts the source-state mismatch. Prefer establishing a new clean reference first.

## Running the matrix

```powershell
.\tests\visual_profile.ps1 -Environments daytime,sunset -Presets 0,1,2,3 -IsolationMode baseline
```

On a multi-adapter Windows host, select the Vulkan device explicitly and preserve the emitted adapter identity:

```powershell
.\tests\visual_profile.ps1 -GpuIndex 2 -Environments daytime,sunset -Presets 1 -IsolationModes baseline,trees,environment_effects,shadows
```

Capture a baseline and candidate with the same hardware/settings, then compare with:

```powershell
.\tests\performance_compare.ps1 -BaselinePath <baseline> -CandidatePath <candidate> -FailOnRegression
```

## Interpretation

These results establish a reproducible measurement contract and useful dated reference points. They do not replace a clean current-master baseline, target-GPU profiling, exported-build testing, long-session play, or human visual review. Active performance work is tracked in [Performance Backlog](PERFORMANCE_BACKLOG.md).