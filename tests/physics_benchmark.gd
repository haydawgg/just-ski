extends Node

const ParkLayout := preload("res://world/park_features/park_layout.gd")

const SAMPLE_INTERVAL := 2
const BENCHMARK_START_POSITION := Vector3(28.0, 97.932, 138.0)
const SETTLE_SECONDS := 1.0
const PURE_CARVE_SECONDS := 3.5
const LINK_TURN_SECONDS := 1.4
const LINK_STEER_AMOUNT := 0.45

const SAMPLE_SCHEMA := [
	"phase", "t", "position_x", "position_y", "position_z", "velocity_x", "velocity_y", "velocity_z",
	"heading_deg", "state", "carve_ratio", "skid_ratio", "edge", "centripetal_demand", "slope_deg",
	"steering_input", "speed_mps", "velocity_heading_deg", "heading_velocity_angle_deg", "lateral_acceleration",
	"grounded", "collision_count", "collision_colliders", "speed_discontinuity",
]

@onready var resort: Node = $Resort
var skier: SkierController
var benchmark_start_transform := Transform3D.IDENTITY
var tick := 0
var clock := 0.0
var phase := "BOOT"
var phase_timer := 0.0
var phase_names: Array[String] = ["BOOT"]
var samples: Array = []
var landings: Array = []
var air_windows: Array = []
var collision_events: Array = []
var speed_discontinuities: Array = []
var latest_telemetry: Dictionary = {}
var scenario_label := ""
var carve_start_speed := 0.0
var carve_min_speed := INF
var carve_start_heading := 0.0
var carve_end_heading := 0.0
var carve_grounded_frames := 0
var link_min_speed := INF
var link_collision_count := 0
var acceleration_start_speed := 0.0
var acceleration_end_speed := 0.0
var acceleration_air_frames := 0
var brake_start_speed := 0.0
var brake_end_speed := 0.0
var air_tracked := false
var air_entry_clock := 0.0
var air_takeoff_pos := Vector3.ZERO
var air_peak_height := 0.0
var air_spin_degrees := 0.0
var air_takeoff_speed := 0.0
var air_trick_name := ""
var grab_armed_press_pending := false
var grab_released_before_landing := false
var completed_tricks: Array = []
var failures: Array[String] = []
var high_speed_start_speed := 0.0
var high_speed_min_speed := INF
var high_speed_start_heading := 0.0
var high_speed_quarter_heading := 0.0
var high_speed_end_heading := 0.0
var high_speed_quarter_captured := false
var high_speed_max_heading_travel := 0.0
var high_speed_min_carve_ratio := 1.0
var high_speed_max_skid := 0.0
var high_speed_max_edge := 0.0

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	skier.landed.connect(_on_landed)
	skier.trick.trick_landed.connect(_on_trick_landed)
	skier.telemetry_updated.connect(_on_telemetry)
	benchmark_start_transform = Transform3D(ParkLayout.downhill_basis(), BENCHMARK_START_POSITION)
	_reset_scenario("BOOT")
	_begin("SETTLE")

func _on_telemetry(data: Dictionary) -> void:
	latest_telemetry = data
	var colliders: Array = data.get("collision_colliders", [])
	var feature_colliders: Array[String] = []
	for collider: String in colliders:
		if collider != "MainSnowFace":
			feature_colliders.append(collider)
	if not feature_colliders.is_empty() and _is_route_diagnostic_phase():
		collision_events.append({
			"frame": tick,
			"t": snappedf(clock, 0.001),
			"phase": phase,
			"colliders": feature_colliders,
			"position": skier.global_position,
			"grounded": bool(data.get("grounded", false)),
			"diagnostics": data.get("collision_diagnostics", []),
		})
		if phase.begins_with("LINK_"):
			link_collision_count += feature_colliders.size()
	var discontinuity: Dictionary = data.get("speed_discontinuity", {})
	if not discontinuity.is_empty():
		discontinuity = discontinuity.duplicate()
		discontinuity["frame"] = tick
		discontinuity["t"] = snappedf(clock, 0.001)
		discontinuity["phase"] = phase
		speed_discontinuities.append(discontinuity)
		print("BENCH_SPEED_DISCONTINUITY ", JSON.stringify(discontinuity))

func _on_landed(result: Dictionary) -> void:
	landings.append({
		"t": snappedf(clock, 0.01),
		"phase": phase,
		"outcome": LandingSolver.Outcome.keys()[int(result.outcome)],
		"score": snappedf(float(result.score), 0.001),
		"impact": snappedf(float(result.impact), 0.001),
	})

func _on_trick_landed(text: String, points: int, quality: float) -> void:
	completed_tricks.append({"text": text, "points": points, "quality": snappedf(quality, 0.001)})

func _physics_process(delta: float) -> void:
	tick += 1
	clock += delta
	_sample()
	_grab_window()
	_air_tracking()
	phase_timer += delta
	match phase:
		"SETTLE":
			if phase_timer >= 3.0:
				carve_start_speed = skier.velocity.length()
				carve_min_speed = carve_start_speed
				carve_start_heading = _heading_degrees()
				carve_grounded_frames = 0
				_begin("PURE_CARVE")
				Input.action_press("steer_left", 1.0)
		"PURE_CARVE":
			carve_min_speed = minf(carve_min_speed, skier.velocity.length())
			carve_end_heading = _heading_degrees()
			if skier.contact.grounded:
				carve_grounded_frames += 1
			if phase_timer >= PURE_CARVE_SECONDS:
				Input.action_release("steer_left")
				_reset_scenario("LINKED_S_TURN")
				_begin("LINK_SETTLE")
		"LINK_SETTLE":
			if phase_timer >= SETTLE_SECONDS:
				_begin("LINK_ACCEL")
		"LINK_ACCEL":
			if phase_timer >= 1.2:
				link_min_speed = INF
				link_collision_count = 0
				_begin("LINK_L1")
				Input.action_press("steer_left", LINK_STEER_AMOUNT)
		"LINK_L1":
			link_min_speed = minf(link_min_speed, skier.velocity.length())
			if phase_timer >= LINK_TURN_SECONDS:
				Input.action_release("steer_left")
				_begin("LINK_R1")
				Input.action_press("steer_right", LINK_STEER_AMOUNT)
		"LINK_R1":
			link_min_speed = minf(link_min_speed, skier.velocity.length())
			if phase_timer >= LINK_TURN_SECONDS:
				Input.action_release("steer_right")
				_begin("LINK_L2")
				Input.action_press("steer_left", LINK_STEER_AMOUNT)
		"LINK_L2":
			link_min_speed = minf(link_min_speed, skier.velocity.length())
			if phase_timer >= LINK_TURN_SECONDS:
				Input.action_release("steer_left")
				_begin("LINK_R2")
				Input.action_press("steer_right", LINK_STEER_AMOUNT)
		"LINK_R2":
			link_min_speed = minf(link_min_speed, skier.velocity.length())
			if phase_timer >= LINK_TURN_SECONDS:
				Input.action_release("steer_right")
				_reset_scenario("HIGH_SPEED_CARVE")
				_begin("HIGH_SPEED_SETTLE")
		"HIGH_SPEED_SETTLE":
			if phase_timer >= SETTLE_SECONDS and skier.state == SkierController.State.GROUND:
				skier.velocity = ParkLayout.downhill() * 22.0
				skier.global_basis = ParkLayout.downhill_basis()
				high_speed_start_speed = skier.velocity.length()
				high_speed_min_speed = high_speed_start_speed
				high_speed_start_heading = _heading_degrees()
				high_speed_quarter_heading = high_speed_start_heading
				high_speed_end_heading = high_speed_start_heading
				high_speed_quarter_captured = false
				high_speed_max_heading_travel = 0.0
				high_speed_min_carve_ratio = 1.0
				high_speed_max_skid = 0.0
				high_speed_max_edge = 0.0
				_begin("HIGH_SPEED_CARVE")
				Input.action_press("steer_left", 1.0)
		"HIGH_SPEED_CARVE":
			high_speed_min_speed = minf(high_speed_min_speed, skier.velocity.length())
			high_speed_end_heading = _heading_degrees()
			high_speed_max_heading_travel = maxf(high_speed_max_heading_travel, absf(skier.heading_travel_angle_degrees))
			high_speed_min_carve_ratio = minf(high_speed_min_carve_ratio, skier.current_carve_ratio)
			high_speed_max_skid = maxf(high_speed_max_skid, skier.skid_amount)
			high_speed_max_edge = maxf(high_speed_max_edge, absf(skier.edge_amount))
			if not high_speed_quarter_captured and phase_timer >= 0.25:
				high_speed_quarter_heading = high_speed_end_heading
				high_speed_quarter_captured = true
			if phase_timer >= 1.0:
				Input.action_release("steer_left")
				_reset_scenario("GROUND_ACCELERATION_TEST")
				_begin("ACCEL_SETTLE")
		"ACCEL_SETTLE":
			if phase_timer >= SETTLE_SECONDS and skier.state == SkierController.State.GROUND:
				# Zero the settled body once, so this measures ground acceleration from
				# rest rather than including the deterministic reset drop.
				skier.velocity = Vector3.ZERO
				acceleration_start_speed = 0.0
				acceleration_air_frames = 0
				_begin("GROUND_ACCELERATION_TEST")
		"GROUND_ACCELERATION_TEST":
			if not skier.contact.grounded:
				acceleration_air_frames += 1
			if phase_timer >= 3.0:
				acceleration_end_speed = skier.velocity.length()
				_reset_scenario("CHARGED_POP")
				_begin("POP_SETTLE")
		"POP_SETTLE":
			if phase_timer >= SETTLE_SECONDS:
				_begin("POP_CHARGE")
				Input.action_press("jump", 1.0)
		"POP_CHARGE":
			if phase_timer >= 0.5:
				Input.action_release("jump")
				_begin("POP_AIR")
		"POP_AIR":
			if skier.state == SkierController.State.GROUND and phase_timer > 0.5:
				_reset_scenario("LEFT_360")
				_begin("TRICK_SETTLE")
		"TRICK_SETTLE":
			if phase_timer >= SETTLE_SECONDS:
				_begin("TRICK_PRELOAD")
				Input.action_press("trick_down", 1.0)
		"TRICK_PRELOAD":
			if phase_timer >= 0.4:
				Input.action_release("trick_down")
				Input.action_press("trick_left", 1.0)
				_begin("TRICK_FLICK")
		"TRICK_FLICK":
			if phase_timer >= 3.0 / float(Engine.physics_ticks_per_second):
				Input.action_release("trick_left")
				_begin("TRICK_AIR")
		"TRICK_AIR":
			if skier.state == SkierController.State.GROUND and phase_timer > 0.5:
				_reset_scenario("SAFETY_GRAB_LEFT")
				_begin("GRAB_SETTLE")
		"GRAB_SETTLE":
			if phase_timer >= SETTLE_SECONDS:
				_begin("GRAB_CHARGE")
				Input.action_press("jump", 1.0)
		"GRAB_CHARGE":
			if phase_timer >= 0.5:
				Input.action_release("jump")
				_begin("GRAB_AIR")
		"GRAB_AIR":
			if air_tracked and not grab_released_before_landing and clock - air_entry_clock >= 0.55:
				Input.action_release("grab_left")
				grab_released_before_landing = true
			if skier.state == SkierController.State.GROUND and phase_timer > 0.5:
				_reset_scenario("BRAKE_TEST")
				_begin("BRAKE_SETTLE")
		"BRAKE_SETTLE":
			if phase_timer >= 1.5:
				brake_start_speed = skier.velocity.length()
				_begin("BRAKE_TEST")
				Input.action_press("brake", 1.0)
		"BRAKE_TEST":
			if phase_timer >= 1.5:
				Input.action_release("brake")
				brake_end_speed = skier.velocity.length()
				_finish()

func _begin(name_value: String) -> void:
	phase = name_value
	phase_timer = 0.0
	phase_names.append(name_value)
	if name_value == "PURE_CARVE":
		carve_start_speed = skier.velocity.length()
		carve_min_speed = carve_start_speed
		carve_start_heading = _heading_degrees()
		carve_end_heading = carve_start_heading

func _reset_scenario(label: String) -> void:
	_release_inputs()
	SessionManager.clear_marker()
	skier.reset_for_benchmark(benchmark_start_transform)
	scenario_label = label
	latest_telemetry = {}
	air_tracked = false
	grab_armed_press_pending = false
	if label == "SAFETY_GRAB_LEFT":
		grab_released_before_landing = false
	print(
		"BENCH_RESET label=", label,
		" position=", skier.global_position,
		" state=", SkierController.State.keys()[skier.state],
		" velocity=", skier.velocity
	)
	if skier.global_position.distance_to(benchmark_start_transform.origin) > 0.01:
		push_error("BENCH_RESET_FAIL: reset position drifted from immutable benchmark start")
	if skier.state != SkierController.State.AIR or skier.velocity.length() > 0.01:
		push_error("BENCH_RESET_FAIL: reset did not clear air state or velocity")

func _release_inputs() -> void:
	for action: StringName in [&"steer_left", &"steer_right", &"jump", &"brake", &"trick_down", &"trick_left", &"grab_left", &"tuck"]:
		Input.action_release(action)

func _is_route_diagnostic_phase() -> bool:
	return phase == "PURE_CARVE" or phase.begins_with("LINK_")

func _heading_degrees() -> float:
	var forward := -skier.global_basis.z
	return rad_to_deg(atan2(forward.x, forward.z))

func _grab_window() -> void:
	if grab_armed_press_pending and air_tracked and clock - air_entry_clock >= 0.1:
		Input.action_press("grab_left", 1.0)
		grab_armed_press_pending = false

func _air_tracking() -> void:
	var deliberate_phase := phase == "POP_AIR" or phase == "TRICK_AIR" or phase == "GRAB_AIR"
	if deliberate_phase and skier.state == SkierController.State.AIR:
		if not air_tracked:
			air_tracked = true
			air_entry_clock = clock
			air_takeoff_pos = skier.global_position
			air_peak_height = 0.0
			air_spin_degrees = 0.0
			air_takeoff_speed = skier.velocity.length()
			air_trick_name = skier.trick.current_name() if skier.trick else ""
			grab_armed_press_pending = phase == "GRAB_AIR"
		air_peak_height = maxf(air_peak_height, (skier.global_position - air_takeoff_pos).dot(ParkLayout.snow_normal()))
		air_spin_degrees += rad_to_deg(absf(skier.angular_velocity.y)) * skier.get_physics_process_delta_time()
		if skier.trick:
			air_trick_name = skier.trick.current_name()
	elif air_tracked:
		air_tracked = false
		grab_armed_press_pending = false
		Input.action_release("grab_left")
		air_windows.append({
			"phase": phase,
			"t": snappedf(air_entry_clock, 0.01),
			"air_seconds": snappedf(clock - air_entry_clock, 0.001),
			"peak_height_m": snappedf(air_peak_height, 0.001),
			"spin_degrees": snappedf(air_spin_degrees, 0.1),
			"takeoff_speed": snappedf(air_takeoff_speed, 0.01),
			"landing_speed": snappedf(skier.velocity.length(), 0.01),
			"trick_name": air_trick_name,
		})

func _sample() -> void:
	if tick % SAMPLE_INTERVAL != 0:
		return
	var forward := -skier.global_basis.z
	var yaw := rad_to_deg(atan2(forward.x, forward.z))
	var current_velocity := skier.velocity
	var velocity_heading := yaw
	var tangent_velocity := current_velocity.slide(ParkLayout.snow_normal())
	if tangent_velocity.length_squared() > 0.01:
		velocity_heading = rad_to_deg(atan2(tangent_velocity.normalized().x, tangent_velocity.normalized().z))
	var heading_velocity_angle := rad_to_deg(angle_difference(deg_to_rad(yaw), deg_to_rad(velocity_heading)))
	var colliders: Array = skier.last_collision_colliders.duplicate()
	samples.append([
		phase_names.size() - 1,
		snappedf(clock, 0.001),
		snappedf(skier.global_position.x, 0.01),
		snappedf(skier.global_position.y, 0.01),
		snappedf(skier.global_position.z, 0.01),
		snappedf(current_velocity.x, 0.01),
		snappedf(current_velocity.y, 0.01),
		snappedf(current_velocity.z, 0.01),
		snappedf(yaw, 0.1),
		skier.state,
		snappedf(skier.current_carve_ratio, 0.001),
		snappedf(skier.skid_amount, 0.001),
		snappedf(skier.edge_amount, 0.001),
		snappedf(skier.centripetal_demand, 0.001),
		snappedf(skier.slope_angle_degrees, 0.1),
		snappedf(skier.steering_input, 0.001),
		snappedf(current_velocity.length(), 0.01),
		snappedf(velocity_heading, 0.1),
		snappedf(heading_velocity_angle, 0.1),
		snappedf(skier.carve_force, 0.001),
		skier.contact.grounded,
		int(latest_telemetry.get("collision_count", 0)),
		colliders,
		latest_telemetry.get("speed_discontinuity", {}),
	])

func _finish() -> void:
	_release_inputs()
	var carve_heading_delta := absf(rad_to_deg(angle_difference(deg_to_rad(carve_start_heading), deg_to_rad(carve_end_heading))))
	var high_speed_quarter_delta := absf(rad_to_deg(angle_difference(deg_to_rad(high_speed_start_heading), deg_to_rad(high_speed_quarter_heading))))
	var high_speed_total_delta := absf(rad_to_deg(angle_difference(deg_to_rad(high_speed_start_heading), deg_to_rad(high_speed_end_heading))))
	var grab_completed := false
	for trick_result: Dictionary in completed_tricks:
		if "Safety Grab Left" in str(trick_result.get("text", "")):
			grab_completed = true
	if collision_events.size() > 0:
		failures.append("Feature collision occurred on the pure carve route")
	if carve_heading_delta < 120.0:
		failures.append("Pure carve only rotated %.1f degrees" % carve_heading_delta)
	if acceleration_air_frames > 0:
		failures.append("Ground acceleration test left the snow for %d frames" % acceleration_air_frames)
	if link_collision_count > 0:
		failures.append("Linked S-turn encountered %d feature collisions" % link_collision_count)
	if not grab_released_before_landing or not grab_completed:
		failures.append("Released grab was not completed and scored")
	if high_speed_quarter_delta > 12.0:
		failures.append("High-speed steering rotated %.1f degrees in 0.25 s instead of loading the edge progressively" % high_speed_quarter_delta)
	if high_speed_total_delta < 18.0 or high_speed_total_delta > 55.0:
		failures.append("High-speed one-second carve rotated %.1f degrees outside the approved 18-55 degree band" % high_speed_total_delta)
	if high_speed_max_heading_travel > skier.profile.high_speed_heading_travel_limit_degrees + 6.0:
		failures.append("High-speed heading/travel separation reached %.1f degrees" % high_speed_max_heading_travel)
	if high_speed_max_edge < 0.9:
		failures.append("High-speed steering never established a full edge")
	if high_speed_min_carve_ratio > 0.97 or high_speed_max_skid < 0.02:
		failures.append("High-speed full input did not transition measurably from carve toward skid")
	if high_speed_min_speed < high_speed_start_speed * 0.6:
		failures.append("High-speed carve destroyed too much momentum")
	var report := {
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"benchmark_start_transform": benchmark_start_transform,
		"sample_schema": SAMPLE_SCHEMA,
		"phase_names": phase_names,
		"landings": landings,
		"air_windows": air_windows,
		"collision_events": collision_events,
		"speed_discontinuities": speed_discontinuities,
		"completed_tricks": completed_tricks,
		"grab_released_before_landing": grab_released_before_landing,
		"scenario_summary": {
			"pure_carve_start_speed": snappedf(carve_start_speed, 0.01),
			"pure_carve_min_speed": snappedf(carve_min_speed, 0.01),
			"pure_carve_heading_delta_deg": snappedf(carve_heading_delta, 0.1),
			"pure_carve_grounded_frames": carve_grounded_frames,
			"linked_turn_min_speed": snappedf(link_min_speed, 0.01),
			"linked_turn_feature_collisions": link_collision_count,
			"high_speed_start_speed": snappedf(high_speed_start_speed, 0.01),
			"high_speed_min_speed": snappedf(high_speed_min_speed, 0.01),
			"high_speed_quarter_heading_delta_deg": snappedf(high_speed_quarter_delta, 0.1),
			"high_speed_total_heading_delta_deg": snappedf(high_speed_total_delta, 0.1),
			"high_speed_max_heading_travel_deg": snappedf(high_speed_max_heading_travel, 0.1),
			"high_speed_min_carve_ratio": snappedf(high_speed_min_carve_ratio, 0.001),
			"high_speed_max_skid": snappedf(high_speed_max_skid, 0.001),
			"ground_acceleration_start_speed": snappedf(acceleration_start_speed, 0.01),
			"ground_acceleration_end_speed": snappedf(acceleration_end_speed, 0.01),
			"ground_acceleration_air_frames": acceleration_air_frames,
			"brake_start_speed": snappedf(brake_start_speed, 0.01),
			"brake_end_speed": snappedf(brake_end_speed, 0.01),
		},
		"samples": samples,
	}
	var report_path := "user://physics_benchmark_results.json"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report))
		file.close()
		print("BENCH_JSON_WRITTEN path=", ProjectSettings.globalize_path(report_path), " samples=", samples.size(), " phases=", phase_names.size())
	else:
		print("BENCH_JSON_FAILED error=", FileAccess.get_open_error())
	for landing in landings:
		print("BENCH_LANDING ", JSON.stringify(landing))
	for window in air_windows:
		print("BENCH_AIR ", JSON.stringify(window))
	print("BENCH_CARVE_SUMMARY start=", carve_start_speed, " min=", carve_min_speed, " collisions=", collision_events.size())
	print("BENCH_HIGH_SPEED_SUMMARY start=", high_speed_start_speed, " min=", high_speed_min_speed, " quarter_deg=", high_speed_quarter_delta, " total_deg=", high_speed_total_delta, " separation_deg=", high_speed_max_heading_travel, " carve_min=", high_speed_min_carve_ratio, " skid_max=", high_speed_max_skid)
	print("BENCH_ACCEL_SUMMARY start=", acceleration_start_speed, " end=", acceleration_end_speed, " air_frames=", acceleration_air_frames)
	print("BENCH_BRAKE_SUMMARY start=", brake_start_speed, " end=", brake_end_speed)
	print("BENCH_DONE")
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("BENCH_PASS: turn inertia, high-speed carve/skid transition, air, landing, grab, and braking passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("BENCH_FAIL: " + failure)
	get_tree().quit(1)
