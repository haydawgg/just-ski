class_name CompositionEvaluator
extends RefCounted

## Pure screen-space composition math. World queries remain with the camera
## collision/query module; this module owns projection, bounds, correction, and
## candidate scoring so those rules have one testable implementation.

static func project_point(camera_position: Vector3, camera_basis: Basis, fov: float, viewport_size: Vector2, world_position: Vector3) -> Dictionary:
	var camera_space := Transform3D(camera_basis, camera_position).affine_inverse() * world_position
	var depth := -camera_space.z
	var safe_depth := maxf(depth, 0.01)
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var focal_scale := 1.0 / tan(deg_to_rad(fov) * 0.5)
	return {
		"screen": Vector2(
			0.5 + camera_space.x * focal_scale / (aspect * safe_depth) * 0.5,
			0.5 - camera_space.y * focal_scale / safe_depth * 0.5
		),
		"depth": depth,
	}

static func rect_violation(value: Rect2, container: Rect2) -> float:
	var value_end := value.position + value.size
	var container_end := container.position + container.size
	return maxf(0.0, maxf(
		maxf(container.position.x - value.position.x, value_end.x - container_end.x),
		maxf(container.position.y - value.position.y, value_end.y - container_end.y)
	))

static func evaluate_landmarks(
	projected_points: Array[Dictionary],
	foreground_occluded_count: int,
	landmark_count: int,
	hard_rect: Rect2,
	inner_rect: Rect2
) -> Dictionary:
	var bounds := Rect2()
	var bounds_initialized := false
	var average_depth := 0.0
	var depth_count := 0
	var body_occluded := foreground_occluded_count
	var behind_count := 0
	for projected: Dictionary in projected_points:
		var depth_val := float(projected.get("depth", -1.0))
		if depth_val <= 0.01:
			behind_count += 1
			body_occluded += 1
			continue
		var screen := projected.get("screen", Vector2(INF, INF)) as Vector2
		if not screen.is_finite():
			behind_count += 1
			body_occluded += 1
			continue
		if not bounds_initialized:
			bounds = Rect2(screen, Vector2.ZERO)
			bounds_initialized = true
		else:
			bounds = bounds.expand(screen)
		average_depth += depth_val
		depth_count += 1
	if not bounds_initialized:
		bounds = Rect2(-10.0, -10.0, 20.0, 20.0)
	var depth := average_depth / maxf(float(depth_count), 1.0)
	var body_occlusion := float(body_occluded) / maxf(float(landmark_count), 1.0)
	var hard_violation := rect_violation(bounds, hard_rect)
	var inner_violation := rect_violation(bounds, inner_rect)
	if behind_count > 0:
		hard_violation = INF
		inner_violation = INF
	return {
		"skier_screen_rect": bounds,
		"hard_violation": hard_violation,
		"inner_violation": inner_violation,
		"body_occlusion": body_occlusion,
		"average_depth": depth,
	}

static func screen_correction_world_offset(
	evaluation: Dictionary,
	desired_rect: Rect2,
	camera_basis: Basis,
	fov: float,
	viewport_size: Vector2,
	minimum_depth: float
) -> Vector3:
	var bounds := evaluation.get("skier_screen_rect", Rect2()) as Rect2
	var rect_end := desired_rect.position + desired_rect.size
	var bounds_end := bounds.position + bounds.size
	var screen_delta := Vector2.ZERO
	if bounds.position.x < desired_rect.position.x:
		screen_delta.x = desired_rect.position.x - bounds.position.x
	elif bounds_end.x > rect_end.x:
		screen_delta.x = rect_end.x - bounds_end.x
	if bounds.position.y < desired_rect.position.y:
		screen_delta.y = desired_rect.position.y - bounds.position.y
	elif bounds_end.y > rect_end.y:
		screen_delta.y = rect_end.y - bounds_end.y
	if screen_delta.length_squared() < 0.000001:
		return Vector3.ZERO
	var depth := maxf(float(evaluation.get("average_depth", minimum_depth)), minimum_depth)
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var vertical_extent := 2.0 * depth * tan(deg_to_rad(fov) * 0.5)
	var horizontal_extent := vertical_extent * aspect
	return -camera_basis.x.normalized() * screen_delta.x * horizontal_extent + camera_basis.y.normalized() * screen_delta.y * vertical_extent

static func score(evaluation: Dictionary, movement: float) -> float:
	var hard_violation := float(evaluation.get("hard_violation", INF))
	var inner_violation := float(evaluation.get("inner_violation", INF))
	var landing_violation := float(evaluation.get("landing_violation", 0.0))
	var body_occlusion := float(evaluation.get("body_occlusion", 1.0))
	var landing_occlusion := float(evaluation.get("landing_occlusion", 0.0))
	if not is_finite(hard_violation) or hard_violation == INF:
		hard_violation = 1.0
	if not is_finite(inner_violation) or inner_violation == INF:
		inner_violation = 1.0
	if not is_finite(movement):
		movement = 0.0
	var landing_penalty := landing_violation * 30.0 + landing_occlusion * 20.0
	return hard_violation * 10000.0 + body_occlusion * 500.0 + inner_violation * 20.0 + landing_penalty + movement * 0.8

static func hard_valid(evaluation: Dictionary, maximum_body_occlusion_fraction: float) -> bool:
	return float(evaluation.get("hard_violation", INF)) <= 0.0001 and float(evaluation.get("body_occlusion", 1.0)) <= maximum_body_occlusion_fraction
