param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$catalogPath = Join-Path $RepoRoot "tests\visual_scenarios.json"
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
if ($catalog.schema_version -ne "visual-scenarios-v1") { throw "Visual scenario catalog has the wrong schema version." }
if ([int]$catalog.capture_size.width -le 0 -or [int]$catalog.capture_size.height -le 0) { throw "Visual scenario catalog capture size is invalid." }

$ids = @($catalog.scenarios | ForEach-Object { [string]$_.id })
$duplicates = @($ids | Group-Object | Where-Object { $_.Count -gt 1 })
if ($duplicates.Count -gt 0) { throw "Visual scenario catalog contains duplicate IDs: $($duplicates.Name -join ', ')" }
$requiredProperties = @("id", "suite", "label", "state", "phase", "view", "capture_key", "required_artifacts", "roi", "masks", "capture_timing", "semantic_checks", "human_review")
foreach ($scenario in @($catalog.scenarios)) {
	foreach ($property in $requiredProperties) {
		if ($null -eq $scenario.PSObject.Properties[$property]) { throw "Visual scenario $($scenario.id) is missing $property." }
	}
	if ($scenario.roi.type -ne "normalized_rect") { throw "Visual scenario $($scenario.id) ROI is not normalized_rect." }
	$baselineId = [string]$scenario.baseline_id
	if (-not [string]::IsNullOrWhiteSpace($baselineId)) {
		$safeSuite = ([string]$scenario.suite -replace '[^A-Za-z0-9_-]', '_').Trim('_').ToLowerInvariant()
		$safeBaseline = ($baselineId -replace '[^A-Za-z0-9_-]', '_').Trim('_').ToLowerInvariant()
		$baselineRoot = Join-Path $RepoRoot ("tests\visual_baselines\$safeSuite")
		$imagePath = Join-Path $baselineRoot "$safeBaseline.png"
		$metadataPath = Join-Path $baselineRoot "$safeBaseline.json"
		if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
			throw "Declared visual baseline is missing its PNG/JSON pair: $($scenario.suite)/$baselineId"
		}
	}
}

$rampScenarioIds = @(
	"environment.ramp_texture.approach",
	"environment.ramp_texture.lip",
	"environment.ramp_texture.deck",
	"environment.ramp_texture.landing",
	"environment.ramp_texture.roller",
	"environment.ramp_texture.berm",
	"environment.ramp_texture.side_hit"
)
foreach ($rampScenarioId in $rampScenarioIds) {
	$rampScenario = @($catalog.scenarios | Where-Object { $_.id -eq $rampScenarioId })
	if ($rampScenario.Count -ne 1) { throw "Ramp surface scenario is missing from the catalog: $rampScenarioId" }
	if ($rampScenario[0].state -ne "RAMP_TEXTURE" -or $rampScenario[0].view -ne "gameplay") { throw "Ramp surface scenario has the wrong state/view contract: $rampScenarioId" }
	$requiredRampArtifacts = @($rampScenario[0].required_artifacts | ForEach-Object { [string]$_ })
	foreach ($requiredArtifact in @("raw", "telemetry")) {
		if ($requiredRampArtifacts -notcontains $requiredArtifact) { throw "Ramp surface scenario $rampScenarioId is missing required artifact role $requiredArtifact." }
	}
}
foreach ($rampFile in @(
	"tests\ramp_surface_visual_inspection.gd",
	"tests\ramp_surface_visual_inspection.tscn",
	"tests\ramp_surface_visual_quality_gate.ps1"
)) {
	if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $rampFile) -PathType Leaf)) { throw "Ramp surface visual acceptance file is missing: $rampFile" }
}

$python = (Get-Command python -ErrorAction SilentlyContinue).Path
if ([string]::IsNullOrWhiteSpace($python)) { throw "Python is required for visual evidence schema tooling." }
& $python -m py_compile (Join-Path $RepoRoot "tests\visual_evidence_tools.py")
if ($LASTEXITCODE -ne 0) { throw "visual_evidence_tools.py did not compile." }
& $python (Join-Path $RepoRoot "tests\visual_evidence_tools.py") acceptance
if ($LASTEXITCODE -ne 0) { throw "Visual evidence negative fixture acceptance failed." }

Write-Output "VISUAL_EVIDENCE_STATIC_PASS: catalog uniqueness/shape and validator fixtures passed."
