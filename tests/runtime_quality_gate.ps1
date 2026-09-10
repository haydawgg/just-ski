param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$GodotPath = "",
	[string]$UserDataRoot = "",
	[string]$LogDirectory = "",
	[string]$CaptureDirectory = "",
	[string]$Shard = "",
	[int]$FixedFps = 0,
	[int]$TimeoutMilliseconds = 120000
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$GodotPath = [System.Environment]::GetEnvironmentVariable("GODOT_PATH")
	if ([string]::IsNullOrWhiteSpace($GodotPath)) {
		$GodotPath = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
	}
}
$godot = (Resolve-Path -LiteralPath $GodotPath -ErrorAction SilentlyContinue).Path
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) {
	Write-Output "FAIL: Godot console executable was not found: $GodotPath"
	exit 1
}

$runRootIsTemporary = $false
if ([string]::IsNullOrWhiteSpace($UserDataRoot)) {
	$UserDataRoot = Join-Path $RepoRoot ".godot_user"
}
else {
	# Only clean a newly-created directory underneath the OS temp root. An
	# explicit existing path belongs to the caller and is left untouched.
	$requestedUserDataRoot = [System.IO.Path]::GetFullPath($UserDataRoot)
	$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
	$runRootIsTemporary = (-not (Test-Path -LiteralPath $requestedUserDataRoot)) -and $requestedUserDataRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)
	$UserDataRoot = $requestedUserDataRoot
}
$UserDataRoot = [System.IO.Path]::GetFullPath($UserDataRoot)
$godotUserRoaming = Join-Path $UserDataRoot "roaming"
if (-not (Test-Path -LiteralPath $godotUserRoaming)) { New-Item -ItemType Directory -Path $godotUserRoaming -Force | Out-Null }
$godotUserLocal = Join-Path $UserDataRoot "local"
if (-not (Test-Path -LiteralPath $godotUserLocal)) { New-Item -ItemType Directory -Path $godotUserLocal -Force | Out-Null }
$env:APPDATA = (Resolve-Path $godotUserRoaming).Path
$env:LOCALAPPDATA = (Resolve-Path $godotUserLocal).Path

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
	$LogDirectory = Join-Path $RepoRoot ".godot_logs"
}
$LogDirectory = [System.IO.Path]::GetFullPath($LogDirectory)
if (-not (Test-Path -LiteralPath $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }
if ([string]::IsNullOrWhiteSpace($CaptureDirectory)) {
	$CaptureDirectory = Join-Path $LogDirectory "captures"
}
$CaptureDirectory = [System.IO.Path]::GetFullPath($CaptureDirectory)
if (-not (Test-Path -LiteralPath $CaptureDirectory)) { New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null }
$runStartedUtc = [DateTime]::UtcNow
$captureExtensions = @(".png", ".jpg", ".jpeg", ".mp4", ".json", ".csv")
$capturedArtifacts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$captureRoots = @(
	(Join-Path $RepoRoot ".godot_user"),
	$UserDataRoot
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -Unique

function Copy-CaptureArtifacts {
	param(
		[string]$SceneName
	)
	$safeSceneName = ($SceneName -replace '^res://', '') -replace '[^A-Za-z0-9_-]', '_'
	foreach ($root in $captureRoots) {
		try {
			$rootPath = (Resolve-Path -LiteralPath $root).Path
			$files = Get-ChildItem -LiteralPath $rootPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
				$captureExtensions -contains $_.Extension.ToLowerInvariant() -and $_.LastWriteTimeUtc -ge $runStartedUtc
			}
			foreach ($file in $files) {
				$artifactKey = "$($file.FullName)|$($file.LastWriteTimeUtc.Ticks)|$($file.Length)"
				if (-not $capturedArtifacts.Add($artifactKey)) {
					continue
				}
				$relative = $file.FullName.Substring($rootPath.Length).TrimStart([char]92, [char]47)
				$destination = Join-Path (Join-Path $CaptureDirectory $safeSceneName) $relative
				$destinationParent = Split-Path -Parent $destination
				if (-not (Test-Path -LiteralPath $destinationParent)) {
					New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
				}
				Copy-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
			}
		}
		catch {
			Write-Warning "Could not preserve capture output from $root for ${SceneName}: $($_.Exception.Message)"
		}
	}
}

function Test-IgnoredGodotWindowsTeardownCrash {
	param(
		[string]$Scene,
		[int]$ExitCode,
		[string]$Output,
		[bool]$SceneHasError
	)
	# Godot 4.7.2 headless on Windows can ACCESS_VIOLATE (0xC0000005 /
	# -1073741819) during process teardown after solver-layer acceptance
	# already printed SOLVER_LAYER_PASS. Assertions finished; do not fail
	# the shard for that engine crash.
	if ($SceneHasError) {
		return $false
	}
	if ($Scene -ne "res://tests/solver_layer_interface_acceptance.tscn") {
		return $false
	}
	if ($ExitCode -ne -1073741819) {
		return $false
	}
	return $Output -match 'SOLVER_LAYER_PASS:'
}

function Invoke-GodotScene {
	param(
		[string]$Executable,
		[string]$WorkingDirectory,
		[string]$Scene,
		[int]$TimeoutMs,
		[int]$FixedFps,
		[string]$StdoutPath,
		[string]$StderrPath
	)

	$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $Executable
	$escapedRoot = $WorkingDirectory.Replace('"', '\"')
	# Headless CI must not wait on a runner-provided audio device. The runtime
	# scenes assert gameplay/rendering behavior; audio timing is profiled in a
	# separate non-headless diagnostic.
	$fixedFpsArgument = if ($FixedFps -gt 0) { ' --fixed-fps ' + $FixedFps } else { '' }
	$startInfo.Arguments = '--headless --audio-driver Dummy' + $fixedFpsArgument + ' --path "' + $escapedRoot + '" ' + $Scene
	$startInfo.WorkingDirectory = $WorkingDirectory
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $startInfo
	$stdoutTask = $null
	$stderrTask = $null
	try {
		if (-not $process.Start()) {
			$message = "Could not start Godot."
			[System.IO.File]::WriteAllText($StdoutPath, "")
			[System.IO.File]::WriteAllText($StderrPath, $message)
			return [pscustomobject]@{ ExitCode = 1; Output = $message; TimedOut = $false }
		}
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()
		if (-not $process.WaitForExit($TimeoutMs)) {
			try {
				$process.Kill($true)
			}
			catch {
				# Windows PowerShell/.NET Framework lacks Kill(bool). taskkill's
				# /T flag keeps the timeout path tree-safe on that host too.
				try { & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null } catch { try { $process.Kill() } catch { } }
			}
			try { $process.WaitForExit() } catch { }
			$stdout = if ($null -ne $stdoutTask) { $stdoutTask.GetAwaiter().GetResult() } else { "" }
			$stderr = if ($null -ne $stderrTask) { $stderrTask.GetAwaiter().GetResult() } else { "" }
			[System.IO.File]::WriteAllText($StdoutPath, $stdout)
			[System.IO.File]::WriteAllText($StderrPath, $stderr)
			return [pscustomobject]@{ ExitCode = 124; Output = "TIMEOUT: Godot did not exit within $TimeoutMs ms.`n$stdout$stderr"; TimedOut = $true }
		}
		# WaitForExit(timeout) can return before asynchronous stream readers have
		# drained. The second wait makes the exit code and captured output stable.
		$process.WaitForExit()
		$exitCode = [int]$process.ExitCode
		$stdout = $stdoutTask.GetAwaiter().GetResult()
		$stderr = $stderrTask.GetAwaiter().GetResult()
		[System.IO.File]::WriteAllText($StdoutPath, $stdout)
		[System.IO.File]::WriteAllText($StderrPath, $stderr)
		return [pscustomobject]@{ ExitCode = $exitCode; Output = "$stdout$stderr"; TimedOut = $false }
	}
	catch {
		$message = "Godot process failed: $($_.Exception.Message)"
		[System.IO.File]::WriteAllText($StdoutPath, "")
		[System.IO.File]::WriteAllText($StderrPath, $message)
		return [pscustomobject]@{ ExitCode = 1; Output = $message; TimedOut = $false }
	}
	finally {
		$process.Dispose()
	}
}

$sceneShards = [ordered]@{
	"environment-camera" = @(
		"res://tests/environment_visual_acceptance.tscn",
		"res://tests/environment_asset_contract_acceptance.tscn",
		"res://tests/environment_asset_production_acceptance.tscn",
		"res://tests/environment_tree_batch_acceptance.tscn",
		"res://tests/content_pass_acceptance.tscn",
		"res://tests/park_content_runtime_acceptance.tscn",
		"res://tests/summit_environment_acceptance.tscn",
		"res://tests/sunset_environment_acceptance.tscn",
		"res://tests/camera_low_speed_acceptance.tscn",
		"res://tests/camera_runtime_stability_acceptance.tscn",
		"res://tests/camera_airborne_viewport_diagnostic.tscn",
		"res://tests/camera_performance_acceptance.tscn",
		"res://tests/camera_phase_performance_acceptance.tscn"
	)
	"physics" = @(
		"res://tests/physics_benchmark.tscn",
		"res://tests/physics_collision_acceptance.tscn",
		"res://tests/ski_feel_acceptance.tscn",
		"res://tests/ground_hover_probe.tscn",
		"res://tests/terrain_suspension_course.tscn",
		"res://tests/crest_unweighting_acceptance.tscn"
	)
	"animation" = @(
		"res://tests/animation_acceptance.tscn",
		"res://tests/character_equipment_scale_acceptance.tscn",
		"res://tests/character_presentation_acceptance.tscn",
		"res://tests/head_presentation_acceptance.tscn",
		"res://tests/skeleton_rig_acceptance.tscn",
		"res://tests/jump_animation_acceptance.tscn",
		"res://tests/landing_animation_acceptance.tscn",
		"res://tests/air_preview_ik_acceptance.tscn",
		"res://tests/landing_orientation_acceptance.tscn",
		"res://tests/rail_animation_acceptance.tscn",
		"res://tests/trick_animation_acceptance.tscn",
		"res://tests/grab_animation_acceptance.tscn",
		"res://tests/animation_silhouette_acceptance.tscn",
		"res://tests/animation_polish_acceptance.tscn",
		"res://tests/animation_transition_regression_acceptance.tscn",
		"res://tests/animation_presentation_quality_acceptance.tscn",
		"res://tests/crash_recovery_acceptance.tscn"
	)
	"tricks-gameplay" = @(
		"res://tests/gameplay_acceptance.tscn",
		"res://tests/flick_trick_acceptance.tscn",
		"res://tests/rotation_intent_acceptance.tscn",
		"res://tests/trick_residual_acceptance.tscn",
		"res://tests/trick_rotation_state_acceptance.tscn",
		"res://tests/air_rotation_integrator_acceptance.tscn",
		"res://tests/flick_takeoff_release_acceptance.tscn",
		"res://tests/trick_rotation_benchmark.tscn",
		"res://tests/flick_gameplay_acceptance.tscn",
		"res://tests/flick_flip_gameplay_acceptance.tscn",
		"res://tests/trick_ui_acceptance.tscn",
		"res://tests/park_challenge_acceptance.tscn",
		"res://tests/session_flow_acceptance.tscn"
	)
	"systems-media" = @(
		"res://tests/runtime_smoke.tscn",
		"res://tests/profiling_acceptance.tscn",
		"res://tests/performance_profile_schema_acceptance.tscn",
		"res://tests/audio_mix_solver_acceptance.tscn",
		"res://tests/clip_recorder_worker_acceptance.tscn",
		"res://tests/clip_recorder_lifecycle_acceptance.tscn",
		"res://tests/settings_acceptance.tscn",
		"res://tests/input_manager_acceptance.tscn",
		"res://tests/skier_input_frame_acceptance.tscn",
		"res://tests/solver_layer_interface_acceptance.tscn",
		"res://tests/mp4_encoder_acceptance.tscn",
		"res://tests/visual_evidence_acceptance.tscn"
	)
}

$allScenes = [System.Collections.Generic.List[string]]::new()
foreach ($shardScenes in $sceneShards.Values) {
	foreach ($scene in $shardScenes) {
		[void]$allScenes.Add($scene)
	}
}
$duplicateScenes = @($allScenes | Group-Object | Where-Object { $_.Count -gt 1 })
if ($duplicateScenes.Count -gt 0) {
	$duplicateNames = ($duplicateScenes | ForEach-Object { $_.Name }) -join ", "
	Write-Output "FAIL: runtime scene shard list contains duplicates: $duplicateNames"
	exit 1
}
if (-not [string]::IsNullOrWhiteSpace($Shard)) {
	if (-not $sceneShards.Contains($Shard)) {
		Write-Output "FAIL: unknown runtime shard '$Shard'. Expected: $($sceneShards.Keys -join ', ')"
		exit 1
	}
	$scenes = @($sceneShards[$Shard])
}
else {
	$scenes = @($allScenes)
}
$shardLabel = if ([string]::IsNullOrWhiteSpace($Shard)) { "all" } else { $Shard }
Write-Output "RUNTIME_SHARD name=$shardLabel scenes=$($scenes.Count)"

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($scene in $scenes) {
	Write-Output "===== $scene ====="
	$safeName = ($scene -replace '^res://', '') -replace '[^A-Za-z0-9_-]', '_'
	$stdoutPath = Join-Path $LogDirectory ($safeName + ".stdout.log")
	$stderrPath = Join-Path $LogDirectory ($safeName + ".stderr.log")
	$sceneTimer = [System.Diagnostics.Stopwatch]::StartNew()
	$result = Invoke-GodotScene -Executable $godot -WorkingDirectory $RepoRoot -Scene $scene -TimeoutMs $TimeoutMilliseconds -FixedFps $FixedFps -StdoutPath $stdoutPath -StderrPath $stderrPath
	$sceneTimer.Stop()
	$exitCode = [int]$result.ExitCode
	$output = [string]$result.Output
	Write-Output $output.TrimEnd()
	$sceneDuration = $sceneTimer.Elapsed.TotalSeconds.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture)
	$sceneHasError = $output -match '(?im)^\s*(?:SHADER ERROR|SCRIPT ERROR|ERROR:)|\b[A-Z_]+_FAIL:|Parameter "t" is null|leaked texture|RIDs of type "Texture" were leaked|Texture.*leaked|ObjectDB instances were leaked|texture-RID'
	$ignoredTeardownCrash = Test-IgnoredGodotWindowsTeardownCrash -Scene $scene -ExitCode $exitCode -Output $output -SceneHasError $sceneHasError
	if ($exitCode -ne 0 -and -not $ignoredTeardownCrash) {
		$failures.Add("$scene exited with code $exitCode; logs: $stdoutPath, $stderrPath")
	}
	if ($sceneHasError) {
		$failures.Add("$scene emitted an engine or acceptance error")
	}
	if (($exitCode -eq 0 -or $ignoredTeardownCrash) -and -not $sceneHasError) {
		Write-Output ("PASS {0} — {1}s" -f $scene, $sceneDuration)
		if ($ignoredTeardownCrash) {
			Write-Output "IGNORED Godot 4.7 Windows ACCESS_VIOLATION after SOLVER_LAYER_PASS during process teardown"
		}
	}
	else {
		Write-Output ("FAIL {0} — {1}s (exit {2})" -f $scene, $sceneDuration, $exitCode)
	}
	Copy-CaptureArtifacts -SceneName $scene
}

if ($failures.Count -gt 0) {
	Write-Output "Runtime logs were preserved in: $LogDirectory"
	Write-Output "Runtime captures were preserved in: $CaptureDirectory"
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: all runtime scenes completed without engine, shader, script, or acceptance errors."
if (Get-ChildItem -LiteralPath $CaptureDirectory -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
	Write-Output "Runtime captures were preserved in: $CaptureDirectory"
}
if ($runRootIsTemporary -and (Test-Path -LiteralPath $UserDataRoot)) {
	Remove-Item -LiteralPath $UserDataRoot -Recurse -Force -ErrorAction SilentlyContinue
}
