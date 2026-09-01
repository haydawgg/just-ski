param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$project = Get-Content -Raw (Join-Path $RepoRoot "project.godot")
$graphics = Get-Content -Raw (Join-Path $RepoRoot "docs/GRAPHICS.md")
$failures = [System.Collections.Generic.List[string]]::new()

function Get-ProjectValue([string]$key) {
	$match = [regex]::Match($project, '(?m)^' + [regex]::Escape($key) + '=([^\r\n]+)(?:\r?$)')
	if (-not $match.Success) { throw "Missing project.godot value: $key" }
	return $match.Groups[1].Value.Trim()
}

$viewportWidth = Get-ProjectValue "window/size/viewport_width"
$viewportHeight = Get-ProjectValue "window/size/viewport_height"
$overrideWidth = Get-ProjectValue "window/size/window_width_override"
$overrideHeight = Get-ProjectValue "window/size/window_height_override"
$windowMode = Get-ProjectValue "window/size/mode"

if ($graphics -notmatch '`project\.godot` is the source of truth') {
	$failures.Add("GRAPHICS.md does not identify project.godot as the display configuration source of truth.")
}
if ($graphics -notmatch ([regex]::Escape("${viewportWidth}×${viewportHeight}"))) {
	$failures.Add("GRAPHICS.md does not document the project viewport ${viewportWidth}×${viewportHeight}.")
}
if ($graphics -notmatch ([regex]::Escape("${overrideWidth}×${overrideHeight}"))) {
	$failures.Add("GRAPHICS.md does not document the project window override ${overrideWidth}×${overrideHeight}.")
}
if ($windowMode -eq "3" -and $graphics -notmatch "fullscreen") {
	$failures.Add("GRAPHICS.md does not document fullscreen startup for project window mode 3.")
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: project.godot display values and GRAPHICS.md documentation agree."
