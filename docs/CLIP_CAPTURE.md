# Clip capture

## Release scope

Clip capture is a **prototype/debug utility**, not a supported player-facing sharing or export feature. The implementation intentionally remains 960×540 / 30 fps MJPEG-in-MP4 and does not capture synchronized game audio. H.264, platform-native encoders, browser/Discord compatibility, and audio muxing are outside the current release scope.

The runtime advertises this boundary through `ClipRecorder.RELEASE_SCOPE = &"prototype_debug"` and user-facing HUD notices use `DEBUG CAPTURE` wording. Do not describe F9 capture as production-ready media export unless that scope is deliberately changed together with codec, audio, platform, and licensing validation.

## Operation

F9 arms the next summit run for a 960×540, 30 fps MJPEG-in-MP4 debug capture. Press F9 again while the recorder is idle to cancel that pending arm. The pending arm survives a run ending before summit capture starts and is consumed only by an explicit Restart from Summit, not by session or course-recovery respawns that happen to use the default spawn.

While recording, F9 stops the current capture. Out-of-bounds recovery interrupts an in-progress clip instead of continuing it across the teleport. The JPEG worker is bounded so capture cannot grow an unbounded queue or block the gameplay thread.

## Timing contract

The recorder advances a capture-slot clock for every elapsed 1/30-second interval. Each successfully encoded JPEG is associated with its slot. When the worker is saturated, elapsed slots are retained and the mux timeline repeats the nearest encoded frame for missing slots. A dropped source frame therefore reduces visual novelty but does not silently shorten the resulting constant-rate clip. Leading gaps use the first available frame.

This is deterministic duplicate-frame compensation rather than variable-duration MP4 timestamps. It preserves the simple MJPEG sample-table and fixed-rate playback contract.

**Current limitation:** the stop-time minimum-length check still uses the number of successfully encoded JPEG frames before sparse-slot expansion. Under heavy worker back-pressure, a capture that ran long enough can therefore be rejected as “too short.” The active defect and intended fix are tracked in [Known Issues](KNOWN_ISSUES.md).

## Memory and shutdown

JPEG samples remain available to the background mux until the clip is written, but `Mp4Encoder.write_to_file()` streams `mdat` samples and writes the `moov` box directly to a temporary `user://` file. The recorder copies that file to Downloads in bounded chunks, falling back to Godot's user-data directory when Downloads is unavailable.

The recorder joins the JPEG worker before assembling the timeline and joins the mux worker before publishing `clip_saved` or `clip_failed`. Normal stops drain queued JPEG frames before muxing. On exit, incomplete capture data is discarded, active encoding is joined, and temporary output is deleted so no partial clip is published. A mux worker that cannot start clears its encoding state, removes temporary output, and emits `clip_failed`.

The compatibility `Mp4Encoder.encode()` byte-returning API remains available for small acceptance fixtures. Long-capture diagnostics use the streaming path.

## Verification

The runtime quality gate covers worker lifecycle, sustained-drop timeline expansion, and MP4 structure. It does not currently prove that the minimum-duration precheck uses elapsed capture slots; that gap is the known issue above. For a longer local capture/memory diagnostic:

```powershell
& $env:GODOT_PATH --headless --path . res://tests/mp4_capture_diagnostic.tscn
```

The diagnostic writes one sample clip to Downloads, or to `user://` when the platform does not expose a Downloads directory. Treat diagnostic timing and memory values as run-specific evidence rather than durable documentation; preserve them in the relevant issue/PR when investigating a regression.