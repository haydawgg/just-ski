class_name BailMotionResult
extends RefCounted

var velocity := Vector3.ZERO
var angular_velocity := Vector3.ZERO
var stage := CrashContext.Stage.RELEASE
var rest_detected := false
var rest_elapsed := 0.0
var should_recover := false
