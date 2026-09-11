param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$project = Get-Content -Raw (Join-Path $RepoRoot "project.godot")
$graphics = Get-Content -Raw (Join-Path $RepoRoot "docs/GRAPHICS.md")
$contentDesign = Get-Content -Raw (Join-Path $RepoRoot "docs/CONTENT_DESIGN_PLAN.md")
$knownIssues = Get-Content -Raw (Join-Path $RepoRoot "docs/KNOWN_ISSUES.md")
$animationDoc = Get-Content -Raw (Join-Path $RepoRoot "docs/ANIMATION.md")
$docsIndex = Get-Content -Raw (Join-Path $RepoRoot "docs/README.md")
$settings = Get-Content -Raw (Join-Path $RepoRoot "autoload/game_settings.gd")
$resort = Get-Content -Raw (Join-Path $RepoRoot "world/resort.gd")
$workflow = Get-Content -Raw (Join-Path $RepoRoot ".github/workflows/quality.yml")
$runtimeGate = Get-Content -Raw (Join-Path $RepoRoot "tests/runtime_quality_gate.ps1")
$gitignore = (Get-Content -Raw (Join-Path $RepoRoot ".gitignore")) -replace "`r", ""
$performanceBaselinePath = Join-Path $RepoRoot "docs/PERFORMANCE_BASELINE_1080P.md"
$controllerValidationPath = Join-Path $RepoRoot "docs/CONTROLLER_VALIDATION.md"
$themePath = Join-Path $RepoRoot "ui/theme/summit_theme.tres"
$fontPath = Join-Path $RepoRoot "assets/ui/fonts/Inter-4.1-Variable.ttf"
$fontSourcePath = Join-Path $RepoRoot "assets/ui/fonts/SOURCE.md"
$fontLicensePath = Join-Path $RepoRoot "assets/ui/fonts/OFL-1.1.txt"
$failures = [System.Collections.Generic.List[string]]::new()

function Get-ProjectValue([string]$key) {
	$match = [regex]::Match($project, '(?m)^' + [regex]::Escape($key) + '=([^\r\n]+)(?:\r?$)')
	if (-not $match.Success) { throw "Missing project.godot value: $key" }
	return $match.Groups[1].Value.Trim()
}

$viewportWidth = Get-ProjectValue "window/size/viewport_width"
$viewportHeight = Get-ProjectValue "window/size/viewport_height"
$overrideWidth = Get-ProjectValue "window/size/window_width_override"
$overrideHeight = Get-ProjectValue "window/size/window_height_override"
$windowMode = Get-ProjectValue "window/size/mode"

if ($graphics -notmatch '`project\.godot` is the source of truth') {
	$failures.Add("GRAPHICS.md does not identify project.godot as the display configuration source of truth.")
}
if ($graphics -notmatch ([regex]::Escape("${viewportWidth}×${viewportHeight}"))) {
	$failures.Add("GRAPHICS.md does not document the project viewport ${viewportWidth}×${viewportHeight}.")
}
if ($graphics -notmatch ([regex]::Escape("${overrideWidth}×${overrideHeight}"))) {
	$failures.Add("GRAPHICS.md does not document the project window override ${overrideWidth}×${overrideHeight}.")
}
if ($windowMode -eq "3" -and $graphics -notmatch "fullscreen") {
	$failures.Add("GRAPHICS.md does not document fullscreen startup for project window mode 3.")
}
if ($settings -notmatch '"gi_enabled"\s*:\s*true' -or $settings -notmatch '"gi_enabled",\s*"units_mph"') {
	$failures.Add("GameSettings does not define a persisted GI default and validation path.")
}
if ($settings -notmatch 'graphics_preset_allows_gi' -or $settings -notmatch 'key != "graphics_preset" and key in RENDERER_SETTING_KEYS') {
	$failures.Add("GameSettings does not expose the explicit GI preset/custom policy.")
}
if ($resort -notmatch 'resolve_effective_gi' -or $resort -notmatch 'effective_gi_enabled') {
	$failures.Add("Resort does not expose the canonical profile/user/preset GI resolver.")
}
if ($graphics -notmatch 'gi_enabled' -or $graphics -notmatch 'Low and Medium forbid it') {
	$failures.Add("GRAPHICS.md does not document the profile/user/preset GI ownership model.")
}

foreach ($requiredContentText in @(
	"maintained course/content design contract",
	"human-only",
	"six stable main-resort spots",
	"ParkFeatureSpec",
	"Session Yard",
	"Fix geometry before physics"
)) {
	if ($contentDesign -notmatch [regex]::Escape($requiredContentText)) {
		$failures.Add("CONTENT_DESIGN_PLAN.md is missing current design/status text: $requiredContentText")
	}
}
if ($contentDesign -match 'The best first code/content change' -or $contentDesign -match '(?m)^# Milestone [0-9]') {
	$failures.Add("CONTENT_DESIGN_PLAN.md still contains superseded implementation-roadmap framing.")
}
if ($knownIssues -notmatch 'concrete, actionable bugs and missing functionality' -or $knownIssues -notmatch 'Resolved items.*relevant project docs') {
	$failures.Add("KNOWN_ISSUES.md must track actionable issues and direct resolved status to the project docs.")
}
if ($graphics -notmatch 'environment_visual_quality_gate.ps1' -or $graphics -notmatch 'shutdown leaks' -or $graphics -notmatch 'human visual review') {
	$failures.Add("GRAPHICS.md is missing the deterministic capture gate, shutdown failure policy, or human review boundary.")
}
if ($animationDoc -notmatch 'capture-animation-presentation-audit' -or $animationDoc -notmatch '30\s*,\s*60\s*,\s*and\s*120' -or $animationDoc -notmatch 'human-only gates') {
	$failures.Add("ANIMATION.md does not document the multi-rate presentation audit and deferred human gates.")
}

foreach ($requiredDocsPolicyText in @(
	"not an archive of implementation history",
	"dated postmortems",
	"pull request",
	"stable behavior and current status"
)) {
	if ($docsIndex -notmatch [regex]::Escape($requiredDocsPolicyText)) {
		$failures.Add("docs/README.md is missing documentation-policy text: $requiredDocsPolicyText")
	}
}
foreach ($obsoletePath in @(
	"docs/BASELINE.md",
	"docs/CONTENT_PASS_IMPLEMENTATION.md",
	"docs/ANIMATION_OWNERSHIP_ROOT_CAUSE.md",
	"docs/VISUAL_QUALITY_FIXES.md",
	"docs/LICENSING_DECISION.md",
	"docs/history"
)) {
	if (Test-Path -LiteralPath (Join-Path $RepoRoot $obsoletePath)) {
		$failures.Add("Obsolete documentation path should not be restored: $obsoletePath")
	}
}

if ($project -notmatch 'theme/custom="res://ui/theme/summit_theme\.tres"') {
	$failures.Add("project.godot does not select the project-wide UI theme.")
}
foreach ($requiredUiAsset in @($themePath, $fontPath, $fontSourcePath, $fontLicensePath)) {
	if (-not (Test-Path -LiteralPath $requiredUiAsset -PathType Leaf)) {
		$failures.Add("Missing required UI theme/font asset: $requiredUiAsset")
	}
}
if (Test-Path -LiteralPath $fontPath -PathType Leaf) {
	$fontHash = (Get-FileHash -LiteralPath $fontPath -Algorithm SHA256).Hash
	if ($fontHash -ne "4989B125924991B90D05B2D16E0E388C48F7D5BB8B30539BBF9C755278D0CCAF") {
		$failures.Add("Pinned Inter 4.1 font checksum changed unexpectedly.")
	}
}
if (Test-Path -LiteralPath $fontSourcePath -PathType Leaf) {
	$fontSource = Get-Content -Raw -LiteralPath $fontSourcePath
	if ($fontSource -notmatch 'Inter 4\.1' -or $fontSource -notmatch 'SIL Open Font License 1\.1' -or $fontSource -notmatch '4989B125924991B90D05B2D16E0E388C48F7D5BB8B30539BBF9C755278D0CCAF') {
		$failures.Add("UI font source record is missing its pinned version, license, or checksum.")
	}
}

if ($workflow -notmatch 'windows-2025' -or $workflow -notmatch 'actions/cache@v4' -or $workflow -notmatch '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953') {
	$failures.Add("Quality Gate workflow is missing the pinned Windows/Godot cache contract.")
}
if ($workflow -notmatch '(?m)^  static:' -or $workflow -notmatch '(?m)^  runtime:' -or $workflow -notmatch '(?m)^  quality:') {
	$failures.Add("Quality Gate workflow is missing separate static, runtime, and required quality jobs.")
}
foreach ($requiredShard in @("environment-camera", "physics", "animation", "tricks-gameplay", "systems-media")) {
	if ($workflow -notmatch ([regex]::Escape("- $requiredShard"))) {
		$failures.Add("Quality Gate workflow is missing runtime shard $requiredShard.")
	}
}
if ($workflow -notmatch 'hashFiles\([^\r\n]*project\.godot' -or $workflow -notmatch '\.godot/imported') {
	$failures.Add("Quality Gate workflow is missing the project import-state cache keyed from project/assets.")
}
if ($workflow -notmatch 'if: \$\{\{ always\(\) \}\}' -or $workflow -notmatch 'needs\.runtime\.result') {
	$failures.Add("Quality Gate workflow is missing the final all-shards quality aggregator.")
}
if ($runtimeGate -notmatch '\[System\.Environment\]::GetEnvironmentVariable\("GODOT_PATH"\)' -or $runtimeGate -notmatch 'Copy-CaptureArtifacts') {
	$failures.Add("Runtime quality gate is missing GODOT_PATH resolution or capture preservation.")
}
if ($runtimeGate -notmatch '\[string\]\$Shard' -or $runtimeGate -notmatch 'RUNTIME_SHARD' -or $runtimeGate -notmatch 'PASS \{0\} .*\{1\}s') {
	$failures.Add("Runtime quality gate is missing shard selection or per-scene timing output.")
}
if ($gitignore -notmatch '(?m)^\.godot_logs/$' -or $gitignore -notmatch '(?m)^\.tmp_male_base_mesh/$') {
	$failures.Add("Generated runtime output and the removed temporary asset directory are not ignored.")
}

if (-not (Test-Path -LiteralPath $performanceBaselinePath -PathType Leaf)) {
	$failures.Add("docs/PERFORMANCE_BASELINE_1080P.md is missing.")
}
else {
	$performanceBaseline = Get-Content -Raw $performanceBaselinePath
	foreach ($requiredBaselineText in @("Measurement contract", "Current discrete-GPU matrix", "Integrated-GPU validation", "Regression policy", "16.67 ms")) {
		if ($performanceBaseline -notmatch [regex]::Escape($requiredBaselineText)) {
			$failures.Add("PERFORMANCE_BASELINE_1080P.md is missing required content: $requiredBaselineText")
		}
	}
}
if (-not (Test-Path -LiteralPath $controllerValidationPath -PathType Leaf)) {
	$failures.Add("docs/CONTROLLER_VALIDATION.md is missing.")
}
else {
	$controllerValidation = Get-Content -Raw $controllerValidationPath
	foreach ($requiredControllerText in @("Xbox", "PlayStation", "lowest connected ID", "rumble", "Pending: no physical gamepad was connected")) {
		if ($controllerValidation -notmatch [regex]::Escape($requiredControllerText)) {
			$failures.Add("docs/CONTROLLER_VALIDATION.md is missing required hardware-validation coverage: $requiredControllerText")
		}
	}
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: project configuration and maintained documentation contracts agree."
