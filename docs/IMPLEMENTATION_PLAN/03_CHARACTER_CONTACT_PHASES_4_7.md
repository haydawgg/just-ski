# Phase 4 — Decouple physical contact footprint from visual ski stance

Fix the architectural reason the skier can look bow-legged before tuning pose values.

### Why this is structural

Reviewed master samples left/right terrain at about −0.34/+0.34 m, then passes left_hit_position/right_hit_position into visual ski targets. That makes the physical 0.68 m sampling footprint capable of becoming the rendered boot/ski stance. Physics stability and anatomical presentation must be separate.

### Inspect / edit

- resources/physics/default_ski_profile.tres

- player/ski_contact_solver.gd

- player/skier_controller.gd

- player/animation/skier_animation_profile.gd and/or the appropriate profile that should own visual stance

- tests/animation_silhouette_acceptance.gd

- tests/environment_visual_inspection.gd

### Implementation

1\. Do not narrow the physics probes merely to make the model look better unless a separate physics study proves the probe width itself is wrong.

2\. Introduce profile-driven visual stance bounds/target. Prefer a representation relative to skeleton/hip width if available; otherwise use a dedicated visual ski-center spacing resource value with min/preferred/max.

3\. When both side contacts are valid, preserve each side’s height, terrain normal and longitudinal information but reproject/clamp the lateral ski centers around the skier/body center so contact width cannot directly force a 0.68 m visible stance.

4\. Allow bounded widening on strongly uneven terrain or landing preparation, but enforce a maximum presentation stance as well as the existing minimum separation.

5\. Keep feature collision and contact confidence authoritative; this phase changes presentation targets, not where the gameplay body thinks the snow is.

### Regression

1\. Add an end-to-end fixture that drives real SkiContactSolver-style hit positions through SkierController animation-frame construction into the rig/IK and measures rendered ski/boot separation.

2\. Include flat snow, cross-slope height difference, one-side low confidence, takeoff handoff and landing-preview cases.

3\. The test must fail if the visible stance simply mirrors ±0.34 m contact probes on flat snow.

> **Gate —** Normal skiing reads approximately hip-width/athletic rather than bow-legged, while the underlying contact solver retains its stability and uneven-terrain behavior.

# Phase 5 — Ground stance, carve loading and ski readability

After stance width is correct, retune the pose hierarchy so speed does not look like permanent impact compression and carves read through the skis/legs.

### Implementation

1\. Reduce speed-only crouch. The connected resource currently combines neutral_knee_flex 0.55 with speed_knee_flex 0.34; move more depth into carve load, terrain compression, braking, jump setup and tuck.

2\. Keep an athletic neutral stance with flexed ankles/knees and slight forward torso, but leave visible suspension travel in reserve.

3\. Strengthen the outside/inside leg contrast already present in the rig: loaded/outside leg visibly longer, inside leg shorter, ski edging readable, pelvis inside the turn, chest/head counterbalanced.

4\. Reduce excessive pelvis lateral travel if it dominates the silhouette. Prioritize ski angle → leg loading → hip angulation → quiet chest/head.

5\. Review ski equipment contrast at normal gameplay distance. Improve topsheet/edge/tip-tail differentiation before enlarging skis unrealistically.

### Tests

- Extend tests/animation_silhouette_acceptance.gd using real visual stance targets.

- Keep tests/animation_polish_acceptance.gd rate-independence coverage.

- Use tests/environment_visual_inspection.gd or equivalent GPU capture for actual chase-distance readability.

> **Gate —** Neutral high-speed skiing is not a permanent deep squat, and a reviewer can identify carve direction/outside-ski load from the normal gameplay camera.

# Phase 6 — Straight-air base pose, landing anticipation, poles and secondary motion

Make no-trick jumps look like skiing before doing any trick-specific polish.

### Straight-air implementation

1\. Add a no-trick athletic AIR flex floor independent of jump/trick size. A starting tuning range of ~0.30–0.45 rad-equivalent knee contribution is reasonable for A/B, but final value must be judged on the actual skeleton.

2\. Cache some takeoff/ground loading at AIR entry and decay it over roughly 0.15–0.25 s so the skier does not go from squat to locked-upright immediately after leaving snow.

3\. Preserve distinct Takeoff → Early Air → Apex → Descent shape, but jump size should add compactness rather than determine whether the pose is athletic at all.

4\. Keep torso slightly forward/active, hands forward/outward, skis controlled, and poles trailing diagonally rather than vertically dangling.

### Landing implementation

1\. Separate pre-contact alignment, impact compression, pose-ownership handoff and rebound. Do not use one short state blend for all four jobs.

2\. Increase normal landing_pose_handoff_duration from 0.08 s toward roughly 0.14–0.20 s as a starting range while keeping the actual impact impulse fast.

3\. Audit landing-preview IK. Do not let high preview weight extend the legs toward the snow so early that the skier has no visible flex range left at first contact.

4\. Use predicted landing normal/heading when valid, but keep a minimum athletic flex and cap visual reach until the final approach window.

5\. After contact, compress quickly, then show a restrained rebound/recovery instead of freezing in a squat.

### Secondary motion

- Add restrained head stabilization, shoulder lag, arm inertia, pole inertia and torso follow-through only after primary pose is correct.

- Do not create flailing. Secondary motion must remain subordinate to ski/leg mechanics.

### Tests

- tests/jump_animation_acceptance.gd

- tests/landing_animation_acceptance.gd

- tests/air_preview_ik_acceptance.gd

- tests/animation_silhouette_acceptance.gd

- tests/animation_polish_acceptance.gd

> **Gate —** A no-trick jump reads as athletic at takeoff, apex and descent; landing alignment begins before contact without early locked-leg reach; impact compresses and rebounds without a 2–3-frame state snap.

# Phase 7 — Snow-contact VFX and contact-shadow correctness

Use the existing contact-presentation architecture to make weight and edge load visible without turning every glide into a particle effect.

### Inspect / edit

- world/vfx/ski_snow_vfx.gd

- world/vfx/ski_contact_presentation.gd

- contact-shadow implementation discovered by searching \_build_contact_shadow / shadow opacity logic

- the existing shadow diagnostic/acceptance file in the local tree

### Implementation

1\. Convert carve/skid emission from fixed left/right ownership to per-ski emission using contact validity/confidence, turn/edge sign, load and slip/skid state. The loaded outside ski should naturally dominate a strong carve.

2\. Ensure particle spawn position is at the real ski/snow contact and ejection direction follows the edge/load/slip relationship rather than a generic cloud.

3\. Make landing spray a single impact event. The reviewed implementation has a ~0.38 s one-shot lifetime inside a ~0.68 s landing window that can restart the emitter; separate evidence/window bookkeeping from the actual one-shot trigger.

4\. Retune tracks, carve spray, skid spray, landing burst and speed snow for visibility at the normal chase distance, not close-up debug distance.

5\. Make contact shadow altitude-aware: darker/smaller/sharper near snow; lighter/larger/softer and/or more elliptical with height; derive AIR confidence from real surface distance instead of a nearly constant hard-coded confidence.

6\. Fix the shadow diagnostic so each sampled height stores its own historical skier/shadow transforms and numerical screen checks use the same camera that produces the reference image.

> **Gate —** Glide, carve, skid and landing can be distinguished visually; one landing causes one burst; shadow provides useful altitude information without looking like a fixed dark disk.
