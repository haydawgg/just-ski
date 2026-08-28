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
$contact = Read-RequiredFile "player/ski_contact_solver.gd"
$camera = Read-RequiredFile "player/camera_controller.gd"
$resort = Read-RequiredFile "world/resort.gd"
$layout = Read-RequiredFile "world/park_features/park_layout.gd"
$rail = Read-RequiredFile "world/park_features/grind_rail_3d.gd"
$builder = Read-RequiredFile "world/course/park_course_builder.gd"
$course = Read-RequiredFile "world/course/park_course_profile.gd"
$ui = Read-RequiredFile "ui/hud/game_ui.gd"

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
Require-Match $resort 'ParkCourseBuilderModule\.build\(self,\s*course_profile,\s*physics_profile\)' "Course construction must receive the active profile."
Require-Match $resort 'player\.profile\s*=\s*physics_profile' "The skier must receive the same active profile."
Require-Match $builder 'build\(parent:\s*Node3D,\s*profile:\s*ParkCourseProfile,\s*physics_profile:\s*SkiPhysicsProfile\)' "The course builder interface must require the active profile."
Require-Match $layout 'resolved_pop_strength\s*:=\s*design_pop_strength\s+if\s+design_pop_strength\s*>=\s*0\.0\s+else\s+physics_profile\.minimum_pop_strength' "Omitted design pop must resolve through the active profile."
Require-Match $layout 'physics_profile\.pop_impulse\s*\*\s*clampf\(resolved_pop_strength' "Jump sizing must use active-profile pop impulse."
Require-Match $layout 'physics_profile\.air_gravity' "Jump sizing must use active-profile air gravity."
Reject-Match $layout 'const\s+AIR_GRAVITY|const\s+HALF_POP' "Duplicated ballistic constants cannot remain in ParkLayout."

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
Require-Match $camera 'PhysicsRayQueryParameters3D\.create\(from,\s*desired,\s*1\s*\|\s*4\)' "Camera collision must retain Terrain and Features layers."

Require-Match $controller 'brake_amount\s*=\s*Input\.get_action_strength\("brake"\)' "Ground braking must preserve analog action strength."
Reject-Match $controller 'braking\s*=\s*Input\.is_action_pressed\("brake"\)' "Braking cannot collapse analog input to a boolean."
Require-Match $controller 'profile\.brake_steer_multiplier' "Analog brake steering must use the profile."
Require-Match $controller 'profile\.brake_speed_scrub_multiplier\s*\*\s*brake_amount' "Brake speed scrub must scale with analog input."
Require-Match $controller '_constrain_heading_to_travel' "Ground handling must constrain excessive heading/travel separation."

foreach ($telemetryKey in @(
	"steering_raw", "steering", "effective_steer_rate", "brake_amount", "skid_amount",
	"carve_ratio", "available_grip", "centripetal_demand", "heading_travel_angle_degrees", "slope_angle_degrees"
)) {
	Require-Match $controller ('"' + [regex]::Escape($telemetryKey) + '"\s*:') "Missing handling telemetry: $telemetryKey"
	Require-Match $ui ([regex]::Escape($telemetryKey)) "Debug HUD does not display handling telemetry: $telemetryKey"
}

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
