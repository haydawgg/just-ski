param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Continue"
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
	Write-Output "FAIL: repository root was not found: $RepoRoot"
	exit 1
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$checks = @(
	"tests/physics_static_acceptance.ps1",
	"tests/collision_layer_static_acceptance.ps1",
	"tests/shader_static_acceptance.ps1",
	"tests/park_render_shell_static_acceptance.ps1",
	"tests/config_docs_static_acceptance.ps1",
	"tests/world_authoring_static_acceptance.ps1",
	"tests/release_static_acceptance.ps1",
	"tests/export_content_static_acceptance.ps1",
	"tests/performance_compare_acceptance.ps1",
	"tests/ci_static_acceptance.ps1",
	"tests/visual_evidence_static_acceptance.ps1"
)
$failures = [System.Collections.Generic.List[string]]::new()
$shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Path
if ([string]::IsNullOrWhiteSpace($shell)) {
	$shell = (Get-Command powershell -ErrorAction SilentlyContinue).Path
}

Push-Location $RepoRoot
try {
	foreach ($relativePath in $checks) {
		$scriptPath = Join-Path $RepoRoot $relativePath
		Write-Output "===== $relativePath ====="
		if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
			$failures.Add("Missing static quality check: $relativePath")
			continue
		}
		if ([string]::IsNullOrWhiteSpace($shell)) {
			& $scriptPath -RepoRoot $RepoRoot
		}
		else {
			& $shell -NoProfile -File $scriptPath -RepoRoot $RepoRoot
		}
		$exitCode = $LASTEXITCODE
		if ($exitCode -ne 0) {
			$failures.Add("$relativePath exited with code $exitCode")
		}
	}
}
finally {
	Pop-Location
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: all static quality checks passed."