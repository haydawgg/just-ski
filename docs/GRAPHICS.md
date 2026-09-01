# Graphics and Settings

This document describes the current visual and settings architecture. Renderer behavior is owned by `project.godot`, `autoload/game_settings.gd`, environment/profile resources, shader resources, and the scene code that applies them.

## Renderer and viewport

Summit Sessions targets Godot 4.7 Forward+.

`project.godot` is the source of truth for display configuration. The current project uses a 1920×1080 viewport coordinate space, a 1920×1080 window override, and starts in fullscreen mode (`window/size/mode=3`). 3D render scaling is applied through the viewport's 3D scale, so lowering render scale does not resize the UI coordinate system.

## Settings model

`GameSettings` keeps two dictionaries:

- `active` — values currently applied to the game.
- `pending` — values being edited in the Options menu.

Opening Options copies active values into pending. Apply promotes pending values, applies display/audio changes, and saves `user://settings.cfg`. Cancel restores pending from active. Reset Defaults replaces pending values with defaults but does not apply them until the user chooses Apply.

The settings loader validates maintained numeric ranges and falls back to defaults for invalid values.

## Graphics presets

The maintained graphics settings include:

- display mode and resolution;
- VSync and FPS cap;
- render scale;
- temporal anti-aliasing;
- shadow quality intent;
- snow shader quality;
- SSAO;
- SSIL;
- SSR;
- fog.

Low / Medium use the Fast snow tier by default. High / Ultra use Premium snow. Editing an individual graphics option changes the preset state to Custom.

The current options menu intentionally exposes a practical subset of Godot's renderer controls rather than every Forward+ feature.

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

### Fast and Premium tiers

Both tiers share the same core triplanar material logic.

Fast snow omits the more expensive subsurface / clearcoat presentation. Premium snow enables the maintained higher-quality reflection and translucency response.

Snow materials listen for applied settings and can switch shader tier without rebuilding the resort.

## Environment

The resort environment uses a procedural sky, directional sun, shadows, scene reflections, atmospheric fog, and optional screen-space effects controlled by the graphics settings.

Environment resources own the maintained presentation values rather than scattering them through documentation. Important visual goals are:

- snow remains readable in sun and shade;
- contact shading grounds skis, rails, trees, and feature seams without painting broad dark bands across the piste;
- distant ridges and sky transitions provide depth without hiding gameplay terrain;
- course guidance remains visually subordinate to skiable features.

The environment is deterministic enough for repeatable capture-based review.

Course guidance is presentation-only. Oversized overhead gates and persistent world labels are replaced by short paired flag posts with no collision, emission, or cross-course beam. They fade at close and long range. Takeoff/landing stamps remain surface-conforming, opaque, rough, and scene-lit so they read as snow treatment rather than see-through geometry, a rail, or a HUD overlay.

The summit-to-first-landing vertical slice adds a deterministic heightfield render layer over the existing `MainSnowFace` collision box. The playable corridor stays coplanar with the collision plane; only the outer shoulder receives seeded relief, so render dressing cannot change ski contact or recovery. The heightfield uses the existing snow texture/detail parameter set through a shadow-safe unshaded variant (`snow_summit.gdshader`) because the large presentation mesh otherwise becomes a full receiver for low-angle sunset shadow cascades. The summit shader remaps the authored broad field into a bounded world-space breakup plus a finer seeded field: the near camera footprint spans only a few meters, so the profile's 0.018 world scale would otherwise sample almost one constant noise cell and flatten the snow. Its GI exclusion is intentional: sunset SDFGI remains enabled for the authored ridges, lift line, trees, and course dressing while the render-only summit surface keeps neutral snow readability. Summit boulders and the lift line are cataloged `DECORATION` assets with finite LOD ranges and no colliders.

## Procedural terrain presentation

Park terrain is generated as actual snow forms rather than assembled only from visible boxes and wedges. Jumps, rollers, banks, aprons, knuckles, landings, and run-outs use sampled geometry that also supplies collision.

This keeps visible terrain and ski contact aligned and allows the same snow material system to run across generated features.

## Character presentation

The production skier uses the imported CC0 Skeleton3D body documented in `assets/characters/skier/SOURCE.md`. Project code and deterministic tooling partition and dress that body for the current prototype, while rigid equipment and accessories are mounted through the animation rig.

The visible presentation includes the skinned body/clothing treatment plus project-built equipment such as skis, poles, helmet, goggles, and related rigid pieces. A generated primitive rig remains available as a fallback/debug presentation.

`default_skier_outfit_profile.tres` and the animation/rig resources are the maintained source of truth for outfit palette, material response, proportions, and attachment calibration.

Do not rely on historical mesh/surface counts in documentation; those are implementation details and change as presentation is refined.

## HUD and VFX

Normal-play HUD hierarchy prioritizes speed and scoring, then contextual trick, landing, rail, and session information.

The control onboarding, right-stick visualizer, and trick/landing callouts are intentionally contextual rather than permanently occupying the screen.

Snow VFX uses existing gameplay/contact signals to differentiate continuous ski spray, stronger skid/brake spray, landings, and bail scraping. Audio and rumble consume the same broad gameplay state but are separate systems.

`snow_depth_visual_metrics.tscn` checks the five fixed gameplay trajectory captures for average neutral-snow value separation and bounds the coverage of dark blue shadows; unrelated diagnostic PNGs in the same directory are ignored. The matching capture loop remains `environment_visual_inspection.tscn`; the snow-depth baseline and result live under `.godot_user/captures/snow_depth_before` and `.godot_user/captures/snow_depth_after`.

## Gameplay clip output

The built-in recorder captures the viewport at 960×540 and 30 fps, JPEG-encodes frames, and muxes them into an MJPEG-in-MP4 file. Encoding occurs after capture on a worker thread so the gameplay loop is not responsible for muxing each frame.

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

The runtime gate is the source of truth for the maintained environment, asset-contract, camera, character-presentation, shader/runtime, and capture acceptance scenes.

Visual inspection scenes and deterministic captures under `.godot_user/captures/` are used for checks that cannot be reduced to a reliable scalar assertion. Automated acceptance should not be treated as a substitute for real hardware profiling or human visual review; the current boundary is recorded in [Known Issues](KNOWN_ISSUES.md).
