# Equipment Collision Research

## Decision

Implement deterministic presentation-only self-collision across the registered
skier body and equipment primitives. Keep equipment-to-world overlap recovery
out of this change because it crosses the gameplay sweep, animation update, and
crash-policy boundaries.

The selected design is a capsule-proxy projection pass behind the rig adapter.
It has a small typed interface—collision context in, bounded actuator result
out—and does not expose skeleton bones to the animation controller or move the
gameplay root.

## Existing coverage

Before this pass, collision handling was distributed across several narrow
mechanisms:

- boot and ski stance/span separation;
- pole-to-body, pole-to-pole, and grounded pole-tip stabilization;
- crash-specific equipment constraints;
- swept visual-ski and airborne-pole checks against solid world features.

Those paths protected their named cases, but there was no common audit of
ski/boot/pole combinations against the final posed body and each other. A new
grab or retargeting adjustment could therefore create a combination that none
of the special-case checks owned.

## Why capsule proxies

Godot recommends simple primitive collision shapes and notes that primitive
shapes are the fastest and most reliable option. Capsules also match the long,
rounded volumes involved here: limbs, ski centerlines, boots, and pole shafts.
The solver registers spheres as zero-length capsules, which keeps the pair
algorithm uniform.

The production skeleton and primitive fallback both publish the same semantic
proxy vocabulary:

- torso and head;
- upper arms, forearms, and hands;
- thighs and shins;
- skis and boots;
- pole shafts and baskets.

Pairs are sorted by stable semantic ID, then projected for six fixed iterations
per solve. The adapter performs at most six bounded reconciliation passes so
bone/attachment constraints are reflected back into the proxy model; each pass
exits early when its real final pose audits cleanly. Boot/ski assemblies
translate as a group and poles rotate around their hand pivot. Corrections are
capped across the full reconciliation, finite, and presentation-only. The final
audit records every unresolved
pair and maximum penetration for acceptance tests and debug snapshots.

## Intentional contacts

Exemptions are explicit shared tags rather than broad side- or type-based
filters. They cover only connected presentation chains:

- the pole grip and its same-side hand/forearm attachment region;
- the boot/ski assembly and its bound same-side leg chain;
- the active grabbing arm and the rigid boot/ski assembly selected by its
  ski-local grab target.

All other registered body/equipment and equipment/equipment combinations stay
in the candidate set, including opposite-side and pole/ski contacts.

## Alternatives rejected

### Compound `CharacterBody3D` collision

Adding animated equipment shapes to the authoritative player body would mix
presentation pose with locomotion ownership. It could change root motion,
landing, rail, and crash behavior when an animation changes, violating the
project's established physics boundary.

### Physical bones or ragdoll simulation

`PhysicalBone3D` and `PhysicalBoneSimulator3D` are designed for physics-driven
bones and ragdoll behavior. The active skier requires authored procedural poses,
deterministic grab contacts, and stable equipment mounts. A simulation layer
would add a competing owner rather than deepen the existing rig-adapter seam.

### Query-only diagnostics

Shape queries would detect bad poses but would not produce a deterministic
correction. They remain useful for external world geometry, where the result
must be reconciled with gameplay collision policy, but are insufficient for the
self-collision goal.

### More pair-specific clamps

Adding another pole/ski or boot/torso special case would preserve the original
coverage gap. A registered proxy set plus one solver makes the policy auditable
and gives future equipment a single extension point.

## Deferred world-collision gap

Equipment-to-world collision remains a separate problem. Godot's
`PhysicsDirectSpaceState3D.cast_motion()` reports safe/unsafe travel fractions
for a swept shape but does not resolve a shape that begins already overlapping.
In this project, final animation attachments are also updated after parts of the
gameplay sweep path. A universal fix therefore needs an explicit starting-
overlap recovery policy and a decision about whether recovery is visual-only or
can trigger gameplay crash behavior. That work is intentionally left as the
single equipment-collision known issue.

## Acceptance

The pure solver acceptance covers stable ordering, bounded translation and
pivoting, six iterations, explicit exemptions, invalid inputs, and unresolved
diagnostics. The production equipment acceptance audits all 20 registered
proxies for ground plus every supported grab at 30, 60, and 120 Hz and requires
zero unwhitelisted contacts while retaining the pre-existing pole/body, snow,
and ski-span checks.

## Primary references

- [Godot: Collision shapes (3D)](https://docs.godotengine.org/en/4.7/tutorials/physics/collision_shapes_3d.html)
- [Godot: PhysicsDirectSpaceState3D](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectspacestate3d.html)
- [Godot: PhysicsShapeQueryParameters3D](https://docs.godotengine.org/en/4.7/classes/class_physicsshapequeryparameters3d.html)
- [Godot: PhysicalBone3D](https://docs.godotengine.org/en/4.7/classes/class_physicalbone3d.html)
- [Godot: PhysicalBoneSimulator3D](https://docs.godotengine.org/en/4.7/classes/class_physicalbonesimulator3d.html)
- [Godot: Physical bones and ragdolls](https://docs.godotengine.org/en/4.7/tutorials/physics/ragdoll_system.html)
