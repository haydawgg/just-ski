param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$GodotPath = "",
	[string]$UserDataRoot = "",
	[string]$IsolationMode = "baseline",
	[string[]]$IsolationModes = @(),
	[string[]]$Environments = @("daytime", "sunset"),
	[int[]]$Presets = @(0, 1, 2, 3),
	[int]$GpuIndex = -1,
	[double]$RenderScale = -1.0,
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
$commitSha = (& git -C $RepoRoot rev-parse HEAD 2>$null).Trim()
if ([string]::IsNullOrWhiteSpace($commitSha)) { $commitSha = "unknown" }
$workingTreeDirty = -not [string]::IsNullOrWhiteSpace((& git -C $RepoRoot status --porcelain --untracked-files=normal 2>$null | Out-String).Trim())
$effectiveIsolationModes = if ($IsolationModes.Count -gt 0) { $IsolationModes } else { @($IsolationMode) }

foreach ($environment in $Environments) {
	$environmentTag = $environment.ToLowerInvariant()
	$scene = switch ($environmentTag) {
		"daytime" { "res://tests/daytime_visual_inspection.tscn" }
		"sunset" { "res://tests/sunset_visual_inspection.tscn" }
		default { throw "Unknown environment '$environment'. Expected daytime or sunset." }
	}
	foreach ($effectiveIsolationMode in $effectiveIsolationModes) {
	foreach ($preset in $Presets) {
	if ($preset -lt 0 -or $preset -gt 3) { throw "Preset must be 0 (Low), 1 (Medium), 2 (High), or 3 (Ultra)." }
	$presetTag = @("low", "medium", "high", "ultra")[$preset]
	$tag = "{0}_{1}_{2}" -f $environmentTag,$presetTag,$effectiveIsolationMode
	$capturePath = Join-Path $captureDirectory ("profile_{0}.png" -f $tag)
	$profilePath = Join-Path $captureDirectory ("profile_{0}.json" -f $tag)
	$projectCapturePath = "res://.godot_user/captures/profile_{0}.png" -f $tag
	$projectProfilePath = "res://.godot_user/captures/profile_{0}.json" -f $tag
	$stdoutPath = Join-Path $logDirectory ("visual_profile_{0}.stdout.log" -f $tag)
	$stderrPath = Join-Path $logDirectory ("visual_profile_{0}.stderr.log" -f $tag)
	Remove-Item -LiteralPath $capturePath,$profilePath,$stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
	$godotArguments = @("--path", $quotedRoot)
	if ($GpuIndex -ge 0) {
		$godotArguments += @("--gpu-index", $GpuIndex)
	}
	$godotArguments += @(
		$scene,
		"--",
		("--sunset-isolation=" + $effectiveIsolationMode),
		("--capture-path=" + $projectCapturePath),
		("--profile-preset=" + $preset),
		("--profile-path=" + $projectProfilePath),
		("--profile-environment=" + $environmentTag),
		("--profile-commit=" + $commitSha),
		("--profile-dirty=" + $workingTreeDirty.ToString().ToLowerInvariant())
	)
	if ($RenderScale -ge 0.0) {
		$godotArguments += ("--profile-render-scale=" + $RenderScale.ToString([System.Globalization.CultureInfo]::InvariantCulture))
	}
	$process = Start-Process -FilePath $godot `
		-ArgumentList $godotArguments `
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
}
}
