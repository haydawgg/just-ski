# Performance & Visual Roadmap

> Execution update (2026-09-02): the reproducible schema/isolation harness and current baseline now live in `docs/PERFORMANCE_BASELINE_1080P.md`. Measurements identified trees as the dominant submission-count source and sunset environment effects as the largest frame-time source. Tree batching and bounded audio fill have been implemented; the roadmap below is retained as decision history and remaining work.

> Release validation update (2026-09-02): Medium at 0.65 render scale now meets the 16.67 ms p95 target on the local Intel UHD adapter for daytime and sunset, including the four isolation scenarios. The adapter-matched repeatability comparison passed; repeat the same matrix on every supported hardware tier before distribution.

> Phase 0 authoritative task. Roadmap frozen until `docs/PERFORMANCE_BASELINE_1080P.md` is reviewed.
> Source: review against `haydawgg/just-ski@c4d323ac79767cc6f025680c7eddb513faafbb91`.
> All line references verified locally; no changes applied to engine scripts by this document.

## Performance contract (frozen)

Optimize for a **1920x1080 output at 60 FPS** (16.67 ms whole-frame budget; measure frame time, do not infer GPU time from FPS).

- **Low-end target:** integrated GPU running **Medium** preset (0.65 3D render scale, `Fast` snow, no GI). `autoload/game_settings.gd:94-110`.
- **Visual-performance target:** 1920x1080 60 FPS **High** on a representative discrete GPU (1.0 render scale, `Premium` snow). `world/snow_material.gd:7`.
- **Ultra:** best-effort. Not a baseline requirement.
- **Sunset** (`world/sunset_resort.tscn`): ship-capable optional variant plus QA reference (`tests/sunset_visual_inspection.gd:1`). Sunset SDFGI is available on **High/Ultra/Custom** when the environment profile enables GI and the user toggle is on; it is **disabled on Low/Medium** (`resources/environment/default_resort_environment_profile.tres:43`, `world/resort_environment_profile.gd:43`, `autoload/game_settings.gd`). Sunset GI performance must not force compromises to the primary daytime 60 FPS target.
- Daytime `world/resort.tscn` and sunset benchmarks are recorded separately.

## Historical evidence (context, not target)

`docs/BASELINE.md:64-73` (RTX 4050 Laptop, `commit 16426398`, Godot 4.7.2, non-headless visual profile):

- 1450 rendered objects, 350-372k primitives, 1134 draw calls, 881-916 MB reported video memory, 73-74 MB buffer memory.
- 14.98 FPS (Fast) / 15.01 FPS (Premium), 66.7 ms average frame.
- World construction 401.64 ms first-frame, 7568 child nodes.
- These numbers are diagnostic observations on a single discrete laptop; they are not portable CI thresholds and are not the new performance target. They motivate but do not justify the work in later phases.

## Confirmed wins (defer execution until Phase 0 baseline is reviewed)

- `assets/materials/snow_02/snow_02_detail_2k.png.import:18,26` and `snow_02_diff_2k.jpg.import:18,26`: `compress/mode=0`, `mipmaps/generate=false`, `high_quality=false`. Packed detail channels `RG=normal XY, B=roughness, A=translucency` per `assets/materials/snow_02/SOURCE.md:20`. `shaders/snow_common.gdshaderinc:1-2` already distinguishes `source_color` (albedo) from non-color (detail).
- `project.godot:204` `textures/default_filters/anisotropic_filtering_level=4`; `project.godot:198` `physics_ticks_per_second=120`.
- `shaders/snow_common.gdshaderinc:82-199` triplanar 6 taps + 4-5 `snow_value_noise:53-62` evals. The 6-tap path is already guarded by `if (detail_visibility > 0.001)` at `:172`; the 4-5 noise evaluations remain outside the guard and need a true far-distance path.
- Material explosion: `world/snow_material.gd:13-25,123` allocates a new `SnowMaterialInstance` per call; `world/resort.gd:667-672` `_simple_material`/`_material` allocates per primitive; `assets/environment/production/low_poly_environment_asset.gd:226-235` builds per-tree bark + 3 foliage + snow materials.
- Zero `MultiMeshInstance3D` repo-wide.
- `world/vfx/ski_snow_vfx.gd:233-238` `SurfaceTool` rebuild every `TRACK_SAMPLE_INTERVAL 0.045:8`; `MAX_TRACK_SAMPLES 180:6`; `MAX_CONTINUOUS_PARTICLES 184:12`.
- `world/resort.gd:441-455` `PlaneMesh 3800x3800` high-haze with `depth_draw_never`, `cull_disabled`, `unshaded` (not always enabled; profile-gated).
- `world/summit_environment_builder.gd:75-78,110-172` synchronous terrain generation, `sample_spacing_m=3.0` `default_summit_environment_profile.tres:10`, `generate_tangents` per mesh.
- `assets/characters/skier/skier_body.glb.import:26-30` requests `ensure_tangents=true`, `generate_lods=true`, `create_shadow_meshes=true`, `light_baking=1` for a dynamic skinned body. `create_shadow_meshes` is a **potential optimization** (simpler hull in shadow pass), not a known cost; audit before removing.

## Explicitly rejected (do not apply without Phase 3 A/B/C captures and user review)

- `minimum_albedo_luminance 0.44 -> 0.34` (`world/snow_presentation_profile.gd:29`, `shaders/snow_common.gdshaderinc:183-189`). The luminance floor exists to prevent charcoal/asphalt snow ramps. Do not lower without capturing every authored surface at lower values.
- `corduroy_amount 0.012 -> 0.08` (6.7x) or any multiplier greater than ~1.5x. `world/snow_material.gd:78,97`; the `gradient * 0.2` at `shaders/snow_common.gdshaderinc:132` is intentionally restrained. Earlier footage showed snow striping becoming visually artificial.
- Darkening ski tracks (`shaders/ski_tracks.gdshader:4-7`). Tracks already trend rail-like; do not lower compressed-snow color further.
- Global `clearcoat 0.6 / SSS 0.35 / anisotropy 0.4` applied to the whole skier. Treat per-surface instead.
- `summit sample_spacing_m 3.0 -> 1.5m` (~4x tri count) before diagnosing whether faceting is geometry, normals, lighting, or `snow_summit.gdshader:2` unshaded divergence.
- `project.godot:204` anisotropic filtering force-reduced to 2x. Snow benefits from AF at grazing angles. The optimization is mipmaps + compression first; AF is a tier setting, not a global reduction.
- `LightmapGI`, `OccluderInstance3D` sectorization, dynamic resolution, persistent `1024^2` snow deformation, custom `EditorImportPlugin`, 4x summit tessellation, large snow-material library, massif/SDF backdrop rebuild. Postpone to post-Phase 4 backlog; require profiling evidence before any of them is admitted to the roadmap.

## Stale findings vs current `c4d323ac` master

- Snow triplanar is not unconditional. `shaders/snow_common.gdshaderinc:172` already short-circuits when `detail_visibility <= 0.001`. The 4-5 `snow_value_noise` evaluations remain unconditional and are the remaining true far-distance cost.
- Shadows are already tiered (`world/resort.gd:114-131,784-808`): High 4 splits at 320 m, Ultra 4 at 400 m, Medium 2 splits at 240 m, Low single orthogonal at 180 m.
- The post stack is not always on. `autoload/game_settings.gd:94-106` gates SSAO/SSIL/SSR/fog/GI per preset; Low/Medium disable significant features.
- Daytime SDFGI is off (`resources/environment/default_resort_environment_profile.tres:43` `gi_enabled=false`); sunset enables it.
- `render_scale 1.5` is the allowed maximum, not the default. Default is 1.0; Low and the target-class Medium preset use 0.65, while High/Ultra use 1.0 (`autoload/game_settings.gd`).
- `SnowPresentationProfile` (`world/snow_presentation_profile.gd:1`) is larger than five exports; it owns form, steepness, scales, colors, shadow colors, luminance, roughness, near/far detail distances. Remaining hardcoded values live in `world/snow_material.gd:32-121` (`texture_world_size`, `triplanar_sharpness`, per-surface strengths, `wind_crust`, `corduroy`, `sparkle`, `SSS`).
- Props are not albedo-only. `assets/environment/production/low_poly_environment_asset.gd:54-59` already sets `roughness` and `metallic`; a shared material library remains worthwhile, but PBR-from-scratch is not the task.
- Course feature definitions are not duplicated in the builder. `world/course/park_course_builder.gd:261` consumes `world/course/park_course_profile.gd:28` `feature_specs()`. Valid task: convert the hard-coded dictionary table to `CourseFeatureSpec` resources.
- Catalog LOD partly wired. Parametric course features (`world/course/park_course_builder.gd:108`) and rails (`world/park_features/grind_rail_3d.gd:115` via `LODContract`) consume `EnvironmentAssetDefinition.lod_distances_m` (`resources/environment/environment_asset_definition.gd:21`). Script-generated production environment assets still hardcode ranges internally.
- Packed detail sampler already distinguished from albedo in shader (`shaders/snow_common.gdshaderinc:1-2`). Do not auto-mark the whole four-channel texture as a normal map; verify channel preservation after import changes.
- CI exists (`.github/workflows`, `tests/environment_asset_contract_acceptance.gd:7`, `quality_gate.ps1`). New lint integrates into the existing gate rather than replacing it.
- `export_presets.cfg:8` `export_filter="all_resources"` and `exclude_filter=""` are real concerns, but PCK contents must be inspected before assuming Python/PowerShell tooling ships; tests and dev resources are likelier bloat.

## Phased plan

### Phase 0 — Performance baseline (this task)

Extend existing profiling infrastructure into a reproducible harness named `docs/PERFORMANCE_BASELINE_1080P.md`. Reuse `tests/sunset_visual_inspection.gd:188-215` (`average_rendered_fps`, `average_frame_ms`, `objects`, `primitives`, `draw_calls`, `video/texture/buffer`, `AudioManager.profiling_snapshot`) rather than building a parallel profiler.

Benchmark the same deterministic scenarios under **Low, Medium, High, Ultra**:

1. Summit overview.
2. Dense vegetation (28 park trees region).
3. Full-park downhill representative run.
4. Heavy ski spray (carve + skid emitters saturated).
5. Rail-heavy view.
6. Large jump / airborne sequence.
7. Bail / crash sequence.
8. Sunset variant (`world/sunset_resort.tscn`) as a separately identified environment scenario.

Record per row:

- Hardware identity (OS, CPU, GPU, driver, Godot version, display configuration per `docs/BASELINE.md:11-13`).
- Output resolution, render scale, active preset, snow tier, effective GI state.
- Frame-time / cadence statistics. Clearly distinguish true measured GPU time, CPU time, and whole-frame / wall-clock time. If no GPU timestamp is available, leave it blank; do not infer GPU time from FPS.
- Average FPS plus 1% low / spike information if reliably measurable.
- Objects, primitives, draw calls, video / texture / buffer memory.
- Particle state and cap (`ski_snow_vfx.gd:184-200` `MAX_CONTINUOUS_PARTICLES 184:12`).
- Track rebuild cost (`ski_snow_vfx.gd:233-238`).

Acceptance for Phase 0:

- Store enough scenario / camera information that the harness repeats unchanged on another machine.
- Every result tagged with hardware identity.
- The RTX / discrete-GPU run establishes the current development baseline.
- Medium 60 FPS on integrated GPU is validated for the recorded Intel UHD target-class run; it remains a release prerequisite to repeat the same harness on every supported hardware tier.
- Old `docs/BASELINE.md` numbers stay historical context only; Phase 1 comparisons use the new Phase 0 numbers on the same machine, scene, preset, camera, and commit ancestry.

**Phase 0 must not:** change snow imports, shaders, materials, MultiMesh architecture, shadows, haze, particles, tracks, physics tick rate, GI, environment art, LODs, or visual constants. Instrumentation and deterministic benchmark scaffolding only.

Finish by reporting the dominant suspected bottleneck as a **hypothesis based on measurements**, not by implementing a fix. Phase 1 begins only after this baseline is reviewed.

### Phase 1 — Unconditional fixes (1-2 weeks, deferred)

- Texture imports: `mipmaps/generate=true`, VRAM compression active, packed `RG normal XY / B roughness / A translucency` preserved. Acceptance: mips present, VRAM compression active, memory lower than the **Phase 0** measurement on the same machine, scene, preset, camera, and commit ancestry (not the historical `881/916 MB` `docs/BASELINE.md:70-73` numbers).
- Material cache keyed by `(Kind, groom_direction_world_xz, feature_emphasis, render_unshaded)` because `render_unshaded` selects `SUMMIT_SHADER` vs `PREMIUM/FAST` (`world/snow_material.gd:29`). Measure cache hit rate; groom-direction / emphasis combinations may keep many cached materials.
- Finish centralizing `world/snow_material.gd:32-121` hardcoded values into `SnowPresentationProfile`.
- Lint: `tools/validate_imports.py` and `tools/lint_assets.py` integrated into the existing GitHub Actions quality gate, not a new validation system.
- Export audit: inspect actual exported PCK contents before assuming `tools/`, `tests/`, or `world/generated/` (`.gitignore:6`) are or are not bundled. Exclude confirmed bloat.
- Skier shadow mesh: profile `with generated shadow mesh vs without` in shadow pass, keep whichever is cheaper; do not assume the generated shadow mesh is wasted.

### Phase 2 — Only if Phase 0 shows the corresponding bound

- GPU-bound: true far-distance snow path (skip remaining `snow_value_noise` beyond `detail_far_distance`), `high_haze_enabled` profile-gated overdraw, High/Ultra shadow distance refinement, particle mesh sharing / `QuadMesh` candidates, already-tiered SSAO/SSR/glow refinement.
- CPU / render-bound: MultiMesh as an **experiment**, batching equivalent tree components / variants (e.g. bark, foliage LODs) rather than collapsing each whole `Node3D` tree into one `MultiMesh`. Production trees already carry LOD components and asset-catalog semantics (`assets/environment/production/low_poly_environment_asset.gd:48-69`). Track coalescing: plain `PackedVector3Array` computed on a worker, `ArrayMesh` build / `commit` on the main thread, no `SurfaceTool` / `RenderingServer` on workers.

### Phase 3 — Controlled visual experiments (A/B/C footage, no auto-merge)

Generate three matched variants with identical camera, sun, slope, and jump:

- **A current reference.**
- **B stronger terrain form.**
- **C stronger visible snow texture.**

Legitimate first changes: stronger base snow detail **after mips are fixed**, derive `form_light_direction_world_xz` from `sun_rotation_degrees`, mountain shader detail, prop material library, particle silhouette tuning. Decisions based on matched captures, not on numeric proposals.

### Phase 4 — Pipeline cleanup (ongoing, backward compatible)

- `resources/course/` `CourseFeatureSpec` resources extracted from `world/course/park_course_profile.gd:28` dictionary table.
- `world/shared/terrain_mesh_builder.gd` unifying `SummitEnvironmentBuilder._create_terrain_mesh:110`, `ParkLayout._profile_grid_mesh:816`, `Resort._create_mountain_mesh:480`.
- Single LOD authority: `EnvironmentAssetDefinition.lod_distances_m` consumed by all dressing, removing the hard-coded ranges in `assets/environment/production/low_poly_environment_asset.gd:215`.
- Shared material library in `assets/materials/library/master_*.tres`.
- Source vs derived asset convention: `assets/source/` (pristine, large, optional LFS) and `assets/art/` (derived, exported, atomic write). Try `EditorScenePostImport` import script first for `assets/characters/skier/skier_body.glb.import:38` before building a full `EditorImportPlugin`.

### Postponed to post-Phase 4 backlog

Persistent `1024^2` snow deformation render target, `LightmapGI` adoption, `OccluderInstance3D` sectorization, dynamic resolution (hysteresis / cooldown, never direct FPS coupling), 4x summit tessellation, large snow-material library expansion, massif / SDF backdrop rebuild, custom `EditorImportPlugin`. All require profiling evidence that simpler approaches are inadequate.

## Codex guardrail

- Verify every cited `file:line` on `c4d323ac` locally before editing.
- Land `docs/PERFORMANCE_BASELINE_1080P.md` first; no rendering architecture change before the baseline is reviewed.
- Change one cost center at a time. Preserve visual equivalence during performance passes; preserve performance budgets during visual passes.
- For any luminance, corduroy, track, or skier constant, ship only via `A/B/C` matched captures with exact parameter diffs; do not auto-pick final values.
- Distinguish true measured GPU time, CPU time, and whole-frame / wall-clock time. Do not infer GPU time from FPS.
- Tag every benchmark row with hardware identity; do not validate the Medium 60 FPS iGPU requirement from a discrete-GPU run.
- The daytime Medium 60 FPS / 16.67 ms budget is inviolable; sunset SDFGI performance must not force compromises to it.
