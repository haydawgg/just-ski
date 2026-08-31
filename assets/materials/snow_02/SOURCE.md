# Snow 02 Source

## Upstream asset

- **Asset:** Snow 02
- **Provider:** Poly Haven
- **Author:** Rob Tuytel
- **Source page:** https://polyhaven.com/a/snow_02
- **License:** CC0 1.0 Universal / public domain
- **Physical reference size:** 2 m
- **Imported resolution:** 2048 × 2048

## Committed files

The repository commits:

- `snow_02_diff_2k.jpg` — the 2K diffuse map.
- `snow_02_detail_2k.png` — a project-generated linear packed detail texture.

The packed detail channels are:

| Channel | Data |
|---|---|
| R | OpenGL normal X |
| G | OpenGL normal Y |
| B | Roughness |
| A | Translucency |

## Import process

`tools/import_snow_02.py` is the reproducible import path. It downloads the required 2K Diffuse, Normal (OpenGL), Roughness, and Translucent source maps, verifies the expected published MD5 checksums, packs the linear detail channels, and removes intermediate source files after conversion.

AO, displacement, DirectX normal, and specular maps are not imported into the project.

The resulting textures are consumed by the project's triplanar snow shaders; terrain meshes do not need Snow 02 UV authoring.

Snow 02 is provided by Poly Haven under CC0.
