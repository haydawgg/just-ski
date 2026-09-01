extends Node

## Verifies that the recorder's bounded background JPEG worker produces a real
## JPEG without touching the renderer or starting a full clip mux.

func _ready() -> void:
	ClipRecorder._frames.clear()
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
	if encoded.size() < 4 or encoded[0] != 0xFF or encoded[1] != 0xD8:
		push_error("CLIP_RECORDER_WORKER_FAIL: background JPEG worker did not produce a valid JPEG")
		get_tree().quit(1)
		return
	print("CLIP_RECORDER_WORKER_PASS: background JPEG worker produced %d bytes" % encoded.size())
	get_tree().quit(0)
