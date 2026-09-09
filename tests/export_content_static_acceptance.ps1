param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$presetPath = Join-Path $RepoRoot "export_presets.cfg"
$failures = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $presetPath -PathType Leaf)) {
	Write-Output "FAIL: export_presets.cfg is missing."
	exit 1
}

$preset = (Get-Content -Raw $presetPath) -replace "`r", ""
if ($preset -notmatch '(?m)^export_filter="all_resources"\s*$') {
	$failures.Add("Windows export must include the complete production resource graph.")
}
var_unused = $null
$excludeMatch = [regex]::Match($preset, '(?m)^exclude_filter="([^"]*)"\s*$')
if (-not $excludeMatch.Success) {
	$failures.Add("Windows export is missing its development-resource exclude filter.")
}
else {
	$exclude = $excludeMatch.Groups[1].Value
	foreach ($requiredPattern in @("tests/*", "tools/*")) {
		if ($exclude -notlike "*$requiredPattern*") {
			$failures.Add("Windows export does not exclude $requiredPattern")
		}
	}
}
if ($preset -match '(?m)^export_filter="scenes"\s*$') {
	$failures.Add("Selected-scene export is unsafe for this project because global class_name dependencies are not all scene dependencies.")
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: Windows export includes production resources while excluding tests and tools."