# Asset Growth Policy

This policy applies before new production art, audio, fonts, video, or source files are committed.

## Storage rules

- Keep generated imports, captures, logs, exports, baked intermediates, and temporary conversion output out of Git. Existing `.gitignore` entries cover `.godot/`, `.godot_user/`, `.godot_logs/`, `world/generated/`, `builds/`, and local tools.
- Assets below 10 MB may use normal Git when they are runtime-ready and their source/license record is committed in `docs/ASSET_SOURCES.md` or a colocated `SOURCE.md`.
- Any individual runtime asset at or above 10 MB requires an explicit review of compression, resolution, channel packing, and whether Git LFS is appropriate before merge.
- Large editable source textures, models, and lossless audio belong under `assets/source/` only after Git LFS is configured. Derived runtime assets belong under `assets/art/` or the established runtime asset directory.
- Do not migrate repository history to Git LFS merely for the current asset set. Adopt LFS prospectively when the first reviewed large source asset requires it.

## Review checklist

Every added binary asset must have:

1. Provenance, author/source URL where applicable, license, and modification notes.
2. A stable runtime filename; generated hash/timestamp names are forbidden.
3. Reviewed import settings and an exported-build inclusion reason.
4. No committed Godot import cache or generated intermediate.
5. A size justification when the file is 10 MB or larger.

The quality gate should gain an automated size/provenance lint before the first production asset expansion. Until then, this checklist is a required review item.
