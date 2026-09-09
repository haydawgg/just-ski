param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
	[int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
	Write-Output "FAIL: repository root was not found: $RepoRoot"
	exit 1
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$godotGui = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
$godotConsole = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $godotGui -PathType Leaf)) { throw "Godot GUI executable was not found: $godotGui" }
if (-not (Test-Path -LiteralPath $godotConsole -PathType Leaf)) { throw "Godot console executable was not found: $godotConsole" }

$godotUserRoaming = Join-Path $RepoRoot ".godot_user/roaming_environment_visual"
$godotUserLocal = Join-Path $RepoRoot ".godot_user/local_environment_visual"
New-Item -ItemType Directory -Path $godotUserRoaming,$godotUserLocal -Force | Out-Null
$env:APPDATA = (Resolve-Path -LiteralPath $godotUserRoaming).Path
$env:LOCALAPPDATA = (Resolve-Path -LiteralPath $godotUserLocal).Path

$captureDirectory = Join-Path $RepoRoot ".godot_user/captures/snow_depth_after"
$logDirectory = Join-Path $RepoRoot ".godot_logs"
New-Item -ItemType Directory -Path $captureDirectory,$logDirectory -Force | Out-Null
$captureFiles = @(
	"gameplay_carve.png",
	"gameplay_transition.png",
	"gameplay_speed.png",
	"gameplay_skid.png",
	"gameplay_landing_first_contact.png",
	"gameplay_landing_impact.png",
	"gameplay_landing_compression.png",
	"gameplay_landing_recovery.png",
	"gameplay_landing.png"
)
foreach ($name in $captureFiles) {
	Remove-Item -LiteralPath (Join-Path $captureDirectory $name),(Join-Path $captureDirectory ([System.IO.Path]::ChangeExtension($name,"json"))) -Force -ErrorAction SilentlyContinue
}
$stdoutPath = Join-Path $logDirectory "environment_visual_gate.stdout.log"
$stderrPath = Join-Path $logDirectory "environment_visual_gate.stderr.log"
Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

$quotedRepoRoot = '"' + $RepoRoot.Replace('"', '\"') + '"'
$projectCaptureDirectory = "res://.godot_user/captures/snow_depth_after"
Write-Output "===== GPU environment capture ====="
$captureProcess = Start-Process -FilePath $godotGui `
	-ArgumentList @("--path", $quotedRepoRoot, "res://tests/environment_visual_inspection.tscn", "--", "--capture-dir=$projectCaptureDirectory", "--skip-player-probe") `
	-WindowStyle Hidden `
	-RedirectStandardOutput $stdoutPath `
	-RedirectStandardError $stderrPath `
	-PassThru

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ($true) {
$captureProcess.Refresh()
if ($captureProcess.HasExited) { break }
	if ([DateTime]::UtcNow -ge $deadline) {
		try { $captureProcess.Kill($true) } catch { try { & taskkill.exe /PID $captureProcess.Id /T /F 2>$null | Out-Null } catch { } }
		throw "Environment visual capture timed out after $TimeoutSeconds seconds"
	}
	Start-Sleep -Milliseconds 250
}

$captureProcess.WaitForExit()
$captureExitCode = [int]$captureProcess.ExitCode

if ($captureExitCode -ne 0) {
    Write-Output "FAIL: environment visual capture exited with code $captureExitCode"
	if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath }
	if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath }
    exit $captureExitCode
}
$captureStdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
$captureStderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
$captureLog = "$captureStdout`n$captureStderr"
if ($captureLog -match 'ENVIRONMENT_VISUAL_CAPTURE_FAIL|Parameter "t" is null|leaked texture|RIDs of type "Texture" were leaked|Texture.*leaked|ObjectDB instances were leaked|texture-RID') {
	Write-Output "FAIL: environment capture log contains a capture or shutdown warning"
	Write-Output $captureLog
	exit 1
}
foreach ($name in $captureFiles) {
	$imagePath = Join-Path $captureDirectory $name
	$jsonPath = Join-Path $captureDirectory ([System.IO.Path]::ChangeExtension($name,"json"))
	if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or (Get-Item -LiteralPath $imagePath).Length -le 0) { throw "Missing environment capture image: $imagePath" }
	if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf) -or (Get-Item -LiteralPath $jsonPath).Length -le 0) { throw "Missing environment telemetry JSON: $jsonPath" }
}
Write-Output "PASS: GPU environment capture produced all required images and telemetry"
Write-Output $captureStdout

Write-Output "===== Snow-depth visual metric ====="
& $godotConsole --headless --path $RepoRoot "res://tests/snow_depth_visual_metrics.tscn" -- "--capture-dir=$projectCaptureDirectory"
$metricExitCode = $LASTEXITCODE
if ($metricExitCode -ne 0) {
	Write-Output "FAIL: snow-depth visual metric exited with code $metricExitCode"
	exit $metricExitCode
}
Write-Output "PASS: GPU environment capture and snow-depth metric passed"
