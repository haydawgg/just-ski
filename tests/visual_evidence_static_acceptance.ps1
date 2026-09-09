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
}

$python = (Get-Command python -ErrorAction SilentlyContinue).Path
if ([string]::IsNullOrWhiteSpace($python)) { throw "Python is required for visual evidence schema tooling." }
& $python -m py_compile (Join-Path $RepoRoot "tests\visual_evidence_tools.py")
if ($LASTEXITCODE -ne 0) { throw "visual_evidence_tools.py did not compile." }
& $python (Join-Path $RepoRoot "tests\visual_evidence_tools.py") acceptance
if ($LASTEXITCODE -ne 0) { throw "Visual evidence negative fixture acceptance failed." }

Write-Output "VISUAL_EVIDENCE_STATIC_PASS: catalog uniqueness/shape and validator fixtures passed."
