param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$GodotPath = "",
	[string]$UserDataRoot = "",
	[string]$LogDirectory = "",
	[string]$CaptureDirectory = ""
)

$ErrorActionPreference = "Continue"
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
	Write-Output "FAIL: repository root was not found: $RepoRoot"
	exit 1
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$checks = @(
	"tests/physics_static_acceptance.ps1",
	"tests/shader_static_acceptance.ps1",
	"tests/config_docs_static_acceptance.ps1",
	"tests/world_authoring_static_acceptance.ps1",
	"tests/runtime_quality_gate.ps1"
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
			$failures.Add("Missing quality check: $relativePath")
			continue
		}
		$scriptArguments = @{ RepoRoot = $RepoRoot }
		if ($relativePath -eq "tests/runtime_quality_gate.ps1") {
			if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $scriptArguments.GodotPath = $GodotPath }
			if (-not [string]::IsNullOrWhiteSpace($UserDataRoot)) { $scriptArguments.UserDataRoot = $UserDataRoot }
			if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) { $scriptArguments.LogDirectory = $LogDirectory }
			if (-not [string]::IsNullOrWhiteSpace($CaptureDirectory)) { $scriptArguments.CaptureDirectory = $CaptureDirectory }
		}
		if ([string]::IsNullOrWhiteSpace($shell)) {
			# Fall back to the current host only when neither PowerShell executable
			# can be resolved (useful for embedded hosts).
			& $scriptPath @scriptArguments
		}
		else {
			# Each check owns its exit code. A child process lets this wrapper run
			# every check and report all failures in one invocation.
			& $shell -NoProfile -File $scriptPath @scriptArguments
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

Write-Output "PASS: static physics, shader, and full runtime quality gates passed."
