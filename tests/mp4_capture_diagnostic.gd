extends Node

## Reproduces the ClipRecorder save path headlessly: synthetic frames,
## real JPEG encoding, real MP4 mux, real Downloads-folder write. Prints
## each stage with timings.

func _ready() -> void:
	var width := 960
	var height := 540
	var directory := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var memory_before := _static_memory_bytes()
	print("DIAG downloads dir: '%s'" % directory)
	if directory.is_empty():
		print("DIAG FAIL: no Downloads dir reported")
		get_tree().quit(1)
		return

	# Simulate a real 15 s capture: 450 frames of moving gradients.
	var started := Time.get_ticks_msec()
	var frames: Array = []
	for f: int in 450:
		var image := Image.create(width, height, false, Image.FORMAT_RGB8)
		for y: int in range(0, height, 4):
			for x: int in range(0, width, 4):
				var r := (x + f * 2) % 256
				var g := (y + f) % 256
				var b := 150 + (f % 100)
				image.fill_rect(Rect2i(x, y, 4, 4), Color8(r, g, b))
		frames.append(image.save_jpg_to_buffer(0.75))
	var memory_after_capture := _static_memory_bytes()
	print("DIAG synthetic frames built and JPEG-encoded in %d ms (%d frames) memory_before=%d memory_after_capture=%d delta=%d" % [Time.get_ticks_msec() - started, frames.size(), memory_before, memory_after_capture, memory_after_capture - memory_before])

	started = Time.get_ticks_msec()
	var bytes := Mp4Encoder.encode(frames, 30, width, height)
	var memory_after_encode := _static_memory_bytes()
	print("DIAG mux took %d ms, %d bytes memory_after_encode=%d delta_from_capture=%d" % [Time.get_ticks_msec() - started, bytes.size(), memory_after_encode, memory_after_encode - memory_after_capture])
	if bytes.is_empty():
		print("DIAG FAIL: encode produced no bytes")
		get_tree().quit(1)
		return

	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := directory.path_join("ski_clip_%s.mp4" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		print("DIAG FAIL: could not open %s (%d %s)" % [path, err, error_string(err)])
		var fallback := OS.get_user_data_dir().path_join("ski_clip_%s.mp4" % stamp)
		var fb := FileAccess.open(fallback, FileAccess.WRITE)
		if fb != null:
			fb.store_buffer(bytes)
			fb.close()
			print("DIAG fallback write OK: %s" % fallback)
		get_tree().quit(1)
		return
	file.store_buffer(bytes)
	file.close()
	var check := FileAccess.open(path, FileAccess.READ)
	var size := 0
	if check != null:
		size = check.get_length()
		check.close()
	print("DIAG PASS: wrote %s (%d bytes on disk)" % [path, size])
	get_tree().quit(0)

func _static_memory_bytes() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))
