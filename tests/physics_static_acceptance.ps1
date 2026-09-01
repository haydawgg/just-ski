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

$inputManager = Read-RequiredFile "autoload/input_manager.gd"
$profile = Read-RequiredFile "resources/physics/ski_physics_profile.gd"
$controller = Read-RequiredFile "player/skier_controller.gd"
$crashContext = Read-RequiredFile "player/crash_context.gd"
$animationController = Read-RequiredFile "player/animation/skier_animation_controller.gd"
$animationFrame = Read-RequiredFile "player/animation/skier_animation_frame.gd"
$trick = Read-RequiredFile "gameplay/trick_system/trick_controller.gd"
$contact = Read-RequiredFile "player/ski_contact_solver.gd"
$camera = Read-RequiredFile "player/camera_controller.gd"
$resort = Read-RequiredFile "world/resort.gd"
$layout = Read-RequiredFile "world/park_features/park_layout.gd"
$rail = Read-RequiredFile "world/park_features/grind_rail_3d.gd"
$builder = Read-RequiredFile "world/course/park_course_builder.gd"
$course = Read-RequiredFile "world/course/park_course_profile.gd"
$courseResource = Read-RequiredFile "resources/course/default_course_profile.tres"
$ui = Read-RequiredFile "ui/hud/game_ui.gd"
$mountainShader = Read-RequiredFile "shaders/distant_mountain.gdshader"

Require-Match $inputManager 'Input\.get_action_raw_strength\(positive_action\)\s*-\s*Input\.get_action_raw_strength\(negative_action\)' "Steering must shape raw action strength exactly once."
Reject-Match $inputManager 'Input\.get_axis\(' "InputManager cannot feed an already-deadzoned axis into its custom deadzone."
Require-Match $inputManager 'func _shape_axis\(raw: float\)' "Raw input shaping must remain centralized."

Require-Match $profile 'maximum_jump_charge:\s*float\s*=\s*0\.32' "Maximum jump charge must be profile-owned."
Require-Match $profile 'minimum_pop_strength:\s*float\s*=\s*0\.72' "Minimum keyboard pop strength must be profile-owned."
Require-Match $controller 'jump_charge\s*\+\s*delta,\s*profile\.maximum_jump_charge' "Jump accumulation must use the profile charge maximum."
Require-Match $controller 'jump_charge\s*/\s*maxf\(profile\.maximum_jump_charge' "Pop normalization must use the profile charge maximum."
Require-Match $controller 'animation_frame\.compression\s*=.*profile\.maximum_jump_charge' "Animation compression must use the same charge maximum."
Reject-Match $controller 'jump_charge\s*/\s*0\.(28|32)' "No second jump-charge normalization constant may remain."

Require-Match $resort '@export var physics_profile:\s*SkiPhysicsProfile' "Resort must own the active physics profile."
Require-Match $resort 'ParkCourseBuilderModule\.build\(self,\s*course_profile,\s*physics_profile(?:,\s*environment_asset_catalog)?\)' "Course construction must receive the active profile."
Require-Match $resort 'player\.profile\s*=\s*physics_profile' "The skier must receive the same active profile."
Require-Match $builder 'build\(parent:\s*Node3D,\s*profile:\s*ParkCourseProfile,\s*physics_profile:\s*SkiPhysicsProfile(?:,\s*asset_catalog:\s*EnvironmentAssetCatalog\s*=\s*null)?\)' "The course builder interface must require the active profile."
Require-Match $layout 'resolved_pop_strength\s*:=\s*design_pop_strength\s+if\s+design_pop_strength\s*>=\s*0\.0\s+else\s+physics_profile\.minimum_pop_strength' "Omitted design pop must resolve through the active profile."
Require-Match $layout 'physics_profile\.pop_impulse\s*\*\s*clampf\(resolved_pop_strength' "Jump sizing must use active-profile pop impulse."
Require-Match $layout 'physics_profile\.air_gravity' "Jump sizing must use active-profile air gravity."
Reject-Match $layout 'const\s+AIR_GRAVITY|const\s+HALF_POP' "Duplicated ballistic constants cannot remain in ParkLayout."
Require-Match $layout 'func\s+_add_profiled_snow_body\(' "Jumps, rollers, and aprons must share the sampled snow-profile builder."
Require-Match $layout 'func\s+_add_grid_snow_body\(' "Sculpted snow meshes and collision must come from the same authored grid."
Require-Match $layout 'mesh\.create_trimesh_shape\(\)' "Sculpted snow collision must match the rendered profile mesh."
Require-Match $layout 'lip_samples\s*:=\s*14' "Jump takeoffs must use enough longitudinal samples to round the lip transition."
Require-Match $layout 'table_samples\s*:=\s*10' "Jump knuckles must use a sampled contour instead of a flat slab."
Require-Match $layout 'landing_samples\s*:=\s*14' "Jump landings and run-outs must use a sampled contour."
Require-Match $layout '"BankSurface"' "Side banks must use the transition-shaped bank surface."
Require-Match $layout 'add_rail_contours' "Rails must author approach and run-out snow contours."
Require-Match $builder 'ParkLayout\.add_rail_contours' "Course construction must build rail approach and run-out zones."

$jumpSpecs = [regex]::Matches($course, '(?m)^.*"kind":\s*"(?:tabletop|hip)".*$')
if ($jumpSpecs.Count -eq 0) {
	$failures.Add("Course profile contains no jump specifications to validate.")
}
foreach ($spec in $jumpSpecs) {
	if ($spec.Value -notmatch '"pop"\s*:') {
		$failures.Add("Every tabletop and hip must author its normalized design pop strength.")
		break
	}
}

Require-Match $layout 'add_slope_box\([^\r\n]+surface_kind:\s*int' "Slope construction must accept physical surface identity explicitly."
Reject-Match "$layout`n$resort" 'set_meta\("ski_surface_kind"[^\r\n]*is_equal_approx|_surface_kind_for_color' "Visual color cannot determine physical surface identity."
Require-Match $contact 'collider\.has_meta\("ski_surface_kind"\)' "Contact sampling must accept only explicitly authored surface identity."
Reject-Match $contact 'get_meta\("ski_surface_kind",\s*0\)' "Unmarked terrain cannot silently become Powder."
Require-Match $resort 'collision_layer\s*=\s*1\s+if\s+surface_kind\s*>=\s*0\s+else\s+4' "Non-snow solid boxes must use the Features layer."

Require-Match $rail '@export_range\(-1\.0,\s*1\.0\)\s*var drift_bias' "Rails must expose authored drift bias."
Require-Match $builder 'rail\.drift_bias\s*=\s*float\(spec\.get\("drift_bias"' "Course authoring must apply rail drift bias."
Reject-Match $controller 'name\.length\(\)\s*%\s*2' "Rail balance cannot depend on object-name length."
$railSpecs = [regex]::Matches($course, '(?m)^.*"kind":\s*"rail".*$')
foreach ($spec in $railSpecs) {
	if ($spec.Value -notmatch '"drift_bias"\s*:') {
		$failures.Add("Every authored rail must provide drift bias.")
		break
	}
}

Reject-Match $camera '1\s*\|\s*4\s*\|\s*8' "Camera collision cannot include the Grind layer."
Require-Match $camera 'collision_mask\s*=\s*1\s*\|\s*4' "Camera collision must retain Terrain and Features layers."
Require-Match $camera 'air_vertical_dead_zone' "Airborne camera framing must have a vertical dead zone."
Require-Match $camera 'func _air_framing_target' "Airborne camera framing must use a filtered target seam."
Require-Match $camera 'predicted_landing_look_weight' "Airborne camera must look toward predicted landings during descent."
Require-Match $camera '_collision_reframed' "Camera collision corrections must be damped separately from pose limits."
Require-Match $camera 'maximum_distance_change_rate' "Camera distance changes must have a separate rate limit from translation safety."
Require-Match $camera 'distance_rate_limit' "Camera distance changes must be bounded before final stabilization."

Require-Match $trick 'func set_grab_contact' "Trick scoring must consume visual grab contact."
Require-Match $trick 'grab_qualified' "Grab scoring must require a qualified visual contact latch."
Require-Match $trick 'air_presentation_eligible' "Straight Air presentation must distinguish meaningful takeoffs from reseats."

Require-Match $controller 'brake_amount\s*=\s*Input\.get_action_strength\("brake"\)' "Ground braking must preserve analog action strength."
Reject-Match $controller 'braking\s*=\s*Input\.is_action_pressed\("brake"\)' "Braking cannot collapse analog input to a boolean."
Require-Match $controller 'profile\.brake_steer_multiplier' "Analog brake steering must use the profile."
Require-Match $controller 'profile\.brake_speed_scrub_multiplier\s*\*\s*brake_amount' "Brake speed scrub must scale with analog input."
Require-Match $controller '_constrain_heading_to_travel' "Ground handling must constrain excessive heading/travel separation."

foreach ($telemetryKey in @(
	"steering_raw", "steering", "effective_steer_rate", "brake_amount", "skid_amount",
	"carve_ratio", "available_grip", "centripetal_demand", "heading_travel_angle_degrees", "slope_angle_degrees",
	"landing_control_multiplier"
)) {
	Require-Match $controller ('"' + [regex]::Escape($telemetryKey) + '"\s*:') "Missing handling telemetry: $telemetryKey"
	Require-Match $ui ([regex]::Escape($telemetryKey)) "Debug HUD does not display handling telemetry: $telemetryKey"
}

Require-Match $profile 'landing_control_penalty_max' "Landing steering softness must remain profile-owned."
Require-Match $controller '_begin_landing_control_recovery' "Successful landings must seed severity-scaled control recovery."
Require-Match $camera 'turn_bank_share' "Camera must retain restrained turn banking."
Require-Match $camera 'speed_fov_gain\s*:=\s*7\.0' "Camera speed FOV must stay within the approved restrained range."
Require-Match $camera 'maximum_relative_correction_speed\s*:=\s*12\.0' "Camera must enforce a bounded relative correction speed of 12 m/s."
Require-Match $camera 'composition_comfortable_correction_speed\s*:=\s*8\.0' "Camera must retain a comfortable correction band of 8 m/s."
Require-Match $camera 'composition_debug_allow_legacy_300' "Camera must gate the legacy 300 m/s path behind a debug flag."
Require-Match $camera '_previous_target_position' "Camera must chase via target displacement feed-forward."
Require-Match $camera 'landing_visibility_hard_floor' "Camera must downgrade landing visibility to a quality metric."
Require-Match $camera '_air_entry_time' "Camera must have AIR entry hysteresis for state-transition continuity."

Require-Match $crashContext 'enum Stage\s*\{[\s\S]*RELEASE[\s\S]*IMPACT[\s\S]*FALL[\s\S]*REST' "CrashContext must own the controlled-fall stages."
Require-Match $controller 'func enter_crash\(context:\s*CrashContext\)\s*->\s*bool' "Crash entry must use one guarded controller seam."
Require-Match $controller 'if state == State\.BAIL[\s\S]*?return false' "Duplicate crash entry must be rejected."
Require-Match $controller '_evaluate_feature_crash_after_motion' "Feature impacts must reuse post-motion collision diagnostics."
Require-Match $controller 'feature_collision_min_normal_speed' "Feature-impact thresholds must be profile-owned."
Require-Match $controller 'crash_context\.reset\(\)' "Respawn and recovery must clear transient crash context."
Reject-Match $controller 'velocity\s*\*=\s*profile\.bail_speed_retain' "Crash entry cannot discard momentum with an immediate velocity multiplier."
Require-Match $animationFrame 'var crash_stage:\s*int' "Animation frames must carry immutable crash-stage data."
Require-Match $animationController 'CrashContext\.Stage\.RELEASE' "Animation must present the crash release stage."
Require-Match $animationController 'CrashContext\.Stage\.IMPACT' "Animation must present the crash impact stage."
Require-Match $animationController 'CrashContext\.Stage\.FALL' "Animation must present the crash fall stage."
Require-Match $animationController 'CrashContext\.Stage\.REST' "Animation must present the crash rest stage."
Require-Match $animationController 'MIN_LANDING_PRESENTATION_TIME' "Landing impact presentation must have a minimum visible hold."
Require-Match $animationController '_capture_crash_handoff' "Crash presentation must seed from the current procedural pose."
Reject-Match "$controller`n$animationController" 'PhysicalBone|RigidBody3D|Skeleton3D|PhysicalBoneSimulator3D' "The primitive rig must use controlled fall rather than a new ragdoll framework."
Require-Match $ui 'crash_reason' "Development HUD must expose crash telemetry."
Require-Match $ui 'clean_capture_mode' "HUD must provide a clean capture mode without disabling recording."

Require-Match $layout 'func\s+_add_feature_snow_collar\(' "Park features must receive a grounded snow collar."
Require-Match $layout 'func\s+_add_feature_trim\(' "Park features must expose restrained manufactured trim."
Require-Match $layout 'func\s+_add_rail_support\(' "Elevated rails must show grounded support posts."
Require-Match $courseResource 'takeoff_marker_depth\s*=\s*0\.44' "Takeoff markers need enough bounded depth for shallow approaches."
Require-Match $courseResource 'landing_marker_width\s*=\s*0\.22' "Landing markers need enough bounded width for gameplay readability."
Require-Match $resort 'distant_mountain\.gdshader' "Distant mountains must use the distance-aware presentation shader."
Require-Match $mountainShader 'distance\s*\(CAMERA_POSITION_WORLD' "Distant mountain tint must use actual camera distance."
Require-Match $mountainShader 'smoothstep\(haze_start_distance' "Distant mountain haze must have a bounded depth ramp."

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
	& git -C $RepoRoot diff --check 2>&1 | ForEach-Object { Write-Output $_ }
	$diffExitCode = $LASTEXITCODE
}
finally {
	$ErrorActionPreference = $previousErrorActionPreference
}
if ($diffExitCode -ne 0) {
	$failures.Add("git diff --check failed.")
}

if ($failures.Count -gt 0) {
	$failures | ForEach-Object { Write-Output "FAIL: $_" }
	exit 1
}

Write-Output "PASS: input, shared physics, handling, surface, rail, camera, and telemetry structure is statically valid."
