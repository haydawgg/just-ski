extends Node

## Reproduces the GifRecorder save path headlessly: synthetic frames, real
## quantize + LZW encode, real Downloads-folder write. Prints each stage.

func _ready() -> void:
	var width := 640
	var height := 360
	var directory := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	print("DIAG downloads dir: '%s'" % directory)
	if directory.is_empty():
		print("DIAG FAIL: no Downloads dir reported")
		get_tree().quit(1)
		return

	# Simulate a real 15 s capture: 300 RGB8 frames of moving gradients.
	var started := Time.get_ticks_msec()
	var frames: Array = []
	for f: int in 300:
		var image := Image.create(width, height, false, Image.FORMAT_RGB8)
		for y: int in range(0, height, 4):
			for x: int in range(0, width, 4):
				var r := (x + f * 2) % 256
				var g := (y + f) % 256
				var b := 150 + (f % 100)
				image.fill_rect(Rect2i(x, y, 4, 4), Color8(r, g, b))
		frames.append(image.get_data())
	print("DIAG synthetic frames built in %d ms (%d frames)" % [Time.get_ticks_msec() - started, frames.size()])

	started = Time.get_ticks_msec()
	var palettized: Array = []
	palettized.resize(frames.size())
	for i: int in range(frames.size()):
		palettized[i] = GifEncoder.quantize_rgb8(frames[i] as PackedByteArray)
	print("DIAG quantize took %d ms" % [Time.get_ticks_msec() - started])

	started = Time.get_ticks_msec()
	var bytes := GifEncoder.encode(palettized, [], width, height)
	print("DIAG encode took %d ms, %d bytes" % [Time.get_ticks_msec() - started, bytes.size()])
	if bytes.is_empty():
		print("DIAG FAIL: encode produced no bytes")
		get_tree().quit(1)
		return

	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := directory.path_join("ski_clip_%s.gif" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		print("DIAG FAIL: could not open %s (%d %s)" % [path, err, error_string(err)])
		var fallback := OS.get_user_data_dir().path_join("ski_clip_%s.gif" % stamp)
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
