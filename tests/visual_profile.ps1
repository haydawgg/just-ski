param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$GodotPath = "",
	[string]$UserDataRoot = "",
	[int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$GodotPath = [System.Environment]::GetEnvironmentVariable("GODOT_GUI_PATH")
	if ([string]::IsNullOrWhiteSpace($GodotPath)) {
		$GodotPath = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
	}
}
$godot = (Resolve-Path -LiteralPath $GodotPath -ErrorAction SilentlyContinue).Path
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) {
	throw "Godot GUI executable was not found: $GodotPath"
}

if ([string]::IsNullOrWhiteSpace($UserDataRoot)) {
	$UserDataRoot = Join-Path $RepoRoot ".godot_user/profiling"
}
$UserDataRoot = [System.IO.Path]::GetFullPath($UserDataRoot)
$roaming = Join-Path $UserDataRoot "roaming"
$local = Join-Path $UserDataRoot "local"
New-Item -ItemType Directory -Path $roaming,$local -Force | Out-Null
$env:APPDATA = (Resolve-Path -LiteralPath $roaming).Path
$env:LOCALAPPDATA = (Resolve-Path -LiteralPath $local).Path

$captureDirectory = Join-Path $RepoRoot ".godot_user/captures"
New-Item -ItemType Directory -Path $captureDirectory -Force | Out-Null
$logDirectory = Join-Path $RepoRoot ".godot_logs"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$quotedRoot = '"' + $RepoRoot.Replace('"', '\"') + '"'

foreach ($quality in @(0, 1)) {
	$tag = if ($quality -eq 0) { "fast" } else { "premium" }
	$capturePath = Join-Path $captureDirectory ("profile_{0}.png" -f $tag)
	$profilePath = Join-Path $captureDirectory ("profile_{0}.json" -f $tag)
	$projectCapturePath = "res://.godot_user/captures/profile_{0}.png" -f $tag
	$projectProfilePath = "res://.godot_user/captures/profile_{0}.json" -f $tag
	$stdoutPath = Join-Path $logDirectory ("visual_profile_{0}.stdout.log" -f $tag)
	$stderrPath = Join-Path $logDirectory ("visual_profile_{0}.stderr.log" -f $tag)
	Remove-Item -LiteralPath $capturePath,$profilePath,$stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
	$process = Start-Process -FilePath $godot `
		-ArgumentList @(
			"--path", $quotedRoot,
			"res://tests/sunset_visual_inspection.tscn",
			"--",
			("--capture-path=" + $projectCapturePath),
			("--profile-snow-quality=" + $quality),
			("--profile-path=" + $projectProfilePath)
		) `
		-WindowStyle Hidden `
		-PassThru `
		-RedirectStandardOutput $stdoutPath `
		-RedirectStandardError $stderrPath
	Wait-Process -Id $process.Id -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue | Out-Null
	$process.Refresh()
	if (-not $process.HasExited) {
		try { $process.Kill($true) } catch { try { & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null } catch { } }
		throw "Visual profile $tag timed out after $TimeoutSeconds seconds"
	}
	if ($process.ExitCode -ne 0) {
		throw "Visual profile $tag exited with code $($process.ExitCode). See $stdoutPath and $stderrPath"
	}
	if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or -not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
		throw "Visual profile $tag did not produce its capture and profile outputs"
	}
	Write-Output "===== $tag ====="
	Get-Content -LiteralPath $stdoutPath
	if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath }
	Write-Output (Get-Content -LiteralPath $profilePath -Raw)
}
