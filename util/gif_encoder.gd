class_name GifEncoder
extends RefCounted

## Minimal dependency-free GIF89a animated encoder.
## Frames are pre-quantized to the built-in 6x6x6 color cube palette
## (one byte per pixel, row-major). Safe to run on a background thread.

const PALETTE_SIZE := 256

static func build_palette() -> PackedByteArray:
	var palette := PackedByteArray()
	palette.resize(PALETTE_SIZE * 3)
	var index := 0
	for r: int in 6:
		for g: int in 6:
			for b: int in 6:
				palette[index] = r * 51
				palette[index + 1] = g * 51
				palette[index + 2] = b * 51
				index += 3
	# Remaining slots: a gray ramp for finer snow/cloud shading.
	for i: int in range(PALETTE_SIZE - 216):
		var value := clampi(roundi(float(i) / float(PALETTE_SIZE - 217) * 255.0), 0, 255)
		palette[index] = value
		palette[index + 1] = value
		palette[index + 2] = value
		index += 3
	return palette

## Maps one RGB8 frame onto the built-in palette. Returns one byte per pixel.
static func quantize_rgb8(data: PackedByteArray) -> PackedByteArray:
	var indices := PackedByteArray()
	indices.resize(data.size() / 3)
	for i: int in range(indices.size()):
		var p := i * 3
		indices[i] = (mini(data[p] / 51, 5) * 36) + (mini(data[p + 1] / 51, 5) * 6) + mini(data[p + 2] / 51, 5)
	return indices

## Quick quantize that blends toward the gray ramp for near-gray pixels.
## Not used by default; plain cube quantize is faster and good enough.
static func encode(frames: Array, delays_cs: Array, width: int, height: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("GIF89a".to_ascii_buffer())
	_append_u16(out, width)
	_append_u16(out, height)
	# Global color table flag | color resolution | sort | table size (256 = 7).
	out.append(0xF7)
	out.append(0x00)
	out.append(0x00)
	out.append_array(build_palette())
	# NETSCAPE2.0 looping extension: loop forever.
	out.append_array(PackedByteArray([
		0x21, 0xFF, 0x0B,
	]))
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	out.append_array(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))
	for i: int in range(frames.size()):
		var delay: int = delays_cs[i] if i < delays_cs.size() else 5
		# Graphic control extension: disposal "keep", delay, no transparency.
		out.append_array(PackedByteArray([
			0x21, 0xF9, 0x04, 0x04,
			delay & 0xFF, (delay >> 8) & 0xFF,
			0x00, 0x00,
		]))
		out.append(0x2C)
		_append_u16(out, 0)
		_append_u16(out, 0)
		_append_u16(out, width)
		_append_u16(out, height)
		out.append(0x00)
		out.append(0x08)
		var lzw := _lzw_compress(frames[i] as PackedByteArray)
		var pos := 0
		while pos < lzw.size():
			var chunk := mini(255, lzw.size() - pos)
			out.append(chunk)
			out.append_array(lzw.slice(pos, pos + chunk))
			pos += chunk
		out.append(0x00)
	out.append(0x3B)
	return out

static func _append_u16(out: PackedByteArray, value: int) -> void:
	out.append(value & 0xFF)
	out.append((value >> 8) & 0xFF)

static func _lzw_compress(pixels: PackedByteArray) -> PackedByteArray:
	var clear_code := 256
	var end_code := 257
	var dict := {}
	var code_size := 9
	var next_code := 258
	var out := PackedByteArray()
	var acc := 0
	var nbits := 0

	# Leading clear code starts every data stream.
	acc = clear_code
	nbits = code_size

	var code := 0
	for i: int in range(pixels.size()):
		var k: int = pixels[i]
		var key := (code << 8) | k
		var found: int = dict.get(key, -1)
		if found >= 0:
			code = found
			continue
		acc |= code << nbits
		nbits += code_size
		while nbits >= 8:
			out.append(acc & 0xFF)
			acc >>= 8
			nbits -= 8
		dict[key] = next_code
		code = k
		next_code += 1
		if next_code > 4095:
			acc |= clear_code << nbits
			nbits += code_size
			while nbits >= 8:
				out.append(acc & 0xFF)
				acc >>= 8
				nbits -= 8
			dict.clear()
			next_code = 258
			code_size = 9
		elif next_code == (1 << code_size) and code_size < 12:
			code_size += 1
	# Flush the pending code, the end-of-information code, and any partial byte.
	acc |= code << nbits
	nbits += code_size
	acc |= end_code << nbits
	nbits += code_size
	while nbits >= 8:
		out.append(acc & 0xFF)
		acc >>= 8
		nbits -= 8
	if nbits > 0:
		out.append(acc & 0xFF)
	return out
