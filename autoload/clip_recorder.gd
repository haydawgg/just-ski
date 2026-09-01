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
const MAX_PENDING_JPEG_FRAMES := 6

var armed := false
var _recording := false
var _encoding := false
var _frames: Array[PackedByteArray] = []
var _capture_accum := 0.0
var _encode_thread: Thread = null
var _jpeg_thread: Thread = null
var _jpeg_mutex := Mutex.new()
var _jpeg_semaphore := Semaphore.new()
var _jpeg_queue: Array[Image] = []
var _jpeg_worker_stop := false
var _jpeg_worker_available := false
var _capture_frame_count := 0
var _dropped_capture_frames := 0

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
	if _jpeg_worker_available and not _can_queue_jpeg_frame():
		_dropped_capture_frames += 1
		return
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null or not viewport_texture.get_rid().is_valid():
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		return
	if _jpeg_worker_available:
		_queue_jpeg_frame(image)
	else:
		var encoded := _encode_jpeg_frame(image)
		if not encoded.is_empty():
			_frames.append(encoded)
	_capture_frame_count += 1
	if _capture_frame_count >= MAX_CLIP_FRAMES:
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
	_capture_frame_count = 0
	_dropped_capture_frames = 0
	_start_jpeg_worker()
	recording_changed.emit(true)

func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	recording_changed.emit(false)
	_stop_jpeg_worker()
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

func _start_jpeg_worker() -> void:
	_stop_jpeg_worker()
	_jpeg_mutex.lock()
	_jpeg_queue.clear()
	_jpeg_worker_stop = false
	_jpeg_mutex.unlock()
	_jpeg_thread = Thread.new()
	var start_error := _jpeg_thread.start(_jpeg_worker)
	if start_error != OK:
		_jpeg_thread = null
		_jpeg_worker_available = false
		push_warning("Clip JPEG worker unavailable (%s); using synchronous capture" % error_string(start_error))
		return
	_jpeg_worker_available = true

func _stop_jpeg_worker() -> void:
	if _jpeg_thread == null:
		_jpeg_worker_available = false
		return
	_jpeg_mutex.lock()
	_jpeg_worker_stop = true
	_jpeg_mutex.unlock()
	_jpeg_semaphore.post()
	_jpeg_thread.wait_to_finish()
	_jpeg_thread = null
	_jpeg_worker_available = false
	_jpeg_mutex.lock()
	_jpeg_queue.clear()
	_jpeg_worker_stop = false
	_jpeg_mutex.unlock()

func _can_queue_jpeg_frame() -> bool:
	_jpeg_mutex.lock()
	var can_queue := _jpeg_queue.size() < MAX_PENDING_JPEG_FRAMES
	_jpeg_mutex.unlock()
	return can_queue

func _queue_jpeg_frame(image: Image) -> void:
	_jpeg_mutex.lock()
	if _jpeg_worker_stop or _jpeg_queue.size() >= MAX_PENDING_JPEG_FRAMES:
		_jpeg_mutex.unlock()
		_dropped_capture_frames += 1
		return
	_jpeg_queue.append(image)
	_jpeg_mutex.unlock()
	_jpeg_semaphore.post()

func _jpeg_worker() -> void:
	while true:
		_jpeg_semaphore.wait()
		var image: Image = null
		var should_stop := false
		_jpeg_mutex.lock()
		if not _jpeg_queue.is_empty():
			image = _jpeg_queue.pop_front()
		elif _jpeg_worker_stop:
			should_stop = true
		_jpeg_mutex.unlock()
		if image != null:
			var encoded := _encode_jpeg_frame(image)
			if not encoded.is_empty():
				_jpeg_mutex.lock()
				_frames.append(encoded)
				_jpeg_mutex.unlock()
		elif should_stop:
			return

func _encode_jpeg_frame(image: Image) -> PackedByteArray:
	image.resize(CAPTURE_WIDTH, CAPTURE_HEIGHT, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	return image.save_jpg_to_buffer(JPEG_QUALITY)

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
