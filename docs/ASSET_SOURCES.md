# Asset Sources

## Snow 02

The snow material uses the 2K diffuse, OpenGL normal, roughness, and translucency maps from [Poly Haven Snow 02](https://polyhaven.com/a/snow_02), created by Rob Tuytel and released under CC0 1.0 Universal.

Only the diffuse texture and a derived linear RGBA detail texture are committed. `tools/import_snow_02.py` verifies Poly Haven's published checksums and packs normal X, normal Y, roughness, and translucency. AO, displacement, DirectX normal, and specular maps are excluded. See `assets/materials/snow_02/SOURCE.md` for the complete conversion record.

All geometry, particles, signs, character visuals, and UI remain project-created Godot primitives.
