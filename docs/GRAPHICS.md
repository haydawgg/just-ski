# Graphics and Settings

The project targets Forward+ at 1600×900 internal UI coordinates and begins with 1280×720 window output. The 3D render scale does not resize the UI.

`GameSettings` keeps separate `active` and `pending` dictionaries. Opening Options copies active values to pending. Controls only edit pending values. Apply promotes pending values, updates the renderer/audio, and saves `user://settings.cfg`; Cancel discards the edits; Reset Defaults changes only pending values until Apply.

Presets modify render scale, temporal anti-aliasing, shadow intent, snow quality, SSAO, SSIL, SSR, and fog. Editing a child graphics value marks the preset Custom. Low and Medium use Fast snow; High and Ultra use Premium snow. The Snow quality control can override that mapping in a Custom preset.

Snow uses signed world-triplanar PBR sampling, so the same 2K CC0 texture set remains coherent across the main face, banks, rotated jumps, and convex landings without relying on mesh UVs. The detail texture packs OpenGL normal X/Y, roughness, and translucency. Normals are transformed with `MODEL_NORMAL_MATRIX`, perturbed in world space, and converted to view space only at the renderer interface.

Both compiled tiers share the triplanar implementation and fade texture detail between 20 m and 60 m. Fast snow omits subsurface and clearcoat outputs. Premium snow uses stable crystal masks to drive the renderer's clearcoat reflection lobe and uses texture translucency for real SSS/transmittance. Neither tier writes procedural AO, modulates dielectric specular, emits fake glitter, runs fBm loops, or uses screen derivatives. Groomed corduroy follows each feature's authored downhill direction and uses an analytic normal gradient.

The scene uses a procedural sky (ambient and reflections), a warm low sun with four-split shadows, height fog with aerial perspective, and the existing SSAO/SSR/fog toggles.

The settings loader validates numeric ranges and recovers individual invalid or absent values from defaults. Existing snow material instances listen for applied settings, swap compiled shader tiers, and reapply their surface-kind parameters without rebuilding the resort.
