param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$presetPath = Join-Path $RepoRoot "export_presets.cfg"
$releasePath = Join-Path $RepoRoot "docs/RELEASE.md"
$readmePath = Join-Path $RepoRoot "README.md"
$licensePath = Join-Path $RepoRoot "LICENSE"
$licensingDecisionPath = Join-Path $RepoRoot "docs/LICENSING_DECISION.md"
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
	# Shipping every repository resource silently packages tests and development
	# fixtures. Keep the release preset explicit about its production boundary.
	if ($preset -match '(?m)^export_filter="all_resources"\s*$') {
		$failures.Add("Windows release preset exports all_resources; use an explicit production resource filter before distribution.")
	}
}

if (-not (Test-Path -LiteralPath $releasePath -PathType Leaf)) {
	$failures.Add("docs/RELEASE.md is missing.")
}
else {
	$release = Get-Content -Raw $releasePath
	foreach ($requiredText in @("4.7.2.stable.official.ed1daf0bf", "Windows Desktop", "--export-release", "--quit-after 120")) {
		if ($release -notmatch [regex]::Escape($requiredText)) {
			$failures.Add("docs/RELEASE.md is missing: $requiredText")
		}
	}
}

$readme = Get-Content -Raw $readmePath
if ($readme -notmatch 'docs/RELEASE\.md') {
	$failures.Add("README.md does not link the release procedure.")
}
if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) {
	$failures.Add("LICENSE is missing.")
}
else {
	$license = Get-Content -Raw $licensePath
	foreach ($requiredLicenseText in @("MIT License", "Copyright (c) 2026 James Daniel", "Permission is hereby granted", 'THE SOFTWARE IS PROVIDED "AS IS"')) {
		if ($license -notmatch [regex]::Escape($requiredLicenseText)) {
			$failures.Add("LICENSE is missing required MIT text: $requiredLicenseText")
		}
	}
}
if ($readme -notmatch '\[MIT License\]\(LICENSE\)') {
	$failures.Add("README.md does not link the project MIT license.")
}
if (-not (Test-Path -LiteralPath $licensingDecisionPath -PathType Leaf)) {
	$failures.Add("docs/LICENSING_DECISION.md is missing.")
}
else {
	$licensingDecision = Get-Content -Raw $licensingDecisionPath
	if ($licensingDecision -notmatch 'Status: \*\*MIT selected and recorded\*\*' -or $licensingDecision -notmatch 'repository-root `LICENSE`') {
		$failures.Add("docs/LICENSING_DECISION.md does not record the MIT decision and LICENSE contract.")
	}
}
$release = Get-Content -Raw $releasePath
if ($release -notmatch 'repository-root `LICENSE` \(MIT\)' -or $release -match 'does not include a project-level license') {
	$failures.Add("docs/RELEASE.md does not describe the active MIT release contract.")
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