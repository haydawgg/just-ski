extends Node

## Headless backdrop visibility diagnostic. Boots the authored resort, then for
## every environment_backdrop ridge reports the geometry that decides whether
## the gameplay camera can actually read it: distance, frustum containment,
## elevation above the local terrain silhouette, and fog transmittance.
## Camera poses default to vantages recorded from the maintained visual sweep
## and the canonical carve capture so the numbers match the evidence bundles.
## CLI overrides: --camera-pos=x,y,z --camera-forward=x,y,z --fov=<deg>

const ParkLayout := preload("res://world/park_features/park_layout.gd")

const VIEW_ASPECT := 16.0 / 9.0
const DEFAULT_FOV := 69.0
const MIN_READABLE_RIDGES := 3
const MIN_FAR_TRANSMITTANCE := 0.25

const DEFAULT_POSES: Array[Dictionary] = [
	{
		"label": "sweep_frame500",
		"position": Vector3(-0.3, 109.2, 170.7),
		"forward": Vector3(-0.082, -0.472, -0.878),
		"fov": DEFAULT_FOV,
	},
	{
		"label": "canonical_carve",
		"position": Vector3(0.0, 97.7, 137.0),
		"forward": Vector3(0.05, -0.47, -0.88),
		"fov": DEFAULT_FOV,
	},
]

@onready var resort: Node3D = $Resort


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run_probe()


func _run_probe() -> void:
	var ridges := _collect_ridges()
	if ridges.is_empty():
		push_error("BACKDROP_PROBE_FAIL: resort built no environment_backdrop ridges")
		AudioManager.shutdown_audio()
		get_tree().quit(1)
		return
	var fog_density := _read_fog_density()
	var poses := _resolve_poses()
	var failures: Array[String] = []
	for pose in poses:
		failures.append_array(_evaluate_pose(pose, ridges, fog_density))
	if failures.is_empty():
		print("BACKDROP_PROBE_PASS: %d ridges evaluated across %d vantages" % [ridges.size(), poses.size()])
		AudioManager.shutdown_audio()
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("BACKDROP_PROBE_FAIL: " + failure)
		AudioManager.shutdown_audio()
		get_tree().quit(1)


func _collect_ridges() -> Array[Dictionary]:
	var ridges: Array[Dictionary] = []
	for node: Node in resort.find_children("*", "Node3D", true, false):
		if not node.has_meta("environment_backdrop"):
			continue
		var root := node as Node3D
		var body := root.get_node_or_null("RidgeBody") as MeshInstance3D
		if body == null or body.mesh == null:
			continue
		var aabb := body.mesh.get_aabb()
		ridges.append({
			"name": str(root.name),
			"position": root.global_position,
			"top_y": root.global_position.y + aabb.position.y + aabb.size.y,
			"base_y": root.global_position.y + aabb.position.y,
		})
	return ridges


func _read_fog_density() -> float:
	var world_environment := resort.get("environment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return 0.0
	return world_environment.environment.fog_density


func _resolve_poses() -> Array[Dictionary]:
	var camera_text := _argument_value("--camera-pos=")
	var forward_text := _argument_value("--camera-forward=")
	if not camera_text.is_empty() and not forward_text.is_empty():
		return [{
			"label": "cli_override",
			"position": _parse_vector3(camera_text),
			"forward": _parse_vector3(forward_text).normalized(),
			"fov": _argument_float("--fov=", DEFAULT_FOV),
		}]
	return DEFAULT_POSES


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _argument_float(prefix: String, fallback: float) -> float:
	var text := _argument_value(prefix)
	if text.is_empty() or not text.is_valid_float():
		return fallback
	return float(text)


func _parse_vector3(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(
		float(parts[0]) if parts[0].is_valid_float() else 0.0,
		float(parts[1]) if parts[1].is_valid_float() else 0.0,
		float(parts[2]) if parts[2].is_valid_float() else 0.0
	)


func _evaluate_pose(pose: Dictionary, ridges: Array[Dictionary], fog_density: float) -> Array[String]:
	var failures: Array[String] = []
	var camera := pose.position as Vector3
	var forward := (pose.forward as Vector3).normalized()
	var fov := float(pose.fov)
	var pitch := asin(clampf(-forward.y, -1.0, 1.0))
	var half_vertical := deg_to_rad(fov * 0.5)
	var frame_top := -pitch + half_vertical
	var frame_bottom := -pitch - half_vertical
	var half_horizontal := atan(tan(half_vertical) * VIEW_ASPECT)
	print("BACKDROP_PROBE_CAMERA label=%s pos=%s pitch_deg=%.1f frame_top_deg=%.1f frame_bottom_deg=%.1f hfov_half_deg=%.1f fog_density=%.5f" % [
		str(pose.label), camera, rad_to_deg(pitch), rad_to_deg(frame_top), rad_to_deg(frame_bottom), rad_to_deg(half_horizontal), fog_density,
	])
	var silhouette_count := 0
	var readable_count := 0
	for ridge in ridges:
		var ridge_position := ridge.position as Vector3
		var top_angle := _elevation_angle(camera, ridge_position.x, float(ridge.top_y), ridge_position.z)
		var horizon := _terrain_horizon_elevation(camera, ridge_position.x, ridge_position.z)
		var lateral := _lateral_angle(camera, forward, ridge_position)
		var distance := float(camera.distance_to(ridge_position))
		var transmittance := exp(-fog_density * distance)
		var in_frame := top_angle < frame_top and top_angle > frame_bottom and lateral < half_horizontal
		var above_horizon := top_angle > horizon
		var readable := in_frame and above_horizon and transmittance >= MIN_FAR_TRANSMITTANCE
		if in_frame and above_horizon:
			silhouette_count += 1
		if readable:
			readable_count += 1
		print("BACKDROP_PROBE_RIDGE label=%s name=%s dist=%.0f top_y=%.1f top_deg=%+.1f horizon_deg=%+.1f lateral_deg=%.1f in_frame=%s above_horizon=%s transmittance=%.2f readable=%s" % [
			str(pose.label), str(ridge.name), distance, float(ridge.top_y), rad_to_deg(top_angle), rad_to_deg(horizon), rad_to_deg(lateral),
			str(in_frame).to_lower(), str(above_horizon).to_lower(), transmittance, str(readable).to_lower(),
		])
	if silhouette_count < MIN_READABLE_RIDGES:
		failures.append("%s: only %d of %d ridges rise above the terrain silhouette inside the frame (need %d)" % [
			str(pose.label), silhouette_count, ridges.size(), MIN_READABLE_RIDGES,
		])
	if readable_count < MIN_READABLE_RIDGES:
		failures.append("%s: only %d of %d ridges survive fog well enough to read (need %d)" % [
			str(pose.label), readable_count, ridges.size(), MIN_READABLE_RIDGES,
		])
	var roi := _roi_distance_band(camera, pitch, half_vertical)
	print("BACKDROP_PROBE_ROI label=%s slope_distance_min_m=%.0f slope_distance_max_m=%.0f" % [str(pose.label), roi.x, roi.y])
	return failures


func _elevation_angle(camera: Vector3, x: float, y: float, z: float) -> float:
	var horizontal := Vector2(x - camera.x, z - camera.z).length()
	return atan2(y - camera.y, horizontal)


func _terrain_horizon_elevation(camera: Vector3, x: float, z: float) -> float:
	# The slope is a single plane, so the sight line's depression angle grows
	# monotonically with distance. The terrain silhouette ends at the face's
	# downhill edge; ridges sitting inside the face z-range are silhouetted
	# against the plane only up to their own base distance.
	var half := ParkLayout.face_half_world_z()
	var ground_z := minf(z, -half)
	var horizontal := Vector2(x - camera.x, ground_z - camera.z).length()
	var ground_y := ParkLayout.snow_at(x, ground_z).y
	return atan2(ground_y - camera.y, horizontal)


func _lateral_angle(camera: Vector3, forward: Vector3, target: Vector3) -> float:
	var view := Vector2(forward.x, forward.z)
	var target_ground := Vector2(target.x - camera.x, target.z - camera.z)
	if view.length_squared() < 0.000001 or target_ground.length_squared() < 0.000001:
		return 0.0
	return absf(view.normalized().angle_to(target_ground.normalized()))


func _roi_distance_band(camera: Vector3, pitch: float, half_vertical: float) -> Vector2:
	# Metric rows 0.42..0.88 of the 720p frame map to slope-surface distances;
	# report the band so snow-shading work knows which distances it must fix.
	var near_angle := _row_angle(0.88, pitch, half_vertical)
	var far_angle := _row_angle(0.42, pitch, half_vertical)
	return Vector2(_slope_distance_for_depression(camera, near_angle), _slope_distance_for_depression(camera, far_angle))


func _row_angle(row: float, pitch: float, half_vertical: float) -> float:
	return pitch + atan(tan(half_vertical) * (1.0 - 2.0 * row))


func _slope_distance_for_depression(camera: Vector3, angle: float) -> float:
	var slope := tan(ParkLayout.pitch_rad())
	var low := 5.0
	var high := 800.0
	for _step: int in range(48):
		var mid := (low + high) * 0.5
		var ground_y := ParkLayout.snow_at(0.0, camera.z - mid).y
		var depression := atan2(camera.y - ground_y, mid)
		if depression < angle:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5
