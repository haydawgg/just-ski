param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$toolPath = Join-Path $RepoRoot "tools/world/bake_resort_preview.gd"
$docsPath = Join-Path $RepoRoot "docs/WORLD_AUTHORING.md"
$gitignorePath = Join-Path $RepoRoot ".gitignore"
$failures = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
	$failures.Add("Resort preview baker is missing.")
}
else {
	$tool = Get-Content -Raw $toolPath
	foreach ($required in @(
		"extends Node",
		"RESORT_SCENE",
		'source.call("_build_environment")',
		'source.call("_build_resort")',
		"PackedScene.new()",
		"ResourceSaver.save",
		"_strip_runtime_scripts",
		"get_tree().root.add_child"
	)) {
		if ($tool -notmatch [regex]::Escape($required)) {
			$failures.Add("Resort preview baker is missing required contract: $required")
		}
	}
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "tools/world/bake_resort_preview.tscn") -PathType Leaf)) {
	$failures.Add("Resort preview baker scene entry point is missing.")
}
if (-not (Test-Path -LiteralPath $docsPath -PathType Leaf)) {
	$failures.Add("World authoring documentation is missing.")
}
else {
	$docs = Get-Content -Raw $docsPath
	foreach ($required in @("bake_resort_preview.gd", "res://world/generated/resort_preview.tscn", "runtime/test builders", "strips runtime scripts")) {
		if ($docs -notmatch [regex]::Escape($required)) {
			$failures.Add("World authoring documentation is missing: $required")
		}
	}
}
$gitignore = (Get-Content -Raw $gitignorePath) -replace "`r", ""
if ($gitignore -notmatch '(?m)^world/generated/$') {
	$failures.Add("Generated resort preview output is not ignored.")
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}
Write-Output "PASS: deterministic resort preview/bake authoring contract is present."
