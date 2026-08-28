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

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
	$output = & $godot --headless --path $RepoRoot res://tests/gif_encoder_acceptance.tscn 2>&1 | Out-String
}
finally {
	$ErrorActionPreference = $previousErrorActionPreference
}
$exitCode = $LASTEXITCODE
Write-Output $output.TrimEnd()
if ($exitCode -ne 0) {
	Write-Output "FAIL: gif encoder scene exited with code $exitCode"
	exit 1
}
if ($output -match '(?m)GIF_FAIL|SCRIPT ERROR|ERROR:') {
	Write-Output "FAIL: gif encoder scene emitted an error"
	exit 1
}

# Validate the produced GIF with a real independent decoder (System.Drawing).
Add-Type -AssemblyName System.Drawing
$gifFile = Get-ChildItem -Path (Join-Path $RepoRoot ".godot_user") -Recurse -Filter "gif_acceptance.gif" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $gifFile) {
	Write-Output "FAIL: gif_acceptance.gif was not written under .godot_user"
	exit 1
}

$image = [System.Drawing.Image]::FromFile($gifFile.FullName)
try {
	if ($image.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Gif.Guid) {
		Write-Output "FAIL: file did not decode as a GIF"
		exit 1
	}
	if ($image.Width -ne 64 -or $image.Height -ne 48) {
		Write-Output "FAIL: unexpected dimensions $($image.Width)x$($image.Height)"
		exit 1
	}
	$dimension = [System.Drawing.Imaging.FrameDimension]::new($image.FrameDimensionsList[0])
	$frames = $image.GetFrameCount($dimension)
	if ($frames -ne 3) {
		Write-Output "FAIL: expected 3 frames, decoder found $frames"
		exit 1
	}
	$delay = $image.GetPropertyItem(0x5100).Value
	$frameDelayCs = [BitConverter]::ToUInt32($delay, 0)
	if ($frameDelayCs -ne 5) {
		Write-Output "FAIL: expected 5 cs frame delay, found $frameDelayCs"
		exit 1
	}
}
finally {
	$image.Dispose()
}

Write-Output "PASS: GIF encoder produced a valid animated GIF ($($gifFile.Length) bytes, 3 frames, 64x48, 5 cs delay)"
exit 0
