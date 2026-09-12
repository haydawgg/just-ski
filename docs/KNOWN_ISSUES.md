# Known Issues

This file tracks concrete, actionable bugs and missing functionality. Resolved items, validation plans, tuning notes, art direction, and future production work belong in the relevant project docs instead.

## Session, recovery, and scoring

- **The run-results "Best trick" stat can include line-link bonus points and the `Line Link +` presentation prefix.** `RunScoring.accept_trick()` adds the line bonus before comparing `best_trick_points`, then stores the linked display string as `best_trick_name`. This can make a weaker linked trick outrank a stronger standalone trick and report a line-link event as the run's best individual trick. Best-trick tracking should compare the underlying trick value/name separately from combo and line bonuses.

## Controls, markers, and device ownership

- **Gameplay input is not isolated to the active controller when multiple gamepads are connected.** `InputManager` tracks an `active_joypad_id` for glyphs and rumble, but `SkierInputSampler` reads Godot's aggregate action state (`Input.get_action_strength`, `Input.is_action_*`, and device-independent InputMap bindings). Inputs from two connected controllers can therefore combine or cancel even though only one is presented as active. Any joypad motion event also selects that pad as active before gameplay deadzone shaping, so low-level stick drift can move glyph/rumble ownership. Gameplay sampling should be scoped to the active device (or deliberately support all-controller input), and active-device selection should ignore sub-threshold motion.

- **Disconnecting the final controller does not pause a controller-first run.** The disconnect path switches prompts to keyboard and shows a notice, but gameplay continues immediately. If the controller disconnects during a downhill section, the skier keeps moving while the player has no equivalent controller input until they reconnect or reach the keyboard. The final-controller disconnect should pause or enter a dedicated reconnect state while preserving intentional keyboard/controller handoff behavior.

## Challenges and content tracking

- **Feature/route challenge credit is still awarded from proximity rather than authoritative feature use.** `ParkContentTracker` marks a feature complete after the player enters a 13 m approach radius and later moves 5 m downhill of it, without requiring jump takeoff, rail capture, feature contact, or another authoritative use event. Route rank is derived from those proximity completions. Score conditions now use attempt-local deltas, multi-step chains are order-checked against the attempt event log, and every course's finish placement is validated downhill of its required feature thresholds, but a player can still receive feature credit by passing near an unused feature — and the Session Yard's safe-route corridor is narrow enough that proximity circles of intermediate/expert features overlap it. Challenge evaluation should move to authoritative feature outcomes (takeoff, capture, contact) so credit reflects real use.

## Display and graphics

- **The Resolution setting is selectable and confirmed in fullscreen modes but is only applied in Windowed mode.** `GameSettings._apply_display()` calls `window_set_size()` only when the window mode is `WINDOW_MODE_WINDOWED`, while the Settings UI leaves the resolution selector enabled for Fullscreen and Exclusive Fullscreen and treats a resolution change as a risky display change requiring Keep/Revert confirmation. In fullscreen modes this can persist a value and show a confirmation flow without changing the actual output resolution. The selector should be disabled/relabeled outside Windowed mode or the selected fullscreen resolution should be applied through a supported display-mode path.

## Debug capture

- **A debug recording can be rejected as "too short" because the minimum-length check counts successfully encoded JPEG frames instead of elapsed capture slots.** The asynchronous recorder intentionally tracks dropped slots and later expands the sparse timeline by repeating nearby encoded frames so encoder back-pressure does not shorten presentation time. `_stop_recording()` performs the `MIN_CLIP_FRAMES` check before that expansion, using `_frames.size()`. Under heavy JPEG-worker back-pressure, a capture that ran longer than the minimum duration can therefore be discarded if fewer than 18 frames finished encoding. Minimum-duration validation should use capture-slot/elapsed time while separately requiring at least one usable encoded frame.

## Ski and pole IK

- **Equipment collision coverage is not yet universal.** Pole shafts now clear torso/leg envelopes and each other (grab-aware), grounded pole tips are floor-bounded, boot targets are stance-separated, ski nose/tail pairs hold span, crash equipment is constrained, swept visual ski segments stop at solid park features, blocked AIR pole shafts retract preview IK, and pole strikes on solid features (plus steep snow faces far from touchdown) bail through the crash evaluator with grab, landing-window, and speed exemptions. There is still no general solver for arbitrary combinations of equipment and body geometry.
