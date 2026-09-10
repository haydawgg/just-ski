# Alpine prop material sources

These 512 x 512 albedo textures were generated for this project with OpenAI's
built-in image generation tool on 2026-09-10, then downsampled from the source
outputs for the game's low-poly environment material budget.

- `conifer_needles_albedo_512.png` — dense spruce/fir needle breakup.
- `snowy_granite_albedo_512.png` — neutral snowy granite breakup.
- `weathered_metal_albedo_512.png` — low-contrast weathered resort metal.

The source prompts requested square, tileable, perspective-free albedo images
without text, logos, watermarks, strong directional gradients, or baked
lighting. Runtime materials use world-space triplanar projection, tinting, and
mipmapped anisotropic filtering, so the primitive meshes require no authored
UV changes. Weathered-metal runtime response stays non-metallic because the
albedo carries rust/dirt breakup; the conifer map is dark (~58/255 mean), so
canopy tints stay near-white to preserve the three-tier hierarchy.
