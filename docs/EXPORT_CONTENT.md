# Export Content Boundary

The Windows release preset exports the complete Godot resource graph and explicitly excludes development-only resource trees. This is deliberate: the project uses global `class_name` types that are resolved through Godot's script-class registry rather than appearing as direct scene dependencies, so a selected-scene export can omit required production scripts.

## Shipped resource boundary

The preset uses `export_filter="all_resources"` with these exclusions:

- `tests/*` — acceptance scenes, diagnostics, capture fixtures, benchmark resources, and test-only assets.
- `tools/*` — editor/baking utilities that are not part of the playable runtime.

Runtime code, gameplay data, production assets, shaders, UI, autoloads, and both resort variants remain in the production pack. Markdown documentation and other non-resource files are not added unless an include filter explicitly requests them.

Do not replace this with a selected-scene export unless the project first removes or explicitly accounts for global-class dependencies. Do not remove a development exclusion without reviewing the exported pack.

## Validation

CI exports `SummitSessions.pck` from the committed Windows preset and launches that exact pack with `--main-pack`. The smoke check must reject script, shader, engine, or acceptance errors even when Godot returns exit code 0. It also records the pack byte size so unexpected growth is visible.

Before distribution, additionally build the full Windows executable with the matching Godot 4.7.2 export templates and run the documented executable smoke test from a clean checkout.