param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$godot = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
	Write-Output "FAIL: Godot console executable was not found: $godot"
	exit 1
}

$godotUserRoaming = Join-Path $RepoRoot ".godot_user/roaming"
if (-not (Test-Path -LiteralPath $godotUserRoaming)) { New-Item -ItemType Directory -Path $godotUserRoaming -Force | Out-Null }
$godotUserLocal = Join-Path $RepoRoot ".godot_user/local"
if (-not (Test-Path -LiteralPath $godotUserLocal)) { New-Item -ItemType Directory -Path $godotUserLocal -Force | Out-Null }
$env:APPDATA = (Resolve-Path $godotUserRoaming).Path
$env:LOCALAPPDATA = (Resolve-Path $godotUserLocal).Path
$scenes = @(
	"res://tests/runtime_smoke.tscn",
	"res://tests/environment_visual_acceptance.tscn",
	"res://tests/environment_asset_contract_acceptance.tscn",
	"res://tests/environment_asset_production_acceptance.tscn",
	"res://tests/summit_environment_acceptance.tscn",
	"res://tests/sunset_environment_acceptance.tscn",
	"res://tests/camera_low_speed_acceptance.tscn",
	"res://tests/camera_runtime_stability_acceptance.tscn",
	"res://tests/camera_airborne_viewport_diagnostic.tscn",
	"res://tests/camera_performance_acceptance.tscn",
	"res://tests/camera_phase_performance_acceptance.tscn",
	"res://tests/clip_recorder_worker_acceptance.tscn",
	"res://tests/gameplay_acceptance.tscn",
	"res://tests/physics_benchmark.tscn",
	"res://tests/physics_collision_acceptance.tscn",
	"res://tests/settings_acceptance.tscn",
	"res://tests/animation_acceptance.tscn",
	"res://tests/character_equipment_scale_acceptance.tscn",
	"res://tests/character_presentation_acceptance.tscn",
	"res://tests/skeleton_rig_acceptance.tscn",
	"res://tests/jump_animation_acceptance.tscn",
	"res://tests/landing_animation_acceptance.tscn",
	"res://tests/rail_animation_acceptance.tscn",
	"res://tests/trick_animation_acceptance.tscn",
	"res://tests/grab_animation_acceptance.tscn",
	"res://tests/animation_silhouette_acceptance.tscn",
	"res://tests/animation_polish_acceptance.tscn",
	"res://tests/crash_recovery_acceptance.tscn",
	"res://tests/ski_feel_acceptance.tscn",
	"res://tests/flick_trick_acceptance.tscn",
	"res://tests/trick_residual_acceptance.tscn",
	"res://tests/trick_rotation_state_acceptance.tscn",
	"res://tests/air_rotation_integrator_acceptance.tscn",
	"res://tests/flick_takeoff_release_acceptance.tscn",
	"res://tests/trick_rotation_benchmark.tscn",
	"res://tests/flick_gameplay_acceptance.tscn",
	"res://tests/trick_ui_acceptance.tscn",
	"res://tests/session_flow_acceptance.tscn",
	"res://tests/ground_hover_probe.tscn",
	"res://tests/terrain_suspension_course.tscn",
	"res://tests/mp4_encoder_acceptance.tscn"
)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($scene in $scenes) {
	Write-Output "===== $scene ====="
	$stdoutPath = [System.IO.Path]::GetTempFileName()
	$stderrPath = [System.IO.Path]::GetTempFileName()
	$process = $null
	$exitCode = 1
	$output = ""
	try {
		$quotedRepoRoot = '"' + $RepoRoot.Replace('"', '\\"') + '"'
		$process = Start-Process -FilePath $godot `
			-ArgumentList @("--headless", "--path", $quotedRepoRoot, $scene) `
			-RedirectStandardOutput $stdoutPath `
			-RedirectStandardError $stderrPath `
			-WindowStyle Hidden `
			-PassThru
		if (-not $process.WaitForExit(120000)) {
			try { $process.Kill() } catch { }
			try { $process.WaitForExit() } catch { }
			$exitCode = 124
			$output = "TIMEOUT: Godot did not exit within 120 seconds."
		}
		else {
			$exitCode = $process.ExitCode
			$stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
			$stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
			$output = "$stdout$stderr"
		}
	}
	finally {
		if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath -Force }
		if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force }
	}
	Write-Output $output.TrimEnd()
	if ($exitCode -ne 0) {
		$failures.Add("$scene exited with code $exitCode")
	}
	if ($output -match '(?m)^\s*(?:SHADER ERROR|SCRIPT ERROR|ERROR:)|\b[A-Z_]+_FAIL:') {
		$failures.Add("$scene emitted an engine or acceptance error")
	}
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: all runtime scenes completed without engine, shader, script, or acceptance errors."
