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

$preset = Get-Content -Raw $presetPath
if ($preset -notmatch '(?m)^export_filter="scenes"\s*$') {
	$failures.Add("Windows export must use selected production scenes, not every project resource.")
}
foreach ($root in @("res://world/resort.tscn", "res://world/sunset_resort.tscn")) {
	if ($preset -notmatch [regex]::Escape($root)) {
		$failures.Add("Windows export is missing production root: $root")
	}
}
if ($preset -match 'res://tests/' -or $preset -match 'res://tools/') {
	$failures.Add("Windows export preset explicitly includes a development/test resource.")
}

# Selected-scene exports follow normal preload/resource dependencies. String-only
# runtime loads are not guaranteed to enter that graph, so flag production code
# that introduces them for explicit review. Test/tool code is intentionally out
# of the shipping graph and is excluded from this scan.
$productionRoots = @("autoload", "audio", "gameplay", "player", "resources", "shaders", "ui", "util", "world")
$stringLoadPattern = '(?<!pre)load\s*\(\s*["'']res://'
foreach ($relativeRoot in $productionRoots) {
	$root = Join-Path $RepoRoot $relativeRoot
	if (-not (Test-Path -LiteralPath $root -PathType Container)) {
		continue
	}
	foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.gd) {
		$text = Get-Content -Raw -LiteralPath $file.FullName
		if ($text -match $stringLoadPattern -or $text -match 'ResourceLoader\.load\s*\(\s*["'']res://') {
			$relative = $file.FullName.Substring($RepoRoot.Length).TrimStart([char]92, [char]47)
			$failures.Add("String-only production resource load requires export review: $relative")
		}
	}
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: Windows export roots are production-only and no string-only production resource loads were found."