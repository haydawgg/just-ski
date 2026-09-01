# Asset Sources

Summit Sessions uses a small number of external CC0 sources. This file is the high-level attribution index; each imported source has a local `SOURCE.md` with the processing record.

## Snow 02

**Source:** Poly Haven — Snow 02  
**Author:** Rob Tuytel  
**License:** CC0 1.0 Universal

The project commits the 2K diffuse texture and a derived packed detail texture. The detail texture is generated from the source OpenGL normal, roughness, and translucency maps.

`tools/import_snow_02.py` downloads the expected source maps, verifies the published checksums, creates the packed texture, and discards source files that are not committed.

Full record: [`assets/materials/snow_02/SOURCE.md`](../assets/materials/snow_02/SOURCE.md)

## Environment asset catalog

Environment prop integration is defined in `docs/ENVIRONMENT_ASSET_CATALOG.md` and `resources/environment/default_environment_asset_catalog.tres`. The active low-poly production scenes are project-authored from Godot primitives under `assets/environment/production/`; their provenance and parametric-feature policy are recorded in that directory's `SOURCE.md`. Reviewed GLB/GLTF replacements can be assigned per catalog ID later.

## Skier body

**Source:** Mesh: 3D Male Base (Rigged) 1.0.2  
**Creator / distributor:** orange-juice-games.itch.io; Godot package maintained by BoQsc  
**License:** CC0

The production body is stored at `assets/characters/skier/skier_body.glb`. Deterministic project tooling partitions the original skinned surface into named material regions and adds the maintained clothing-shell treatment while preserving the underlying skeleton and skinning contract.

Model-specific retarget mapping lives in `resources/animation/default_skier_skeleton_profile.tres`.

Full record: [`assets/characters/skier/SOURCE.md`](../assets/characters/skier/SOURCE.md)

## Project-created content

Unless a source is listed above or documented by another local provenance record, the prototype's gameplay code, procedural park geometry, rigid ski equipment/accessories, particles, signs, UI, shaders, and generated presentation assets are project-created.

The primitive skier is a project-generated fallback/debug presentation. Normal runtime prefers the imported Skeleton3D production body when its rig contract validates.
