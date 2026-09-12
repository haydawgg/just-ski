param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
	[ValidateSet("daytime", "golden", "sunset")]
	[string]$EnvironmentName = "daytime",
	[switch]$HideGuides,
	[int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$godot = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) { throw "Godot GUI executable was not found: $godot" }

$runName = "ramp_surface_$EnvironmentName"
if ($HideGuides) { $runName += "_noguides" }
$evidenceRootRelative = "res://.godot_user/visual_runs/$runName"
$evidenceRoot = Join-Path $RepoRoot ".godot_user\visual_runs\$runName"
$captureRootRelative = "res://.godot_user/captures/$runName"
$logDirectory = Join-Path $RepoRoot ".godot_logs"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$stdoutPath = Join-Path $logDirectory "$runName.stdout.log"
$stderrPath = Join-Path $logDirectory "$runName.stderr.log"
Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

$quotedRepoRoot = '"' + $RepoRoot.Replace('"', '\"') + '"'
$arguments = @(
	"--path", $quotedRepoRoot,
	"res://tests/ramp_surface_visual_inspection.tscn",
	"--",
	"--fixed-fps=60",
	"--visual-environment=$EnvironmentName",
	"--evidence-root=$evidenceRootRelative",
	"--capture-dir=$captureRootRelative",
	"--skip-player-probe"
)
if ($HideGuides) { $arguments += "--hide-guides" }
$process = Start-Process -FilePath $godot -WorkingDirectory $RepoRoot -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ($true) {
	$process.Refresh()
	if ($process.HasExited) { break }
	if ([DateTime]::UtcNow -ge $deadline) {
		try { $process.Kill($true) } catch { try { & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null } catch {} }
		throw "Ramp surface visual capture timed out after $TimeoutSeconds seconds"
	}
	Start-Sleep -Milliseconds 250
}
$process.WaitForExit()
$exitCode = [int]$process.ExitCode
$stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
$stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
if ($exitCode -ne 0) {
	Write-Output $stdout
	Write-Output $stderr
	throw "Ramp surface visual capture exited with code $exitCode"
}

$manifestPath = Join-Path $evidenceRoot "visual_run.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Ramp surface visual manifest was not produced: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.status -ne "pass") { throw "Ramp surface visual manifest did not pass: $manifestPath" }
$expectedScenarioIds = @(
	"environment.ramp_texture.approach",
	"environment.ramp_texture.lip",
	"environment.ramp_texture.deck",
	"environment.ramp_texture.landing",
	"environment.ramp_texture.medium_deck",
	"environment.ramp_texture.medium_landing",
	"environment.ramp_texture.large_knuckle",
	"environment.ramp_texture.large_landing",
	"environment.ramp_texture.roller",
	"environment.ramp_texture.berm",
	"environment.ramp_texture.side_hit"
)
foreach ($scenarioId in $expectedScenarioIds) {
	$scenario = @($manifest.scenarios | Where-Object { $_.id -eq $scenarioId })
	if ($scenario.Count -ne 1) { throw "Ramp surface scenario is missing from the manifest: $scenarioId" }
	$rawArtifact = @($manifest.artifacts | Where-Object { $_.scenario_id -eq $scenarioId -and $_.role -eq "raw" })
	if ($rawArtifact.Count -ne 1) { throw "Ramp surface raw artifact is missing: $scenarioId" }
	$telemetry = @($manifest.telemetry | Where-Object { $_.scenario_id -eq $scenarioId })
	if ($telemetry.Count -ne 1) { throw "Ramp surface telemetry is missing: $scenarioId" }
	$rawPath = Join-Path $evidenceRoot ($rawArtifact[0].path -replace '/', '\')
	if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf) -or (Get-Item -LiteralPath $rawPath).Length -le 0) { throw "Ramp surface image is missing: $rawPath" }
}
Write-Output "RAMP_SURFACE_VISUAL_PASS: $EnvironmentName produced seven gameplay-camera ramp surface captures and telemetry."
Write-Output "RAMP_SURFACE_EVIDENCE: $evidenceRoot"
Write-Output $stdout
if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Output $stderr }
