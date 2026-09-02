param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$comparatorPath = Join-Path $RepoRoot "tests/performance_compare.ps1"
$shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Path
if ([string]::IsNullOrWhiteSpace($shell)) {
	$shell = (Get-Command powershell -ErrorAction SilentlyContinue).Path
}
if ([string]::IsNullOrWhiteSpace($shell)) {
	Write-Output "FAIL: PowerShell executable was not found"
	exit 1
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("just-ski-performance-compare-" + [guid]::NewGuid().ToString("N"))
$baselineDirectory = Join-Path $testRoot "baseline"
$candidateDirectory = Join-Path $testRoot "candidate"
$outputPath = Join-Path $testRoot "compare.log"
New-Item -ItemType Directory -Path $baselineDirectory,$candidateDirectory -Force | Out-Null

function New-TestProfile {
	param([string]$Adapter)
	return [ordered]@{
		schema_version = "1.0"
		identity = [ordered]@{
			environment = "daytime"
			preset = "medium"
			scenario = "baseline"
			commit_sha = "test"
			working_tree_dirty = $false
		}
		runtime = [ordered]@{
			platform = "Windows"
			godot_version = "4.7.2-stable"
			processor_name = "Test CPU"
			video_adapter_vendor = "Test Vendor"
			video_adapter = $Adapter
			headless = $false
		}
		frames = [ordered]@{
			p95_ms = 10.0
		}
		render = [ordered]@{
			viewport_width = 1920
			viewport_height = 1080
			render_scale = 0.65
			draw_calls = 100
			objects = 200
		}
		audio = [ordered]@{
			average_usec = 100
		}
	}
}

try {
	$baseline = New-TestProfile "Test GPU"
	$candidate = New-TestProfile "Test GPU"
	$baselinePath = Join-Path $baselineDirectory "profile_daytime_medium_baseline.json"
	$candidatePath = Join-Path $candidateDirectory "profile_daytime_medium_baseline.json"
	$baseline | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $baselinePath -Encoding utf8
	$candidate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $candidatePath -Encoding utf8

	& $shell -NoProfile -File $comparatorPath -BaselineDirectory $baselineDirectory -CandidateDirectory $candidateDirectory -FailOnRegression *> $outputPath
	if ($LASTEXITCODE -ne 0) {
		throw "Matching hardware profiles unexpectedly failed: $((Get-Content -LiteralPath $outputPath -Raw).Trim())"
	}

	$candidate.runtime.video_adapter = "Different GPU"
	$candidate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $candidatePath -Encoding utf8
	& $shell -NoProfile -File $comparatorPath -BaselineDirectory $baselineDirectory -CandidateDirectory $candidateDirectory -FailOnRegression *> $outputPath
	if ($LASTEXITCODE -eq 0) {
		throw "Mismatched hardware profiles were accepted"
	}
	if ((Get-Content -LiteralPath $outputPath -Raw) -notmatch "hardware identity mismatch") {
		throw "Mismatched hardware output did not explain the hardware identity failure"
	}
	Write-Output "PASS: performance comparator enforces matching hardware/render identities."
}
catch {
	Write-Output "FAIL: $($_.Exception.Message)"
	exit 1
}
finally {
	if (Test-Path -LiteralPath $testRoot) {
		Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}
