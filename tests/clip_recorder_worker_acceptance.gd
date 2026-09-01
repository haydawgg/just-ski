extends Node

const ClipTimelineModule = preload("res://util/clip_timeline.gd")

## Verifies that the recorder's bounded background JPEG worker produces a real
## JPEG without touching the renderer or starting a full clip mux.

func _ready() -> void:
	ClipRecorder._frames.clear()
	ClipRecorder._encoded_frames_by_slot.clear()
	ClipRecorder._start_jpeg_worker()
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color("#4b91c9"))
	ClipRecorder._queue_jpeg_frame(image)
	var waited := 0
	while ClipRecorder._frames.is_empty() and waited < 120:
		await get_tree().process_frame
		waited += 1
	var encoded := ClipRecorder._frames[0] if not ClipRecorder._frames.is_empty() else PackedByteArray()
	ClipRecorder._stop_jpeg_worker()
	ClipRecorder._frames.clear()
	ClipRecorder._encoded_frames_by_slot.clear()
	if encoded.size() < 4 or encoded[0] != 0xFF or encoded[1] != 0xD8:
		push_error("CLIP_RECORDER_WORKER_FAIL: background JPEG worker did not produce a valid JPEG")
		get_tree().quit(1)
		return

	# Simulate sustained worker back-pressure. Capture slots 1 and 3 are the
	# only encoded source frames; the expanded 30 Hz timeline must retain all
	# four elapsed slots instead of compressing the clip to two frames.
	var frame_a := PackedByteArray([0xFF, 0xD8, 0x01])
	var frame_b := PackedByteArray([0xFF, 0xD8, 0x02])
	var slotted: Dictionary = {1: frame_a, 3: frame_b}
	var timeline: Array[PackedByteArray] = ClipTimelineModule.expand(slotted, 4)
	if timeline.size() != 4 or timeline[0] != frame_a or timeline[1] != frame_a or timeline[2] != frame_a or timeline[3] != frame_b:
		push_error("CLIP_RECORDER_TIMELINE_FAIL: dropped slots were not duration-preserving")
		get_tree().quit(1)
		return
	print("CLIP_RECORDER_WORKER_PASS: background JPEG worker produced %d bytes; timeline preserved %d slots under sustained drops" % [encoded.size(), timeline.size()])
	get_tree().quit(0)
