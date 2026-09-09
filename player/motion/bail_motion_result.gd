class_name BailMotionResult
extends RefCounted

var velocity := Vector3.ZERO
var angular_velocity := Vector3.ZERO
var planar_travel := Vector3.ZERO
var roll_axis := Vector3.ZERO
var roll_valid := false
var generated_roll_speed := 0.0
var align_rate := 0.0
var stage := CrashContext.Stage.RELEASE
var rest_detected := false
var rest_elapsed := 0.0
var should_recover := false
var should_respawn := false
