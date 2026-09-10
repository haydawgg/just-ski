param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$layoutPath = Join-Path $RepoRoot "world/park_features/park_layout.gd"
$failures = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) {
	Write-Output "FAIL: park_layout.gd is missing."
	exit 1
}

$layout = (Get-Content -Raw -LiteralPath $layoutPath) -replace "`r", ""

foreach ($required in @(
	'const RENDER_SKIRT_DEPTH := 0.18',
	'var collision_mesh := _profile_grid_mesh(local_rows, normal, bury, true)',
	'var render_mesh := _profile_grid_mesh(local_rows, normal, RENDER_SKIRT_DEPTH, true)',
	'bottom.append(point - normal * bury)',
	'_add_flat_quad(st, bottom_rows[row_index][column_index], bottom_rows[row_index + 1][column_index], bottom_rows[row_index + 1][column_index + 1], bottom_rows[row_index][column_index + 1])',
	'_add_flat_quad(st, rows[row_index][0], rows[row_index + 1][0], bottom_rows[row_index + 1][0], bottom_rows[row_index][0])',
	'_add_flat_quad(st, rows[0][column_index], bottom_rows[0][column_index], bottom_rows[0][column_index + 1], rows[0][column_index + 1])',
	'(shape_node.shape as ConcavePolygonShape3D).backface_collision = true'
)) {
	if (-not $layout.Contains($required)) {
		$failures.Add("Profiled snow render/collision shell contract is missing: $required")
	}
}

if ($layout -match 'var render_mesh := _profile_grid_mesh\([^\n]+,\s*false\)') {
	$failures.Add("Profiled snow render mesh is open; backface-culling can make raised features see-through.")
}

$depthMatch = [regex]::Match($layout, '(?m)^const RENDER_SKIRT_DEPTH := ([0-9.]+)\s*$')
if (-not $depthMatch.Success) {
	$failures.Add("RENDER_SKIRT_DEPTH is missing or not a numeric constant.")
}
else {
	$depth = [double]::Parse($depthMatch.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
	if ($depth -le 0.0 -or $depth -gt 0.25) {
		$failures.Add("RENDER_SKIRT_DEPTH must remain a shallow positive skirt (0 < depth <= 0.25 m); got $depth")
	}
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: profiled snow render mesh uses a shallow closed skirt while collision retains the full shell."