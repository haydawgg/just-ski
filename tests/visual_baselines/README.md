# Curated visual baselines

This directory is intentionally seeded only from an explicit, reviewed reference run. Use:

```powershell
.\tests\visual_analysis_bundle.ps1 -UpdateBaselines
```

The command refuses dirty worktrees by default. Each PNG must be accompanied by a JSON sidecar containing the visual-evidence schema version, baseline ID, suite, compatible Godot/renderer/GPU/viewport/environment/preset/render-scale/fixed-rate identity, thresholds, source run, and source hash.

The curated set is five environment trajectory frames, 18 canonical animation presentation frames at the reference rate, and one sunset capture (24 PNG/JSON pairs). Full animation audit-rate and profile matrices stay in run bundles and are not committed here. Environment motion sweeps and recovery lifecycle captures are also review-only artifacts; use the matrix flags documented in `docs/VISUAL_EVIDENCE.md` when tuning them.
