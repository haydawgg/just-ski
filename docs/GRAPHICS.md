# Graphics and Settings

The project targets Forward+ at 1600×900 internal UI coordinates and begins with 1280×720 window output. The 3D render scale does not resize the UI.

`GameSettings` keeps separate `active` and `pending` dictionaries. Opening Options copies active values to pending. Controls only edit pending values. Apply promotes pending values, updates the renderer/audio, and saves `user://settings.cfg`; Cancel discards the edits; Reset Defaults changes only pending values until Apply.

Presets modify render scale, temporal anti-aliasing, shadow intent, SSAO, SSIL, SSR, and fog. Editing a child graphics value marks the preset Custom. The graybox uses bright rough snow, darker banks for terrain readability, orange features, filmic tone mapping, directional shadows, fog, and scalable screen-space effects.

The settings loader validates numeric ranges and recovers individual invalid or absent values from defaults.
