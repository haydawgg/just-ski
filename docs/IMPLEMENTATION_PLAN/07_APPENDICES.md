# Appendix A — Repository evidence reviewed for this revision

Connected-master snapshot: 760393ced82df8c4047bbb590c1265bb87f286b5. The following paths materially informed the plan; local versions must still be re-read before implementation.

- player/camera_controller.gd — state profiles, target displacement/feed-forward, final fallback/revalidation, composition, surface-up, FOV/look-ahead.

- player/camera/camera_collision_solver.gd — cast_motion + destination overlap behavior.

- player/camera/camera_framing_solver.gd — AIR vertical dead zone/recovery and first-0.18-s response suppression.

- player/camera/composition_evaluator.gd — screen rect, body occlusion and candidate scoring.

- resources/physics/default_ski_profile.tres; player/ski_contact_solver.gd; player/skier_controller.gd — ±0.34 m contact sampling and transfer of hit positions into visual ski targets.

- player/animation/skier_animation_controller.gd; player/animation/air_trick_pose_layer.gd; resources/animation/default_animation_profile.tres — ground flex, AIR compactness and landing handoff.

- tests/animation_silhouette_acceptance.gd; animation_polish_acceptance.gd; jump_animation_acceptance.gd; landing_animation_acceptance.gd; air_preview_ik_acceptance.gd — current animation QA.

- world/vfx/ski_snow_vfx.gd; world/vfx/ski_contact_presentation.gd — contact-driven snow presentation and landing/carve emitters.

- world/course/park_course_profile.gd; world/course/park_course_builder.gd; world/park_features/park_layout.gd — data-driven course and trajectory-aware jumps.

- world/summit_environment_builder.gd; shaders/snow_summit.gdshader; world/resort_environment_profile.gd — presentation terrain, shadow suppression and environment fill/haze.

- world/environment/park_tree_batch.gd; distant mountain shader/builder paths; world/resort.gd — tree batching, mountain generation, resort dressing and reflection probe.

- tests/environment_tree_batch_acceptance.gd; tests/environment_visual_inspection.gd; tests/shader_static_acceptance.ps1; tests/quality_gate.ps1 — environment/visual gates.

- tests/runtime_quality_gate.ps1; tests/profiling_acceptance.tscn; tests/performance_profile_schema_acceptance.tscn — reviewed-master evidence for executable gate registration and performance characterization.

- tests/crash_recovery_acceptance.tscn; tests/settings_acceptance.tscn; tests/audio_mix_solver_acceptance.tscn — reviewed-master preservation coverage used by the revised integrated acceptance contract.

- docs/KNOWN_ISSUES.md — reviewed for pre-existing session/recovery, challenge/content, display/HDR, capture and equipment issues that must be distinguished from regressions introduced by this plan.

# Appendix B — Handoff note for the coding model

> **Final instruction —** This document is a dependency-ordered specification. Do not attempt to “complete the whole plan” by editing every subsystem at once. Read all phases, implement the assigned phase only, and treat each gate as a checkpoint. If local code differs, preserve the intent and adapt the edit rather than forcing the old implementation. If a GPU visual gate cannot be inspected by the model, generate the evidence and report HUMAN VISUAL REVIEW REQUIRED instead of claiming success. Before claiming a phase PASS, confirm any new test is registered in the executable gate, preserve the Phase 0 baseline status outside the assigned change family, and use the canonical acceptance artifact for comparable evidence.
