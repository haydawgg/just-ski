# Controller Validation

This document separates automated input-contract coverage from the physical-device checks that still require a controller connected to a Windows desktop.

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
| Two pads connected | Confirm active input selects the producing ID; disconnect it and confirm the lowest remaining ID becomes active | Pending hardware run; deterministic fallback is covered |
| Final pad disconnect | Confirm aggregate availability changes to false and keyboard presentation is restored | Pending hardware run; deterministic final-disconnect path is covered |
| Keyboard after controller input | Confirm keyboard glyphs appear while the active controller ID remains available for the documented rumble policy | Deterministic path covered; physical presentation pending |
| Stick sweep | Check inner deadzone, outer deadzone, center stability, full-scale response, and left/right symmetry on both sticks | Pending: default shaping is inner `0.18`, outer `0.06`, response `1.35` |

## Manual procedure

1. Start the game with one Xbox-family device and exercise jump, brake, grabs, and rumble-producing landing/rail/crash events. Record the reported family and confirm the displayed glyphs.
2. Repeat with a DualShock/DualSense device.
3. Connect two devices, use each one in turn, then disconnect the active device. Confirm the remaining device is selected without an aggregate disconnect event.
4. Disconnect the last device and confirm the UI returns to keyboard controls.
5. After controller input, use the keyboard and verify the UI changes presentation while the documented controller identity/rumble policy remains intact.
6. Sweep both sticks slowly through center, the inner deadzone edge, and full travel. Repeat at several frame rates if possible and record any drift or abrupt response changes.

The hardware results should be appended to this matrix with the OS, Godot version, device name, connection order, and date. Automated CI does not claim to replace this physical pass.

## Validation log

### 2026-09-02 — host availability check (physical pass blocked)

- OS: Microsoft Windows 11 Pro 10.0.26200 (64-bit)
- Godot: 4.7.2.stable.official.ed1daf0bf
- Device names: no present Xbox/XInput, DualShock/DualSense, or other gamepad device was detected
- Connection order: not applicable; no gamepad was connected
- Observed mappings: none; the physical matrix remains pending
