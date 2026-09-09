param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$failures = [System.Collections.Generic.List[string]]::new()
$workflowPath = Join-Path $RepoRoot ".github/workflows/quality.yml"
$actionPath = Join-Path $RepoRoot ".github/actions/setup-godot/action.yml"
if (-not (Test-Path -LiteralPath $actionPath -PathType Leaf)) {
	$failures.Add("Missing shared setup-godot composite action")
}
if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
	$failures.Add("Missing quality workflow")
}
else {
	$workflow = Get-Content -LiteralPath $workflowPath -Raw
	if (($workflow | Select-String -Pattern 'uses:\s+\./\.github/actions/setup-godot' -AllMatches).Matches.Count -ne 3) {
		$failures.Add("Prepare, runtime, and export-pack jobs must use the shared Godot setup action")
	}
	if ($workflow -match 'Invoke-WebRequest|Expand-Archive|Get-FileHash') {
		$failures.Add("Godot download/checksum/extraction logic is duplicated in the workflow")
	}
	foreach ($required in @('export_pack:', '--export-pack "Windows Desktop"', '--main-pack builds\\windows\\SummitSessions.pck', 'EXPORT_PACK_RESULT')) {
		if ($workflow -notmatch [regex]::Escape($required)) {
			$failures.Add("Quality workflow is missing production pack contract: $required")
		}
	}
}
if (Test-Path -LiteralPath $actionPath -PathType Leaf) {
	$action = Get-Content -LiteralPath $actionPath -Raw
	foreach ($required in @('actions/cache@v4', 'Invoke-WebRequest', 'Get-FileHash', 'Expand-Archive', 'GODOT_PATH')) {
		if ($action -notmatch [regex]::Escape($required)) { $failures.Add("Shared action is missing $required") }
	}
}
if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}
Write-Output "PASS: Godot setup is shared/checksum-verified and CI exports/smokes the production PCK."
