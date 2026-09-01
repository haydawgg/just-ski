class_name CrashReactionLayer
extends RefCounted

func step_pre_bail(current_weight: float, current_side: float, frame: SkierAnimationFrame, delta: float, profile: SkierAnimationProfile) -> Dictionary:
	var target := clampf(frame.pre_bail_weight, 0.0, 1.0) if frame.locomotion_state == 1 else 0.0
	var response := profile.pre_bail_response if target > current_weight else profile.secondary_release_response
	var weight := lerpf(current_weight, target, 1.0 - exp(-response * delta))
	var side := lerpf(current_side, clampf(frame.pre_bail_side, -1.0, 1.0), 1.0 - exp(-response * delta))
	return {"weight": weight, "side": side}

func is_crash_stage(stage: int) -> bool:
	return stage in [CrashContext.Stage.RELEASE, CrashContext.Stage.IMPACT, CrashContext.Stage.FALL, CrashContext.Stage.REST]
