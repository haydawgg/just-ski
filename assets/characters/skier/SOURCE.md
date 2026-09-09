# Skier Body Source

## Upstream asset

- **Asset:** Mesh: 3D Male Base (Rigged) 1.0.2
- **Creator / distributor:** orange-juice-games.itch.io
- **Godot package / repository maintainer:** BoQsc
- **Godot Asset Library:** https://godotengine.org/asset-library/asset/3690
- **Repository:** https://github.com/BoQsc/Godot-Male-Base-Mesh/
- **Release archive:** https://github.com/BoQsc/Godot-Male-Base-Mesh/releases/latest/download/male_base_mesh.zip
- **License:** CC0, as stated by the upstream asset page and repository
- **Upstream file:** `male_base_mesh.glb`
- **Project file:** `assets/characters/skier/skier_body.glb`
- **Recorded SHA-256:** `08071618F05CB13F43259E81E5B38662FE5373135F8E08A87A5CAE0802A3C0EA`

## Project processing

The source GLB is used as the production skinned body. Project tooling modifies the presentation deterministically without replacing the skeleton or skinning contract.

Processing is performed in this order:

1. `tools/character/rebuild_skier_body_materials.py`
   - starts from the pristine source;
   - partitions the original skinned triangle stream into named material regions:
     - `Outfit_Jacket`
     - `Outfit_Pants`
     - `Outfit_Skin`
     - `Outfit_Gloves`
     - `Outfit_BootUnderlay`;
   - clips triangles at the hem and collar, adding interpolated seam vertices with normalized skin weights;
   - preserves existing vertices, skeleton nodes, inverse bind matrices, and authored animation data.

2. `tools/character/build_skier_clothing.py`
   - appends skinned clothing shells for the jacket, pants, and gloves regions;
   - duplicates the source triangles and offsets them along vertex normals;
   - uses per-bone volume and geodesic border taper for the shell shape;
   - extends the jacket shell above the collar cut (`COLLAR_SKIRT_TOP_Y`)
     with a guaranteed minimum offset (`COLLAR_SKIRT_MIN_OFFSET`) so the
     shell overlaps the jacket/skin seam as a turtleneck lip;
   - copies `JOINTS_0` and `WEIGHTS_0` directly so the added shells deform with the original body.

The project file is therefore not a pristine byte-for-byte copy of the upstream GLB. The skeleton and skinning contract are preserved while the visible body is prepared for the prototype's outfit system.

To rebuild from the pristine source (requires network for the upstream
archive; both scripts are idempotent and refuse to double-apply):

```powershell
Expand-Archive male_base_mesh.zip -DestinationPath pristine -Force
Copy-Item pristine/male_base_mesh.glb assets/characters/skier/skier_body.glb -Force
py tools/character/rebuild_skier_body_materials.py
py tools/character/build_skier_clothing.py
```

An existing processed body can be re-tailored offline with `py tools/character/rebuild_skier_body_materials.py --from-processed`, followed by `py tools/character/build_skier_clothing.py`. This extracts the base surfaces before rebuilding their clothing shells.

After replacing the GLB, re-run the editor import so `.godot/imported`
regenerates (the cache is git-ignored and must never be hand-edited), then
verify with `tests/character_equipment_scale_acceptance.tscn`, which gates
the collar-skirt overlap above the `0.62` material cut.

## Runtime contract

The production rig expects:

- meter scale;
- +Y up;
- -Z forward;
- one usable `Skeleton3D`;
- at least one skinned body / clothing mesh;
- no dependency on authored root motion;
- no requirement for skis, boots, poles, helmet, or goggles to be included in the source body.

Rigid equipment is supplied by the project and attached through the skier presentation rig.

Model-specific bone mapping, neutral orientation data, axis correction, scale, and equipment offsets are stored in:

`resources/animation/default_skier_skeleton_profile.tres`

Normal runtime uses automatic rig selection and prefers this Skeleton3D body. The generated primitive skier remains the fallback/debug presentation.
