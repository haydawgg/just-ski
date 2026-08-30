# Skier Body Source

- Asset: Mesh: 3D Male Base (Rigged) 1.0.2
- Creator/distributor: orange-juice-games.itch.io; Godot package maintained by BoQsc
- Original page: https://godotengine.org/asset-library/asset/3690
- Repository: https://github.com/BoQsc/Godot-Male-Base-Mesh/
- Download: https://github.com/BoQsc/Godot-Male-Base-Mesh/releases/latest/download/male_base_mesh.zip
- License: CC0 (as stated by the asset page and repository)
- Imported file: `male_base_mesh.glb`, renamed to `skier_body.glb`
- Modifications: renamed; the single skinned triangle stream was partitioned into
  five named material regions (`Outfit_Jacket`, `Outfit_Pants`, `Outfit_Skin`,
  `Outfit_Gloves`, and `Outfit_BootUnderlay`) with clean geometric boundaries
  (torso clothing cut at hip height and the collar line, hand/finger triangles
  grouped into `Outfit_Gloves`). `tools/character/build_skier_clothing.py` then
  appends skinned clothing shells over the jacket, pants, and gloves regions:
  duplicated triangles offset along vertex normals with per-bone volume and
  geodesic border taper, cloning `JOINTS_0`/`WEIGHTS_0` verbatim so the shells
  deform identically to the body. Vertex attributes, skin weights, skeleton
  nodes, inverse bind matrices, and animation data are otherwise unchanged.
  The deterministic tools are `tools/character/rebuild_skier_body_materials.py`
  (run first, from the pristine source) and `tools/character/build_skier_clothing.py`.
- SHA-256: `A72B5F867AAC549CB69BB5D400267E375A23134E4B92EA2650D6D51D4F0C9C77`

The runtime contract is meters, +Y up, -Z forward, one `Skeleton3D`, at least
one skinned body/clothing mesh, and no skis, boots, poles, root motion, or
required authored animation. Bone-name calibration is stored in
`resources/animation/default_skier_skeleton_profile.tres`.
