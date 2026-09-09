# Export Content Boundary

The Windows release preset exports the two production resort scenes and their transitive Godot resource dependencies. Test scenes, diagnostics, capture fixtures, and historical documentation are intentionally outside the shipped resource graph.

## Production roots

- `res://world/resort.tscn`
- `res://world/sunset_resort.tscn`

Any production resource loaded only through a runtime string path must either become a normal scene/resource dependency or be added explicitly to the export preset. Avoid introducing untracked string-only production loads.

Before distribution, build the Windows preset from a clean checkout, launch the exported executable with the documented smoke test, and inspect the resulting artifact size. A successful source/runtime quality gate is not a substitute for an export smoke test.