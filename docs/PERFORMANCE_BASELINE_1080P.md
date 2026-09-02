# Current 1080p Performance Baseline

## Identity and measurement contract

- Source commit: `012a0d40f6b7c91a53c80840794dacee5b651a29`.
- Working tree: dirty. The tree already contained uncommitted graphics/presentation work before this execution; these results must not be described as a pristine commit baseline.
- Capture date: 2026-09-02.
- Godot: `4.7.2-stable (official)`.
- Host: Windows, 12th Gen Intel Core i7-12650H, NVIDIA GeForce RTX 4050 Laptop GPU.
- Project output contract: 1920×1080. VSync and the FPS cap were disabled for profiling.
- Frame values are whole rendered-frame/wall-clock measurements from the deterministic inspection trajectory. They are not GPU timestamps.
- Raw schema `1.0` JSON is produced under `.godot_user/captures/` by `tests/visual_profile.ps1`; captures and local profiling output remain ignored build artifacts.

The profiler records environment, graphics preset, isolation scenario, full commit SHA, dirty-tree flag, host/adapter identity, sample count, average/min/max/p50/p95/p99 frame time, render counts/memory, and audio processing cost. `tests/performance_compare.ps1` compares matching environment/preset/scenario rows only when the runtime hardware, Godot version, viewport, and render scale also match; `-FailOnRegression` rejects both measured regressions and mismatched capture identities.

## Pre-optimization snapshot

These four rows were captured immediately after the schema/isolation harness landed and before tree batching or audio work. “Fast” and “Premium” identify the former snow-tier-only harness mode; all future runs use Low/Medium/High/Ultra graphics presets.

| Environment | Snow tier | Average frame | p95 | FPS | Objects | Draw calls | Primitives | Audio average | Audio max |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Daytime | Fast | 3.463 ms | 5.082 ms | 288.7 | 1,449 | 1,133 | 350,764 | 80.30 µs | 8,616 µs |
| Daytime | Premium | 3.658 ms | 5.101 ms | 273.4 | 1,449 | 1,133 | 369,964 | 83.98 µs | 6,955 µs |
| Sunset | Fast | 4.234 ms | 5.729 ms | 236.2 | 1,450 | 1,134 | 350,872 | 95.08 µs | 6,928 µs |
| Sunset | Premium | 4.512 ms | 6.078 ms | 221.7 | 1,450 | 1,134 | 370,072 | 103.17 µs | 6,928 µs |

This refresh invalidates the historical 15 FPS diagnosis in `docs/BASELINE.md`: uncapped current measurements are comfortably within the 16.67 ms discrete-GPU target. It also shows procedural audio below the `<1 ms` average target, though its initial buffer fill still produced a 6.9–8.6 ms spike.

## Sunset Fast isolation results

| Disabled subsystem | p95 frame | Objects | Draw calls | Evidence |
| --- | ---: | ---: | ---: | --- |
| Nothing (baseline) | 5.729 ms | 1,450 | 1,134 | Reference |
| Audio | 5.646 ms | 1,450 | 1,134 | No material frame-time change; average audio cost was already negligible |
| Trees | 5.645 ms | 1,015 | 699 | Trees account for 435 objects and 435 submissions |
| Course dressing | 5.652 ms | 1,284 | 968 | Secondary submission/node cost |
| Distant ridges | 5.764 ms | 1,429 | 1,113 | Small render-count effect |
| Character | 5.676 ms | 1,253 | 937 | Material submission count; modest frame effect on this GPU |
| Shadows | 5.944 ms | 634 | 318 | Large count change but no reliable frame gain in this noisy run |
| Environment effects | 4.747 ms | 1,450 | 1,134 | Largest measured p95 gain; sunset GI/fog/glow memory and GPU work dominate |

## Implemented performance changes and gates

- Tree presentation now uses one render-only `ParkTreeBatch` with six component `MultiMeshInstance3D` submissions. Thirty lightweight placement roots preserve collision, scale variation, deterministic placement, and asset-catalog metadata.
- The final six-component batch reduces the comparable sunset High result from 1,134 to 729 draw calls (35.7%) and from 1,450 to 1,045 objects (27.9%). Its p95 is 5.646 ms versus the 6.078 ms pre-change Premium snapshot. Primitives rose 8.2% (370,072 to 400,288) because MultiMesh submits the full batch; this is an accepted measured tradeoff for 405 fewer submissions and must be revisited on the target iGPU.
- Procedural audio work is capped at 1,024 generated frames per process tick and uses a pure `AudioMixSolver`; the non-headless repeat must remain below 1 ms average and should reduce the initial maximum from the 6.9–8.6 ms reference range.
- Whole-frame p95 must not regress by more than 10% on matching scenarios. Draw calls and objects must not regress by more than 10% unless an intentional visual change is reviewed.
- The target-class integrated-GPU Medium result is validated below on the local Intel UHD adapter using Vulkan GPU index 2; repeat on each supported hardware tier before release.

## Post-change 1080p preset matrix

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

All discrete-GPU rows are well below the 16.67 ms whole-frame target. The persisted machine-readable summary is `docs/performance/2026-09-02-current-tree-summary.json`; full raw schema documents and captures are reproducible local artifacts.

Run the maintained matrix with:

```powershell
.\tests\visual_profile.ps1 -Environments daytime,sunset -Presets 0,1,2,3 -IsolationMode baseline
```

On a multi-adapter Windows host, pass Godot's Vulkan device index explicitly
(`-GpuIndex 2` for the Intel UHD adapter on the validation host) and preserve
the emitted `runtime.video_adapter` identity with the captures:

```powershell
.\tests\visual_profile.ps1 -GpuIndex 2 -Environments daytime,sunset -Presets 1 -IsolationModes baseline,trees,environment_effects,shadows
```

Run an isolation subset with `-IsolationModes`, preserve the output directory as the baseline, capture the candidate with the same adapter and settings, then compare the two result directories with `tests/performance_compare.ps1 -FailOnRegression`. A cross-adapter comparison is intentionally rejected rather than reported as a frame-time regression.

## Target integrated-GPU validation

The same schema/isolation harness was forced to Vulkan GPU index 2 on the
local Intel UHD Graphics adapter. Medium now uses a measured 0.65 3D render
scale while retaining its Fast snow and no-GI policy. All eight daytime and
sunset cases stayed below the 16.67 ms p95 frame budget; baseline p95 was
14.134 ms daytime and 14.202 ms sunset. Baseline audio averages were 266.92 µs
and 303.91 µs respectively. The machine-readable records are in
`docs/performance/2026-09-02-intel-uhd-medium.json`.
