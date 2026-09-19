# Visual evidence workflow

The maintained environment, animation, and sunset visual suites produce one Codex-facing run bundle. The bundle is the review boundary: Godot scenes capture deterministic evidence and semantic telemetry, while the post-processor merges suite processes, validates files, creates derived images, compares curated baselines, and writes the report.

## Run it

The capture command requires the pinned Godot GUI executable and a GPU renderer. Pillow is required by the Python post-processor.

```powershell
.\tests\visual_analysis_bundle.ps1
```

Useful variants:

```powershell
# Run one maintained suite.
.\tests\visual_analysis_bundle.ps1 -Suite animation

# Validate an existing bundle without launching Godot.
.\tests\visual_analysis_bundle.ps1 -ValidateOnly -BundlePath .godot_user\visual_runs\<run-id>

# Explicitly update curated baselines after reviewing a clean reference run.
.\tests\visual_analysis_bundle.ps1 -UpdateBaselines

# Capture ten-second Day/Golden/Sunset motion sweeps at High 1.0/0.8/0.65.
.\tests\visual_analysis_bundle.ps1 -Suite environment -IncludeMotion -Environments daytime,golden,sunset -RenderScales 1.0,0.8,0.65 -MotionDurationSeconds 10

# Capture the out-of-bounds fade → respawn → completed recovery sequence.
.\tests\visual_analysis_bundle.ps1 -Suite environment -IncludeRecovery

# Capture the close-range park-snow role review on the reference GPU.
.\tests\ramp_surface_visual_quality_gate.ps1 -EnvironmentName daytime
.\tests\ramp_surface_visual_quality_gate.ps1 -EnvironmentName sunset
```

The command prints absolute `CODEX_VISUAL_MANIFEST`, `CODEX_VISUAL_REPORT`, and `CODEX_VISUAL_STATUS` values. Open `visual_report.md` first; it links to contact sheets, subject crops, telemetry summaries, raw captures, and any baseline overlays or heatmaps.

## Bundle layout

```text
.godot_user/visual_runs/<run-id>/
  run_context.json
  visual_run.json
  visual_report.md
  contact_sheets/
  artifacts/
    crops/
  telemetry/
  diffs/
  logs/
  suites/<suite>/<variant>/
    visual_run.json
    artifacts/
    telemetry/
    diffs/
    logs/
    compat/                 # legacy filenames for existing metrics/review tools
```

`visual_run.json` is the canonical index. It records the Git commit and dirty state, Godot version, renderer, GPU identity, resolution, render scale, preset, environment, fixed rate, seed, command, scenario definitions, artifact dimensions and SHA-256 hashes, checks, review prompts, compatibility comparisons, and missing/malformed evidence.

## Stable scenarios and adapters

`tests/visual_scenarios.json` is the catalog. Scenario IDs are stable review keys; labels, state, phase, view, capture timing, required artifact roles, normalized ROIs, masks, baseline IDs, semantic checks, and human prompts live there. Matrix-only animation scenarios use catalog templates and remain review artifacts rather than committed baselines.

The three maintained adapters use `VisualEvidenceSession` from `tests/visual_evidence.gd`:

```text
begin(config)
capture_viewport(scenario_id, role, viewport, metadata)
record_sample(scenario_id, payload)
record_check(id, kind, status, value, threshold, message)
finish()
```

Adapters describe what was observed. The session owns paths, JSON normalization, structured numeric telemetry, artifact hashes, ordering, and suite manifests. Positions use `_m` fields with `[x, y, z]`; rotations use `_rad` fields with numeric arrays.

## What Codex should review

1. Contact sheets grouped by suite, state, and view.
2. Failed or missing semantic/evidence checks.
3. Subject crops for skier, snow, landing, and feature readability. For the
   focused ramp run, review the seven raw gameplay-camera shots in order:
   approach, lip, deck/knuckle, landing, roller, berm, and side hit.
4. Baseline overlays and heatmaps marked `review_required`.
5. `telemetry/timeline_summary.json` before opening large raw traces.

Raw captures retain user-visible composition. The runner passes `--clean-capture` so capture-only HUD notices/debug overlays are suppressed where the existing UI supports it; compatibility files retain legacy names for existing metrics.

Contact sheets and subject crops prefer the clean `analysis` artifact when an adapter can produce one. The report links both `analysis` and `raw` so Codex can judge readable pixels first and then verify the user-visible composition.

## Status semantics

- `pass`: semantic/evidence checks passed and no compatible baseline comparison requested a review.
- `fail`: a semantic check, deterministic metric, capture process, malformed file, or missing required artifact failed. This is CI-blocking.
- `review_required`: a compatible baseline changed beyond advisory image thresholds. Human/Codex review is required; CI does not fail for pixels alone.
- `not_comparable`: the baseline is absent or differs in Godot version, renderer, viewport, environment, preset, render scale, fixed rate, or GPU identity. It is not a regression.
- `missing`: the bundle or evidence is incomplete or structurally unsafe.

## Baselines

Curated baselines live under `tests/visual_baselines/` and are created only by the explicit `-UpdateBaselines` command. The command refuses a dirty worktree unless `-AllowDirtyBaseline` is supplied. Baseline seeding must use an explicitly reviewed clean reference capture; dirty-tree captures are never authoritative baseline evidence.

The intended curated set is five environment trajectory frames, the 18 canonical animation presentation frames at the reference rate, and one sunset capture. Animation audit-rate/profile matrices, environment motion sweeps, recovery lifecycle captures, and the close-range ramp role shots remain in run bundles for review until a human review explicitly selects a baseline. Every baseline has a sidecar JSON file containing compatibility identity, thresholds, source run, and source hash. Matrix captures record fixed-rate per-frame telemetry and generate one motion contact sheet per behavior/variant. Do not seed or overwrite an existing baseline automatically from the ramp run.

## CI boundary

The normal CI gate remains headless. `visual_evidence_acceptance.tscn` exercises the Godot session seam for ordering, structured telemetry, dimensions, hashes, and path containment. `visual_evidence_static_acceptance.ps1` validates the catalog and malformed-fixture cases without a GPU. Real rendered captures and pixel comparisons run locally on the reference GPU; visual differences remain advisory while semantic and evidence integrity checks block.
