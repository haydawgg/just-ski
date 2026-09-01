# World Authoring

The runtime resort remains deterministic and procedural so automated acceptance scenes can build the same course on every run. For editor inspection, the repository includes a one-shot baker that materializes the current environment and course into a static preview scene.

Run it from the project root with the pinned Godot executable (or set `GODOT_PATH`):

```powershell
& $env:GODOT_PATH --headless --path . res://tools/world/bake_resort_preview.tscn -- --output=res://world/generated/resort_preview.tscn
```

Open `res://world/generated/resort_preview.tscn` in the editor after the bake. The output directory is ignored because the preview is a derived artifact; commit a reviewed, intentionally named asset separately if a production workflow later requires versioned baked geometry. The `bake_resort_preview.gd` baker strips runtime scripts from the output, so opening it cannot spawn a second player, camera, UI, recorder, or procedural rebuild.

The same source profiles and `ParkCourseBuilder` feed both the bake and runtime/test builders. This keeps the preview useful for checking stable generated meshes, feature placement, rail paths, collision companions, LOD metadata, and lighting while preserving deterministic runtime construction for acceptance scenes.
