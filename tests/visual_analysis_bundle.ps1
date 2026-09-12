param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$GodotPath = "",
	[string]$PythonPath = "",
	[ValidateSet("all", "environment", "animation", "sunset")]
	[string]$Suite = "all",
	[string]$BundlePath = "",
	[int]$Preset = 2,
	[double]$RenderScale = 1.0,
	[int]$FixedFps = 60,
	[int]$GpuIndex = -1,
	[int]$TimeoutSeconds = 180,
	[string[]]$AnimationAuditRates = @("30", "60", "120"),
	[string[]]$Environments = @(),
	[double[]]$RenderScales = @(),
	[int]$MotionDurationSeconds = 10,
	[switch]$IncludeMotion,
	[switch]$IncludeRecovery,
	[switch]$SkipAnimationAudit,
	[switch]$UpdateBaselines,
	[switch]$AllowDirtyBaseline,
	[switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Test-PathWithin {
	param([string]$Candidate, [string]$Parent)
	$candidatePath = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([char]92, [char]47)
	$parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd([char]92, [char]47)
	return $candidatePath.Equals($parentPath, [System.StringComparison]::OrdinalIgnoreCase) -or $candidatePath.StartsWith($parentPath + [char]92, [System.StringComparison]::OrdinalIgnoreCase) -or $candidatePath.StartsWith($parentPath + [char]47, [System.StringComparison]::OrdinalIgnoreCase)
}

function Quote-ProcessArgument {
	param([string]$Value)
	$escaped = $Value.Replace('"', '\"')
	return '"' + $escaped + '"'
}

function Invoke-CapturedProcess {
	param(
		[string]$Executable,
		[string[]]$Arguments,
		[string]$StdoutPath,
		[string]$StderrPath,
		[int]$TimeoutSeconds
	)
	$stdoutParent = Split-Path -Parent $StdoutPath
	$stderrParent = Split-Path -Parent $StderrPath
	New-Item -ItemType Directory -Path $stdoutParent,$stderrParent -Force | Out-Null
	$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $Executable
	$startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " ")
	$startInfo.WorkingDirectory = $RepoRoot
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
			[System.IO.File]::WriteAllText($StdoutPath, "")
			[System.IO.File]::WriteAllText($StderrPath, "Could not start process.")
			return [pscustomobject]@{ ExitCode = 1; Output = "Could not start process."; TimedOut = $false }
		}
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()
		if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
			try { $process.Kill($true) } catch { try { & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null } catch { } }
			try { $process.WaitForExit() } catch { }
			$stdout = if ($null -ne $stdoutTask) { $stdoutTask.GetAwaiter().GetResult() } else { "" }
			$stderr = if ($null -ne $stderrTask) { $stderrTask.GetAwaiter().GetResult() } else { "" }
			[System.IO.File]::WriteAllText($StdoutPath, $stdout)
			[System.IO.File]::WriteAllText($StderrPath, $stderr)
			return [pscustomobject]@{ ExitCode = 124; Output = "TIMEOUT: process exceeded $TimeoutSeconds seconds.`n$stdout$stderr"; TimedOut = $true }
		}
		$process.WaitForExit()
		$exitCode = [int]$process.ExitCode
		$stdout = $stdoutTask.GetAwaiter().GetResult()
		$stderr = $stderrTask.GetAwaiter().GetResult()
		[System.IO.File]::WriteAllText($StdoutPath, $stdout)
		[System.IO.File]::WriteAllText($StderrPath, $stderr)
		return [pscustomobject]@{ ExitCode = $exitCode; Output = "$stdout$stderr"; TimedOut = $false }
	}
	catch {
		$message = "Process failed: $($_.Exception.Message)"
		[System.IO.File]::WriteAllText($StdoutPath, "")
		[System.IO.File]::WriteAllText($StderrPath, $message)
		return [pscustomobject]@{ ExitCode = 1; Output = $message; TimedOut = $false }
	}
	finally {
		$process.Dispose()
	}
}

function Get-ProjectPath {
	param([string]$Path)
	# Windows PowerShell/.NET Framework does not expose Path.GetRelativePath;
	# URI-relative paths keep the bundle runnable on both supported hosts.
	$rootPath = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd([char]92, [char]47) + [char]92
	$candidatePath = [System.IO.Path]::GetFullPath($Path)
	$rootUri = New-Object System.Uri($rootPath)
	$candidateUri = New-Object System.Uri($candidatePath)
	$relative = [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($candidateUri).ToString()).Replace([char]92, [char]47)
	return "res://$relative"
}

function Get-SafeLabel {
	param([string]$Value)
	$result = $Value -replace '[^A-Za-z0-9_-]', '_'
	return $result.Trim('_').ToLowerInvariant()
}

function Write-SuiteFailureManifest {
	param(
		[string]$Path,
		[string]$SuiteName,
		[hashtable]$Context,
		[string]$Message,
		[int]$ExitCode = 1
	)
	$payload = [ordered]@{
		schema_version = "visual-evidence-v1"
		suite = $SuiteName
		started_at_utc = [DateTime]::UtcNow.ToString("o")
		finished_at_utc = [DateTime]::UtcNow.ToString("o")
		status = "missing"
		exit_code = $ExitCode
		context = $Context
		scenarios = @()
		artifacts = @()
		telemetry = @()
		checks = @([ordered]@{ id = "$SuiteName.capture.process"; kind = "capture"; status = "missing"; value = $null; threshold = $null; message = $Message })
		review_items = @()
		errors = @($Message)
	}
	New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
	[System.IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 30))
}

function Mark-SuiteFailureManifest {
	param(
		[string]$Path,
		[string]$SuiteName,
		[string]$Message,
		[int]$ExitCode = 1
	)
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		Write-SuiteFailureManifest -Path $Path -SuiteName $SuiteName -Context @{} -Message $Message -ExitCode $ExitCode
		return
	}
	try {
		$manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
		$manifest.status = "fail"
		$manifest.exit_code = $ExitCode
		$errors = [System.Collections.ArrayList]::new()
		foreach ($error in @($manifest.errors)) { [void]$errors.Add($error) }
		[void]$errors.Add($Message)
		$manifest.errors = $errors.ToArray()
		$checks = [System.Collections.ArrayList]::new()
		foreach ($check in @($manifest.checks)) { [void]$checks.Add($check) }
		[void]$checks.Add([ordered]@{
			id = "$SuiteName.capture.process"
			kind = "capture"
			status = "fail"
			value = $ExitCode
			threshold = 0
			message = $Message
		})
		$manifest.checks = $checks.ToArray()
		[System.IO.File]::WriteAllText($Path, ($manifest | ConvertTo-Json -Depth 30))
	}
	catch {
		Write-SuiteFailureManifest -Path $Path -SuiteName $SuiteName -Context @{} -Message $Message -ExitCode $ExitCode
	}
}

function Add-MetricResult {
	param(
		[string]$ManifestPath,
		[string]$CheckId,
		[string]$MetricName,
		[int]$ExitCode,
		[string]$LogPath
	)
	if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return }
	$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
	$checks = [System.Collections.ArrayList]::new()
	foreach ($check in @($manifest.checks)) { [void]$checks.Add($check) }
	[void]$checks.Add([ordered]@{
		id = $CheckId
		kind = "deterministic_metric"
		status = if ($ExitCode -eq 0) { "pass" } else { "fail" }
		value = $null
		threshold = $null
		message = "$MetricName exit code $ExitCode; log: $LogPath"
	})
	$manifest.checks = $checks.ToArray()
	if ($ExitCode -ne 0) {
		$manifest.status = "fail"
		$manifest.exit_code = $ExitCode
		$errors = [System.Collections.ArrayList]::new()
		foreach ($error in @($manifest.errors)) { [void]$errors.Add($error) }
		[void]$errors.Add("$MetricName failed; log: $LogPath")
		$manifest.errors = $errors.ToArray()
	}
	[System.IO.File]::WriteAllText($ManifestPath, ($manifest | ConvertTo-Json -Depth 30))
}

if (-not $ValidateOnly) {
	if ([string]::IsNullOrWhiteSpace($GodotPath)) {
		$GodotPath = [System.Environment]::GetEnvironmentVariable("GODOT_GUI_PATH")
		if ([string]::IsNullOrWhiteSpace($GodotPath)) {
			$GodotPath = Join-Path $RepoRoot ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
		}
	}
	$GodotPath = (Resolve-Path -LiteralPath $GodotPath -ErrorAction SilentlyContinue).Path
	if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
		throw "Godot GUI executable was not found. Pass -GodotPath or set GODOT_GUI_PATH."
	}
}

if ([string]::IsNullOrWhiteSpace($PythonPath)) {
	$PythonPath = [System.Environment]::GetEnvironmentVariable("PYTHON")
	if ([string]::IsNullOrWhiteSpace($PythonPath)) { $PythonPath = "python" }
}
if ($Preset -lt 0 -or $Preset -gt 3) { throw "Preset must be 0 (Low), 1 (Medium), 2 (High), or 3 (Ultra)." }
if ($RenderScale -lt 0.5 -or $RenderScale -gt 1.5) { throw "RenderScale must be between 0.5 and 1.5." }
if ($FixedFps -lt 0 -or $FixedFps -gt 240) { throw "FixedFps must be between 0 and 240." }
if ($TimeoutSeconds -lt 1) { throw "TimeoutSeconds must be positive." }
if ($MotionDurationSeconds -lt 1 -or $MotionDurationSeconds -gt 30) { throw "MotionDurationSeconds must be between 1 and 30." }

# PowerShell's -File binder treats a comma-delimited array differently across
# hosts. Normalize both `30,60,120` and `30 60 120` before validation.
$normalizedAuditRates = [System.Collections.Generic.List[int]]::new()
foreach ($rateToken in @($AnimationAuditRates)) {
	foreach ($ratePart in ([string]$rateToken -split ',')) {
		if ([string]::IsNullOrWhiteSpace($ratePart)) { continue }
		$parsedRate = 0
		if (-not [int]::TryParse($ratePart.Trim(), [ref]$parsedRate)) {
			throw "Animation audit rate '$ratePart' is not an integer."
		}
		[void]$normalizedAuditRates.Add($parsedRate)
	}
}
$AnimationAuditRates = $normalizedAuditRates.ToArray()
foreach ($rate in $AnimationAuditRates) {
	$rateValue = [int]$rate
	if ($rateValue -lt 1 -or $rateValue -gt 240) { throw "Animation audit rates must be between 1 and 240." }
}

$normalizedEnvironments = [System.Collections.Generic.List[string]]::new()
foreach ($environmentToken in @($Environments)) {
	foreach ($environmentPart in ([string]$environmentToken -split ',')) {
		if ([string]::IsNullOrWhiteSpace($environmentPart)) { continue }
		$environmentName = $environmentPart.Trim().ToLowerInvariant()
		if ($environmentName -notin @("daytime", "golden", "sunset")) { throw "Environment '$environmentName' must be daytime, golden, or sunset." }
		if (-not $normalizedEnvironments.Contains($environmentName)) { [void]$normalizedEnvironments.Add($environmentName) }
	}
}
$matrixEnvironments = if ($normalizedEnvironments.Count -gt 0) { $normalizedEnvironments.ToArray() } else { @("daytime") }
$normalizedRenderScales = [System.Collections.Generic.List[double]]::new()
foreach ($scaleToken in @($RenderScales)) {
	foreach ($scalePart in ([string]$scaleToken -split ',')) {
		if ([string]::IsNullOrWhiteSpace($scalePart)) { continue }
		$parsedScale = 0.0
		if (-not [double]::TryParse($scalePart.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedScale)) {
			throw "Render scale '$scalePart' is not numeric."
		}
		if ($parsedScale -lt 0.5 -or $parsedScale -gt 1.5) { throw "Render scales must be between 0.5 and 1.5." }
		if (-not $normalizedRenderScales.Contains($parsedScale)) { [void]$normalizedRenderScales.Add($parsedScale) }
	}
}
$matrixRenderScales = if ($normalizedRenderScales.Count -gt 0) { $normalizedRenderScales.ToArray() } else { @($RenderScale) }

$catalogPath = Join-Path $RepoRoot "tests\visual_scenarios.json"
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$visualRunsRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".godot_user\visual_runs"))
$runId = "visual_{0}_{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")), ((& git -C $RepoRoot rev-parse --short HEAD 2>$null).Trim())
if ($runId.EndsWith('_')) { $runId += "unknown" }

if ([string]::IsNullOrWhiteSpace($BundlePath)) {
	$BundlePath = Join-Path $visualRunsRoot $runId
}
elseif ($BundlePath.StartsWith("res://", [System.StringComparison]::OrdinalIgnoreCase)) {
	$BundlePath = Join-Path $RepoRoot ($BundlePath.Substring(6).Replace('/', [char]92))
}
$BundlePath = [System.IO.Path]::GetFullPath($BundlePath)
if (-not (Test-PathWithin $BundlePath $visualRunsRoot)) {
	throw "BundlePath must be contained by $visualRunsRoot"
}

if ($ValidateOnly) {
	if (-not (Test-Path -LiteralPath $BundlePath -PathType Container)) { throw "BundlePath was not found: $BundlePath" }
	$validateArgs = @("$RepoRoot\tests\visual_evidence_tools.py", "validate", "--repo-root", $RepoRoot, "--bundle", $BundlePath)
	& $PythonPath @validateArgs
	exit $LASTEXITCODE
}

if (Test-Path -LiteralPath $BundlePath) {
	$existing = Get-ChildItem -LiteralPath $BundlePath -Force -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $existing) { throw "BundlePath is not empty; choose a new run directory: $BundlePath" }
}
New-Item -ItemType Directory -Path $BundlePath,(Join-Path $BundlePath "suites"),(Join-Path $BundlePath "contact_sheets"),(Join-Path $BundlePath "artifacts"),(Join-Path $BundlePath "telemetry"),(Join-Path $BundlePath "diffs"),(Join-Path $BundlePath "logs") -Force | Out-Null

$commit = (& git -C $RepoRoot rev-parse HEAD 2>$null).Trim()
if ([string]::IsNullOrWhiteSpace($commit)) { $commit = "unknown" }
$branch = (& git -C $RepoRoot branch --show-current 2>$null).Trim()
$statusText = (& git -C $RepoRoot status --porcelain --untracked-files=normal 2>$null | Out-String).Trim()
$dirty = -not [string]::IsNullOrWhiteSpace($statusText)
$shortCommit = if ($commit.Length -ge 12) { $commit.Substring(0, 12) } else { $commit }
$expectedScenarioIds = @($catalog.scenarios | Where-Object {
	$suiteMatches = $Suite -eq "all" -or $_.suite -eq $Suite
	$scenarioId = [string]$_.id
	$optionalMotion = $scenarioId.StartsWith("environment.motion.", [System.StringComparison]::OrdinalIgnoreCase)
	$optionalRecovery = $scenarioId.StartsWith("environment.recovery.", [System.StringComparison]::OrdinalIgnoreCase)
	$suiteMatches -and ((-not $optionalMotion -and -not $optionalRecovery) -or ($optionalMotion -and $IncludeMotion.IsPresent) -or ($optionalRecovery -and $IncludeRecovery.IsPresent))
} | ForEach-Object { [string]$_.id })
$presetNames = @("low", "medium", "high", "ultra")
$presetName = $presetNames[$Preset]
$commandText = [string]$MyInvocation.Line
if ([string]::IsNullOrWhiteSpace($commandText)) {
	$commandParts = [System.Collections.Generic.List[string]]::new()
	[void]$commandParts.Add("pwsh")
	[void]$commandParts.Add("-NoProfile")
	[void]$commandParts.Add("-File")
	[void]$commandParts.Add((Quote-ProcessArgument $PSCommandPath))
	foreach ($parameterName in ($PSBoundParameters.Keys | Sort-Object)) {
		$value = $PSBoundParameters[$parameterName]
		if ($value -is [System.Management.Automation.SwitchParameter]) {
			if ($value.IsPresent) { [void]$commandParts.Add("-$parameterName") }
			continue
		}
		$valueText = if ($value -is [System.Array]) { (@($value) -join ",") } else { [string]$value }
		[void]$commandParts.Add("-$parameterName")
		[void]$commandParts.Add((Quote-ProcessArgument $valueText))
	}
	$commandText = $commandParts -join " "
}
$runContext = [ordered]@{
	schema_version = "visual-evidence-v1"
	run_id = $runId
	started_at_utc = [DateTime]::UtcNow.ToString("o")
	git = [ordered]@{ commit = $commit; short_commit = $shortCommit; branch = $branch; working_tree_dirty = $dirty }
	godot = [ordered]@{ executable = $GodotPath; version = "4.7.2" }
	renderer = "Forward Plus"
	gpu = "captured in each Godot suite manifest"
	resolution = @(1280, 720)
	render_scale = $RenderScale
	preset = $presetName
	environment = if ($Suite -eq "sunset") { "sunset" } else { "daytime" }
	fixed_fps = $FixedFps
	seed = 0
	command = $commandText
	suite_selection = $Suite
	expected_scenarios = $expectedScenarioIds
	bundle_root = $BundlePath
	baseline_policy = "curated baselines only; visual diffs are advisory"
	skip_animation_audit = $SkipAnimationAudit.IsPresent
	environment_matrix = $matrixEnvironments
	render_scale_matrix = $matrixRenderScales
	motion_duration_s = $MotionDurationSeconds
	include_motion = $IncludeMotion.IsPresent
	include_recovery = $IncludeRecovery.IsPresent
}
[System.IO.File]::WriteAllText((Join-Path $BundlePath "run_context.json"), ($runContext | ConvertTo-Json -Depth 30))

$userDataRoot = Join-Path $BundlePath "user_data"
$roaming = Join-Path $userDataRoot "roaming"
$local = Join-Path $userDataRoot "local"
New-Item -ItemType Directory -Path $roaming,$local -Force | Out-Null
$env:APPDATA = (Resolve-Path -LiteralPath $roaming).Path
$env:LOCALAPPDATA = (Resolve-Path -LiteralPath $local).Path

function Invoke-VisualCapture {
	param(
		[string]$SuiteName,
		[string]$VariantName,
		[string]$Scene,
		[int]$CaptureFps,
		[string[]]$UserArguments,
		[string]$EnvironmentName = "daytime",
		[double]$CaptureRenderScale = $RenderScale,
		[string]$CapturePreset = $presetName
	)
	$variantRoot = Join-Path (Join-Path $BundlePath "suites") (Join-Path (Get-SafeLabel $SuiteName) (Get-SafeLabel $VariantName))
	New-Item -ItemType Directory -Path (Join-Path $variantRoot "logs") -Force | Out-Null
	$evidenceRoot = Get-ProjectPath $variantRoot
	$stdoutPath = Join-Path $variantRoot "logs\godot.stdout.log"
	$stderrPath = Join-Path $variantRoot "logs\godot.stderr.log"
	$engineArguments = @()
	if ($CaptureFps -gt 0) { $engineArguments += @("--fixed-fps", $CaptureFps) }
	$engineArguments += @("--resolution", "1280x720")
	if ($GpuIndex -ge 0) { $engineArguments += @("--gpu-index", $GpuIndex) }
	$engineArguments += @("--path", $RepoRoot, $Scene, "--")
	$engineArguments += @(
		"--evidence-root=$evidenceRoot",
		"--fixed-fps=$CaptureFps",
		"--clean-capture",
		"--skip-player-probe",
		"--visual-preset=$CapturePreset",
		("--visual-render-scale=" + $CaptureRenderScale.ToString([System.Globalization.CultureInfo]::InvariantCulture)),
		"--visual-environment=$EnvironmentName",
		"--visual-seed=0"
	)
	$engineArguments += $UserArguments
	Write-Host "===== GPU visual capture $SuiteName/$VariantName ====="
	$result = Invoke-CapturedProcess -Executable $GodotPath -Arguments $engineArguments -StdoutPath $stdoutPath -StderrPath $stderrPath -TimeoutSeconds $TimeoutSeconds
	Write-Host $result.Output.TrimEnd()
	$manifestPath = Join-Path $variantRoot "visual_run.json"
	if ($result.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
		# Allow the renderer process a short filesystem-flush window before
		# converting a clean exit into a missing-evidence failure.
		for ($attempt = 0; $attempt -lt 20 -and -not (Test-Path -LiteralPath $manifestPath -PathType Leaf); $attempt++) {
			Start-Sleep -Milliseconds 100
		}
	}
	$context = @{
		scene = $Scene
		environment = $EnvironmentName
		preset = $CapturePreset
		render_scale = $CaptureRenderScale
		fixed_fps = $CaptureFps
		resolution = @(1280, 720)
	}
	if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
		$message = if ($result.ExitCode -ne 0) { "Godot capture exited with code $($result.ExitCode); log: $stdoutPath" } else { "Godot capture did not write visual_run.json; log: $stdoutPath" }
		Write-SuiteFailureManifest -Path $manifestPath -SuiteName $SuiteName -Context $context -Message $message -ExitCode ([int]$result.ExitCode)
		return $false
	}
	$shutdownWarningPattern = 'Parameter "t" is null|leaked texture|RIDs of type "Texture" were leaked|Texture.*leaked|ObjectDB instances were leaked|texture-RID'
	if ($result.Output -match $shutdownWarningPattern) {
		$message = "Godot capture log contains a renderer shutdown warning; log: $stderrPath"
		Mark-SuiteFailureManifest -Path $manifestPath -SuiteName $SuiteName -Message $message -ExitCode 1
		return $false
	}
	return $true
}

function Invoke-VisualMetric {
	param(
		[string]$SuiteName,
		[string]$VariantName,
		[string]$Scene,
		[string]$ArgumentName,
		[string]$ArgumentValue,
		[string]$CheckId
	)
	$variantRoot = Join-Path (Join-Path $BundlePath "suites") (Join-Path (Get-SafeLabel $SuiteName) (Get-SafeLabel $VariantName))
	$stdoutPath = Join-Path $variantRoot "logs\metric.stdout.log"
	$stderrPath = Join-Path $variantRoot "logs\metric.stderr.log"
	$consolePath = [System.Environment]::GetEnvironmentVariable("GODOT_CONSOLE_PATH")
	if ([string]::IsNullOrWhiteSpace($consolePath)) {
		$consolePath = Join-Path (Split-Path -Parent $GodotPath) "Godot_v4.7.2-stable_win64_console.exe"
	}
	$consolePath = (Resolve-Path -LiteralPath $consolePath -ErrorAction SilentlyContinue).Path
	if ([string]::IsNullOrWhiteSpace($consolePath) -or -not (Test-Path -LiteralPath $consolePath -PathType Leaf)) {
		Write-Host "Metric skipped: Godot console executable was not found."
		Add-MetricResult -ManifestPath (Join-Path $variantRoot "visual_run.json") -CheckId $CheckId -MetricName $Scene -ExitCode 1 -LogPath $stderrPath
		return $false
	}
	$metricArguments = @("--headless", "--audio-driver", "Dummy", "--path", $RepoRoot, $Scene, "--", "$ArgumentName=$ArgumentValue")
	$result = Invoke-CapturedProcess -Executable $consolePath -Arguments $metricArguments -StdoutPath $stdoutPath -StderrPath $stderrPath -TimeoutSeconds $TimeoutSeconds
	Write-Host $result.Output.TrimEnd()
	Add-MetricResult -ManifestPath (Join-Path $variantRoot "visual_run.json") -CheckId $CheckId -MetricName $Scene -ExitCode ([int]$result.ExitCode) -LogPath $stdoutPath
	return $result.ExitCode -eq 0
}

$captureFailed = $false
if ($Suite -eq "all" -or $Suite -eq "environment") {
	$ok = Invoke-VisualCapture -SuiteName "environment" -VariantName "canonical_60" -Scene "res://tests/environment_visual_inspection.tscn" -CaptureFps $FixedFps -EnvironmentName "daytime" -UserArguments @()
	$metricOk = Invoke-VisualMetric -SuiteName "environment" -VariantName "canonical_60" -Scene "res://tests/snow_depth_visual_metrics.tscn" -ArgumentName "--capture-dir" -ArgumentValue (Get-ProjectPath (Join-Path (Join-Path (Join-Path $BundlePath "suites") "environment") "canonical_60\compat")) -CheckId "environment.snow_depth.metric"
	if (-not $ok -or -not $metricOk) { $captureFailed = $true }
	$rampScaleLabel = $RenderScale.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', 'p')
	$rampVariant = "ramp_texture_daytime_{0}" -f $rampScaleLabel
	$rampOk = Invoke-VisualCapture -SuiteName "environment" -VariantName $rampVariant -Scene "res://tests/ramp_surface_visual_inspection.tscn" -CaptureFps $FixedFps -EnvironmentName "daytime" -CaptureRenderScale $RenderScale -CapturePreset $presetName -UserArguments @()
	if (-not $rampOk) { $captureFailed = $true }
	# Phase 9 review variant: the same hero-seam/ramp coverage with the opaque
	# takeoff/landing guide stamps hidden so geometry and material must carry
	# readability on their own.
	$rampNoGuidesVariant = "ramp_texture_daytime_noguides_{0}" -f $rampScaleLabel
	$rampNoGuidesOk = Invoke-VisualCapture -SuiteName "environment" -VariantName $rampNoGuidesVariant -Scene "res://tests/ramp_surface_visual_inspection.tscn" -CaptureFps $FixedFps -EnvironmentName "daytime" -CaptureRenderScale $RenderScale -CapturePreset $presetName -UserArguments @("--hide-guides")
	if (-not $rampNoGuidesOk) { $captureFailed = $true }
	if ($IncludeMotion.IsPresent) {
		foreach ($environmentName in $matrixEnvironments) {
			foreach ($captureScale in $matrixRenderScales) {
				$scaleLabel = $captureScale.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', 'p')
				foreach ($behavior in @("carve", "straight", "landing")) {
					$motionVariant = "motion_{0}_{1}_{2}" -f (Get-SafeLabel $environmentName), $scaleLabel, $behavior
					$motionArguments = @(
						"--capture-motion",
						"--motion-behavior=$behavior",
						"--motion-duration=$MotionDurationSeconds"
					)
					$motionOk = Invoke-VisualCapture -SuiteName "environment" -VariantName $motionVariant -Scene "res://tests/environment_visual_inspection.tscn" -CaptureFps $FixedFps -EnvironmentName $environmentName -CaptureRenderScale $captureScale -CapturePreset $presetName -UserArguments $motionArguments
					if (-not $motionOk) { $captureFailed = $true }
				}
			}
		}
	}
	if ($IncludeRecovery.IsPresent) {
		$recoveryVariant = "recovery_daytime_{0}" -f $RenderScale.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', 'p')
		$recoveryOk = Invoke-VisualCapture -SuiteName "environment" -VariantName $recoveryVariant -Scene "res://tests/environment_visual_inspection.tscn" -CaptureFps $FixedFps -EnvironmentName "daytime" -UserArguments @("--capture-recovery")
		if (-not $recoveryOk) { $captureFailed = $true }
	}
}

if ($Suite -eq "all" -or $Suite -eq "animation") {
	$ok = Invoke-VisualCapture -SuiteName "animation" -VariantName "canonical_60" -Scene "res://tests/animation_silhouette_inspection.tscn" -CaptureFps 60 -EnvironmentName "daytime" -UserArguments @("--capture-character-presentation")
	if (-not $ok) { $captureFailed = $true }
	if (-not $SkipAnimationAudit) {
		foreach ($rate in $AnimationAuditRates) {
			$auditOk = Invoke-VisualCapture -SuiteName "animation" -VariantName ("audit_{0}" -f $rate) -Scene "res://tests/animation_silhouette_inspection.tscn" -CaptureFps $rate -EnvironmentName "daytime" -UserArguments @("--capture-animation-presentation-audit", "--audit-fps=$rate")
			if (-not $auditOk) { $captureFailed = $true }
		}
	}
}

if ($Suite -eq "all" -or $Suite -eq "sunset") {
	$sunsetArguments = @(
		"--profile-preset=$Preset",
		"--profile-environment=sunset",
		("--profile-render-scale=" + $RenderScale.ToString([System.Globalization.CultureInfo]::InvariantCulture)),
		"--profile-commit=$commit",
		"--profile-dirty=$($dirty.ToString().ToLowerInvariant())"
	)
	$ok = Invoke-VisualCapture -SuiteName "sunset" -VariantName "canonical" -Scene "res://tests/sunset_visual_inspection.tscn" -CaptureFps $FixedFps -EnvironmentName "sunset" -UserArguments $sunsetArguments
	$metricOk = Invoke-VisualMetric -SuiteName "sunset" -VariantName "canonical" -Scene "res://tests/sunset_visual_metrics.tscn" -ArgumentName "--capture-path" -ArgumentValue (Get-ProjectPath (Join-Path (Join-Path (Join-Path $BundlePath "suites") "sunset") "canonical\compat\sunset_resort.png")) -CheckId "sunset.near_black.metric"
	if (-not $ok -or -not $metricOk) { $captureFailed = $true }
}

$buildArgs = @("$RepoRoot\tests\visual_evidence_tools.py", "build", "--repo-root", $RepoRoot, "--bundle", $BundlePath)
if ($UpdateBaselines) { $buildArgs += "--update-baselines" }
if ($AllowDirtyBaseline) { $buildArgs += "--allow-dirty-baseline" }
Write-Host "===== Build Codex visual evidence bundle ====="
& $PythonPath @buildArgs
$buildExitCode = [int]$LASTEXITCODE
if ($buildExitCode -ne 0) {
	Write-Host "Visual bundle build failed with exit code $buildExitCode."
	exit $buildExitCode
}
if ($captureFailed) {
	Write-Host "One or more capture processes or deterministic metrics failed; the manifest/report records the failure."
	exit 1
}
exit 0
