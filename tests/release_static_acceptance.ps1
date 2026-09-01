param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$presetPath = Join-Path $RepoRoot "export_presets.cfg"
$releasePath = Join-Path $RepoRoot "docs/RELEASE.md"
$readmePath = Join-Path $RepoRoot "README.md"
$gitignorePath = Join-Path $RepoRoot ".gitignore"
$failures = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $presetPath -PathType Leaf)) {
	$failures.Add("export_presets.cfg is missing.")
}
else {
	$preset = Get-Content -Raw $presetPath
	foreach ($requiredText in @(
		'name="Windows Desktop"',
		'platform="Windows Desktop"',
		'export_path="builds/windows/SummitSessions.exe"',
		'binary_format/architecture="x86_64"',
		'binary_format/embed_pck=true'
	)) {
		if ($preset -notmatch [regex]::Escape($requiredText)) {
			$failures.Add("export_presets.cfg is missing: $requiredText")
		}
	}
}

if (-not (Test-Path -LiteralPath $releasePath -PathType Leaf)) {
	$failures.Add("docs/RELEASE.md is missing.")
}
else {
	$release = Get-Content -Raw $releasePath
	foreach ($requiredText in @("4.7.2.stable.official.ed1daf0bf", "Windows Desktop", "--export-release", "--quit-after 120", "does not include a")) {
		if ($release -notmatch [regex]::Escape($requiredText)) {
			$failures.Add("docs/RELEASE.md is missing: $requiredText")
		}
	}
}

$readme = Get-Content -Raw $readmePath
if ($readme -notmatch 'docs/RELEASE\.md') {
	$failures.Add("README.md does not link the release procedure.")
}
$gitignore = (Get-Content -Raw $gitignorePath) -replace "`r", ""
if ($gitignore -notmatch '(?m)^builds/$') {
	$failures.Add("Generated builds/ output is not ignored.")
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: export preset and release/build documentation are consistent."
