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
