extends Node

const ClipTimelineModule = preload("res://util/clip_timeline.gd")

## Verifies that the recorder's bounded background JPEG worker produces real
## JPEGs without touching the renderer or starting a full clip mux. The test
## queues several frames so worker shutdown is exercised with pending work.

func _ready() -> void:
	ClipRecorder._frames.clear()
	ClipRecorder._encoded_frames_by_slot.clear()
	ClipRecorder._start_jpeg_worker()
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color("#4b91c9"))
	const expected_frames := 4
	for capture_slot in range(expected_frames):
		if not ClipRecorder._queue_jpeg_frame(image, capture_slot):
			push_error("CLIP_RECORDER_WORKER_FAIL: could not queue frame %d" % capture_slot)
			get_tree().quit(1)
			return
	var deadline := Time.get_ticks_msec() + 2000
	while ClipRecorder._encoded_frames_by_slot.size() < expected_frames and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	ClipRecorder._stop_jpeg_worker()
	var encoded := ClipRecorder._encoded_frames_by_slot.get(0, PackedByteArray()) as PackedByteArray
	var encoded_frame_count := ClipRecorder._encoded_frames_by_slot.size()
	var queue_empty := ClipRecorder._jpeg_queue.is_empty()
	var worker_stopped := ClipRecorder._jpeg_thread == null and not ClipRecorder._jpeg_worker_available
	ClipRecorder._frames.clear()
	ClipRecorder._encoded_frames_by_slot.clear()
	if encoded_frame_count != expected_frames or encoded.size() < 4 or encoded[0] != 0xFF or encoded[1] != 0xD8 or not queue_empty or not worker_stopped:
		push_error("CLIP_RECORDER_WORKER_FAIL: queued JPEG frames did not drain cleanly (%d/%d)" % [encoded_frame_count, expected_frames])
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
