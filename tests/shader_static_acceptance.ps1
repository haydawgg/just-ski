param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$failures = [System.Collections.Generic.List[string]]::new()

function Read-RequiredFile([string]$RelativePath) {
	$path = Join-Path $RepoRoot $RelativePath
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		$failures.Add("Missing required file: $RelativePath")
		return ""
	}
	return Get-Content -LiteralPath $path -Raw
}

function Require-Match([string]$Text, [string]$Pattern, [string]$Message) {
	if ($Text -notmatch $Pattern) {
		$failures.Add($Message)
	}
}

function Reject-Match([string]$Text, [string]$Pattern, [string]$Message) {
	if ($Text -match $Pattern) {
		$failures.Add($Message)
	}
}

$common = Read-RequiredFile "shaders/snow_common.gdshaderinc"
$fast = Read-RequiredFile "shaders/snow_fast.gdshader"
$premium = Read-RequiredFile "shaders/snow_premium.gdshader"
$material = Read-RequiredFile "world/snow_material.gd"
$settings = Read-RequiredFile "autoload/game_settings.gd"
$ui = Read-RequiredFile "ui/hud/game_ui.gd"
$attribution = Read-RequiredFile "assets/materials/snow_02/SOURCE.md"
$importer = Read-RequiredFile "tools/import_snow_02.py"
$shaderText = "$common`n$fast`n$premium"

Require-Match $shaderText 'MODEL_NORMAL_MATRIX\s*\*\s*NORMAL' "Snow shaders must transform normals with MODEL_NORMAL_MATRIX."
Require-Match $shaderText 'mat3\s*\(\s*VIEW_MATRIX\s*\)' "Each tier must provide the current view rotation to shared snow shading."
Require-Match $common 'view_rotation\s*\*\s*detailed_normal' "World-space detail normals must be converted to view space before assigning NORMAL."
Require-Match $common 'sample_triplanar' "Both tiers must share the triplanar implementation."
Require-Match $common 'snow_albedo_texture\s*:\s*source_color,\s*filter_linear_mipmap_anisotropic,\s*repeat_enable' "Diffuse sampling must be sRGB, mipmapped, anisotropic, and repeating."
Require-Match $common 'snow_detail_texture\s*:\s*filter_linear_mipmap_anisotropic,\s*repeat_enable' "Packed detail sampling must be linear, mipmapped, anisotropic, and repeating."
if ([regex]::Matches($common, '\btexture\s*\(').Count -ne 6) {
	$failures.Add("Shared near-field triplanar sampling must use exactly six texture samples.")
}
Require-Match $common 'geometry_normal\s*\+\s*mapped_x\s*-\s*vec3\(sign_x' "Triplanar X detail must perturb, not replace, the geometric normal."
Require-Match $common 'geometry_normal\s*\+\s*mapped_y\s*-\s*vec3\(0\.0,\s*sign_y' "Triplanar Y detail must perturb, not replace, the geometric normal."
Require-Match $common 'geometry_normal\s*\+\s*mapped_z\s*-\s*vec3\(0\.0,\s*0\.0,\s*sign_z' "Triplanar Z detail must perturb, not replace, the geometric normal."
Require-Match $fast '#include\s+"res://shaders/snow_common\.gdshaderinc"' "Fast shader must include the shared snow implementation."
Require-Match $premium '#include\s+"res://shaders/snow_common\.gdshaderinc"' "Premium shader must include the shared snow implementation."
Reject-Match $common 'void\s+snow_vertex\s*\(' "Varyings must be assigned directly inside each shader's vertex function."
foreach ($tier in @($fast, $premium)) {
	Require-Match $tier 'void\s+vertex\s*\(\s*\)[\s\S]*snow_world_position\s*=\s*\(MODEL_MATRIX' "Each snow tier must assign world position directly in vertex()."
	Require-Match $tier 'void\s+vertex\s*\(\s*\)[\s\S]*snow_world_normal\s*=\s*normalize\(MODEL_NORMAL_MATRIX\s*\*\s*NORMAL\)' "Each snow tier must assign world normal directly in vertex()."
}

Reject-Match $shaderText 'mat3\s*\(\s*MODEL_MATRIX\s*\)\s*\*\s*NORMAL' "MODEL_MATRIX cannot be used as the normal matrix."
Reject-Match $shaderText '\bdFdx\b|\bdFdy\b' "Screen derivatives cannot drive snow normals."
Reject-Match $shaderText '\bfbm\s*\(' "The old multi-octave fBm path must be removed."
Reject-Match $shaderText '(?m)^\s*AO\s*=' "Snow cannot write fake procedural AO."
Reject-Match $shaderText 'SPECULAR\s*=.*spark' "Sparkle cannot be driven through SPECULAR."
Reject-Match $shaderText 'EMISSION\s*=.*spark' "Sparkle cannot be faked with emission."

Require-Match $fast 'SPECULAR\s*=\s*0\.5' "Fast snow must keep a fixed dielectric specular value."
Reject-Match $fast 'SSS_STRENGTH|SSS_TRANSMITTANCE|CLEARCOAT' "Fast snow must not compile premium SSS or clearcoat outputs."
Require-Match $premium 'SPECULAR\s*=\s*0\.5' "Premium snow must keep a fixed dielectric specular value."
Require-Match $premium 'CLEARCOAT\s*=' "Premium sparkle must use the reflection model."
Require-Match $premium 'SSS_STRENGTH\s*=' "Premium snow must provide real SSS strength."
Require-Match $premium 'SSS_TRANSMITTANCE_COLOR\s*=' "Premium snow must provide transmittance color."
Reject-Match $common 'SSS_STRENGTH|SSS_TRANSMITTANCE|CLEARCOAT' "Premium-only renderer outputs cannot leak into shared code."
Require-Match $common 'smoothstep\(detail_near_distance,\s*max\(detail_far_distance' "Snow detail must fade between its near and far boundaries."
Require-Match $common 'if\s*\(detail_visibility\s*>\s*0\.001\)' "Texture sampling must be skipped beyond the detail boundary."
Require-Match $common 'macro_tint_amount\s*\*\s*detail_visibility' "Macro tint must fade to the flat far-field response."
Require-Match $common 'groom_direction_world_xz' "Corduroy must use an explicit world-XZ track direction."
Require-Match $common 'cos\(phase\).*corduroy_amount' "Corduroy normal perturbation must use an analytic gradient."

Require-Match $material 'snow_fast\.gdshader' "SnowMaterial must own the fast shader adapter."
Require-Match $material 'snow_premium\.gdshader' "SnowMaterial must own the premium shader adapter."
Require-Match $material 'groom_direction_world_xz' "SnowMaterial.create must accept groom direction."
Require-Match $settings '"snow_quality"\s*:\s*1' "High defaults must select premium snow."
Require-Match $settings 'pending\["snow_quality"\]\s*=\s*1\s+if\s+preset\s*>=\s*2\s+else\s+0' "Low/Medium and High/Ultra preset mapping is missing."
Require-Match $ui 'SnowQuality' "Graphics options must expose snow quality."

$diffusePath = Join-Path $RepoRoot "assets/materials/snow_02/snow_02_diff_2k.jpg"
$detailPath = Join-Path $RepoRoot "assets/materials/snow_02/snow_02_detail_2k.png"
foreach ($texturePath in @($diffusePath, $detailPath)) {
	if (-not (Test-Path -LiteralPath $texturePath -PathType Leaf)) {
		$failures.Add("Missing required 2K texture: $texturePath")
		continue
	}
	Add-Type -AssemblyName System.Drawing
	$image = [System.Drawing.Image]::FromFile($texturePath)
	try {
		if ($image.Width -ne 2048 -or $image.Height -ne 2048) {
			$failures.Add("Texture must be 2048x2048: $texturePath")
		}
	} finally {
		$image.Dispose()
	}
}

Require-Match $attribution 'https://polyhaven\.com/a/snow_02' "Snow asset source URL is missing."
Require-Match $attribution '\bCC0\b' "Snow asset CC0 status is missing."
Require-Match $attribution 'Rob Tuytel' "Snow asset author is missing."
Require-Match $attribution 'R:\s*OpenGL normal X' "Packed channel documentation must identify OpenGL normal X."
Require-Match $attribution 'G:\s*OpenGL normal Y' "Packed channel documentation must identify OpenGL normal Y."
Require-Match $importer 'snow_02_nor_gl_2k\.png' "Importer must use Poly Haven's OpenGL normal map."
Require-Match $importer 'Image\.merge\("RGBA",\s*\(normal_x,\s*normal_y,\s*roughness,\s*translucency\)\)' "Importer channel packing must remain normal X/Y, roughness, translucency."

if (Test-Path -LiteralPath $detailPath -PathType Leaf) {
	$bitmap = [System.Drawing.Bitmap]::FromFile($detailPath)
	try {
		$channelFingerprints = @("", "", "", "")
		for ($y = 0; $y -lt $bitmap.Height; $y += 64) {
			for ($x = 0; $x -lt $bitmap.Width; $x += 64) {
				$pixel = $bitmap.GetPixel($x, $y)
				$channelFingerprints[0] += [char]$pixel.R
				$channelFingerprints[1] += [char]$pixel.G
				$channelFingerprints[2] += [char]$pixel.B
				$channelFingerprints[3] += [char]$pixel.A
			}
		}
		if (($channelFingerprints | Sort-Object -Unique).Count -ne 4) {
			$failures.Add("Packed snow detail channels must contain four distinct source signals.")
		}
	} finally {
		$bitmap.Dispose()
	}
}

if (Test-Path -LiteralPath (Join-Path $RepoRoot "shaders/snow.gdshader")) {
	$failures.Add("Legacy procedural snow shader still exists.")
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: snow shader structure, settings, assets, and attribution are statically valid."
