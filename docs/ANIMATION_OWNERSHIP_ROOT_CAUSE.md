# Animation ownership and root-cause note

## Runtime write order before the repair

| Stage | Owner | Writes |
| --- | --- | --- |
| Physics tick | `SkierController` | Character root transform, velocity, gameplay state, rail attachment |
| Presentation input | `SkierController._update_animation` | `SkierAnimationFrame` telemetry |
| Pose composition | `SkierAnimationController.apply_frame` | Canonical pelvis, spine, limbs, boots, skis, poles |
| Pose smoothing | `SkierAnimationController._blend_targets` | Canonical joint transforms |
| Skeleton adapter | `SkeletonSkierRig.sync_pose` | Imported skeleton bones and arm/grab solve |
| Equipment output | `SkeletonSkierRig._sync_equipment_pose` | Ski and pole pivots |
| Pole stabilization | `SkeletonSkierRig._stabilize_equipment_poles` | Pole pivots only |

There is no `AnimationPlayer`, `AnimationTree`, animation root motion, leg IK,
physical-bone ragdoll, or unrelated late-frame skeleton writer. Gameplay is the
root owner and the procedural controller is the pose owner.

## Confirmed causes

1. `SkierController._update_animation` replaced the active trick phase with
   `LANDING` at a fixed anticipation threshold. The animation controller then
   reduced the trick layer again, so a still-rotating body presented a neutral
   lower body before contact.
2. Rail capture changed the base pose from air to grind in one frame. The
   existing rail influence only affected release overlays and did not blend
   the two evaluated base poses.
3. Skis were children of boot mounts but also received rotations independent
   of hips, knees, and boots. Combined trick layers could therefore produce a
   locally attached yet visibly incoherent leg/equipment chain.
4. Rail slip called the general air-entry helper, which cleared angular
   velocity and trick history. The subsequent crash lost useful continuity.
5. Crash fall/rest presentation used mostly fixed targets and global crash
   elapsed time. Recovery then switched directly to ground and invoked the
   respawn reset event, producing the frozen interval and final snap.
6. Existing acceptance sequences exercised trick, rail, and bail mostly as
   separate segments and held crash elapsed constant within stages, so they
   could not detect static bail presentation or the combined transition path.

## Target ownership

```text
physics/gameplay root
  -> gameplay state and contact targets
  -> base procedural pose
  -> trick / rail / crash layers
  -> evaluated-pose transition
  -> smoothed ski targets
  -> bounded pelvis compensation
  -> ski-constrained two-bone leg IK
  -> arm/grab IK
  -> skeleton and equipment output
```

Ground and rail contact own ski targets. In free air and bail, the evaluated
boot pose owns the rigid boot/ski assembly. Transitions blend ownership; no
second system may alter lower-body or ski transforms after final output.
