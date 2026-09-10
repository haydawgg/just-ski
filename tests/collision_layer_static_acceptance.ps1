param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Read-RepoFile([string]$relativePath) {
	$path = Join-Path $RepoRoot $relativePath
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		$failures.Add("Missing collision contract file: $relativePath")
		return ""
	}
	return Get-Content -Raw -LiteralPath $path
}

function Require-Match([string]$text, [string]$pattern, [string]$message) {
	if ($text -notmatch $pattern) {
		$failures.Add($message)
	}
}

function Reject-Match([string]$text, [string]$pattern, [string]$message) {
	if ($text -match $pattern) {
		$failures.Add($message)
	}
}

$layers = Read-RepoFile "resources/physics/collision_layers.gd"
Require-Match $layers '(?m)^const TERRAIN\s*:=\s*1\s*<<\s*0\s*$' "Terrain collision ABI must remain bit 0 (1)."
Require-Match $layers '(?m)^const SKIER\s*:=\s*1\s*<<\s*1\s*$' "Skier collision ABI must remain bit 1 (2)."
Require-Match $layers '(?m)^const FEATURE\s*:=\s*1\s*<<\s*2\s*$' "Feature collision ABI must remain bit 2 (4)."
Require-Match $layers '(?m)^const BOUNDARY\s*:=\s*FEATURE\s*$' "Boundary collisions must continue to share the Feature layer."
Require-Match $layers '(?m)^const GRIND\s*:=\s*1\s*<<\s*3\s*$' "Grind collision ABI must remain bit 3 (8)."
Require-Match $layers '(?m)^const WORLD_SOLID_MASK\s*:=\s*TERRAIN\s*\|\s*FEATURE\s*$' "World-solid queries must remain Terrain | Feature."
Require-Match $layers '(?m)^const SKIER_COLLISION_MASK\s*:=\s*WORLD_SOLID_MASK\s*$' "Skier mask must retain Terrain | Feature."
Require-Match $layers '(?m)^const CAMERA_COLLISION_MASK\s*:=\s*WORLD_SOLID_MASK\s*$' "Camera mask must retain Terrain | Feature and exclude Grind."
Require-Match $layers '(?m)^const GRIND_COLLISION_MASK\s*:=\s*SKIER\s*$' "Grind rail bodies must continue to target the Skier layer."

$grindSolver = Read-RepoFile "player/motion/grind_collision_solver.gd"
Require-Match $grindSolver 'CollisionLayers\.FEATURE' "Grind collision solver must use the shared Feature layer."
Reject-Match $grindSolver '(?m)^const FEATURE_MASK\s*:=\s*4\s*$' "Grind collision solver reintroduced a private Feature mask."

$cameraSolver = Read-RepoFile "player/camera/camera_collision_solver.gd"
Require-Match $cameraSolver 'collision_mask\s*:=\s*CollisionLayers\.CAMERA_COLLISION_MASK' "Camera collision solver must default to the shared camera mask."
Reject-Match $cameraSolver 'collision_mask\s*:=\s*1\s*\|\s*4' "Camera collision solver reintroduced a numeric Terrain | Feature mask."

$rail = Read-RepoFile "world/park_features/grind_rail_3d.gd"
Require-Match $rail 'collision_layer\s*=\s*CollisionLayers\.GRIND' "Grind rails must use the shared Grind layer."
Require-Match $rail 'collision_mask\s*=\s*CollisionLayers\.GRIND_COLLISION_MASK' "Grind rails must use the shared skier-target mask."
Reject-Match $rail 'collision_layer\s*=\s*8' "Grind rail numeric layer assignment bypasses the shared ABI."

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: collision-layer ABI and migrated production users are centralized without numeric drift."
