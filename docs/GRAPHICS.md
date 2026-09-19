# Graphics and Settings

This document describes the current visual and settings architecture. Renderer behavior is owned by `project.godot`, `autoload/game_settings.gd`, environment/profile resources, shader resources, and the scene code that applies them.

## Renderer and viewport

Summit Sessions targets Godot 4.7 Forward+.

`project.godot` is the source of truth for display configuration. The current project uses a 1920×1080 viewport coordinate space, a 1920×1080 window override, and starts in fullscreen mode (`window/size/mode=3`). 3D render scaling is applied through the viewport's 3D scale, so lowering render scale does not resize the UI coordinate system.

## Settings model

`GameSettings` keeps two dictionaries:

- `active` — values currently applied to the game.
- `pending` — values being edited in the in-game Settings menu.

Open Pause → Settings during a run to edit these values. Apply promotes pending values, changes the display/renderer/audio state immediately, and saves `user://settings.cfg`; a successful apply shows `SETTINGS SAVED`. Cancel restores pending from active. Reset Defaults replaces pending values with defaults but does not apply them until the user chooses Apply.

The settings loader validates maintained numeric ranges and falls back to defaults for invalid values.

Resolution is a Windowed-mode display change only: the selector is disabled for fullscreen modes with an explanatory tooltip, and in fullscreen modes the stored value is not applied, so a fullscreen resolution change alone never triggers the risky-display Keep/Revert confirmation.

## Graphics presets

The maintained graphics settings include:

- display mode and resolution;
- VSync and FPS cap;
- render scale;
- upscaling (Bilinear / FSR 1.0 / FSR 2.2) with FSR sharpness;
- temporal anti-aliasing;
- shadow quality intent;
- snow shader quality;
- SSAO;
- SSIL;
- SSR;
- reflection quality (SSR steps plus player-probe intensity/range);
- HDR output (Display tab, covered by the Keep/Revert confirmation);
- fog.

Low / Medium use the Fast snow tier by default. High / Ultra use Premium snow. Editing an individual graphics option changes the preset state to Custom.

The current Settings menu intentionally exposes a practical subset of Godot's renderer controls rather than every Forward+ feature. It includes a staged GI toggle. GI is effective only when the selected environment profile exposes GI, the user setting `gi_enabled` is true, and the graphics preset permits GI (High, Ultra, or Custom; Low and Medium forbid it). The profile is the upper-level capability gate, the user setting is the preference, and the preset is the hardware-capability policy. Apply updates the live environment before persistence; a save failure is reported without rolling back the applied runtime state.

Time of day follows the same staged settings model. `environment_preset` selects one of three authored `ResortEnvironmentProfile` resources: Day, Golden Hour, or Sunset. `resort.gd` owns the small preset-to-resource seam and applies the selected profile to the existing sky, sun, fill, fog, post-processing, and GI configuration without another autoload. Dedicated QA scenes such as `sunset_resort.tscn` opt out of the user preference so their authored lighting remains deterministic.

HDR output is opt-in on every preset and defaults off. Enabling it requests HDR on the window, enables the 16F 2D pipeline, and switches the resort tonemapper from Filmic to AgX (Filmic/ACES are SDR-only curves and would crush highlights against a display peak); exposure, glow, and adjustment stay profile-owned. The AgX presentation now follows the display's *actual active* HDR state (`DisplayServer.window_is_hdr_output_enabled()`), not just the saved preference: a requested mode on an SDR output keeps the Filmic curve, and the active state is polled once per frame so dynamic display changes re-grade without a settings round-trip. The window request no-ops on headless/dummy servers and SDR outputs fall back gracefully. Because an HDR mode switch can blank the display, it routes through the same timed Keep/Revert confirmation as display mode and resolution. HDR grading still requires human review on a capable display; automated captures run SDR.

Composition limits are normalized viewport fractions (`CompositionEvaluator`), so camera framing generalizes across aspect ratios; `tests/display_aspect_acceptance.tscn` verifies 4:3/16:10/16:9/21:9 projection and correction scaling, the four supported 16:9 resolution presets against menu and fixed-design-space HUD containment, the HDR active-state policy, and clean-capture HUD separation. Wider/narrower aspect ratios are not user-selectable in the Settings UI and are documented as unsupported rather than silently letterboxed.

## Snow shading

Snow uses world-space triplanar sampling so terrain, banks, rotated jump surfaces, and landings do not depend on authored mesh UVs.

The committed Snow 02 source data provides diffuse color plus a derived packed detail texture containing normal X, normal Y, roughness, and translucency. See [Asset Sources](ASSET_SOURCES.md) and `assets/materials/snow_02/SOURCE.md` for provenance.

The snow presentation combines:

- triplanar material sampling;
- large-scale value / temperature / roughness variation;
- gameplay-distance detail fading;
- directional groomer corduroy on authored surfaces;
- surface-kind and traffic variation;
- geometry-aware lighting response for lips, knuckles, banks, and landings;
- persistent ski-ribbon presentation.

Fine detail fades before large-scale form so distant terrain remains readable without excessive shimmer.

`SnowMaterial.PresentationRole` keeps ordinary piste snow on the `GROUND` path by
default. Generated snow surfaces owned by `ParkLayout` opt into
`PARK_FEATURE`, which reuses the same Snow 02 albedo/detail textures and
world-space triplanar projection with a finer 1.10 m footprint, stronger
bounded albedo/normal/roughness response, slightly stronger form and groom
contrast, and an 84 m detail horizon. The editable
`default_snow_presentation_profile.tres` owns those role-specific values;
geometry, collision, surface kind, shadow-safe summit selection, and camera
behavior are unchanged. Natural piste, diagnostic flat snow, rails, trees, and
non-snow wallride/bonk faces remain on their existing ground or hard-surface
materials.

### Fast and Premium tiers

Both tiers share the same core triplanar material logic.

Fast snow omits the more expensive subsurface / clearcoat presentation. Premium snow enables the maintained higher-quality reflection and translucency response.

Snow materials listen for applied settings and can switch shader tier without rebuilding the resort.

## Environment

The resort environment uses a procedural sky, directional sun, shadows, scene reflections, atmospheric fog, and optional screen-space effects controlled by the graphics settings.

The transparent high-haze card is retained as a fog-off atmospheric fallback. When environment fog is enabled, the haze mesh is hidden before rendering because matched non-headless captures showed no visible contribution from stacking both effects and measurable full-screen fragment cost.

The authored backdrop uses six mountain topology families (massif, sharp peak, saddle/double peak, long ridge, asymmetric shoulder, distant low ridge) placed on a rebalanced near/mid/far depth ladder. Global environment fog is the primary aerial-perspective system; the mountain shader only adds a bounded local `haze_blend` (default 0.28) so distant peaks are not double-washed into the sky.

Near-course parallax comes from deterministic off-corridor dressing: regular piste markers, snow banks at lift and snowmaking infrastructure, a coherent lift chain with a station, and clustered structural conifer families. All of it stays outside the ±27 m competition corridor and is catalog-driven.

Environment resources own the maintained presentation values rather than scattering them through documentation. Important visual goals are:

- snow remains readable in sun and shade;
- contact shading grounds skis, rails, trees, and feature seams without painting broad dark bands across the piste;
- distant ridges and sky transitions provide depth without hiding gameplay terrain;
- course guidance remains visually subordinate to skiable features.

The environment is deterministic enough for repeatable capture-based review.

Headless correctness runs use `RuntimeEnvironment.is_headless()` as the single
capability check. They omit the transparent high-haze card and the player
reflection probe, and every generated performance profile records the result as
`runtime.headless=true`. GPU visual gates retain those presentation probes and
validate their rendered pixels separately.

Course guidance is presentation-only. Oversized overhead gates and persistent world labels are replaced by short paired flag posts with no collision, emission, or cross-course beam. They fade at close and long range. Takeoff/landing stamps remain surface-conforming, opaque, rough, and scene-lit so they read as snow treatment rather than see-through geometry, a rail, or a HUD overlay.

The summit-to-first-landing vertical slice adds a deterministic heightfield render layer over the existing `MainSnowFace` collision box. The playable corridor stays coplanar with the collision plane; only the outer shoulder receives seeded relief, so render dressing cannot change ski contact or recovery. Phase 10 splits that render layer into three regions: the ±27 m playable piste renders through the standard shadow-receiving snow tier (premium/fast) so directional sun and course-object shadows land on it, while the two outer shoulder bands keep the shadow-safe `snow_summit.gdshader` workaround that avoids swallowing the presentation-only relief under low-angle shadow cascades. Both regions share an identical boundary column at x = ±27 m, so the split is crack-free. The summit shader remaps the authored broad field into bounded multiplicative world-space breakup plus a finer seeded field: the near camera footprint spans only a few meters, so the profile's 0.018 world scale would otherwise sample almost one constant noise cell and flatten the snow. Drift is multiplicative and bounded, and the luminance floor matches the shared readability floor so shadowed relief keeps its value separation instead of being lifted into flat white. Sunset SDFGI reads the sky with energy 1.1 to preserve ambient snow visibility. The render layer remains excluded from GI geometry baking; authored ridges, lift line, trees, and course dressing retain their existing GI participation. Summit boulders and the lift line are cataloged `DECORATION` assets with finite LOD ranges and no colliders.

## Procedural terrain presentation

Park terrain is generated as actual snow forms rather than assembled only from visible boxes and wedges. Jumps, rollers, banks, aprons, knuckles, landings, and run-outs use sampled geometry that also supplies collision.

This keeps visible terrain and ski contact aligned and allows the same snow material system to run across generated features.

## Character presentation

The production skier uses the imported CC0 Skeleton3D body documented in `assets/characters/skier/SOURCE.md`. Project code and deterministic tooling partition and dress that body for the current prototype, while rigid equipment and accessories are mounted through the animation rig.

The visible presentation includes the skinned body/clothing treatment plus project-built equipment such as skis, poles, helmet, goggles, and related rigid pieces. A generated primitive rig remains available as a fallback/debug presentation.

`default_skier_outfit_profile.tres` and the animation/rig resources are the maintained source of truth for outfit palette, material response, proportions, and attachment calibration.

The five original `Outfit_*` body regions retain UV0 data; generated jacket, pants, and glove shells intentionally do not. Material polish uses per-region roughness, metallic, and specular response across the existing skeleton/outfit pipeline, plus a neutral near-white technical-ripstop albedo (`assets/materials/skier_cloth/technical_ripstop_albedo_512.png`) multiplied by the outfit colors on jacket, pants, and gloves. Local (non-world) triplanar projection at a 0.40 m repeat keeps the weave stable on both authored UV surfaces and generated shells without swimming through the world as the skeleton moves. The jacket also has authored panel, trim, zipper, pocket-flap, and back-stripe materials so close inspection has stable detail variation without cloth simulation.

Do not rely on historical mesh/surface counts in documentation; those are implementation details and change as presentation is refined.

## HUD and VFX

Normal-play HUD hierarchy prioritizes speed and scoring, then contextual trick, landing, rail, and session information.

The control onboarding, right-stick visualizer, and trick/landing callouts are intentionally contextual rather than permanently occupying the screen.

The project-wide control theme uses the pinned Inter 4.1 variable font and a restrained shared panel/button/focus treatment. HUD labels keep their local size and contrast overrides. Font provenance, checksum, and the bundled OFL license are recorded under `assets/ui/fonts/`.

Snow VFX uses existing gameplay/contact signals to differentiate continuous ski spray, stronger skid/brake spray, landings, and bail scraping. Contact-spray density ramps toward demand each frame (`SkiSnowVFX.smooth_emitter_ratio`) instead of switching on/off in one tick, so spray fades in and trails off rather than popping. Landing captures expose `vfx_mode="landing"`, `landing_spray_active`, and the configured emitter amount so the cool-gray spray can be reviewed against the snow surface. The summit shader's form/drift/luminance controls are profile-driven while its shadow-safe and GI-excluded restrictions remain explicit. Audio and rumble consume the same broad gameplay state but are separate systems.

`tests/environment_visual_quality_gate.ps1` clears and refreshes the canonical `res://.godot_user/captures/snow_depth_after` directory, requires every PNG and telemetry JSON, rejects capture errors, nonzero exits, timeouts, and renderer shutdown leaks, then runs `snow_depth_visual_metrics.tscn` against those fresh files. The metric checks the five fixed gameplay trajectory captures for average neutral-snow value separation and bounds the coverage of dark blue shadows. The canonical capture loop is `tests/visual_analysis_bundle.ps1`, which keeps its review bundle isolated while using the same capture contract. The scenario catalog, ROIs, masks, baseline compatibility rules, and review order are documented in [Visual evidence](VISUAL_EVIDENCE.md).

The bail HUD notice follows the player's `BAIL` state through rest and get-up,
then clears on recovery or respawn. It takes priority over transient notices;
ordinary notices retain their two-second expiry. The crash recovery acceptance
suite checks persistence, stage wording, late HUD binding, unrelated notices,
and recovery/respawn cleanup.

The center-top trick label is the single scored-trick readout. The lower-right
Flick-It visualizer is an input-teaching widget: it shows the recognized
gesture, phase, stick path, and trigger state with rotation arcs, never the
scored trick name or degrees. The trick UI suite guards the separation.

## Gameplay clip output

The built-in recorder captures the viewport at 960×540 and 30 fps, JPEG-encodes frames, and muxes them into an MJPEG-in-MP4 file. Encoding occurs after capture on a worker thread so the gameplay loop is not responsible for muxing each frame. Capture slots are retained when the bounded JPEG queue is saturated and missing slots repeat the nearest encoded frame, preserving presentation duration. The long-capture mux streams MP4 samples to a temporary file rather than building a second complete payload in memory; see [Clip capture](CLIP_CAPTURE.md).

The capture contains video only. See [Controls](CONTROLS.md) for recorder behavior.

## Verification

Fast shader/source checks:

```powershell
.\tests\shader_static_acceptance.ps1
```

Full runtime gate:

```powershell
.\tests\runtime_quality_gate.ps1
```

GPU environment gate:

```powershell
.\tests\environment_visual_quality_gate.ps1
```

The standalone sunset gate applies the same process exit, timeout, required-file,
capture-error, and shutdown-warning checks before running its near-black-region
metric.

The runtime gate is the source of truth for the maintained environment, asset-contract, camera, character-presentation, shader/runtime, and capture acceptance scenes.

Visual inspection scenes and deterministic captures under `.godot_user/visual_runs/` are used for checks that cannot be reduced to a reliable scalar assertion. Run `tests/visual_analysis_bundle.ps1` on the reference GPU, then review `visual_report.md`; automated acceptance should not be treated as a substitute for real hardware profiling or human visual review. The current boundary is recorded in [Known Issues](KNOWN_ISSUES.md).
