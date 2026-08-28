extends Node

## F9 start/stop gameplay GIF capture. Recordings cap at 15 seconds and save
## to the user's Downloads folder (user:// fallback). Encoding runs on a
## background thread so play continues while the GIF is written.

signal recording_changed(active: bool)
signal encoding_changed(active: bool)
signal clip_saved(path: String)
signal clip_failed(reason: String)
signal clip_info(message: String)

const CAPTURE_FPS := 20.0
const MAX_CLIP_FRAMES := 300
const CAPTURE_WIDTH := 640
const CAPTURE_HEIGHT := 360
const DELAY_CENTISECONDS := 5

var _recording := false
var _encoding := false
var _frames: Array[PackedByteArray] = []
var _delays: Array[int] = []
var _capture_accum := 0.0
var _encode_thread: Thread = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_gif"):
		get_viewport().set_input_as_handled()
		if _recording:
			_stop_recording()
		else:
			_start_recording()

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
	_frames.append(image.get_data())
	_delays.append(DELAY_CENTISECONDS)
	if _frames.size() >= MAX_CLIP_FRAMES:
		_stop_recording()

func _start_recording() -> void:
	if _encoding:
		clip_info.emit("STILL ENCODING THE PREVIOUS CLIP — TRY AGAIN IN A MOMENT")
		return
	if _recording:
		return
	_recording = true
	_frames.clear()
	_delays.clear()
	_capture_accum = 1.0 / CAPTURE_FPS
	recording_changed.emit(true)

func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	recording_changed.emit(false)
	if _frames.size() < 12:
		clip_info.emit("CLIP TOO SHORT — RIDE A MOMENT BEFORE SAVING")
		_frames.clear()
		_delays.clear()
		return
	var frames := _frames.duplicate()
	var delays := _delays.duplicate()
	_frames.clear()
	_delays.clear()
	_encoding = true
	encoding_changed.emit(true)
	_encode_thread = Thread.new()
	_encode_thread.start(_encode_clip.bind(frames, delays, CAPTURE_WIDTH, CAPTURE_HEIGHT))

func _encode_clip(frames: Array, delays: Array, width: int, height: int) -> void:
	# Quantize on the worker thread so the main thread never hitches per pixel.
	var palettized: Array = []
	palettized.resize(frames.size())
	for i: int in range(frames.size()):
		palettized[i] = GifEncoder.quantize_rgb8(frames[i] as PackedByteArray)
	var bytes := GifEncoder.encode(palettized, delays, width, height)
	_on_encoded.call_deferred(bytes)

func _on_encoded(bytes: PackedByteArray) -> void:
	if _encode_thread != null:
		_encode_thread.wait_to_finish()
		_encode_thread = null
	_encoding = false
	encoding_changed.emit(false)
	if bytes.is_empty():
		_fail("GIF encoding produced no data")
		return
	var directory := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if directory.is_empty():
		directory = OS.get_user_data_dir()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := directory.path_join("ski_clip_%s.gif" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_buffer(bytes)
	file.close()
	clip_saved.emit(path)

func _fail(reason: String) -> void:
	push_warning("GIF capture failed: %s" % reason)
	clip_failed.emit(reason)
