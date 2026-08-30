param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$godot = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
	Write-Output "FAIL: Godot console executable was not found: $godot"
	exit 1
}

$env:APPDATA = (Resolve-Path (Join-Path $RepoRoot ".godot_user/roaming")).Path
$env:LOCALAPPDATA = (Resolve-Path (Join-Path $RepoRoot ".godot_user/local")).Path
$scenes = @(
	"res://tests/runtime_smoke.tscn",
	"res://tests/environment_visual_acceptance.tscn",
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
	# Godot writes shutdown warnings to stderr. Capture those for inspection without
	# letting PowerShell promote a warning record into a terminating script error.
	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try {
		$output = & $godot --headless --path $RepoRoot $scene 2>&1 | Out-String
	}
	finally {
		$ErrorActionPreference = $previousErrorActionPreference
	}
	$exitCode = $LASTEXITCODE
	Write-Output $output.TrimEnd()
	if ($exitCode -ne 0) {
		$failures.Add("$scene exited with code $exitCode")
	}
	if ($output -match '(?m)^(?:SHADER ERROR|SCRIPT ERROR|ERROR:)|\b[A-Z_]+_FAIL:') {
		$failures.Add("$scene emitted an engine or acceptance error")
	}
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: all runtime scenes completed without engine, shader, script, or acceptance errors."
