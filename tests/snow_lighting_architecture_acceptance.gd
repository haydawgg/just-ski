extends Node

## Phase 10 snow lighting architecture acceptance.
##
## The interactive piste must render through the standard shadow-receiving snow
## path while only the presentation-only shoulder relief keeps the shadow-safe
## summit workaround. The summit's value manipulation, the ground/feature
## detail fade ordering, and the resort lighting bands are validated against
## the real built resort.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const SnowMaterial := preload("res://world/snow_material.gd")

const EXPECTED_REGIONS := {"playable": 1, "shoulder_left": 1, "shoulder_right": 1}
const MIN_PLAYABLE_HALF_WIDTH := 26.0
const BOUNDARY_TOLERANCE_M := 0.002
const MIN_GROUND_DETAIL_M := 60.0
const MIN_FEATURE_DETAIL_GAP_M := 16.0
const MAX_SUMMIT_DRIFT := 0.25
const MAX_SUMMIT_FLOOR := 0.5
const MIN_SNOW_LUMINANCE_FLOOR := 0.4

@onready var resort: Node3D = $Resort

var failures: Array[String] = []
var profile: SummitEnvironmentProfile

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	profile = resort.get("summit_environment_profile") as SummitEnvironmentProfile
	_validate_region_architecture()
	_validate_region_boundary()
	_validate_detail_fades()
	_validate_value_bounds()
	_finish()

func _validate_region_architecture() -> void:
	if profile == null or not profile.enabled:
		failures.append("Summit presentation profile was unavailable")
		return
	var region_counts: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("environment_summit_visual"):
		var visual := node as MeshInstance3D
		if visual == null or visual.mesh == null:
			failures.append("Summit render region %s is not a mesh" % node.name)
			continue
		var region := str(visual.get_meta("summit_render_region", ""))
		region_counts[region] = int(region_counts.get(region, 0)) + 1
		var material := visual.material_override as ShaderMaterial
		if material == null or material.shader == null:
			failures.append("Summit render region %s has no snow shader material" % node.name)
		elif region == "playable":
			if bool(material.get("render_shadow_safe")) or material.shader == SnowMaterial.SUMMIT_SHADER:
				failures.append("Playable piste still uses the shadow-safe summit workaround")
			if material.shader != SnowMaterial.PREMIUM_SHADER and material.shader != SnowMaterial.FAST_SHADER:
				failures.append("Playable piste does not use a standard shadow-receiving snow tier")
		elif region.begins_with("shoulder"):
			if not bool(material.get("render_shadow_safe")) or material.shader != SnowMaterial.SUMMIT_SHADER:
				failures.append("Shoulder relief %s lost its shadow-safe summit material" % node.name)
		if visual.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
			failures.append("Summit render region %s is no longer GI-excluded" % node.name)
	if region_counts != EXPECTED_REGIONS:
		failures.append("Summit render regions were %s (expected %s)" % [region_counts, EXPECTED_REGIONS])
	var main_face := resort.get_node_or_null("MainSnowFace") as StaticBody3D
	if main_face == null:
		failures.append("MainSnowFace is missing")
		return
	for mesh_node: Node in main_face.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null:
			continue
		if mesh_instance.visible:
			failures.append("Coarse MainSnowFace render mesh is visible again")
		if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("Coarse MainSnowFace render mesh resumed shadow casting")
		if not bool(mesh_instance.get_meta("gi_exclude", false)):
			failures.append("Coarse MainSnowFace render mesh is no longer GI-excluded")
	if not main_face.find_children("*", "CollisionShape3D", true, false).is_empty() and main_face.collision_layer != 1:
		failures.append("MainSnowFace collision layer changed while splitting the render surface")

func _validate_region_boundary() -> void:
	if profile == null:
		return
	var playable_half := clampf(profile.playable_half_width_m, 1.0, ParkLayout.FACE_WIDTH * 0.5)
	var outer_half := clampf(profile.outer_half_width_m, playable_half + 1.0, ParkLayout.FACE_WIDTH * 0.5)
	if playable_half < MIN_PLAYABLE_HALF_WIDTH:
		failures.append("Playable render region is only %.1f m half-width" % playable_half)
	var playable_visual := _region_visual("playable")
	var right_visual := _region_visual("shoulder_right")
	if playable_visual == null or right_visual == null:
		return
	var playable_edge := _boundary_heights(playable_visual, playable_half)
	var shoulder_edge := _boundary_heights(right_visual, playable_half)
	if playable_edge.is_empty() or shoulder_edge.is_empty():
		failures.append("Playable/shoulder render regions do not share the x=%.1f m boundary column" % playable_half)
		return
	var maximum_gap := 0.0
	for z_key: float in playable_edge:
		if not shoulder_edge.has(z_key):
			failures.append("Boundary column row z=%.1f is missing from the right shoulder region" % z_key)
			continue
		maximum_gap = maxf(maximum_gap, absf(float(playable_edge[z_key]) - float(shoulder_edge[z_key])))
	print("LIGHTING_BOUNDARY_SAMPLE x=%.1f max_gap=%.4f rows=%d" % [playable_half, maximum_gap, playable_edge.size()])
	if maximum_gap > BOUNDARY_TOLERANCE_M:
		failures.append("Playable/shoulder boundary columns diverged %.4f m" % maximum_gap)
	# The outer relief must still be present beyond the playable boundary.
	var shoulder_outer := _boundary_heights(right_visual, outer_half)
	var relief := 0.0
	for z_key: float in shoulder_outer:
		if playable_edge.has(z_key):
			relief = maxf(relief, absf(float(shoulder_outer[z_key]) - float(playable_edge[z_key])))
	if relief < 0.02:
		failures.append("Shoulder region carries no relief beyond the playable boundary")

func _validate_detail_fades() -> void:
	var presentation := SnowMaterial.PRESENTATION
	var ground_detail := presentation.detail_far_distance
	var feature_detail := presentation.park_feature_detail_far_distance
	if ground_detail < MIN_GROUND_DETAIL_M:
		failures.append("Ground snow detail fades at %.1f m; the piste loses form before the park features" % ground_detail)
	if feature_detail - ground_detail < MIN_FEATURE_DETAIL_GAP_M:
		failures.append("Park feature detail (%.1f m) is not meaningfully farther than ground detail (%.1f m)" % [feature_detail, ground_detail])
	print("LIGHTING_DETAIL_SAMPLE ground=%.1f feature=%.1f" % [ground_detail, feature_detail])

func _validate_value_bounds() -> void:
	var presentation := SnowMaterial.PRESENTATION
	if presentation.summit_drift_strength > MAX_SUMMIT_DRIFT:
		failures.append("Summit drift is %.3f; additive/strong drift compresses terrain values" % presentation.summit_drift_strength)
	if presentation.summit_luminance_floor > MAX_SUMMIT_FLOOR:
		failures.append("Summit luminance floor is %.2f; the floor flattens shadowed relief" % presentation.summit_luminance_floor)
	if presentation.minimum_albedo_luminance < MIN_SNOW_LUMINANCE_FLOOR:
		failures.append("Snow readability luminance floor dropped below %.2f" % MIN_SNOW_LUMINANCE_FLOOR)
	var sun := resort.get("sun") as DirectionalLight3D
	if sun == null or not sun.shadow_enabled:
		failures.append("Resort sun lost its directional shadow source")
	print("LIGHTING_VALUE_SAMPLE summit_drift=%.3f summit_floor=%.2f albedo_floor=%.2f" % [presentation.summit_drift_strength, presentation.summit_luminance_floor, presentation.minimum_albedo_luminance])

func _region_visual(region: String) -> MeshInstance3D:
	for node: Node in get_tree().get_nodes_in_group("environment_summit_visual"):
		var visual := node as MeshInstance3D
		if visual != null and str(visual.get_meta("summit_render_region", "")) == region:
			return visual
	return null

func _boundary_heights(visual: MeshInstance3D, boundary_x: float) -> Dictionary:
	var result: Dictionary = {}
	var arrays := (visual.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index: int in range(vertices.size()):
		if normals[index].dot(ParkLayout.snow_normal()) <= 0.3:
			continue
		var vertex := vertices[index]
		if absf(vertex.x - boundary_x) <= 0.01:
			result[snappedf(vertex.z, 0.01)] = vertex.y
	return result

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("SNOW_LIGHTING_ARCHITECTURE_PASS: playable piste receives shadows, shoulder relief keeps the shadow-safe workaround, and value/detail bounds hold")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SNOW_LIGHTING_ARCHITECTURE_FAIL: " + failure)
	get_tree().quit(1)
