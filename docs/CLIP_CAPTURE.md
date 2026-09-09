# Clip capture

F9 arms the next summit run for a 960×540, 30 fps MJPEG-in-MP4 capture. Press
F9 again while the recorder is idle to cancel that pending arm. The pending
arm survives a run ending before summit capture starts and is consumed only by
an explicit Restart from Summit, not by session or course-recovery respawns
that happen to use the default spawn. While recording, F9 stops the current
capture. Out-of-bounds recovery interrupts an in-progress clip instead of
continuing it across the teleport. The JPEG
worker is bounded so capture cannot grow an unbounded queue or block the
gameplay thread.

## Timing contract

The recorder advances a capture-slot clock for every elapsed 1/30-second
interval. Each successfully encoded JPEG is associated with its slot. When
the worker is saturated, the elapsed slots are retained and the mux timeline
repeats the nearest encoded frame for missing slots. A dropped source frame
therefore reduces visual novelty, but it does not silently shorten the run in
the resulting constant-rate clip. Leading gaps use the first available frame.

This is deliberately deterministic duplicate-frame compensation rather than
variable-duration MP4 timestamps. It keeps the existing simple MJPEG sample
tables and preserves the current fixed-rate playback contract.

## Memory and shutdown

JPEG samples remain available to the background mux until the clip is written,
but `Mp4Encoder.write_to_file()` streams the `mdat` samples and writes the
`moov` box directly to a temporary `user://` file. The recorder then copies
that file to Downloads in bounded 1 MiB chunks, falling back to Godot's user
data directory if Downloads is unavailable. It joins the JPEG worker before
assembling the timeline and joins the mux worker before publishing
`clip_saved` or `clip_failed`. Normal capture stops drain queued JPEG frames
before muxing. If the recorder exits, incomplete capture data is discarded,
any active encode is joined, and the temporary MP4 is deleted; no partial
clip is published. An MP4 worker that cannot start clears its encoding state,
removes its temporary output, and emits `clip_failed`.

The compatibility `Mp4Encoder.encode()` byte-returning API remains available
for small acceptance fixtures. The long-capture diagnostic uses the streaming
path and records static-memory samples before capture, after JPEG capture, and
after muxing.

## Verification

The runtime quality gate covers the worker acceptance and MP4 structure test.
The worker acceptance also exercises sustained-drop timeline expansion. For a
longer local memory sample:

```powershell
& $env:GODOT_PATH --headless --path . res://tests/mp4_capture_diagnostic.tscn
```

The diagnostic writes one sample clip to Downloads, or to `user://` when the
platform does not expose a Downloads directory.

The 2026-09-01 reference run built 450 960×540 JPEG frames in `3648 ms`,
streamed the `14084968`-byte MP4 in `10 ms`, and measured static memory of
`59418594` bytes before capture, `73541859` bytes after capture, and
`73541995` bytes after muxing. The final mux delta was `136` bytes in this
run, compared with the pre-streaming diagnostic's additional full-payload
allocation documented in `docs/BASELINE.md`.
