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
	# GitHub's Windows runners may materialize the repository with CRLF while
	# local checks use LF. Normalize here so line-anchored import assertions
	# validate the setting rather than the checkout's newline convention.
	return (Get-Content -LiteralPath $path -Raw) -replace "`r", ""
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
$summit = Read-RequiredFile "shaders/snow_summit.gdshader"
$mountain = Read-RequiredFile "shaders/distant_mountain.gdshader"
$treeBatch = Read-RequiredFile "world/environment/park_tree_batch.gd"
$treeAsset = Read-RequiredFile "assets/environment/production/low_poly_environment_asset.gd"
$catalogTres = Read-RequiredFile "resources/environment/default_environment_asset_catalog.tres"
$tracks = Read-RequiredFile "shaders/ski_tracks.gdshader"
$particle = Read-RequiredFile "shaders/snow_particle.gdshader"
$material = Read-RequiredFile "world/snow_material.gd"
$snowProfile = Read-RequiredFile "world/snow_presentation_profile.gd"
$parkLayout = Read-RequiredFile "world/park_features/park_layout.gd"
$contact = Read-RequiredFile "player/ski_contact_solver.gd"
$resort = Read-RequiredFile "world/resort.gd"
$summitEnvironment = Read-RequiredFile "world/summit_environment_builder.gd"
$snowVfx = Read-RequiredFile "world/vfx/ski_snow_vfx.gd"
$settings = Read-RequiredFile "autoload/game_settings.gd"
$ui = Read-RequiredFile "ui/hud/game_ui.gd"
$attribution = Read-RequiredFile "assets/materials/snow_02/SOURCE.md"
$importer = Read-RequiredFile "tools/import_snow_02.py"
$diffuseImport = Read-RequiredFile "assets/materials/snow_02/snow_02_diff_2k.jpg.import"
$detailImport = Read-RequiredFile "assets/materials/snow_02/snow_02_detail_2k.png.import"
$shaderText = "$common`n$fast`n$premium"

Require-Match $diffuseImport '(?m)^mipmaps/generate=true$' "Snow diffuse import must generate mipmaps for distant 3D sampling."
Require-Match $detailImport '(?m)^mipmaps/generate=true$' "Packed snow detail import must generate mipmaps for distant 3D sampling."
Require-Match $diffuseImport '(?m)^mipmaps/limit=-1$' "Snow diffuse import must retain the full generated mip chain."
Require-Match $detailImport '(?m)^mipmaps/limit=-1$' "Packed snow detail import must retain the full generated mip chain."

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
Require-Match $common 'smoothstep\(detail_near_distance,\s*max\(detail_far_distance' "Snow detail must fade between its near and far boundaries."Require-Match $common 'if\s*\(detail_visibility\s*>\s*0\.001\)' "Texture sampling must be skipped beyond the detail boundary."
Require-Match $common 'macro_tint_amount\s*\*\s*detail_visibility' "Macro tint must fade to the flat far-field response."
Require-Match $common 'far_macro_tint_amount' "Snow must retain broad terrain variation beyond the micro-detail boundary."
Require-Match $common 'warm_snow_tint' "Snow must provide subtle warm base-color variation."
Require-Match $common 'cool_snow_tint' "Snow must provide subtle cool base-color variation."
Require-Match $common 'macro_roughness_amount' "Broad terrain variation must also affect roughness."
Require-Match $common 'detail\.roughness\s*-\s*0\.5' "Micro roughness must perturb each authored surface base instead of replacing it."
Require-Match $common 'disturbed_detail_boost' "Feature traffic must reveal more disturbed-snow detail than the groomed run."
Require-Match $common 'slope_contrast_strength' "Snow must retain slope/aspect readability at gameplay distance."
Require-Match $common 'form_light_direction_world_xz' "Snow must expose a stable large-scale form-light direction."
Require-Match $common 'form_aspect\s*\*\s*form_contrast_strength' "Geometric normals must retain sun-oriented form separation beyond texture detail range."
Require-Match $common 'steepness\s*\*\s*steepness_contrast_strength' "Steep snow faces must preserve restrained value separation."
Require-Match $common 'wind_crust_amount' "Snow must provide restrained wind-crust variation without extra texture samples."
Require-Match $common 'groom_direction_world_xz' "Corduroy must use an explicit world-XZ track direction."
Require-Match $common 'cos\(phase\).*corduroy_amount' "Corduroy normal perturbation must use an analytic gradient."

Require-Match $material 'snow_fast\.gdshader' "SnowMaterial must own the fast shader adapter."
Require-Match $material 'snow_premium\.gdshader' "SnowMaterial must own the premium shader adapter."
Require-Match $material 'groom_direction_world_xz' "SnowMaterial.create must accept groom direction."
Require-Match $material 'feature_emphasis' "SnowMaterial must support subtle jump and landing emphasis."
Require-Match $material 'enum\s+PresentationRole\s*\{\s*GROUND,\s*PARK_FEATURE\s*\}' "SnowMaterial must expose the ground/park-feature presentation role seam."
Require-Match $material 'presentation_role:\s*PresentationRole\s*=\s*PresentationRole\.GROUND' "SnowMaterial callers must retain GROUND as the backward-compatible default."
Require-Match $material 'PRESENTATION\.park_feature_texture_world_size' "SnowMaterial must source park-feature texture scale from the presentation profile."
Require-Match $material 'PRESENTATION\.park_feature_detail_far_distance' "SnowMaterial must source park-feature detail distance from the presentation profile."
Require-Match $material 'func\s+_apply_park_feature_parameters' "SnowMaterial must centralize park-feature response tuning."
Require-Match $snowProfile 'park_feature_texture_world_size' "Snow presentation profile must expose park-feature texture scale."
Require-Match $snowProfile 'park_feature_albedo_texture_strength' "Snow presentation profile must expose park-feature albedo response."
Require-Match $snowProfile 'park_feature_normal_max' "Snow presentation profile must bound park-feature normal response."
Require-Match $snowProfile 'park_feature_roughness_texture_max' "Snow presentation profile must bound park-feature roughness response."
Require-Match $snowProfile 'park_feature_emphasis_floor' "Snow presentation profile must enforce a minimum park-feature emphasis."
Require-Match $snowProfile 'park_feature_detail_far_distance' "Snow presentation profile must retain park-feature detail at gameplay distance."
Require-Match $parkLayout 'presentation_role:\s*int\s*=\s*SnowSurface\.PresentationRole\.GROUND' "ParkLayout must keep GROUND as the default slope-box role."
Require-Match $parkLayout 'SnowSurface\.PresentationRole\.PARK_FEATURE' "ParkLayout must route generated park snow through PARK_FEATURE."
Require-Match $parkLayout '_park_feature_snow_material' "ParkLayout must centralize its park-feature snow material adapter."
Require-Match $material 'default_snow_presentation_profile\.tres' "SnowMaterial must source important readability tuning from an editable resource."
Require-Match $material 'albedo_texture_strength"\s*,\s*0\.055' "Groomed snow must keep the footprint-heavy source albedo subtle."
Require-Match $material 'sparkle_amount"\s*,\s*0\.05' "Premium snow sparkle must remain restrained."
Require-Match $material 'corduroy_amount"\s*,\s*0\.08' "Groomed corduroy must retain the visually reviewed normal relief."
Require-Match $material 'corduroy_frequency"\s*,\s*1\.8' "Groomed corduroy frequency must stay broad and low-noise."
Require-Match $resort 'MainSnowFace[^\r\n]+SnowSurface\.Kind\.POWDER[^\r\n]+SnowSurface\.Kind\.GROOMED' "The main resort face must read as groomed snow without changing established ski physics."
Require-Match $resort 'default_resort_environment_profile\.tres' "The resort must source environment readability tuning from an editable resource."
Require-Match $resort 'high_haze\.visible\s*=\s*environment_profile\.high_haze_enabled\s+and\s+not\s+env\.fog_enabled' "High haze must skip its transparent noise pass while environment fog already supplies atmospheric depth."
Require-Match $tracks 'distance_fade_start' "Persistent tracks must fade before the far view becomes noisy."
Require-Match $tracks 'float\s+skid\s*=\s*clamp\(COLOR\.r' "Ski tracks must preserve the disturbed/skid signal separately from carving."
Require-Match $tracks 'float\s+carve\s*=\s*clamp\(COLOR\.g' "Ski tracks must preserve the carve signal separately from disturbance."
Require-Match $tracks 'ROUGHNESS\s*=\s*mix\(0\.7,\s*0\.96,\s*skid\)\s*\*\s*mix\(1\.0,\s*0\.92,\s*carve\)' "Carved and disturbed ski tracks must have distinct snow-like reflection responses."
Require-Match $snowVfx 'surface\.set_uv' "Track ribbons must carry a cross-section coordinate for soft groove edges."
Require-Match $tracks 'UV\.x' "The track material must use the ribbon cross-section."
Require-Match $tracks 'COLOR\.a\s*\*\s*distance_visibility' "Track age and distance visibility must both bound screen persistence."
Require-Match $particle 'soft_disc|smoothstep' "Snow particles must use a soft non-square silhouette."
Require-Match $particle 'shape_aspect' "Snow particles must expose a directional aspect control instead of rendering round beads."
Require-Match $particle 'distance_fade' "Snow particles must fade when they approach the camera."
Require-Match $particle 'CAMERA_POSITION_WORLD' "Snow particles must measure near-camera fade in world space."
Require-Match $snowVfx 'scale_curve' "Snow particles must shrink over their lifetime."
Require-Match $snowVfx 'color_ramp' "Snow particles must fade in and out over their lifetime."
Require-Match $snowVfx 'var particle_mesh := QuadMesh\.new\(\)' "Snow particles must use a lightweight camera-facing draw pass."
Require-Match $snowVfx 'particle_mesh\.size\s*=\s*Vector2\(1\.0,\s*1\.0\)' "Snow particle draw passes must preserve a stable unit footprint for shader sizing."
Reject-Match $snowVfx 'var particle_mesh := SphereMesh\.new\(\)' "Snow particles cannot use low-resolution sphere beads."
Require-Match $snowVfx 'MAX_TRACK_SAMPLES\s*:=\s*180' "Ski track history must have a hard sample cap."
Require-Match $snowVfx 'MAX_CONTINUOUS_PARTICLES\s*:=\s*184' "Continuous particle budget must remain explicitly capped."
Require-Match $snowVfx 'skier\.contact\.(left_hit_position|right_hit_position)' "Tracks must consume the existing per-ski contact points."
Require-Match $snowVfx 'skier\.landed\.connect' "Landing spray must use the existing landing result signal."
Require-Match $snowVfx 'SkiContactPresentation' "Snow VFX must consume the shared contact presentation module."
Require-Match $snowVfx 'allows_snow_effects' "Snow VFX must reject non-snow feature surfaces."
Require-Match $contact 'enum\s+SurfaceClass' "Contact must distinguish physical snow kind from presentation surface class."
Reject-Match $snowVfx 'RayCast3D|intersect_ray|PhysicsRayQueryParameters3D' "Environment VFX cannot create a second terrain-contact system."
Require-Match $settings '"snow_quality"\s*:\s*1' "High defaults must select premium snow."
Require-Match $settings 'pending\["snow_quality"\]\s*=\s*1\s+if\s+(?:preset|selected_preset)\s*>=\s*2\s+else\s+0' "Low/Medium and High/Ultra preset mapping is missing."
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
Require-Match $attribution 'R\s*(?::|\|)\s*OpenGL normal X' "Packed channel documentation must identify OpenGL normal X."
Require-Match $attribution 'G\s*(?::|\|)\s*OpenGL normal Y' "Packed channel documentation must identify OpenGL normal Y."
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


Require-Match $resort 'ReflectionProbe\.new\(\)' "Resort must own exactly one player-following reflection probe."
if (([regex]::Matches($resort, 'ReflectionProbe\.new\(\)')).Count -ne 1) {
	$failures.Add("Resort must contain exactly one ReflectionProbe (the player-following experiment).")
}
Require-Match $resort 'static func player_probe_allowed_for_preset' "Probe preset policy must be a dedicated resort-local gate, not the GI policy."
Require-Match $resort 'static func probe_should_recapture' "Probe relocation throttle must be a pure testable policy."
Require-Match $resort 'static func probe_should_snap' "Probe teleport snap must be a pure testable policy."
Require-Match $resort 'probe_should_recapture\(distance,\s*_probe_time_since_capture\)' "Probe updates must gate relocation on distance AND elapsed time."
Require-Match $resort 'probe_should_snap\(distance\)' "Probe updates must snap on teleport distance."
Require-Match $resort 'ambient_mode\s*=\s*ReflectionProbe\.AMBIENT_DISABLED' "Player-following probe must not contribute moving ambient light."
Require-Match $resort 'PLAYER_PROBE_RECAPTURE_DISTANCE\s*:=\s*10\.0' "Probe recapture distance must be an explicit named constant."
Require-Match $resort 'PLAYER_PROBE_RECAPTURE_INTERVAL\s*:=\s*0\.33' "Probe recapture interval must be an explicit named constant."
Require-Match $resort 'PLAYER_PROBE_SNAP_DISTANCE\s*:=\s*40\.0' "Probe snap distance must be an explicit named constant."
Reject-Match $resort 'update_mode\s*=\s*ReflectionProbe\.UPDATE_ALWAYS' "Player-following probe must never use continuous recapture."
Reject-Match $resort 'graphics_preset_allows_gi\(int\(GameSettings\.active\.get\("graphics_preset"' "Probe preset gating must not reuse the GI capability policy."
Require-Match $resort 'func effective_hdr_enabled' "Resort must own an explicit HDR presentation gate."
Require-Match $resort 'TONE_MAPPER_AGX' "HDR presentation must grade through an HDR-capable tonemapper."
Require-Match $resort 'TONE_MAPPER_FILMIC' "SDR presentation must keep the authored filmic tonemapper."
Require-Match $resort '_apply_hdr_presentation\(\)' "Graphics apply must refresh the HDR tonemapper presentation."

# Phase 10: the summit workaround is scoped to the presentation-only shoulder
# regions; the interactive piste renders through the standard shadow-receiving
# tier, and the summit's value manipulation stays multiplicative and bounded.
Require-Match $summit 'render_mode shadows_disabled' "Presentation-only shoulder relief must keep its shadow-safe workaround."
Require-Match $summit 'surface_albedo\s*\*=\s*1\.0\s*\+\s*drift_value' "Summit drift must modulate the surface multiplicatively."
Reject-Match $summit 'surface_albedo\s*\+=\s*vec3\(drift_value' "Summit drift cannot rejoin the additive value path."
Require-Match $summit 'summit_drift_strength\s*:\s*hint_range\(0\.0,\s*0\.4\)' "Summit drift strength must stay bounded to subtle variation."
Require-Match $snowProfile 'summit_drift_strength\s*:=\s*0\.16' "Summit drift default must remain subtler than the retired strong drift."
Require-Match $snowProfile 'summit_luminance_floor\s*:=\s*0\.44' "Summit luminance floor must match the shared readability floor."
Require-Match $snowProfile 'detail_far_distance\s*:=\s*64\.0' "Ground detail must carry piste form into the approach sightline."
Require-Match $summitEnvironment 'SummitPlayableRenderSurface' "Summit builder must create the shadow-receiving playable region."
Require-Match $summitEnvironment 'SummitReliefRenderSurfaceLeft' "Summit builder must keep the left shadow-safe shoulder region."
Require-Match $summitEnvironment 'SummitReliefRenderSurfaceRight' "Summit builder must keep the right shadow-safe shoulder region."
Require-Match $summitEnvironment 'SnowSurface\.create\(SnowSurface\.Kind\.GROOMED,\s*Vector2\(0\.0,\s*-1\.0\),\s*0\.0,\s*shadow_safe,\s*SnowSurface\.PresentationRole\.GROUND\)' "Summit region materials must select shadow safety per region."
Reject-Match $summitEnvironment 'SnowSurface\.create\(SnowSurface\.Kind\.GROOMED,\s*Vector2\(0\.0,\s*-1\.0\),\s*0\.0,\s*true\)' "Summit render surface cannot blanket the playable piste with the shadow-safe workaround."

# Phase 11: structural tree families render through deterministic spatial
# MultiMesh chunks, and global fog is the single primary aerial-perspective
# system (the mountain shader only adds a bounded local blend).
Require-Match $treeBatch 'FAMILY_COUNT\s*:=\s*4' "Tree batching must expose four structural conifer families."
Require-Match $treeBatch 'multimesh\.custom_aabb\s*=' "Tree chunk components must carry chunk-local visibility bounds."
Require-Match $treeBatch 'tree_chunk' "Tree chunks must record their spatial chunk for tests and debugging."
Require-Match $treeAsset 'TREE_FAMILY_PROFILES' "Tree assets must own a structural family table."
Require-Match $treeAsset 'AssetKind\s*\{[^}]*PISTE_MARKER[^}]*SNOW_BANK[^}]*LIFT_STATION' "Density assets must be concrete low-poly kinds."
Require-Match $catalogTres 'asset_id = "piste_marker"' "Catalog must register the piste marker asset."
Require-Match $catalogTres 'asset_id = "snow_bank"' "Catalog must register the snow bank asset."
Require-Match $catalogTres 'asset_id = "lift_station"' "Catalog must register the lift station asset."
Require-Match $catalogTres 'lod_distances_m = Vector3\(48, 96, 235\)' "Tree LOD must reduce its near/far overlap."
Require-Match $mountain 'uniform float haze_blend\s*:\s*hint_range\(0\.0,\s*1\.0\)\s*=\s*0\.28' "Mountain haze blend must be an explicit bounded uniform."
Require-Match $mountain 'depth_haze\s*\*\s*haze_blend' "Mountain shading must use the bounded local haze blend."
Reject-Match $mountain 'depth_haze\s*\*\s*0\.66' "Mountain shading cannot double-wash distance haze again."
Require-Match $summitEnvironment '"topology": "long_ridge"' "Backdrop must author multiple topology families."
Require-Match $summitEnvironment '"topology": "saddle"' "Backdrop must include the saddle/double-peak family."
Require-Match $summitEnvironment '"topology": "low_ridge"' "Backdrop must include the distant low-ridge family."

if (Test-Path -LiteralPath (Join-Path $RepoRoot "shaders/snow.gdshader")) {
	$failures.Add("Legacy procedural snow shader still exists.")
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: snow shader structure, settings, assets, and attribution are statically valid."
