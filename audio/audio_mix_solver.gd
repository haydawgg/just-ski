class_name AudioMixSolver
extends RefCounted

func resolve(speed: float, skid: float, airborne: float, surface_kind: int, rail: float = 0.0) -> Dictionary:
	var speed_mix := clampf(speed / 32.0, 0.0, 1.0)
	var surface_loudness := 1.12 if surface_kind == 0 else (0.9 if surface_kind == 1 else 0.78)
	var ground_mix := 1.0 - clampf(airborne, 0.0, 1.0) * 0.88
	var rail_mix := clampf(rail, 0.0, 1.0) * (0.012 + speed_mix * 0.026)
	return {
		"speed_mix": speed_mix,
		"surface_amplitude": (speed_mix * 0.025 + clampf(skid, 0.0, 1.0) * 0.052) * surface_loudness * ground_mix,
		"wind_amplitude": 0.0035 + speed_mix * 0.018 + clampf(airborne, 0.0, 1.0) * 0.034,
		"rail_amplitude": rail_mix,
	}
