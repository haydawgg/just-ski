param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
	Write-Output "FAIL: repository root was not found: $RepoRoot"
	exit 1
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$godotGui = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
$godotConsole = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $godotGui -PathType Leaf)) {
	Write-Output "FAIL: Godot GUI executable was not found: $godotGui"
	exit 1
}
if (-not (Test-Path -LiteralPath $godotConsole -PathType Leaf)) {
	Write-Output "FAIL: Godot console executable was not found: $godotConsole"
	exit 1
}

# Keep this hardware-backed capture profile separate from the headless runtime
# profile. The 1080 profile is also used by the local reference capture runs.
$godotUserRoaming = Join-Path $RepoRoot ".godot_user/roaming_1080"
$godotUserLocal = Join-Path $RepoRoot ".godot_user/local_1080"
if (-not (Test-Path -LiteralPath $godotUserRoaming)) { New-Item -ItemType Directory -Path $godotUserRoaming -Force | Out-Null }
if (-not (Test-Path -LiteralPath $godotUserLocal)) { New-Item -ItemType Directory -Path $godotUserLocal -Force | Out-Null }
$env:APPDATA = (Resolve-Path -LiteralPath $godotUserRoaming).Path
$env:LOCALAPPDATA = (Resolve-Path -LiteralPath $godotUserLocal).Path

$captureDirectory = Join-Path $RepoRoot ".godot_user/captures"
if (-not (Test-Path -LiteralPath $captureDirectory)) { New-Item -ItemType Directory -Path $captureDirectory -Force | Out-Null }
$captureName = "sunset_visual_gate_{0}.png" -f (Get-Date -Format "yyyyMMdd_HHmmss_fff")
$capturePath = Join-Path $captureDirectory $captureName
$projectCapturePath = "res://.godot_user/captures/$captureName"

Write-Output "===== GPU sunset capture ====="
Write-Output "Capture: $capturePath"
$quotedRepoRoot = '"' + $RepoRoot.Replace('"', '\"') + '"'
$captureProcess = Start-Process -FilePath $godotGui `
	-ArgumentList @("--path", $quotedRepoRoot, "res://tests/sunset_visual_inspection.tscn", "--", "--capture-path=$projectCapturePath") `
	-WindowStyle Hidden `
	-PassThru

$captureDeadline = [DateTime]::UtcNow.AddSeconds(90)
while (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or (Get-Item -LiteralPath $capturePath).Length -le 0) {
	if ([DateTime]::UtcNow -ge $captureDeadline) {
		try { if ($captureProcess -and -not $captureProcess.HasExited) { $captureProcess.Kill() } } catch { }
		Write-Output "FAIL: sunset capture was not produced within 90 seconds"
		exit 1
	}
	Start-Sleep -Milliseconds 250
}

Write-Output "PASS: GPU sunset capture completed"
Write-Output "===== Sunset near-black visual metric ====="
& $godotConsole --headless --path $RepoRoot "res://tests/sunset_visual_metrics.tscn" -- "--capture-path=$projectCapturePath"
$metricExitCode = $LASTEXITCODE
if ($metricExitCode -ne 0) {
	Write-Output "FAIL: sunset near-black visual metric exited with code $metricExitCode"
	exit $metricExitCode
}

Write-Output "PASS: GPU sunset capture and lower-frame near-black metric passed"
