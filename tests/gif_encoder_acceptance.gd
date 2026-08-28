extends Node

const OUTPUT_NAME := "gif_acceptance.gif"

func _ready() -> void:
	var width := 64
	var height := 48
	var frames: Array = []
	var delays := [5, 5, 5]
	for f: int in 3:
		var image := Image.create(width, height, false, Image.FORMAT_RGB8)
		for y: int in height:
			for x: int in width:
				var r := int(x / float(width) * 255.0)
				var g := int(y / float(height) * 255.0)
				var b := 190
				if absi(x - (10 + f * 18)) < 9 and y > 16 and y < 32:
					r = 30
					g = 30
					b = 240
				image.set_pixel(x, y, Color8(r, g, b))
		frames.append(GifEncoder.quantize_rgb8(image.get_data()))
	var bytes := GifEncoder.encode(frames, delays, width, height)
	if bytes.size() < 64:
		push_error("GIF_FAIL: encoded clip suspiciously small (%d bytes)" % bytes.size())
		get_tree().quit(1)
		return
	if bytes.slice(0, 6).get_string_from_ascii() != "GIF89a":
		push_error("GIF_FAIL: missing GIF89a signature")
		get_tree().quit(1)
		return
	if bytes[bytes.size() - 1] != 0x3B:
		push_error("GIF_FAIL: missing trailer byte")
		get_tree().quit(1)
		return
	if bytes[6] != (width & 0xFF) or bytes[7] != ((width >> 8) & 0xFF):
		push_error("GIF_FAIL: wrong logical screen width")
		get_tree().quit(1)
		return
	var netscape := "NETSCAPE2.0".to_ascii_buffer()
	var netscape_at := -1
	for i: int in range(bytes.size() - netscape.size()):
		if bytes[i] == netscape[0]:
			var matched := true
			for j: int in range(1, netscape.size()):
				if bytes[i + j] != netscape[j]:
					matched = false
					break
			if matched:
				netscape_at = i
				break
	if netscape_at < 0:
		push_error("GIF_FAIL: missing looping extension")
		get_tree().quit(1)
		return
	var gce_count := 0
	for i: int in range(bytes.size() - 1):
		if bytes[i] == 0x21 and bytes[i + 1] == 0xF9:
			gce_count += 1
	if gce_count != frames.size():
		push_error("GIF_FAIL: expected %d frames, found %d" % [frames.size(), gce_count])
		get_tree().quit(1)
		return
	var path := "user://%s" % OUTPUT_NAME
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GIF_FAIL: could not write %s" % path)
		get_tree().quit(1)
		return
	file.store_buffer(bytes)
	file.close()
	print("GIF_ACCEPTANCE_PASS: wrote %s (%d bytes, %d frames)" % [path, bytes.size(), frames.size()])
	get_tree().quit(0)
