extends Node

## Validates the Mp4Encoder byte stream headlessly: real JPEG samples from
## Image.save_jpg_to_buffer, muxed via Mp4Encoder, then structural checks
## on the resulting ISO-BMFF boxes (top-level box walk, sample table
## entries, and JPEG SOI markers).

const OUTPUT_NAME := "mp4_acceptance.mp4"

func _ready() -> void:
	var width := 64
	var height := 48
	var frames: Array = []
	for f: int in 5:
		var image := Image.create(width, height, false, Image.FORMAT_RGB8)
		for y: int in height:
			for x: int in width:
				var r := int(x / float(width) * 255.0)
				var g := int(y / float(height) * 255.0)
				var b := 190
				if absi(x - (8 + f * 10)) < 5 and y > 16 and y < 32:
					r = 30
					g = 30
					b = 240
				image.set_pixel(x, y, Color8(r, g, b))
		frames.append(image.save_jpg_to_buffer(0.75))
	var bytes := Mp4Encoder.encode(frames, 30, width, height)
	if bytes.size() < 128:
		_fail("encoded clip suspiciously small (%d bytes)" % bytes.size())
		return

	var boxes := {}
	var offset := 0
	while offset + 8 <= bytes.size():
		var size := _read_u32(bytes, offset)
		var kind := bytes.slice(offset + 4, offset + 8).get_string_from_ascii()
		if size < 8 or offset + size > bytes.size():
			_fail("malformed box %s (size %d at %d)" % [kind, size, offset])
			return
		if not boxes.has(kind):
			boxes[kind] = Vector2i(offset, size)
		offset += size
	for kind: String in ["ftyp", "mdat", "moov"]:
		if not boxes.has(kind):
			_fail("missing top-level %s box" % kind)
			return
	if offset != bytes.size():
		_fail("box walk did not consume the whole file (%d of %d)" % [offset, bytes.size()])
		return

	var moov := bytes.slice(boxes["moov"].x, boxes["moov"].x + boxes["moov"].y)
	for marker: String in ["trak", "mdia", "minf", "stbl", "jpeg", "stts", "stsc", "stsz", "stco"]:
		if _find_bytes(moov, marker.to_ascii_buffer()) < 0:
			_fail("missing %s inside moov" % marker)
			return

	var ftyp_size: int = boxes["ftyp"].y
	var chunk_offset: int = ftyp_size + 8
	if bytes[chunk_offset] != 0xFF or bytes[chunk_offset + 1] != 0xD8:
		_fail("stco chunk offset does not point at a JPEG SOI marker")
		return
	var soi_count := 0
	var search: int = chunk_offset
	while true:
		var found: int = _find_bytes(bytes, PackedByteArray([0xFF, 0xD8]), search)
		if found < 0:
			break
		soi_count += 1
		search = found + 2
	if soi_count < frames.size():
		_fail("expected at least %d JPEG SOI markers, found %d" % [frames.size(), soi_count])
		return

	var path := "user://%s" % OUTPUT_NAME
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write %s" % path)
		return
	file.store_buffer(bytes)
	file.close()
	print("MP4_ACCEPTANCE_PASS: wrote %s (%d bytes, %d frames, %dx%d)" % [path, bytes.size(), frames.size(), width, height])
	get_tree().quit(0)

func _fail(reason: String) -> void:
	push_error("MP4_FAIL: %s" % reason)
	get_tree().quit(1)

func _find_bytes(data: PackedByteArray, pattern: PackedByteArray, from: int = 0) -> int:
	for i: int in range(maxi(from, 0), data.size() - pattern.size() + 1):
		var matched := true
		for j: int in pattern.size():
			if data[i + j] != pattern[j]:
				matched = false
				break
		if matched:
			return i
	return -1

func _read_u32(data: PackedByteArray, offset: int) -> int:
	return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]
