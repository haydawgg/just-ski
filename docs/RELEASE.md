# Release and build hygiene

## Supported toolchain

Use the official Godot `4.7.2.stable.official.ed1daf0bf` release. The project
configuration remains the source of truth for the main scene, Forward+ feature
set, 1920×1080 viewport/window override, and fullscreen startup. The pinned
Windows console binary used by CI is downloaded from the official Godot
release URL and checksum-verified by `.github/workflows/quality.yml`.

## Windows export

`export_presets.cfg` contains the maintained `Windows Desktop` preset and
exports to `builds/windows/SummitSessions.exe`. The preset exports the daytime
and sunset production resort scenes plus their transitive Godot resource
dependencies instead of packaging every repository resource. The production
resource boundary and string-load rule are documented in
`docs/EXPORT_CONTENT.md`.

Install the matching 4.7.2 official export templates, then run from the
repository root:

```powershell
$godot = $env:GODOT_PATH
New-Item -ItemType Directory -Force builds\windows | Out-Null
& $godot --headless --path . --export-release "Windows Desktop" builds\windows\SummitSessions.exe
```

Do not commit the generated `builds/` directory. Before distributing an
export, run the static and runtime quality gates from a clean checkout, then
smoke-test the exported executable:

```powershell
& .\builds\windows\SummitSessions.exe --headless --quit-after 120
```

An exported build should reach its main scene and exit without script,
shader, or asset-loading errors. Record the artifact size as part of release
validation; an unexpected size increase can indicate that development-only
resources entered the production dependency graph.

Project-authored code and content are licensed under the repository-root
`LICENSE` (MIT). Distribute that file with the source or export documentation.
The CC0/OFL external assets are documented separately in
`docs/ASSET_SOURCES.md` and retain their own notices and license files. New
binary assets must also follow `docs/ASSET_POLICY.md`.