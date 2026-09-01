# Environment asset catalog

The runtime environment uses `res://resources/environment/default_environment_asset_catalog.tres` as the authoritative registry for resort props and course features. Every entry records a stable asset ID, nominal dimensions in meters, semantic class, readability category, LOD distances, and source/license text.

`EnvironmentAssetCatalog.AssetMode.AUTO` is the normal runtime setting. Every current course/environment ID now has a project-authored production `PackedScene`, so AUTO selects the production set. `GRAYBOX_FALLBACK` remains available for isolated physics tests. Set the catalog to `PRODUCTION`, enable `Resort.force_production_assets`, or pass the `--production-assets` user argument for release validation; missing scenes become hard failures and no primitive substitute is created.

The production source scenes live in `res://assets/environment/production/`:

- Trees, route gates, boundary fences, lift towers, snowmakers, trail boards, and summit boulders use concrete low-poly render scenes. Physical props have separate collision companions and all concrete scenes build `Render/LOD0` and `Render/LOD1` nodes. The summit lift line is a decoration scene with opaque cable/chair silhouettes and no collider.
- Rails and sculpted snow features use authored parametric scene templates. Their path/dimensions come from the course specification, and the same generated geometry remains authoritative for rendering and collision.

Production scene requirements:

- Use one Godot unit per meter and place the scene origin at the snow-contact point.
- Keep visible bounds within the catalog nominal dimensions (default tolerance ±10%).
- Include separate render, collision, and LOD nodes where the asset needs them. A separate `collision_scene` is supported for independently authored colliders.
- Use `SOLID`, `GRIND_ONLY`, `GUIDE`, `BOUNDARY`, or `DECORATION` semantics consistently. Guides must remain collider-free and visually soft/translucent; decorations are opaque presentation-only geometry with no collider; grind-only collision belongs on layer 8; boundaries use explicit layer-4 collision or recovery volumes.
- Keep source/license text current. The included set is project-authored and its provenance is recorded in `assets/environment/production/SOURCE.md`.

The catalog remains a replacement seam: an art pass can substitute reviewed GLB/GLTF scenes per asset ID without changing the course, collision, recovery, or camera interfaces.
