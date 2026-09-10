extends RefCounted

## Stable collision-layer ABI shared by production physics/query code.
## Keep these bit values fixed unless a deliberate migration updates every
## serialized scene, runtime query, and acceptance test together.
const TERRAIN := 1 << 0
const SKIER := 1 << 1
const FEATURE := 1 << 2
const BOUNDARY := FEATURE
const GRIND := 1 << 3

const WORLD_SOLID_MASK := TERRAIN | FEATURE
const SKIER_COLLISION_MASK := WORLD_SOLID_MASK
const CAMERA_COLLISION_MASK := WORLD_SOLID_MASK
const TERRAIN_COLLISION_MASK := SKIER
const FEATURE_COLLISION_MASK := SKIER
const GRIND_COLLISION_MASK := SKIER
