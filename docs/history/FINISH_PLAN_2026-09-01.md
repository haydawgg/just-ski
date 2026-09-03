# Summit Sessions — Completion Plan

This plan starts from the post-review architecture state introduced by commit `56f858c6c6741669e5ef7cb631e5091c947d2e52` and defines the remaining work required to complete the stabilization and modularization effort safely.

The governing rule is simple:

> Do not resume broad architectural extraction until Milestone 1 is fully green, measured, and documented.

The current code already contains useful animation, camera, and skier-controller seams. The goal is not to undo those changes. The goal is to close the missing safety work, establish a trustworthy baseline, then continue decomposition in small, behavior-preserving slices.

---

## Status at plan start

Already implemented or substantially completed:

- GitHub Actions quality-gate workflow exists and runs the static + headless runtime suite.
- Godot 4.7.2 is pinned and the downloaded archive is checksum-verified.
- Runtime quality-gate scripts accept an explicit Godot executable path.
- Settings validation is substantially hardened.
- Runtime Apply and persistence failure are separated correctly.
- Active controller identity and controller-family glyph behavior are implemented.
- Rumble no longer targets joypad `0` unconditionally.
- Scoring consumes the authoritative landing outcome instead of duplicating the `0.72` clean threshold.
- The airborne trick guide now reflects the current inertia-management model.
- Initial `RefCounted` solver/layer seams exist for animation, camera, and skier motion.
- Runtime interface acceptance coverage exists for the new solver/layer boundaries.

Known plan gaps:

- The current quality-gate workflow must be proven green and made merge-blocking.
- CI does not yet cache the pinned Godot binary.
- Failure artifacts do not yet preserve the deterministic visual-capture output expected by the original plan.
- Direct runtime-gate invocation does not yet prefer `$env:GODOT_PATH` before the repository-local fallback.
- Tier-1 `gi_enabled` settings support is missing.
- GI preset/profile/user gating is missing.
- GI staged Apply UI and persistence tests are missing.
- Repository hygiene cleanup is incomplete; `.tmp_male_base_mesh` remains tracked and ignore rules are minimal.
- `docs/BASELINE.md` does not yet exist.
- The initial CPU/GPU/query profiling pass has not been documented.
- Animation, camera, and skier decomposition started before the baseline was established.

## Current implementation status — 2026-09-01

The following slices have since landed on `master` and passed the local full
Quality Gate from isolated temporary Godot user directories:

- M1.1 CI/runtime stabilization: explicit `GODOT_PATH` resolution, pinned
  Godot 4.7.2 download/checksum, hashed import caching, timeout-safe
  process-tree cleanup, stdout/stderr preservation, failure captures, and
  five parallel runtime shards behind a required `quality` aggregator are
  implemented in `tests/runtime_quality_gate.ps1` and
  `.github/workflows/quality.yml`.
- M1.2 GI settings, profile/preset/user gating, staged UI, persistence error
  reporting, and acceptance coverage are implemented.
- M1.4 repository hygiene, M1.5's post-initial-decomposition baseline, and
  M1.6's initial CPU/GPU/query/audio/world/rail/memory profiling are recorded
  in the repository.
- M2 initial animation, camera, and skier `RefCounted` layer/solver seams are
  present, with direct interface tests and coordinator integration coverage.
- M3.1 contact-probe geometry and M3.2 landing evaluation weights are
  profile-driven. M3.3 has a deterministic editor preview baker documented in
  `docs/WORLD_AUTHORING.md`.
- M4.2 clip capture now preserves elapsed 30 Hz slots through deterministic
  duplicate-frame compensation and streams MP4 samples to disk. Sustained
  drops and streaming output are acceptance-tested; the measured diagnostic
  is in `docs/CLIP_CAPTURE.md`.
- M4.3 has a maintained Windows export preset, documented build/smoke-test
  procedure, and the project-authored MIT license recorded in `LICENSE`.

The sharded hosted Quality Gate passed in PR [#2](https://github.com/haydawgg/just-ski/pull/2)
and the post-merge `master` run [33564513153](https://github.com/haydawgg/just-ski/actions/runs/33564513153).
The `quality` check is configured as required on `master` with strict status
checks and administrator enforcement.

Remaining external work is explicit: physical Xbox/PlayStation/multi-device
validation remains pending as documented in `docs/CONTROLLER_VALIDATION.md`.
Target-class Medium performance is recorded for the local Intel UHD adapter;
repeat the same matrix on each representative release hardware tier. Neither
hardware requirement is inferred from headless tests.

---

# Milestone 1 — Finish stabilization before more refactors

Milestone 1 is complete only when every subsection below is finished and the full quality gate is green from a clean checkout.

## M1.1 — Make CI authoritative

### Required work

- [ ] Confirm the current `Quality Gate` workflow completes successfully on `master`.
- [ ] Fix any static, runtime, shader, script, or acceptance failure before doing any additional architecture work.
- [ ] Update `tests/runtime_quality_gate.ps1` Godot resolution order to:
  1. explicit `-GodotPath`
  2. `$env:GODOT_PATH`
  3. repository-local `.tools/godot-4.7.2/...`
- [ ] Add GitHub Actions caching for the pinned Godot 4.7.2 archive or extracted binary.
- [ ] Keep checksum verification even when restoring from cache.
- [ ] Preserve current runtime stdout/stderr logs on failure.
- [ ] Also upload deterministic capture output produced by the quality suite when available.
- [ ] Keep the workflow running on both `push` and `pull_request`.
- [ ] Configure repository rules/branch protection so `Quality Gate` is required before merging to `master`.

### Acceptance criteria

- A clean GitHub-hosted Windows runner can check out the repository and run the entire gate with no preinstalled project tools.
- CI never executes an unverified Godot archive.
- A failing runtime acceptance test leaves enough logs/captures to diagnose the failure without reproducing it locally first.
- `master` cannot accept a normal PR while the required Quality Gate is failing or pending.

### Stop condition

Do not begin any new M2 extraction while the required Quality Gate is red or unverified.

---

## M1.2 — Complete settings correctness, including GI

### Required work

Add a real Tier-1 GI control instead of leaving GI as an undocumented renderer/profile side effect.

- [ ] Add `gi_enabled` to `GameSettings.DEFAULTS`.
- [ ] Validate it as a strict boolean.
- [ ] Persist and reload it with all other settings.
- [ ] Include `gi_enabled` in the set of renderer settings that mark the graphics preset as `Custom` when individually changed.
- [ ] Define explicit preset capability policy for GI.
- [ ] Apply effective GI with one canonical rule:

```text
effective_gi = environment_profile.gi_enabled
               && GameSettings.active["gi_enabled"]
               && current_graphics_preset_allows_gi
```

- [ ] Ensure the environment/profile flag remains an upper-level capability gate rather than being overwritten by UI state.
- [ ] Add an Options-menu GI toggle.
- [ ] GI edits must remain staged while the Options menu is open.
- [ ] Cancel must restore the pending value and leave active renderer state unchanged.
- [ ] Apply must update runtime renderer/environment state immediately, then attempt persistence.
- [ ] Persistence failure must warn/signal without rolling back the successfully applied runtime setting.
- [ ] Update graphics documentation to describe the profile/user/preset GI ownership model.

### Required tests

- [ ] Default GI value is present and validated.
- [ ] Malformed GI config input falls back to the default.
- [ ] Pending GI edits do not affect active state before Apply.
- [ ] Cancel restores the previous pending GI value.
- [ ] Apply changes effective GI when the profile and preset allow it.
- [ ] GI remains disabled if the environment profile disables it.
- [ ] GI remains disabled if the selected graphics preset forbids it.
- [ ] Changing GI directly switches the graphics preset to `Custom`.
- [ ] GI survives save/reload.
- [ ] A save failure does not roll back active GI runtime state.

### Acceptance criteria

There is exactly one understandable chain from environment capability + user preference + preset capability to the renderer's effective GI state.

---

## M1.3 — Hardware-level controller validation

The source-level controller defects have been corrected, but physical-device testing is still required.

### Required work

- [ ] Verify Xbox-family controller identification and glyph output on hardware.
- [ ] Verify PlayStation-family controller identification and glyph output on hardware.
- [ ] Verify active-controller switching when two controllers are connected.
- [ ] Verify disconnecting the active controller selects another connected controller rather than reporting aggregate disconnection.
- [ ] Verify aggregate `controller_connection_changed` semantics.
- [ ] Verify rumble targets the intended active controller.
- [ ] Decide and document rumble policy after the keyboard becomes the most recent input source while a controller remains connected.
- [ ] Verify deadzone, outer-deadzone, and response shaping on physical sticks.

### Acceptance criteria

The active device, displayed glyph family, hotplug state, and rumble target remain mutually consistent through multi-controller and keyboard/controller transitions.

---

## M1.4 — Repository hygiene

### Required work

- [ ] Remove `.tmp_male_base_mesh` from the tracked project tree, or move any intentional source asset into a clearly named asset/source location.
- [ ] Add temp/generated asset directories to `.gitignore` where appropriate.
- [ ] Add runtime log/capture output directories to `.gitignore` if they can be generated locally.
- [ ] Review the root for other temporary or generated artifacts that should not be versioned.
- [ ] Confirm no required production source file is hidden by an overly broad ignore rule.

### Acceptance criteria

A clean checkout contains only intentional source/assets/configuration, and running tests locally does not create noisy untracked files under normal use.

---

## M1.5 — Establish `docs/BASELINE.md`

The original plan intended to capture the baseline before the first decomposition. That point has passed. Do not manufacture historical measurements.

Create a new baseline from the first fully green stabilized commit after M1.1–M1.4 and explicitly state that it is a **post-initial-decomposition baseline**.

### Required contents

- [ ] Baseline commit SHA.
- [ ] Godot version.
- [ ] OS/hardware used for local measurements where applicable.
- [ ] Quality Gate workflow run reference/result.
- [ ] Representative ground-speed measurements.
- [ ] Representative braking/deceleration measurements.
- [ ] Representative jump/pop apex and airtime measurements.
- [ ] Representative landing outcomes/quality cases.
- [ ] Rotation/trick benchmark outputs already available in the test suite.
- [ ] Camera query/performance acceptance outputs.
- [ ] Rail behavior/performance sample.
- [ ] Known unresolved behavior that is accepted as baseline rather than silently treated as fixed.
- [ ] Explicit note that this baseline cannot prove all numerical equivalence between `820def3` and `56f858` because the first architecture extraction landed before baseline capture.

### Acceptance criteria

Future refactors can compare behavior/performance against named numbers and a named commit rather than relying on memory or subjective feel alone.

---

## M1.6 — Complete the first profiling pass

Profile before deciding what to optimize or extract next.

### Required measurements

- [ ] Snow shader/GPU cost at representative quality levels.
- [ ] Camera query counts and camera update cost during normal ground riding, airborne tricks, landing, rails, and constrained spaces.
- [ ] Procedural audio CPU cost during representative riding and impact activity.
- [ ] Rail runtime cost as rail count/path length increases.
- [ ] Resort/world construction cost and any noticeable startup spikes.
- [ ] Main-thread frame-time sample during a representative summit-to-lower-run session.
- [ ] Memory sample during clip capture and final MP4 encode.

### Rules

- Record measurements before making optimization changes.
- Prefer representative scenarios already exercised by acceptance scenes.
- Store important measurements in `docs/BASELINE.md` or a linked profiling document.
- Do not optimize solely from source inspection when profiling shows the path is insignificant.

### Acceptance criteria

The next structural/performance priorities are justified by measurements, not file size alone.

---

# Milestone 1 exit gate

M2 may resume only when all of the following are true:

- [ ] GitHub Quality Gate is green from a clean checkout.
- [ ] Quality Gate is required for normal merges to `master`.
- [ ] Tier-1 GI setting is implemented, staged, applied, persisted, and tested.
- [ ] Controller hardware validation is documented.
- [ ] Repository hygiene cleanup is complete.
- [ ] `docs/BASELINE.md` exists and names a baseline commit.
- [ ] Initial profiling results are recorded.
- [ ] No known regression from `56f858` remains unexplained.

---

# Milestone 2 — Resume controlled decomposition

Do not perform another omnibus architecture commit. Each subsection below should be implemented as independently reviewable work with the full Quality Gate run before proceeding.

General M2 rules:

1. Preserve authoritative coordinators.
2. Prefer `RefCounted`/pure helper objects over new scene nodes unless lifecycle actually requires a node.
3. Avoid a signal maze between modules.
4. Extract policy/calculation, not arbitrary line-count chunks.
5. Keep gameplay authority out of presentation layers.
6. Add or strengthen behavioral/interface tests before or in the same change as each extraction.
7. Compare affected baseline metrics after every extraction.
8. If behavior changes intentionally, document and test the new contract instead of hiding the change inside a refactor.

---

## M2.1 — Finish animation decomposition first

Current state: useful layer seams exist, but `skier_animation_controller.gd` remains the largest coordinator.

### Target architecture

`SkierAnimationController` remains the sole animation coordinator and scene-facing owner. Extracted layers consume `SkierAnimationFrame` + profile/configuration and return pose/state contributions.

Preferred layer boundaries:

- `GroundPoseLayer`
- `AirTrickPoseLayer`
- `GrabPoseLayer`
- `StylePoseLayer`
- `LandingPoseLayer`
- `RailPoseLayer`
- `CrashReactionLayer`
- `SecondaryMotionLayer`

### Work order

Continue with the lowest-risk remaining logic first rather than moving the biggest functions first.

- [ ] Audit each new layer and identify duplicated policy still present in the coordinator.
- [ ] Finish secondary-motion ownership.
- [ ] Finish crash/pre-bail reaction ownership.
- [ ] Finish rail approach/rail/release pose ownership.
- [ ] Finish grab/style pose weight/target ownership.
- [ ] Finish landing anticipation/readiness/recovery ownership.
- [ ] Finish airborne trick phase/pose ownership.
- [ ] Finish ground locomotion pose ownership last if it still carries broad cross-layer dependencies.
- [ ] Keep joint-limit enforcement, final blending/order, adapter synchronization, and scene-node application in the coordinator unless a cleaner proven seam emerges.

### Do not

- Do not create separate competing animation state machines.
- Do not allow layers to mutate gameplay root transforms, gameplay velocity, collision state, rail state, trick score, or landing outcome.
- Do not duplicate smoothing state between a layer and coordinator.

### Acceptance criteria

- Existing animation acceptance scenes remain green.
- Silhouette, landing, rail, grab, crash, and jump acceptance behavior remains within baseline expectations.
- Coordinator responsibility is visibly orchestration/blending/application rather than owning every policy calculation.

---

## M2.2 — Continue camera decomposition

Current state: `CameraCollisionSolver`, `CameraFramingSolver`, and `CompositionEvaluator` are good initial seams.

### Required work

- [ ] Audit for duplicate collision/composition/framing math still retained in `camera_controller.gd`.
- [ ] Move remaining pure collision-query implementation into `CameraCollisionSolver` where appropriate.
- [ ] Move remaining pure screen-space scoring/bounds/correction logic into `CompositionEvaluator`.
- [ ] Move deterministic framing target/smoothing policy into `CameraFramingSolver` where doing so does not obscure state transitions.
- [ ] Keep camera state transitions, target ownership, final candidate selection, transform application, and public telemetry in the coordinator.
- [ ] Preserve query counters and performance diagnostics.
- [ ] Compare camera acceptance/performance metrics after every extraction.

### Acceptance criteria

- No camera acceptance regression.
- No increase in unexplained shape/ray query counts.
- Camera collision safety remains intact in constrained spaces.
- Airborne/landing framing remains stable.
- Coordinator remains understandable as a state/policy orchestrator.

---

## M2.3 — Continue skier-controller decomposition last

Current state: small motion/transition/evaluation helpers exist, but `SkierController` correctly remains authoritative.

### Preferred helper boundaries

- Ground motion policy
- Air ballistic policy
- Rail motion policy
- Landing transition/evaluation policy
- Collision crash evaluation
- Additional helpers only when they can consume sampled data and return explicit results without taking gameplay authority

### Required work

- [ ] Audit `GroundMotionSolver` for additional pure ground calculations that can move without owning node state.
- [ ] Keep contact sampling in `SkiContactSolver`; do not duplicate terrain ownership.
- [ ] Audit air code for pure ballistic/assist calculations while keeping trick angular state authoritative in `SkierController`/existing trick modules.
- [ ] Keep landing outcome ownership consistent with `LandingSolver` and explicit transition results.
- [ ] Keep crash state/context authority consistent with `CrashContext`.
- [ ] Extract rail motion only where the result can be represented as explicit returned data.
- [ ] Preserve the authoritative `State { GROUND, AIR, GRIND, BAIL }` transition owner in `SkierController`.
- [ ] Compare ski-feel, collision, suspension, landing, rail, trick, and benchmark results after every extraction.

### Do not

- Do not convert the skier into many mutually signaling gameplay nodes.
- Do not create multiple owners for velocity, transform, angular state, landing outcome, or bail state.
- Do not combine refactoring with physics tuning unless the tuning is intentionally scoped, measured, documented, and separately testable.

### Acceptance criteria

`SkierController` is primarily an authoritative orchestrator of sampled input/contact/state transitions while mathematical policy becomes easier to test independently.

---

# Milestone 2 exit gate

- [ ] Animation, camera, and skier helpers have clear single responsibilities.
- [ ] Coordinators still own lifecycle and authoritative state.
- [ ] Full Quality Gate is green.
- [ ] Baseline behavior/performance metrics have not regressed without an intentional documented decision.
- [ ] Static acceptance tests enforce only high-value architectural invariants rather than incidental source spelling.
- [ ] Runtime/behavioral tests carry the majority of refactor-safety responsibility.

---

# Milestone 3 — Data-driven physics and production tooling

Begin only after M2 is stable.

## M3.1 — Move remaining ski-contact geometry into data

Current hardcoded probe geometry should become profile/resource data where tuning benefits from it.

- [ ] Front/rear probe offsets.
- [ ] Left/right probe offsets.
- [ ] Any contact confidence geometry constants that represent skier/ski setup rather than universal math.
- [ ] Keep invariant numeric safety epsilons local when they are implementation details, not tuning parameters.

### Acceptance criteria

Contact geometry can be tuned through a resource/profile without editing solver source, while existing contact acceptance scenes remain green.

---

## M3.2 — Move landing evaluation weights into a profile/resource

Data-drive the remaining landing scoring/severity weights that represent game design rather than numerical safety.

Candidate data:

- alignment weight
- upright weight
- impact weight
- spin/angular weight
- impact severity weighting/bias values
- balance weighting/bias values

Do not data-drive constants merely because they are numeric. Keep hard failure safety logic readable and explicit.

### Acceptance criteria

Landing tuning has one authoritative profile path and scoring/animation/UI do not independently reinterpret thresholds.

---

## M3.3 — Production world/rail authoring workflow

Preserve deterministic procedural generation for tests, but improve content-authoring ergonomics.

- [ ] Add editor preview/bake workflow for procedural course/world construction where practical.
- [ ] Allow artists/designers to inspect stable generated geometry without requiring runtime reconstruction.
- [ ] Evaluate editor-baked/aggregated rail collision for large rail counts or long paths if profiling shows the current per-segment collision bodies matter.
- [ ] Keep deterministic runtime/test builders available for automated acceptance scenes.

### Acceptance criteria

Production iteration becomes more editor-friendly without sacrificing deterministic automated construction.

---

# Milestone 4 — Performance and production hardening

## M4.1 — Optimize only measured hot paths

Use M1.6 profiling to choose actual targets.

Potential targets, only if measurements justify them:

- snow rendering/shader variants
- camera collision/composition queries
- procedural audio synthesis
- rail collision representation
- world construction
- animation pose processing

Every optimization must have before/after measurements.

---

## M4.2 — Clip recorder timing and memory hardening

The current recorder is threaded and bounded at capture time, but production behavior still needs improvement.

- [ ] Preserve real presentation timing when capture frames are dropped instead of silently compressing elapsed time into a fixed-30-fps sequence.
- [ ] Decide between timestamps, duplicate-frame compensation, or another deterministic pacing scheme.
- [ ] Avoid holding both the entire compressed frame collection and entire final MP4 payload in memory if profiling shows this is material.
- [ ] Prefer streamed/chunked mux output when practical.
- [ ] Preserve current worker shutdown correctness.
- [ ] Keep capture/encode work off the main gameplay path.
- [ ] Add stress coverage for sustained frame drops and long captures.

### Acceptance criteria

A capture with dropped source frames has correct playback duration, and long captures do not cause unacceptable memory spikes.

---

## M4.3 — Release/build hygiene

- [x] Add and maintain `export_presets.cfg` when the project is ready for reproducible builds.
- [x] Add the project MIT license and retain third-party notices.
- [x] Document supported Godot version and build/export procedure.
- [x] Add a release smoke test around the exported build once exports become part of normal development.

---

# Working rules for every future PR/commit

Use these rules for all remaining work in this plan.

## Scope

- One conceptual behavior/refactor boundary per PR where practical.
- Avoid mixing settings correctness, content changes, physics tuning, and architecture extraction in one changeset.
- Keep commit messages specific enough to identify the affected contract.

## Verification

Before merging each significant change:

- [ ] Run relevant focused acceptance tests.
- [ ] Run the full local quality gate when practical.
- [ ] Require the GitHub Quality Gate to pass.
- [ ] Check the affected baseline metrics.
- [ ] Review warnings/errors, not only process exit codes.
- [ ] Update docs when the user-facing or architectural contract changes.

## Regression policy

If an acceptance test changes during a refactor, determine which is true before editing the expected value:

1. The code regressed and should be fixed.
2. The old test encoded an accidental implementation detail and should be replaced with a behavioral invariant.
3. Behavior intentionally changed and the new contract must be documented and measured.

Never update expected values solely to make a refactor green.

## Architecture policy

- Coordinators own lifecycle and authoritative state.
- Solvers/layers should prefer explicit inputs and explicit result objects/dictionaries over hidden global reads.
- `CrashContext` remains the model for explicit cross-system context transfer.
- Presentation systems must not gain gameplay authority.
- Avoid new signals when a direct coordinator-to-helper call is clearer.

---

# Recommended execution order from the current repository state

1. Get the current GitHub Quality Gate green.
2. Harden CI path resolution, cache, artifacts, and merge requirement.
3. Implement Tier-1 GI setting + UI + environment/preset gating + tests.
4. Finish controller hardware validation.
5. Clean repository temp/generated artifacts.
6. Create `docs/BASELINE.md` from the first fully green stabilized commit.
7. Run and record the profiling pass.
8. Resume animation decomposition in narrow slices.
9. Continue camera decomposition in narrow slices.
10. Continue skier-controller decomposition last.
11. Data-drive contact geometry and landing weights.
12. Improve editor/world/rail production tooling where profiling/workflow evidence supports it.
13. Harden clip timing/memory behavior.
14. Add release/export hygiene when distribution work begins.

---

# Definition of done

This plan is complete when:

- CI is reproducible, required, and diagnostically useful.
- Runtime settings have one authoritative validation/apply/persistence model including GI.
- Controller identity/hotplug/glyph/rumble behavior is hardware-validated.
- The repository is free of accidental temporary/generated source artifacts.
- A named baseline commit and measured behavior/performance reference exist.
- Animation, camera, and skier code are decomposed around testable pure/refcounted policy while authoritative coordinators remain intact.
- Physics tuning constants that should be design data are profile-driven.
- Production content authoring and measured performance bottlenecks have appropriate tooling/optimization.
- Clip capture preserves timing and acceptable memory behavior under stress.
- The full quality gate remains green throughout the completed system.
