class_name FrameDelta
extends RefCounted

## Rate calculations must not explode on a near-zero or hitch-sized delta.

const MIN_RATE_DELTA := 1.0 / 240.0
const MAX_RATE_DELTA := 0.05


static func stable(delta: float) -> float:
	if not is_finite(delta) or delta <= 0.0:
		return MIN_RATE_DELTA
	return clampf(delta, MIN_RATE_DELTA, MAX_RATE_DELTA)
