param(
	[Parameter(Mandatory = $true)][string]$BaselineDirectory,
	[Parameter(Mandatory = $true)][string]$CandidateDirectory,
	[double]$MaximumFrameRegressionPercent = 10.0,
	[double]$MaximumDrawCallRegressionPercent = 10.0,
	[double]$MaximumObjectRegressionPercent = 10.0,
	[double]$MaximumAudioAverageUsec = 1000.0,
	[switch]$FailOnRegression
)

$ErrorActionPreference = "Stop"
$baselineRoot = (Resolve-Path -LiteralPath $BaselineDirectory).Path
$candidateRoot = (Resolve-Path -LiteralPath $CandidateDirectory).Path

function Get-IdentityKey {
	param([object]$Profile)
	return "{0}/{1}/{2}" -f $Profile.identity.environment,$Profile.identity.preset,$Profile.identity.scenario
}

function Get-PercentDelta {
	param([double]$Before, [double]$After)
	if ([Math]::Abs($Before) -lt 0.000001) { return 0.0 }
	return (($After - $Before) / $Before) * 100.0
}

function Get-HardwareIdentity {
	param([object]$Profile)
	$runtime = $Profile.runtime
	$render = $Profile.render
	if ($null -eq $runtime -or $null -eq $render) { return "" }
	# Frame-time comparisons are only meaningful when the execution context is
	# comparable. In particular, never compare an integrated-GPU capture with a
	# discrete-GPU capture and report the difference as a code regression.
	return @(
		[string]$runtime.platform,
		[string]$runtime.godot_version,
		[string]$runtime.processor_name,
		[string]$runtime.video_adapter_vendor,
		[string]$runtime.video_adapter,
		[string]$runtime.headless,
		[string]$render.viewport_width,
		[string]$render.viewport_height,
		[string]$render.render_scale
	) -join "|"
}

$baselines = @{}
Get-ChildItem -LiteralPath $baselineRoot -Filter '*.json' -File | ForEach-Object {
	$profile = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
	if ($profile.schema_version -eq '1.0') { $baselines[(Get-IdentityKey $profile)] = $profile }
}

$failures = [System.Collections.Generic.List[string]]::new()
$compared = 0
Get-ChildItem -LiteralPath $candidateRoot -Filter '*.json' -File | ForEach-Object {
	$candidate = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
	if ($candidate.schema_version -ne '1.0') { return }
	$key = Get-IdentityKey $candidate
	if (-not $baselines.ContainsKey($key)) {
		Write-Warning "No baseline profile for $key"
		return
	}
	$baseline = $baselines[$key]
	$baselineHardware = Get-HardwareIdentity $baseline
	$candidateHardware = Get-HardwareIdentity $candidate
	if ([string]::IsNullOrWhiteSpace($baselineHardware) -or [string]::IsNullOrWhiteSpace($candidateHardware) -or $baselineHardware -ne $candidateHardware) {
		$message = "$key hardware identity mismatch: baseline='$baselineHardware' candidate='$candidateHardware'"
		Write-Output "PROFILE_COMPARE_SKIP $message"
		$failures.Add($message)
		return
	}
	$frameDelta = Get-PercentDelta ([double]$baseline.frames.p95_ms) ([double]$candidate.frames.p95_ms)
	$drawDelta = Get-PercentDelta ([double]$baseline.render.draw_calls) ([double]$candidate.render.draw_calls)
	$objectDelta = Get-PercentDelta ([double]$baseline.render.objects) ([double]$candidate.render.objects)
	$audioUsec = [double]$candidate.audio.average_usec
	$compared++
	Write-Output ("PROFILE_COMPARE {0} p95_ms={1:N2}% draw_calls={2:N2}% objects={3:N2}% audio_average_us={4:N2}" -f $key,$frameDelta,$drawDelta,$objectDelta,$audioUsec)
	if ($frameDelta -gt $MaximumFrameRegressionPercent) { $failures.Add("$key p95 frame time regressed $($frameDelta.ToString('N2'))%") }
	if ($drawDelta -gt $MaximumDrawCallRegressionPercent) { $failures.Add("$key draw calls regressed $($drawDelta.ToString('N2'))%") }
	if ($objectDelta -gt $MaximumObjectRegressionPercent) { $failures.Add("$key rendered objects regressed $($objectDelta.ToString('N2'))%") }
	if ($key.EndsWith('/baseline') -and $audioUsec -gt $MaximumAudioAverageUsec) { $failures.Add("$key audio average $($audioUsec.ToString('N2')) us exceeds $MaximumAudioAverageUsec us") }
}

if ($compared -eq 0) { throw "No matching schema 1.0 profiles were compared." }
if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "REGRESSION: $_" }
	if ($FailOnRegression) { exit 1 }
}
Write-Output "PROFILE_COMPARE_PASS: compared $compared profile(s); regressions=$($failures.Count)"
