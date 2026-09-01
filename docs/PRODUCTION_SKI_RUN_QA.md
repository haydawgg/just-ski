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

## Human visual pass

- [ ] Replay the supplied route at 30, 60, and 120 Hz with keyboard and controller.
- [ ] Compare gate posts, trees, rails, slabs, panels, boundaries, and the skier against the meter-scale reference at near, mid, and gameplay distances.
- [ ] Contact every reachable solid feature and confirm the visual surface and collider agree; pass through route guides to confirm they never produce an invisible impact.
- [ ] Grind rails and boxes capture only through the grind affordance and never bounce the skier capsule.
- [ ] Trigger high-speed landings, rail exits, boundary recoveries, and the supplied crash. Confirm the HUD identifies the reason and the camera keeps the pelvis/upper body readable.
- [ ] Confirm fade-out → respawn → camera reset → fade-in occurs once, combo/link clears, and total score remains unchanged.
- [ ] Install Godot 4.7.2 export templates, create the platform release export used for the target build, and smoke-test that exported build with the same route.
- [ ] Compare the daytime and sunset scenes at near, mid, and horizon distances; tune glare, shadow density, and snow readability on the target display.
- [ ] Review `phase_15_after/gameplay_landing.png` and the capture produced by `sunset_visual_quality_gate.ps1` on the target display; confirm the shadow-safe summit surface retains shoulder/form readability while the rest of the scene keeps the intended GI/shadow balance.

## GPU-backed sunset visual check

Run this on the Vulkan/NVIDIA reference machine after the headless gates:

```powershell
.\tests\sunset_visual_quality_gate.ps1
```

The command captures the same deterministic 1280×720 sunset trajectory, then rejects any contiguous near-black region larger than 2% of the lower gameplay ROI after HUD/skier masks. It is intentionally supplemental and separate from `quality_gate.ps1`, because the headless runtime gate does not validate the rendered pixels on the reference GPU.
