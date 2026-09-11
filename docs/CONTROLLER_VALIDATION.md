# Controller Validation

This document separates automated input-contract coverage from the physical-device checks that still require a controller connected to a Windows desktop. It also distinguishes presentation/device-identity behavior from gameplay-device isolation; unresolved behavior is tracked in [Known Issues](KNOWN_ISSUES.md).

## Automated coverage

`tests/input_manager_acceptance.tscn` validates the source-level behavior that is deterministic without hardware:

- joypad IDs are retained as the active identity;
- controller-family detection maps Xbox, PlayStation, and unknown names to the expected glyph family;
- aggregate connection availability emits only on the zero/nonzero transition;
- disconnecting the active pad selects the lowest connected ID;
- the final disconnect clears the active identity and returns presentation to keyboard;
- keyboard/mouse input changes presentation without discarding a connected controller;
- rumble is resolved to the active connected ID and never hard-codes joypad `0`.

`tests/skier_input_frame_acceptance.tscn` additionally sends a gameplay event from joypad ID `7`, verifies that every gameplay joypad binding accepts all devices, and confirms steering/trick compatibility data arrives in one sequenced `SkierInputFrame`. `SkierController` reads this frame once per physics tick; it no longer reads live action state from its ground, air, rail, or trick policies.

That coverage does **not** mean gameplay input is isolated to the active controller. `SkierInputSampler` still reads Godot's aggregate action state, so simultaneous input from multiple connected pads can combine or cancel. Low-level joypad motion can also change active presentation/rumble ownership before gameplay deadzone shaping. Those are current defects, not pending hardware questions.

The current rumble policy is deliberate: keyboard presentation changes the displayed control glyphs, but does not discard the connected active controller. Feedback may therefore still rumble that controller until it disconnects or another controller becomes active. `stop_rumble()` stops all known connected pads during connection changes.

Run the deterministic check with:

```powershell
.\tests\runtime_quality_gate.ps1
```

## Physical-device matrix

| Device / transition | Required check | Result on baseline host |
| --- | --- | --- |
| Xbox One/Series or XInput pad | Family detection, A/B/X/Y glyphs, stick deadzone/outer deadzone/response, trigger mapping, rumble target | Pending: no physical gamepad was connected |
| DualShock/DualSense pad | PlayStation family detection, Cross/Circle/Square/Triangle glyphs, stick shaping, trigger mapping, rumble target | Pending: no physical gamepad was connected |
| Two pads connected | Confirm presentation/rumble ownership follows the producing ID; separately reproduce the known aggregate-gameplay-input limitation | Pending hardware run; deterministic identity fallback is covered, gameplay isolation is not |
| Final pad disconnect | Confirm aggregate availability changes to false and keyboard presentation is restored; also assess whether continuing unpaused is acceptable | Pending hardware run; deterministic final-disconnect path is covered, pause/reconnect behavior remains a known issue |
| Keyboard after controller input | Confirm keyboard glyphs appear while the active controller ID remains available for the documented rumble policy | Deterministic path covered; physical presentation pending |
| Stick sweep | Check inner deadzone, outer deadzone, center stability, full-scale response, and left/right symmetry on both sticks; note whether sub-threshold drift changes active-device ownership | Pending: default shaping is inner `0.18`, outer `0.06`, response `1.35` |

## Manual procedure

1. Start the game with one Xbox-family device and exercise jump, brake, grabs, and rumble-producing landing/rail/crash events. Record the reported family and confirm the displayed glyphs.
2. Repeat with a DualShock/DualSense device.
3. Connect two devices, use each one in turn, then disconnect the active device. Confirm the remaining device is selected for presentation/rumble, and separately test whether simultaneous gameplay inputs combine or cancel as described in Known Issues.
4. Disconnect the last device and confirm the UI returns to keyboard controls; record whether the downhill run continues unpaused.
5. After controller input, use the keyboard and verify the UI changes presentation while the documented controller identity/rumble policy remains intact.
6. Sweep both sticks slowly through center, the inner deadzone edge, and full travel. Repeat at several frame rates if possible and record drift, abrupt response changes, or unintended active-device ownership changes.

The hardware results should be appended to this matrix with the OS, Godot version, device name, connection order, and date. Automated CI does not claim to replace this physical pass.

## Validation log

### 2026-09-02 — host availability check (physical pass blocked)

- OS: Microsoft Windows 11 Pro 10.0.26200 (64-bit)
- Godot: 4.7.2.stable.official.ed1daf0bf
- Device names: no present Xbox/XInput, DualShock/DualSense, or other gamepad device was detected
- Connection order: not applicable; no gamepad was connected
- Observed mappings: none; the physical matrix remains pending

This dated entry is retained only because it is the latest physical-device evidence. Replace or append it when a real hardware pass is performed; do not infer current device compatibility from an availability check alone.
