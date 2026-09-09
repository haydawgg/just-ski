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

# Keep this hardware-backed capture profile separate from the headless runtime profile.
$godotUserRoaming = Join-Path $RepoRoot ".godot_user/roaming_1080"
$godotUserLocal = Join-Path $RepoRoot ".godot_user/local_1080"
New-Item -ItemType Directory -Path $godotUserRoaming,$godotUserLocal -Force | Out-Null
$env:APPDATA = (Resolve-Path -LiteralPath $godotUserRoaming).Path
$env:LOCALAPPDATA = (Resolve-Path -LiteralPath $godotUserLocal).Path

$captureDirectory = Join-Path $RepoRoot ".godot_user/captures"
$logDirectory = Join-Path $RepoRoot ".godot_logs"
New-Item -ItemType Directory -Path $captureDirectory,$logDirectory -Force | Out-Null
$captureName = "sunset_visual_gate_{0}.png" -f (Get-Date -Format "yyyyMMdd_HHmmss_fff")
$capturePath = Join-Path $captureDirectory $captureName
$profilePath = Join-Path $captureDirectory "sunset_visual_profile.json"
$projectCapturePath = "res://.godot_user/captures/$captureName"
$projectProfilePath = "res://.godot_user/captures/sunset_visual_profile.json"
$stdoutPath = Join-Path $logDirectory "sunset_visual_gate.stdout.log"
$stderrPath = Join-Path $logDirectory "sunset_visual_gate.stderr.log"
Remove-Item -LiteralPath $capturePath,$profilePath,$stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

Write-Output "===== GPU sunset capture ====="
Write-Output "Capture: $capturePath"
$quotedRepoRoot = '"' + $RepoRoot.Replace('"', '\"') + '"'
$captureProcess = Start-Process -FilePath $godotGui `
	-ArgumentList @("--path", $quotedRepoRoot, "res://tests/sunset_visual_inspection.tscn", "--", "--capture-path=$projectCapturePath", "--profile-path=$projectProfilePath", "--skip-player-probe") `
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
		throw "Sunset visual capture timed out after $TimeoutSeconds seconds"
	}
	Start-Sleep -Milliseconds 250
}

$captureProcess.WaitForExit()
$captureExitCode = [int]$captureProcess.ExitCode
$captureStdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
$captureStderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
$captureLog = "$captureStdout`n$captureStderr"
if ($captureExitCode -ne 0) {
    Write-Output "FAIL: sunset capture exited with code $captureExitCode"
	Write-Output $captureLog
    exit $captureExitCode
}
if ($captureLog -match 'SUNSET_VISUAL_CAPTURE_FAIL|SUNSET_VISUAL_PROFILE_SCHEMA_FAIL|SUNSET_VISUAL_PROFILE_FAIL|Parameter "t" is null|leaked texture|RIDs of type "Texture" were leaked|Texture.*leaked|ObjectDB instances were leaked|texture-RID') {
	Write-Output "FAIL: sunset capture log contains a capture or shutdown warning"
	Write-Output $captureLog
	exit 1
}
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or (Get-Item -LiteralPath $capturePath).Length -le 0) {
	Write-Output "FAIL: sunset capture was not produced: $capturePath"
	Write-Output $captureLog
	exit 1
}
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf) -or (Get-Item -LiteralPath $profilePath).Length -le 0) {
	Write-Output "FAIL: sunset profile JSON was not produced: $profilePath"
	Write-Output $captureLog
	exit 1
}
Write-Output "PASS: GPU sunset capture completed"
Write-Output $captureStdout

Write-Output "===== Sunset near-black visual metric ====="
& $godotConsole --headless --path $RepoRoot "res://tests/sunset_visual_metrics.tscn" -- "--capture-path=$projectCapturePath"
$metricExitCode = $LASTEXITCODE
if ($metricExitCode -ne 0) {
	Write-Output "FAIL: sunset near-black visual metric exited with code $metricExitCode"
	exit $metricExitCode
}

Write-Output "PASS: GPU sunset capture and lower-frame near-black metric passed"
