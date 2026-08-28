# Snow 02 PBR Source

- Asset: [Snow 02](https://polyhaven.com/a/snow_02)
- Author: Rob Tuytel
- Provider: Poly Haven
- License: CC0 1.0 Universal / public domain
- Physical reference size: 2 m
- Imported resolution: 2048 × 2048

The project commits only the 2K diffuse map and a derived linear detail map. The detail channels are:

- R: OpenGL normal X
- G: OpenGL normal Y
- B: roughness
- A: translucency

`tools/import_snow_02.py` downloads the exact Diffuse, Normal (GL), Roughness, and Translucent maps, verifies their published MD5 checksums, packs the linear channels, and discards the intermediate source files. AO, displacement, DirectX normal, and specular maps are not imported.

Powered by Poly Haven.
