# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Session, recovery, and scoring

- **Automatic course recovery can apply the marker-retry score penalty when a marker exists.** `SessionManager` emits an explicit `course_recovery` respawn reason, but `SkierController.respawn_at()` currently ignores its `_reason` argument and calls `scoring.apply_retry_cost()` whenever `SessionManager.has_marker` is true. As a result, leaving the course after saving a marker can reduce total score even though course recovery is supposed to preserve total score and only clear transient combo/link state. Retry cost should be gated on an explicit player marker-return/session-retry reason, with regression coverage for course recovery while a marker is present.

- **Personal-best persistence failures are not distinguishable from “not a new personal best,” and a corrupt progress file can block future saves.** `SessionManager.submit_score()` returns `false` both when a score does not beat the record and when `progress.cfg` cannot be loaded or saved. The results UI therefore cannot tell the player that a new record failed to persist. A parse/load failure also causes every later record submission to abort instead of repairing or replacing the bad records section. Persistence should return a distinct result/error state, surface the failure in the UI, and recover safely from malformed progress data without discarding unrelated progress.

- **The run-results “Best trick” stat can include line-link bonus points and the `Line Link +` presentation prefix.** `RunScoring.accept_trick()` adds the line bonus before comparing `best_trick_points`, then stores the linked display string as `best_trick_name`. This can make a weaker linked trick outrank a stronger standalone trick and report a line-link event as the run’s best individual trick. Best-trick tracking should compare the underlying trick value/name separately from combo and line bonuses.

## Controls and device ownership

- **Gameplay input is not isolated to the active controller when multiple gamepads are connected.** `InputManager` tracks an `active_joypad_id` for glyphs and rumble, but `SkierInputSampler` reads Godot’s aggregate action state (`Input.get_action_strength`, `Input.is_action_*`, and device-independent InputMap bindings). Inputs from two connected controllers can therefore combine or cancel even though only one is presented as active. Any joypad motion event also selects that pad as active before gameplay deadzone shaping, so low-level stick drift can move glyph/rumble ownership. Gameplay sampling should be scoped to the active device (or deliberately support all-controller input), and active-device selection should ignore sub-threshold motion.

- **Disconnecting the final controller does not pause a controller-first run.** The disconnect path switches prompts to keyboard and shows a notice, but gameplay continues immediately. If the controller disconnects during a downhill section, the skier keeps moving while the player has no equivalent controller input until they reconnect or reach the keyboard. The final-controller disconnect should pause or enter a dedicated reconnect state while preserving intentional keyboard/controller handoff behavior.

## Challenges and content tracking

- **Feature/route challenge credit can be awarded from proximity rather than authoritative feature use, and score requirements use the whole run total.** `ParkContentTracker` marks a feature complete after the player enters a 13 m approach radius and later moves 5 m downhill of it, without requiring jump takeoff, rail capture, feature contact, or another authoritative use event. Route rank is derived from those proximity completions. `minimum_score` conditions also receive the current run total rather than the score earned during the active spot attempt. A player can therefore receive route/sequence credit by passing near expert features and satisfy a local score target with points earned earlier in the run. Challenge evaluation should use authoritative feature outcomes and attempt-local score deltas.

## Display and graphics

- **The Resolution setting is selectable and confirmed in fullscreen modes but is only applied in Windowed mode.** `GameSettings._apply_display()` calls `window_set_size()` only when the window mode is `WINDOW_MODE_WINDOWED`, while the Settings UI leaves the resolution selector enabled for Fullscreen and Exclusive Fullscreen and treats a resolution change as a risky display change requiring Keep/Revert confirmation. In fullscreen modes this can persist a value and show a confirmation flow without changing the actual output resolution. The selector should be disabled/relabeled outside Windowed mode or the selected fullscreen resolution should be applied through a supported display-mode path.

- **HDR presentation is gated by the requested setting rather than the window’s actual active HDR output state.** `Resort.effective_hdr_enabled()` returns the saved `hdr_output` preference whenever the game is not headless, so the scene switches to the HDR AgX presentation even if HDR was requested but the current display/system did not actually enable HDR. Godot exposes actual HDR-enabled state separately and it can change dynamically with system settings, display capability, or which screen contains the window. The presentation tonemapper should follow the actual active HDR output state and refresh when that state changes.

## Animation, physics, and bail recovery

- **Extreme high-energy bails can briefly show a near-vertical ski silhouette during `FALL`.** The body collider and contact probes now stay surface-aligned while the rendered skier tumbles, roll speed is capped, and `REST` cannot begin until the root is snow-aligned. Tumble caps were lowered (`crash_roll_max_angular_speed` 3.2→2.2, `crash_ground_max_rotation_rate_degrees` 300→200, `crash_ground_angular_damping` 4.0→5.0) to shorten the worst frames, but the fall animation is still visibly stylized at the highest angular speeds and the improvement still needs human clip review.

## Ski and pole IK

- **Equipment collision coverage is not yet universal.** Pole shafts now clear torso/leg envelopes and each other (grab-aware), grounded pole tips are floor-bounded, boot targets are stance-separated, ski nose/tail pairs hold span, crash equipment is constrained, swept visual ski segments stop at solid park features, blocked AIR pole shafts retract preview IK, and pole strikes on solid features (plus steep snow faces far from touchdown) bail through the crash evaluator with grab, landing-window, and speed exemptions. There is still no general solver for arbitrary combinations of equipment and body geometry.
