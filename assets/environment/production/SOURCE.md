# Project-authored environment set

These low-poly Godot scenes were authored specifically for this repository on 2026-08-30. They use only Godot primitive meshes, project code, and project colors; no third-party model or texture source is included.

All dimensions are authored in meters from a snow-contact origin. Concrete props separate render, collision, and LOD nodes; summit boulders and the lift line are presentation-only decorations with no gameplay collider. Rails and shaped snow features use catalog-backed parametric templates because their dimensions and paths are course data; their render and collision geometry continue to be generated from the same authored specification.

The near and batched tree canopies, boulders, and maintained resort
metal props use the project-owned material set documented in
`assets/materials/alpine_props/SOURCE.md`. Textures are projected in world
space so presentation detail does not alter mesh topology, collision, or LOD
bounds. Small snow caps stay flat-shaded to avoid binding the 2K piste
diffuse to sub-meter cones; grind rails and the summit lift structure reuse
the weathered-metal breakup with non-metallic response for weathered parts.
