class_name GrindCollisionSolver
extends RefCounted

const CollisionLayers := preload("res://resources/physics/collision_layers.gd")
const MAX_COLLISIONS := 8
const GrindCollisionResultModule := preload("res://player/motion/grind_collision_result.gd")

## Probe the actual skier body along the rail's requested translation. Rails
## stay outside the body mask, while terrain under a rail is ignored here so
## only authored solid Features can interrupt spline-driven grind motion.
func sweep(body: CharacterBody3D, motion: Vector3) -> RefCounted:
	var result: Variant = GrindCollisionResultModule.new()
	if body == null or motion.length_squared() < 0.000001:
		return result
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = body.global_transform
	parameters.motion = motion
	parameters.max_collisions = MAX_COLLISIONS
	parameters.recovery_as_collision = true
	var physics_result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), parameters, physics_result):
		return result
	for index: int in range(physics_result.get_collision_count()):
		var collider = physics_result.get_collider(index)
		var collider_layer: int = collider.collision_layer if collider is CollisionObject3D else 0
		if (collider_layer & CollisionLayers.FEATURE) == 0:
			continue
		result.hit = true
		result.travel = physics_result.get_travel()
		result.safe_fraction = physics_result.get_collision_safe_fraction()
		result.collider = collider
		result.collider_layer = collider_layer
		result.normal = physics_result.get_collision_normal(index)
		result.position = physics_result.get_collision_point(index)
		return result
	return result
