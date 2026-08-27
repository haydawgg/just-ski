# Graphics and Settings

The project targets Forward+ at 1600×900 internal UI coordinates and begins with 1280×720 window output. The 3D render scale does not resize the UI.

`GameSettings` keeps separate `active` and `pending` dictionaries. Opening Options copies active values to pending. Controls only edit pending values. Apply promotes pending values, updates the renderer/audio, and saves `user://settings.cfg`; Cancel discards the edits; Reset Defaults changes only pending values until Apply.

Presets modify render scale, temporal anti-aliasing, shadow intent, SSAO, SSIL, SSR, and fog. Editing a child graphics value marks the preset Custom.

Snow is a world-space shader, not a flat albedo. Powder, packed, and groomed variants share one shader with different grain, dune, sparkle, and corduroy settings so large graybox faces do not show stretched UVs. Shade picks up a cool blue subsurface tint; sun-facing crystals emit tiny sparkles that the alpine sky, filmic tonemap, and a light glow pass catch. Distant snow ridges and tree caps sit outside the playable collision set.

The scene uses a procedural sky (ambient and reflections), a warm low sun with four-split shadows, height fog with aerial perspective, and the existing SSAO/SSR/fog toggles.

The settings loader validates numeric ranges and recovers individual invalid or absent values from defaults.
