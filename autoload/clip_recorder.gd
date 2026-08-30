extends Node

## F9-armed gameplay clip capture. Pressing F9 arms the recorder; the next
## run started from the summit spawn is recorded until the finish trigger
## (or an early save / 90 s safety cap) and saved to the user's Downloads
## folder (user:// fallback) as an MJPEG-in-MP4 file. Frames are
## JPEG-encoded during capture and the MP4 is muxed on a background thread
## so play continues.

signal recording_changed(active: bool)
signal encoding_changed(active: bool)
signal clip_saved(path: String)
signal clip_failed(reason: String)
signal clip_info(message: String)
signal armed_changed(armed: bool)

const CAPTURE_FPS := 30.0
const MAX_CLIP_FRAMES := 2700         # = 90 s at 30 fps
const CAPTURE_WIDTH := 960
const CAPTURE_HEIGHT := 540
const JPEG_QUALITY := 0.75
const MIN_CLIP_FRAMES := 18           # ~0.6 s

var armed := false
var _recording := false
var _encoding := false
var _frames: Array[PackedByteArray] = []
var _capture_accum := 0.0
var _encode_thread: Thread = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_clip"):
		get_viewport().set_input_as_handled()
		if _recording:
			_stop_recording()
		elif _encoding:
			clip_info.emit("STILL ENCODING THE PREVIOUS CLIP — TRY AGAIN IN A MOMENT")
		else:
			arm()

func _process(delta: float) -> void:
	if not _recording or get_tree().paused:
		return
	_capture_accum += delta
	var interval := 1.0 / CAPTURE_FPS
	if _capture_accum < interval:
		return
	_capture_accum = fmod(_capture_accum, interval)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	image.resize(CAPTURE_WIDTH, CAPTURE_HEIGHT, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	_frames.append(image.save_jpg_to_buffer(JPEG_QUALITY))
	if _frames.size() >= MAX_CLIP_FRAMES:
		_stop_recording()

func is_recording() -> bool:
	return _recording

func arm() -> void:
	if _recording or armed:
		return
	armed = true
	armed_changed.emit(true)
	clip_info.emit("RECORDER ARMED — TAKE A RUN FROM THE SUMMIT")

func begin_run_capture() -> void:
	if _encoding:
		# Previous clip is still muxing; stay armed so the next run records.
		clip_info.emit("STILL ENCODING THE PREVIOUS CLIP — WAIT A MOMENT")
		return
	if armed:
		armed = false
		armed_changed.emit(false)
	_start_recording()

func end_run_capture() -> void:
	if armed:
		armed = false
		armed_changed.emit(false)
	_stop_recording()

func _start_recording() -> void:
	if _encoding:
		clip_info.emit("STILL ENCODING THE PREVIOUS CLIP — TRY AGAIN IN A MOMENT")
		return
	if _recording:
		return
	_recording = true
	_frames.clear()
	_capture_accum = 1.0 / CAPTURE_FPS
	recording_changed.emit(true)

func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	recording_changed.emit(false)
	if _frames.size() < MIN_CLIP_FRAMES:
		clip_info.emit("CLIP TOO SHORT — RIDE A MOMENT BEFORE SAVING")
		_frames.clear()
		return
	var frames := _frames.duplicate()
	_frames.clear()
	_encoding = true
	encoding_changed.emit(true)
	_encode_thread = Thread.new()
	_encode_thread.start(_encode_clip.bind(frames, CAPTURE_WIDTH, CAPTURE_HEIGHT))

func _encode_clip(frames: Array, width: int, height: int) -> void:
	# Frames arrive pre-encoded as JPEG; muxing is pure byte assembly.
	var bytes := Mp4Encoder.encode(frames, int(CAPTURE_FPS), width, height)
	_on_encoded.call_deferred(bytes)

func _on_encoded(bytes: PackedByteArray) -> void:
	if _encode_thread != null:
		_encode_thread.wait_to_finish()
		_encode_thread = null
	_encoding = false
	encoding_changed.emit(false)
	if bytes.is_empty():
		_fail("MP4 encoding produced no data")
		return
	var directory := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if directory.is_empty():
		directory = OS.get_user_data_dir()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := directory.path_join("ski_clip_%s.mp4" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_buffer(bytes)
	file.close()
	clip_saved.emit(path)

func _fail(reason: String) -> void:
	push_warning("Clip capture failed: %s" % reason)
	clip_failed.emit(reason)
