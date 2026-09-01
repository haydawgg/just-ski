extends Node

## Reproduces the ClipRecorder save path headlessly: synthetic frames,
## real JPEG encoding, streamed MP4 mux, real Downloads-folder write. Prints
## each stage with timings and static-memory samples.

func _ready() -> void:
	var width := 960
	var height := 540
	var directory := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var memory_before := _static_memory_bytes()
	var target_directory := directory if not directory.is_empty() else OS.get_user_data_dir()
	print("DIAG downloads dir: '%s' (target '%s')" % [directory, target_directory])

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
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := target_directory.path_join("ski_clip_%s.mp4" % stamp)
	var mux_error := Mp4Encoder.write_to_file(frames, 30, width, height, path)
	var memory_after_encode := _static_memory_bytes()
	print("DIAG streamed mux took %d ms error=%d memory_after_encode=%d delta_from_capture=%d" % [Time.get_ticks_msec() - started, mux_error, memory_after_encode, memory_after_encode - memory_after_capture])
	if mux_error != OK:
		print("DIAG FAIL: streamed encode failed (%s)" % error_string(mux_error))
		get_tree().quit(1)
		return

	var check := FileAccess.open(path, FileAccess.READ)
	var size := 0
	if check != null:
		size = check.get_length()
		check.close()
	print("DIAG PASS: wrote %s (%d bytes on disk)" % [path, size])
	get_tree().quit(0)

func _static_memory_bytes() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))
