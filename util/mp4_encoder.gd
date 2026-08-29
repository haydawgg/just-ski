class_name Mp4Encoder
extends RefCounted

## Minimal dependency-free MP4 (ISO-BMFF) muxer for MJPEG clips.
## Every frame is a complete JPEG produced by Image.save_jpg_to_buffer().
## Samples are stored contiguously in a single mdat chunk at a constant
## frame rate, so all sample tables are trivial. Safe to run on a
## background thread; no allocations are shared with the caller.

const VIDEO_TIMESCALE := 30000
const MOVIE_TIMESCALE := 1000

static func encode(jpeg_frames: Array, fps: int, width: int, height: int) -> PackedByteArray:
	if jpeg_frames.is_empty() or fps <= 0:
		return PackedByteArray()
	var ftyp := _build_ftyp()
	var sizes := PackedInt32Array()
	sizes.resize(jpeg_frames.size())
	var mdat_payload := PackedByteArray()
	for i: int in jpeg_frames.size():
		var frame: PackedByteArray = jpeg_frames[i]
		if frame.is_empty():
			return PackedByteArray()
		sizes[i] = frame.size()
		mdat_payload.append_array(frame)
	var delta := maxi(roundi(float(VIDEO_TIMESCALE) / fps), 1)
	var chunk_offset := ftyp.size() + 8
	var bytes := PackedByteArray()
	bytes.append_array(ftyp)
	bytes.append_array(_box("mdat", mdat_payload))
	bytes.append_array(_build_moov(sizes, delta, chunk_offset, width, height, fps))
	return bytes

static func _build_ftyp() -> PackedByteArray:
	var payload := PackedByteArray()
	payload.append_array(_tag("isom"))
	payload.append_array(_u32(512))
	for brand: String in ["isom", "iso2", "jpeg", "mp41"]:
		payload.append_array(_tag(brand))
	return _box("ftyp", payload)

static func _build_moov(sizes: PackedInt32Array, delta: int, chunk_offset: int, width: int, height: int, fps: int) -> PackedByteArray:
	var frame_count := sizes.size()
	var track_duration := delta * frame_count
	var movie_duration := roundi(frame_count * float(MOVIE_TIMESCALE) / float(fps))

	var mvhd := PackedByteArray()
	mvhd.append_array(_u32(0))
	mvhd.append_array(_u32(0))
	mvhd.append_array(_u32(MOVIE_TIMESCALE))
	mvhd.append_array(_u32(movie_duration))
	mvhd.append_array(_u32(0x00010000))
	mvhd.append_array(_u16(0x0100))
	mvhd.append_array(_u16(0))
	mvhd.append_array(_u32(0))
	mvhd.append_array(_u32(0))
	mvhd.append_array(_unity_matrix())
	mvhd.resize(mvhd.size() + 24)
	mvhd.append_array(_u32(2))

	var tkhd := PackedByteArray()
	tkhd.append_array(_u32(0))
	tkhd.append_array(_u32(0))
	tkhd.append_array(_u32(1))
	tkhd.append_array(_u32(0))
	tkhd.append_array(_u32(movie_duration))
	tkhd.append_array(_u32(0))
	tkhd.append_array(_u32(0))
	tkhd.append_array(_u16(0))
	tkhd.append_array(_u16(0))
	tkhd.append_array(_u16(0))
	tkhd.append_array(_u16(0))
	tkhd.append_array(_unity_matrix())
	tkhd.append_array(_u32(width << 16))
	tkhd.append_array(_u32(height << 16))

	var mdhd := PackedByteArray()
	mdhd.append_array(_u32(0))
	mdhd.append_array(_u32(0))
	mdhd.append_array(_u32(VIDEO_TIMESCALE))
	mdhd.append_array(_u32(track_duration))
	mdhd.append_array(_u16(0x55C4))
	mdhd.append_array(_u16(0))

	var hdlr := PackedByteArray()
	hdlr.append_array(_u32(0))
	hdlr.append_array(_tag("vide"))
	hdlr.append_array(_u32(0))
	hdlr.append_array(_u32(0))
	hdlr.append_array(_u32(0))
	hdlr.append_array("VideoHandler".to_ascii_buffer())
	hdlr.append(0)

	var minf := PackedByteArray()
	minf.append_array(_full_box("vmhd", 0, 1, _u16(0) + _u16(0) + _u16(0) + _u16(0)))
	var dref_payload := PackedByteArray()
	dref_payload.append_array(_u32(1))
	dref_payload.append_array(_full_box("url ", 0, 1, PackedByteArray()))
	minf.append_array(_full_box("dref", 0, 0, dref_payload))
	minf.append_array(_build_stbl(sizes, delta, chunk_offset, width, height))

	var mdia := PackedByteArray()
	mdia.append_array(_full_box("mdhd", 0, 0, mdhd))
	mdia.append_array(_full_box("hdlr", 0, 0, hdlr))
	mdia.append_array(_box("minf", minf))

	var trak := _full_box("tkhd", 0, 7, tkhd)
	trak.append_array(_box("mdia", mdia))

	var moov := _full_box("mvhd", 0, 0, mvhd)
	moov.append_array(_box("trak", trak))
	return _box("moov", moov)

static func _build_stbl(sizes: PackedInt32Array, delta: int, chunk_offset: int, width: int, height: int) -> PackedByteArray:
	var stbl := PackedByteArray()
	var stsd_payload := PackedByteArray()
	stsd_payload.append_array(_u32(1))
	stsd_payload.append_array(_build_jpeg_entry(width, height))
	stbl.append_array(_full_box("stsd", 0, 0, stsd_payload))

	var stts_payload := PackedByteArray()
	stts_payload.append_array(_u32(1))
	stts_payload.append_array(_u32(sizes.size()))
	stts_payload.append_array(_u32(delta))
	stbl.append_array(_full_box("stts", 0, 0, stts_payload))

	var stsc_payload := PackedByteArray()
	stsc_payload.append_array(_u32(1))
	stsc_payload.append_array(_u32(1))
	stsc_payload.append_array(_u32(sizes.size()))
	stsc_payload.append_array(_u32(1))
	stbl.append_array(_full_box("stsc", 0, 0, stsc_payload))

	var stsz_payload := PackedByteArray()
	stsz_payload.append_array(_u32(0))
	stsz_payload.append_array(_u32(sizes.size()))
	for size: int in sizes:
		stsz_payload.append_array(_u32(size))
	stbl.append_array(_full_box("stsz", 0, 0, stsz_payload))

	var stco_payload := PackedByteArray()
	stco_payload.append_array(_u32(1))
	stco_payload.append_array(_u32(chunk_offset))
	stbl.append_array(_full_box("stco", 0, 0, stco_payload))
	return _box("stbl", stbl)

static func _build_jpeg_entry(width: int, height: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(6)
	payload.append_array(_u16(1))
	payload.append_array(_u16(0))
	payload.append_array(_u16(0))
	payload.resize(payload.size() + 12)
	payload.append_array(_u16(width))
	payload.append_array(_u16(height))
	payload.append_array(_u32(0x00480000))
	payload.append_array(_u32(0x00480000))
	payload.append_array(_u32(0))
	payload.append_array(_u16(1))
	payload.resize(payload.size() + 32)
	payload.append_array(_u16(0x0018))
	payload.append_array(_u16(0xFFFF))
	return _box("jpeg", payload)

static func _unity_matrix() -> PackedByteArray:
	var values := [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
	var bytes := PackedByteArray()
	for value: int in values:
		bytes.append_array(_u32(value))
	return bytes

static func _box(kind: String, payload: PackedByteArray) -> PackedByteArray:
	var bytes := _u32(payload.size() + 8)
	bytes.append_array(_tag(kind))
	bytes.append_array(payload)
	return bytes

static func _full_box(kind: String, version: int, flags: int, payload: PackedByteArray) -> PackedByteArray:
	var head := _u32((version << 24) | (flags & 0x00FFFFFF))
	head.append_array(payload)
	return _box(kind, head)

static func _u32(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes[0] = (value >> 24) & 0xFF
	bytes[1] = (value >> 16) & 0xFF
	bytes[2] = (value >> 8) & 0xFF
	bytes[3] = value & 0xFF
	return bytes

static func _u16(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(2)
	bytes[0] = (value >> 8) & 0xFF
	bytes[1] = value & 0xFF
	return bytes

static func _tag(text: String) -> PackedByteArray:
	var bytes := text.to_ascii_buffer()
	bytes.resize(4)
	return bytes
